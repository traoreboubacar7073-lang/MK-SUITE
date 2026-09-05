import 'package:flutter/material.dart';
import '../data/repository.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

/// Formulaire d'ajout / modification d'un client — utilisé dans une
/// showAppBottomSheet depuis la liste des clients ou depuis la fiche
/// détail. Reprend les mêmes champs que le formulaire de la version
/// ordinateur (ui.clients.ClientsView.open_form) : nom, téléphone,
/// adresse, NIF, type de client, statut.
class ClientFormSheet extends StatefulWidget {
  final Client? existing;
  final VoidCallback onSaved;
  const ClientFormSheet({super.key, this.existing, required this.onSaved});

  @override
  State<ClientFormSheet> createState() => _ClientFormSheetState();
}

class _ClientFormSheetState extends State<ClientFormSheet> {
  final _repo = ClientRepository();
  final _nomCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _adresseCtrl = TextEditingController();
  final _nifCtrl = TextEditingController();
  late String _typeClient;
  late String _statut;
  bool _saving = false;

  static const _typeOptions = ['Particulier', 'Entreprise', 'Chantier'];

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _nomCtrl.text = c?.nom ?? '';
    _telCtrl.text = c?.telephone ?? '';
    _adresseCtrl.text = c?.adresse ?? '';
    _nifCtrl.text = c?.nif ?? '';
    _typeClient = c?.typeClient ?? 'Particulier';
    _statut = c?.statut ?? 'Actif';
  }

  @override
  void dispose() {
    _nomCtrl.dispose();
    _telCtrl.dispose();
    _adresseCtrl.dispose();
    _nifCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nom = _nomCtrl.text.trim();
    if (nom.isEmpty) {
      showFormError(context, 'Indique le nom (ou la raison sociale) du client.');
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.existing != null) {
        final updated = widget.existing!.copyWith(
          nom: nom,
          typeClient: _typeClient,
          telephone: _telCtrl.text.trim(),
          adresse: _adresseCtrl.text.trim(),
          nif: _nifCtrl.text.trim(),
          statut: _statut,
        );
        await _repo.update(updated);
      } else {
        final created = await _repo.create(
          nom: nom,
          typeClient: _typeClient,
          telephone: _telCtrl.text.trim(),
          adresse: _adresseCtrl.text.trim(),
          nif: _nifCtrl.text.trim(),
        );
        // create() force toujours le statut "Actif" — si l'utilisateur a
        // choisi "Inactif" dès la création, on l'applique juste après.
        if (_statut != 'Actif') {
          await _repo.update(created.copyWith(statut: _statut));
        }
      }
      if (!mounted) return;
      widget.onSaved();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Nom complet / Raison sociale *', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(controller: _nomCtrl, decoration: const InputDecoration(hintText: 'Ex : Amadou Traoré')),
        const SizedBox(height: 14),
        Text('Téléphone', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(controller: _telCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(hintText: '+223 …')),
        const SizedBox(height: 14),
        Text('Adresse', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(controller: _adresseCtrl, decoration: const InputDecoration(hintText: 'Quartier, ville…')),
        const SizedBox(height: 14),
        Text("NIF (Numéro d'Identification Fiscale)", style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(controller: _nifCtrl, decoration: const InputDecoration(hintText: 'Facultatif')),
        const SizedBox(height: 14),
        Text('Type de client', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        CatalogPickerField(
          options: _typeOptions,
          initialValue: _typeClient,
          hintText: 'Choisir le type…',
          onChanged: (v) => setState(() => _typeClient = (v == null || v.isEmpty) ? 'Particulier' : v),
        ),
        const SizedBox(height: 14),
        Text('Statut', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _statut,
          dropdownColor: AppColors.surface,
          decoration: const InputDecoration(),
          items: const [
            DropdownMenuItem(value: 'Actif', child: Text('Actif', style: TextStyle(color: AppColors.textPrimary))),
            DropdownMenuItem(value: 'Inactif', child: Text('Inactif', style: TextStyle(color: AppColors.textPrimary))),
          ],
          onChanged: (v) => setState(() => _statut = v ?? 'Actif'),
        ),
        const SizedBox(height: 22),
        GoldButton(
          label: _saving ? 'Enregistrement…' : (widget.existing != null ? 'Enregistrer les modifications' : 'Enregistrer'),
          onPressed: _saving ? () {} : _save,
        ),
      ],
    );
  }
}
