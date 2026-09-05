import 'package:flutter/material.dart';
import '../data/repository.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

/// Une ligne saisie dans l'éditeur de lignes (quantité / description / prix
/// unitaire) — miroir du comportement de `_lines_editor` côté ordinateur :
/// 3 lignes vides par défaut, bouton "+ Ajouter une ligne", suppression
/// ligne par ligne, total recalculé en direct.
class _LigneRow {
  final TextEditingController qte = TextEditingController(text: '1');
  final TextEditingController desc = TextEditingController();
  final TextEditingController prix = TextEditingController(text: '0');

  double get total {
    final q = double.tryParse(qte.text.replaceAll(',', '.')) ?? 0;
    final p = double.tryParse(prix.text.replaceAll(',', '.')) ?? 0;
    return q * p;
  }

  bool get valide => desc.text.trim().isNotEmpty;

  void dispose() {
    qte.dispose();
    desc.dispose();
    prix.dispose();
  }
}

/// Éditeur de lignes réutilisable (Qté × Description × Prix unitaire) avec
/// total HT recalculé à chaque frappe. Il n'existe pas de widget partagé
/// pour ça dans shared_widgets.dart — construit ici pour devis_form_sheet.
class LigneItemsEditor extends StatefulWidget {
  final ValueChanged<double> onTotalChanged;
  const LigneItemsEditor({super.key, required this.onTotalChanged});

  @override
  State<LigneItemsEditor> createState() => LigneItemsEditorState();
}

class LigneItemsEditorState extends State<LigneItemsEditor> {
  final List<_LigneRow> _rows = [];

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < 3; i++) {
      _rows.add(_LigneRow());
    }
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  double get _total => _rows.fold(0.0, (s, r) => s + r.total);

  void _notify() => widget.onTotalChanged(_total);

  void _addRow() {
    setState(() => _rows.add(_LigneRow()));
    _notify();
  }

  void _removeRow(int i) {
    setState(() {
      _rows[i].dispose();
      _rows.removeAt(i);
    });
    _notify();
  }

  /// Retourne les lignes valides (description non vide), sous la forme
  /// attendue par `DevisRepository.create` — un record `List<({...})>`.
  List<({double quantite, String description, double prixUnitaire})> validLines() {
    return _rows.where((r) => r.valide).map((r) {
      final q = double.tryParse(r.qte.text.replaceAll(',', '.')) ?? 1;
      final p = double.tryParse(r.prix.text.replaceAll(',', '.')) ?? 0;
      return (quantite: q, description: r.desc.text.trim(), prixUnitaire: p);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(width: 44, child: Text('Qté', style: TextStyle(color: context.textFaint, fontSize: 10.5, fontWeight: FontWeight.w700))),
            Expanded(child: Text('Description', style: TextStyle(color: context.textFaint, fontSize: 10.5, fontWeight: FontWeight.w700))),
            SizedBox(width: 78, child: Text('Prix unit.', style: TextStyle(color: context.textFaint, fontSize: 10.5, fontWeight: FontWeight.w700))),
            const SizedBox(width: 32),
          ],
        ),
        const SizedBox(height: 6),
        for (int i = 0; i < _rows.length; i++) _buildRow(i),
        const SizedBox(height: 4),
        GhostButton(label: '+ Ajouter une ligne', onPressed: _addRow),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: AppColors.gold.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total HT', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 13)),
              Text(fmtFcfa(_total), style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 15)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRow(int i) {
    final r = _rows[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 44,
            child: TextField(
              controller: r.qte,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(color: context.textPrimary, fontSize: 13),
              decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10)),
              onChanged: (_) => _notify(),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: r.desc,
              style: TextStyle(color: context.textPrimary, fontSize: 13),
              decoration: const InputDecoration(hintText: 'Description', contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
              onChanged: (_) => _notify(),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 78,
            child: TextField(
              controller: r.prix,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(color: context.textPrimary, fontSize: 13),
              decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10)),
              onChanged: (_) => _notify(),
            ),
          ),
          SizedBox(
            width: 32,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.close, size: 17, color: AppColors.textFaint),
              onPressed: _rows.length > 1 ? () => _removeRow(i) : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Formulaire de création d'un devis — client, objet, validité (jours),
/// TVA 18% (appliquée automatiquement à la conversion en facture), et les
/// lignes du document. Mirroir de `_open_devis_form` côté ordinateur.
/// Le dépôt `DevisRepository` n'offre pas de mise à jour générale (seulement
/// `create`, `updateStatut`, `delete`, `convertirEnFacture`) — ce formulaire
/// ne sert donc qu'à la création, jamais à la modification d'un devis
/// existant (voir le rapport de fin de tâche pour ce manque côté dépôt).
class DevisFormSheet extends StatefulWidget {
  final List<Client> clients;
  final VoidCallback onSaved;
  const DevisFormSheet({super.key, required this.clients, required this.onSaved});

  @override
  State<DevisFormSheet> createState() => _DevisFormSheetState();
}

class _DevisFormSheetState extends State<DevisFormSheet> {
  final _repo = DevisRepository();
  final _objetCtrl = TextEditingController();
  final _validiteCtrl = TextEditingController(text: '30');
  final _linesKey = GlobalKey<LigneItemsEditorState>();
  int? _clientId;
  bool _appliquerTva = true;
  bool _saving = false;
  double _total = 0;

  @override
  void initState() {
    super.initState();
    if (widget.clients.isNotEmpty) _clientId = widget.clients.first.id;
  }

  @override
  void dispose() {
    _objetCtrl.dispose();
    _validiteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_clientId == null) {
      showFormError(context, 'Choisis un client avant d\'enregistrer.');
      return;
    }
    final lignes = _linesKey.currentState?.validLines() ?? [];
    if (lignes.isEmpty) {
      showFormError(context, 'Ajoute au moins une ligne avec une description.');
      return;
    }
    final validite = int.tryParse(_validiteCtrl.text.trim()) ?? 30;
    setState(() => _saving = true);
    try {
      await _repo.create(
        clientId: _clientId!,
        objet: _objetCtrl.text.trim(),
        validiteJours: validite,
        appliquerTva: _appliquerTva,
        lignes: lignes,
      );
      if (!mounted) return;
      widget.onSaved();
    } catch (_) {
      if (mounted) showFormError(context, 'Impossible d\'enregistrer ce devis.');
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
        Text('Objet', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(controller: _objetCtrl, decoration: const InputDecoration(hintText: 'Ex : Fourniture et pose de fenêtres aluminium')),
        const SizedBox(height: 14),
        Text('Validité (jours)', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(controller: _validiteCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration()),
        const SizedBox(height: 10),
        Row(
          children: [
            Switch(value: _appliquerTva, activeColor: AppColors.gold, onChanged: (v) => setState(() => _appliquerTva = v)),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _appliquerTva = !_appliquerTva),
                child: Text(
                  'Appliquer la TVA (18%) — reprise automatiquement lors de la conversion en facture',
                  style: TextStyle(color: context.textMuted, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('Lignes du document', style: TextStyle(color: AppColors.gold, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        LigneItemsEditor(key: _linesKey, onTotalChanged: (t) => setState(() => _total = t)),
        const SizedBox(height: 20),
        GoldButton(label: _saving ? 'Enregistrement…' : 'Enregistrer le devis', onPressed: _saving ? () {} : _save),
      ],
    );
  }
}
