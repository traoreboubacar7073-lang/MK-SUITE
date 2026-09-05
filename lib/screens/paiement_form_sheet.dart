import 'package:flutter/material.dart';
import '../data/repository.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

/// Modes de paiement — reprend `ui/reference_lists.py::MODE_PAIEMENT` de la
/// version ordinateur.
const List<String> kModesPaiement = ['Espèces', 'Mobile Money (Orange Money)', 'Virement Bancaire', 'Chèque'];

/// Formulaire "Enregistrer un paiement" pour une facture — reprend
/// `_open_paiement_form` côté ordinateur (montant reçu, mis à jour de
/// l'avance / reste à payer / statut via `FactureRepository.enregistrerPaiement`).
///
/// Différence assumée avec la version ordinateur : là-bas, encaisser un
/// paiement ne crée PAS de reçu automatiquement (les reçus y sont un module
/// à part, saisis à la main). Ici on ajoute une case à cocher, cochée par
/// défaut, pour émettre dans la foulée un `Recu` lié à cette facture via
/// `RecuRepository.create` — un confort qui ne change rien à la facture
/// elle-même et reste facultatif.
class PaiementFormSheet extends StatefulWidget {
  final Facture facture;
  final Client? client;
  final VoidCallback onSaved;
  const PaiementFormSheet({super.key, required this.facture, required this.client, required this.onSaved});

  @override
  State<PaiementFormSheet> createState() => _PaiementFormSheetState();
}

class _PaiementFormSheetState extends State<PaiementFormSheet> {
  final _factureRepo = FactureRepository();
  final _recuRepo = RecuRepository();
  late final TextEditingController _montantCtrl;
  String _mode = kModesPaiement.first;
  bool _emettreRecu = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _montantCtrl = TextEditingController(text: widget.facture.resteAPayer.round().toString());
  }

  @override
  void dispose() {
    _montantCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final montant = double.tryParse(_montantCtrl.text.replaceAll(',', '.'));
    if (montant == null || montant <= 0) {
      showFormError(context, 'Indique un montant reçu valide.');
      return;
    }
    setState(() => _saving = true);
    try {
      final f = widget.facture;
      await _factureRepo.enregistrerPaiement(f, montant, _mode);
      if (_emettreRecu && f.clientId != null) {
        await _recuRepo.create(
          clientId: f.clientId!,
          factureNumero: f.numero,
          motif: 'Paiement facture ${f.numero}',
          montant: montant,
          modePaiement: _mode,
        );
      }
      if (!mounted) return;
      widget.onSaved();
    } catch (_) {
      if (mounted) showFormError(context, 'Impossible d\'enregistrer ce paiement.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.facture;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Reste à payer actuel : ${fmtFcfa(f.resteAPayer)}', style: TextStyle(color: context.textMuted, fontSize: 12.5)),
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
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: _emettreRecu, activeColor: AppColors.gold, onChanged: (v) => setState(() => _emettreRecu = v ?? true)),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _emettreRecu = !_emettreRecu),
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('Émettre un reçu pour ce paiement', style: TextStyle(color: context.textMuted, fontSize: 12.5)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GoldButton(label: _saving ? 'Enregistrement…' : 'Confirmer le paiement', onPressed: _saving ? () {} : _save),
      ],
    );
  }
}
