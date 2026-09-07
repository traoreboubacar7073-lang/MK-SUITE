import 'package:flutter/material.dart';
import '../data/repository.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import '../services/pdf_service.dart';
import '../services/whatsapp_service.dart';
import 'paiement_form_sheet.dart';

/// Fiche détail d'une facture — montants (HT, réduction, TVA, TTC, avance,
/// reste à payer), lignes, aperçu/partage PDF, enregistrement d'un paiement
/// (`FactureRepository.enregistrerPaiement`), suppression.
///
/// Le dépôt ne propose ni `update()` ni `create()` autonome pour les
/// factures (seules `convertirEnFacture` côté devis et `enregistrerPaiement`
/// existent) — cette fiche ne propose donc pas de "Modifier" : côté
/// ordinateur une facture peut aussi être créée à la main sans devis
/// préalable (voir `_open_facture_form(from_devis=None)`), ce que la couche
/// de données actuelle ne permet pas de reproduire (signalé dans le rapport).
class FactureDetailScreen extends StatefulWidget {
  final Facture facture;
  final Client? client;
  const FactureDetailScreen({super.key, required this.facture, required this.client});

  @override
  State<FactureDetailScreen> createState() => _FactureDetailScreenState();
}

class _FactureDetailScreenState extends State<FactureDetailScreen> {
  final _repo = FactureRepository();
  late Facture _facture;
  List<LigneDocument> _lignes = [];
  bool _loading = true;
  bool _busy = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _facture = widget.facture;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final lignes = await _repo.lignes(_facture.numero);
    final all = await _repo.all();
    Facture latest = _facture;
    for (final f in all) {
      if (f.numero == _facture.numero) {
        latest = f;
        break;
      }
    }
    if (!mounted) return;
    setState(() {
      _lignes = lignes;
      _facture = latest;
      _loading = false;
    });
  }

  Future<void> _preview() async {
    setState(() => _busy = true);
    try {
      final bytes = await PdfService.facturePdf(_facture, widget.client, _lignes);
      if (!mounted) return;
      await PdfService.preview(bytes, 'Facture ${_facture.numero}');
    } catch (_) {
      if (mounted) showFormError(context, 'Impossible de générer le PDF de cette facture.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final bytes = await PdfService.facturePdf(_facture, widget.client, _lignes);
      if (!mounted) return;
      await PdfService.share(bytes, '${_facture.numero}.pdf');
    } catch (_) {
      if (mounted) showFormError(context, 'Impossible de partager cette facture.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendWhatsapp() async {
    setState(() => _busy = true);
    try {
      final bytes = await PdfService.facturePdf(_facture, widget.client, _lignes);
      if (!mounted) return;
      final telephone = widget.client?.telephone.trim() ?? '';
      final resteTxt = _facture.resteAPayer > 0 ? ' Reste à payer : ${fmtFcfa(_facture.resteAPayer)}.' : ' Facture soldée, merci !';
      if (WhatsappService.numeroValide(telephone)) {
        await showAppBottomSheet(
          context,
          title: 'Message WhatsApp',
          child: WhatsappMessageSheet(
            telephone: telephone,
            messageInitial: 'Bonjour ${widget.client?.nom ?? ''}, voici votre facture ${_facture.numero} d\'un montant de ${fmtFcfa(_facture.montantTtc)}.$resteTxt — MK Entreprise.',
            introTexte: 'Un message peut accompagner l\'envoi de la facture sur WhatsApp',
            onOuvert: () => PdfService.share(bytes, '${_facture.numero}.pdf'),
          ),
        );
      } else {
        await PdfService.share(bytes, '${_facture.numero}.pdf');
      }
    } catch (_) {
      if (mounted) showFormError(context, 'Impossible d\'envoyer cette facture par WhatsApp.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPaiement() async {
    await showAppBottomSheet(
      context,
      title: 'Enregistrer un paiement',
      child: PaiementFormSheet(
        facture: _facture,
        client: widget.client,
        onSaved: () {
          Navigator.of(context).pop();
          _changed = true;
          _load();
          showFormSuccess(context, 'Paiement enregistré.');
        },
      ),
    );
  }

  Future<void> _delete() async {
    final ok = await confirmDelete(context, nom: _facture.numero, typeElement: 'cette facture');
    if (!ok) return;
    await _repo.delete(_facture);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final reste = _facture.resteAPayer;
    return Scaffold(
      appBar: AppBar(
        title: Text(_facture.numero),
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
                    StatutBadge(statut: _facture.statut),
                    const SizedBox(height: 16),
                    AppCard(
                      child: Column(
                        children: [
                          _infoRow(context, 'Description', _facture.description.isEmpty ? '—' : _facture.description),
                          _infoRow(context, 'Date', _facture.dateFacture.split('T').first),
                          if (_facture.devisNumero != null) _infoRow(context, 'Devis d\'origine', _facture.devisNumero!),
                          _infoRow(context, 'Montant HT', fmtFcfa(_facture.montantHt)),
                          if (_facture.reductionPct > 0) _infoRow(context, 'Réduction', '${_facture.reductionPct.toStringAsFixed(0)}%'),
                          _infoRow(context, 'TVA', fmtFcfa(_facture.tva)),
                          _infoRow(context, 'Montant TTC', fmtFcfa(_facture.montantTtc)),
                          _infoRow(context, 'Avance reçue', fmtFcfa(_facture.avanceRecue)),
                          if (_facture.modePaiement.isNotEmpty) _infoRow(context, 'Mode de paiement', _facture.modePaiement),
                        ],
                      ),
                    ),
                    if (_lignes.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text('Contenu de la facture (${_lignes.length} ligne${_lignes.length > 1 ? 's' : ''})',
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
                      decoration: BoxDecoration(color: reste > 0 ? AppColors.danger : AppColors.success, borderRadius: BorderRadius.circular(14)),
                      child: Column(
                        children: [
                          Text(reste > 0 ? 'RESTE À PAYER' : 'SOLDÉE', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700, fontSize: 11)),
                          const SizedBox(height: 4),
                          Text(fmtFcfa(reste), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700, fontSize: 20)),
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
                      if (reste > 0) ...[
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _openPaiement,
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 15)),
                            child: const Text('Enregistrer un paiement', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      TextButton(
                        onPressed: _delete,
                        style: TextButton.styleFrom(foregroundColor: AppColors.danger, padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                        child: const Text('Supprimer cette facture', style: TextStyle(fontWeight: FontWeight.w600)),
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
