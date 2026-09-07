import 'package:flutter/material.dart';
import '../data/repository.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import '../services/pdf_service.dart';
import '../services/whatsapp_service.dart';
import 'paiement_form_sheet.dart' show kModesPaiement;

/// Formulaire "Nouveau reçu" indépendant — reprend `_open_recu_form` côté
/// ordinateur : un reçu peut être émis pour n'importe quel motif (pas
/// forcément un paiement de facture), avec une facture liée optionnelle.
class RecuFormSheet extends StatefulWidget {
  final List<Client> clients;
  final List<Facture> factures;
  final VoidCallback onSaved;
  const RecuFormSheet({super.key, required this.clients, required this.factures, required this.onSaved});

  @override
  State<RecuFormSheet> createState() => _RecuFormSheetState();
}

class _RecuFormSheetState extends State<RecuFormSheet> {
  final _repo = RecuRepository();
  final _motifCtrl = TextEditingController();
  final _montantCtrl = TextEditingController();
  final _recuParCtrl = TextEditingController();
  int? _clientId;
  String? _factureNumero;
  String _mode = kModesPaiement.first;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.clients.isNotEmpty) _clientId = widget.clients.first.id;
  }

  @override
  void dispose() {
    _motifCtrl.dispose();
    _montantCtrl.dispose();
    _recuParCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_clientId == null) {
      showFormError(context, 'Choisis un client avant d\'enregistrer.');
      return;
    }
    final montant = double.tryParse(_montantCtrl.text.replaceAll(',', '.'));
    if (montant == null || montant <= 0) {
      showFormError(context, 'Indique un montant reçu valide.');
      return;
    }
    setState(() => _saving = true);
    try {
      await _repo.create(
        clientId: _clientId!,
        factureNumero: _factureNumero,
        motif: _motifCtrl.text.trim(),
        montant: montant,
        modePaiement: _mode,
        recuPar: _recuParCtrl.text.trim(),
      );
      if (!mounted) return;
      widget.onSaved();
    } catch (_) {
      if (mounted) showFormError(context, 'Impossible d\'enregistrer ce reçu.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Client *', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        DropdownButtonFormField<int>(
          value: _clientId,
          dropdownColor: AppColors.surface,
          isExpanded: true,
          hint: Text(widget.clients.isEmpty ? 'Aucun client — ajoute-en un d\'abord' : 'Choisir…', style: TextStyle(color: context.textFaint)),
          items: [for (final c in widget.clients) DropdownMenuItem(value: c.id, child: Text(c.nom, style: TextStyle(color: context.textPrimary), overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _clientId = v),
        ),
        const SizedBox(height: 14),
        Text('Facture liée (facultatif)', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String?>(
          value: _factureNumero,
          dropdownColor: AppColors.surface,
          isExpanded: true,
          hint: Text('Aucune', style: TextStyle(color: context.textFaint)),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Aucune', style: TextStyle(color: AppColors.textPrimary))),
            for (final f in widget.factures) DropdownMenuItem<String?>(value: f.numero, child: Text(f.numero, style: const TextStyle(color: AppColors.textPrimary))),
          ],
          onChanged: (v) => setState(() => _factureNumero = v),
        ),
        const SizedBox(height: 14),
        Text('Motif', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(controller: _motifCtrl, decoration: const InputDecoration(hintText: 'Ex : Avance sur commande')),
        const SizedBox(height: 14),
        Text('Montant reçu (FCFA) *', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(controller: _montantCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration()),
        const SizedBox(height: 14),
        Text('Mode de paiement', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _mode,
          dropdownColor: AppColors.surface,
          isExpanded: true,
          items: [for (final m in kModesPaiement) DropdownMenuItem(value: m, child: Text(m, style: TextStyle(color: context.textPrimary)))],
          onChanged: (v) => setState(() => _mode = v ?? kModesPaiement.first),
        ),
        const SizedBox(height: 14),
        Text('Reçu par', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(controller: _recuParCtrl, decoration: const InputDecoration(hintText: 'Nom de la personne qui encaisse')),
        const SizedBox(height: 20),
        GoldButton(label: _saving ? 'Enregistrement…' : 'Enregistrer le reçu', onPressed: _saving ? () {} : _save),
      ],
    );
  }
}

/// Détail d'un reçu — plus léger que devis/facture donc présenté en
/// bottom sheet plutôt qu'en écran dédié : montant, motif, facture liée,
/// export PDF, suppression.
class RecuDetailSheet extends StatefulWidget {
  final Recu recu;
  final Client? client;
  final VoidCallback onDeleted;
  const RecuDetailSheet({super.key, required this.recu, required this.client, required this.onDeleted});

  @override
  State<RecuDetailSheet> createState() => _RecuDetailSheetState();
}

class _RecuDetailSheetState extends State<RecuDetailSheet> {
  final _repo = RecuRepository();
  bool _busy = false;

  Future<void> _preview() async {
    setState(() => _busy = true);
    try {
      final bytes = await PdfService.recuPdf(widget.recu, widget.client);
      if (!mounted) return;
      await PdfService.preview(bytes, 'Reçu ${widget.recu.numero}');
    } catch (_) {
      if (mounted) showFormError(context, 'Impossible de générer le PDF de ce reçu.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final bytes = await PdfService.recuPdf(widget.recu, widget.client);
      if (!mounted) return;
      await PdfService.share(bytes, '${widget.recu.numero}.pdf');
    } catch (_) {
      if (mounted) showFormError(context, 'Impossible de partager ce reçu.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendWhatsapp() async {
    setState(() => _busy = true);
    try {
      final bytes = await PdfService.recuPdf(widget.recu, widget.client);
      if (!mounted) return;
      final telephone = widget.client?.telephone.trim() ?? '';
      if (WhatsappService.numeroValide(telephone)) {
        await showAppBottomSheet(
          context,
          title: 'Message WhatsApp',
          child: WhatsappMessageSheet(
            telephone: telephone,
            messageInitial: 'Bonjour ${widget.client?.nom ?? ''}, voici votre reçu ${widget.recu.numero} d\'un montant de ${fmtFcfa(widget.recu.montantRecu)}. Merci de votre confiance — MK Entreprise.',
            introTexte: 'Un message peut accompagner l\'envoi du reçu sur WhatsApp',
            onOuvert: () => PdfService.share(bytes, '${widget.recu.numero}.pdf'),
          ),
        );
      } else {
        await PdfService.share(bytes, '${widget.recu.numero}.pdf');
      }
    } catch (_) {
      if (mounted) showFormError(context, 'Impossible d\'envoyer ce reçu par WhatsApp.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDelete(context, nom: widget.recu.numero, typeElement: 'ce reçu');
    if (!ok) return;
    await _repo.delete(widget.recu);
    if (!mounted) return;
    widget.onDeleted();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.recu;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.client?.nom ?? 'Client non renseigné', style: TextStyle(color: context.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(r.dateRecu.split('T').first, style: TextStyle(color: context.textFaint, fontSize: 12)),
        const SizedBox(height: 12),
        _infoRow(context, 'Motif', r.motif.isEmpty ? '—' : r.motif),
        _infoRow(context, 'Facture liée', r.factureNumero ?? '—'),
        _infoRow(context, 'Mode de paiement', r.modePaiement.isEmpty ? '—' : r.modePaiement),
        _infoRow(context, 'Reçu par', r.recuPar.isEmpty ? '—' : r.recuPar),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(10)),
          alignment: Alignment.center,
          child: Column(
            children: [
              const Text('MONTANT REÇU', style: TextStyle(color: AppColors.background, fontWeight: FontWeight.w700, fontSize: 11)),
              const SizedBox(height: 2),
              Text(fmtFcfa(r.montantRecu), style: const TextStyle(color: AppColors.background, fontWeight: FontWeight.w700, fontSize: 18)),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (_busy)
          const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 8), child: CircularProgressIndicator(color: AppColors.gold)))
        else ...[
          GoldButton(label: 'Aperçu PDF', onPressed: _preview),
          const SizedBox(height: 10),
          WhatsappButton(onPressed: _sendWhatsapp),
          const SizedBox(height: 10),
          GhostButton(label: 'Partager', onPressed: _share),
        ],
        const SizedBox(height: 14),
        TextButton(
          onPressed: _busy ? null : _delete,
          style: TextButton.styleFrom(foregroundColor: AppColors.danger, padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
          child: const Text('Supprimer ce reçu', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: context.textMuted, fontSize: 12.5)),
          Flexible(child: Text(value, textAlign: TextAlign.right, style: TextStyle(color: context.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
