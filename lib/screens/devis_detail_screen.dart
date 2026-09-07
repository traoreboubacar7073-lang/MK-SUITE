import 'package:flutter/material.dart';
import '../data/repository.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import '../services/pdf_service.dart';
import '../services/whatsapp_service.dart';
import 'facture_detail_screen.dart';

/// Fiche détail d'un devis — objet, validité, lignes, montant HT, et les
/// actions : aperçu/partage PDF, changement de statut, conversion en
/// facture (via `DevisRepository.convertirEnFacture`, qui ne s'active que
/// pour un devis "Accepté" pas déjà converti — même règle que
/// `_show_devis_detail` côté ordinateur), suppression.
///
/// Le dépôt n'offre pas de mise à jour générale du devis (objet / lignes /
/// montant) — seulement `updateStatut` — donc, contrairement à la version
/// ordinateur, cette fiche ne propose pas de "Modifier" au-delà du statut.
class DevisDetailScreen extends StatefulWidget {
  final Devis devis;
  final Client? client;
  const DevisDetailScreen({super.key, required this.devis, required this.client});

  @override
  State<DevisDetailScreen> createState() => _DevisDetailScreenState();
}

class _DevisDetailScreenState extends State<DevisDetailScreen> {
  final _repo = DevisRepository();
  late Devis _devis;
  List<LigneDocument> _lignes = [];
  bool _loading = true;
  bool _busy = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _devis = widget.devis;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final lignes = await _repo.lignes(_devis.numero);
    final all = await _repo.all();
    Devis latest = _devis;
    for (final d in all) {
      if (d.numero == _devis.numero) {
        latest = d;
        break;
      }
    }
    if (!mounted) return;
    setState(() {
      _lignes = lignes;
      _devis = latest;
      _loading = false;
    });
  }

  Future<void> _preview() async {
    setState(() => _busy = true);
    try {
      final bytes = await PdfService.devisPdf(_devis, widget.client, _lignes);
      if (!mounted) return;
      await PdfService.preview(bytes, 'Devis ${_devis.numero}');
    } catch (_) {
      if (mounted) showFormError(context, 'Impossible de générer le PDF de ce devis.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final bytes = await PdfService.devisPdf(_devis, widget.client, _lignes);
      if (!mounted) return;
      await PdfService.share(bytes, '${_devis.numero}.pdf');
    } catch (_) {
      if (mounted) showFormError(context, 'Impossible de partager ce devis.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendWhatsapp() async {
    setState(() => _busy = true);
    try {
      final bytes = await PdfService.devisPdf(_devis, widget.client, _lignes);
      if (!mounted) return;
      final telephone = widget.client?.telephone.trim() ?? '';
      if (WhatsappService.numeroValide(telephone)) {
        await showAppBottomSheet(
          context,
          title: 'Message WhatsApp',
          child: WhatsappMessageSheet(
            telephone: telephone,
            messageInitial: 'Bonjour ${widget.client?.nom ?? ''}, voici votre devis ${_devis.numero} d\'un montant de ${fmtFcfa(_devis.montantHt)}. Merci de votre confiance — MK Entreprise.',
            introTexte: 'Un message peut accompagner l\'envoi du devis sur WhatsApp',
            onOuvert: () => PdfService.share(bytes, '${_devis.numero}.pdf'),
          ),
        );
      } else {
        await PdfService.share(bytes, '${_devis.numero}.pdf');
      }
    } catch (_) {
      if (mounted) showFormError(context, 'Impossible d\'envoyer ce devis par WhatsApp.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatut(String statut) async {
    setState(() => _busy = true);
    try {
      await _repo.updateStatut(_devis.numero, statut);
      _changed = true;
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _convertir() async {
    setState(() => _busy = true);
    try {
      final facture = await _repo.convertirEnFacture(_devis);
      _changed = true;
      await _load();
      if (!mounted) return;
      showFormSuccess(context, 'Facture ${facture.numero} créée à partir de ce devis.');
      Navigator.push(context, MaterialPageRoute(builder: (_) => FactureDetailScreen(facture: facture, client: widget.client)));
    } catch (_) {
      if (mounted) showFormError(context, 'Impossible de convertir ce devis en facture.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDelete(context, nom: _devis.numero, typeElement: 'ce devis');
    if (!ok) return;
    await _repo.delete(_devis);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_devis.numero),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context, _changed)),
      ),
      body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
            : SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.client?.nom ?? 'Client non renseigné', style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      StatutBadge(statut: _devis.statut),
                      const SizedBox(height: 16),
                      AppCard(
                        child: Column(
                          children: [
                            _infoRow(context, 'Objet', _devis.objet.isEmpty ? '—' : _devis.objet),
                            _infoRow(context, 'Date', _devis.dateDevis.split('T').first),
                            _infoRow(context, 'Validité', '${_devis.validiteJours} jours'),
                            _infoRow(context, 'Date limite', (_devis.dateLimite ?? '').split('T').first),
                            _infoRow(context, 'TVA', _devis.appliquerTva ? 'Oui (18%)' : 'Non'),
                          ],
                        ),
                      ),
                      if (_lignes.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Text('Contenu du devis (${_lignes.length} ligne${_lignes.length > 1 ? 's' : ''})',
                            style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 12.5)),
                        const SizedBox(height: 8),
                        AppCard(
                          child: Column(
                            children: [
                              for (final l in _lignes) _ligneRow(context, l),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(14)),
                        child: Column(
                          children: [
                            const Text('MONTANT HT', style: TextStyle(color: AppColors.background, fontWeight: FontWeight.w700, fontSize: 11)),
                            const SizedBox(height: 4),
                            Text(fmtFcfa(_devis.montantHt), style: const TextStyle(color: AppColors.background, fontWeight: FontWeight.w700, fontSize: 20)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_busy)
                        const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 10), child: CircularProgressIndicator(color: AppColors.gold)))
                      else ...[
                        GoldButton(label: 'Aperçu PDF', onPressed: _preview),
                        const SizedBox(height: 10),
                        WhatsappButton(onPressed: _sendWhatsapp),
                        const SizedBox(height: 10),
                        GhostButton(label: 'Partager', onPressed: _share),
                        const SizedBox(height: 14),
                        if (_devis.convertiFacture != null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                            decoration: BoxDecoration(color: AppColors.success.withOpacity(0.15), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.success.withOpacity(0.4))),
                            child: Text('✓ Converti en ${_devis.convertiFacture}', style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
                          ),
                        ] else if (_devis.statut == 'Accepté') ...[
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _convertir,
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 15)),
                              child: const Text('Convertir en facture', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        for (final s in ['En attente', 'Accepté', 'Refusé'])
                          if (s != _devis.statut)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: GhostButton(label: 'Marquer « $s »', onPressed: () => _setStatut(s)),
                            ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _delete,
                          style: TextButton.styleFrom(foregroundColor: AppColors.danger, padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                          child: const Text('Supprimer ce devis', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: context.textMuted, fontSize: 12.5)),
          Flexible(child: Text(value, textAlign: TextAlign.right, style: TextStyle(color: context.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _ligneRow(BuildContext context, LigneDocument l) {
    final qte = l.quantite == l.quantite.roundToDouble() ? l.quantite.toStringAsFixed(0) : l.quantite.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$qte × ${l.description}', style: TextStyle(color: context.textPrimary, fontSize: 13)),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${fmtFcfa(l.prixUnitaire)} / unité', style: TextStyle(color: context.textFaint, fontSize: 11)),
              Text(fmtFcfa(l.totalLigne), style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}
