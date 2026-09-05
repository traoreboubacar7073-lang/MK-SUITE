import 'package:flutter/material.dart';
import '../data/repository.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import 'client_form_sheet.dart';

/// Fiche détail d'un client — équivalent du panneau de droite de
/// ClientsView.show_detail() côté ordinateur : coordonnées, statistiques
/// (devis / factures / total facturé / encaissé / solde dû calculées
/// depuis les factures) et les notes rattachées au client.
class ClientDetailScreen extends StatefulWidget {
  final int clientId;
  const ClientDetailScreen({super.key, required this.clientId});

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  final _clientRepo = ClientRepository();
  final _noteRepo = NoteClientRepository();

  Client? _client;
  List<NoteClient> _notes = [];
  int _nbDevis = 0;
  int _nbFactures = 0;
  double _totalTtc = 0;
  double _totalEncaisse = 0;
  double _solde = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final client = await _clientRepo.byId(widget.clientId);
    final allNotes = await _noteRepo.all();
    final allDevis = await DevisRepository().all();
    final allFactures = await FactureRepository().all();

    final notes = allNotes.where((n) => n.clientId == widget.clientId).toList()
      ..sort((a, b) => b.dateNote.compareTo(a.dateNote));
    final devisClient = allDevis.where((d) => d.clientId == widget.clientId);
    final facturesClient = allFactures.where((f) => f.clientId == widget.clientId);

    double ttc = 0, encaisse = 0, solde = 0;
    var nbFactures = 0;
    for (final f in facturesClient) {
      ttc += f.montantTtc;
      encaisse += f.avanceRecue;
      solde += f.resteAPayer;
      nbFactures++;
    }

    if (!mounted) return;
    setState(() {
      _client = client;
      _notes = notes;
      _nbDevis = devisClient.length;
      _nbFactures = nbFactures;
      _totalTtc = ttc;
      _totalEncaisse = encaisse;
      _solde = solde;
      _loading = false;
    });
  }

  void _openEdit() async {
    final client = _client;
    if (client == null) return;
    await showAppBottomSheet(
      context,
      title: 'Modifier le client',
      child: ClientFormSheet(
        existing: client,
        onSaved: () {
          Navigator.of(context).pop();
          _load();
        },
      ),
    );
  }

  Future<void> _delete() async {
    final client = _client;
    if (client == null) return;
    final confirme = await confirmDelete(context, nom: client.nom, typeElement: 'ce client');
    if (!confirme) return;
    await _clientRepo.delete(client);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _openNoteForm({NoteClient? existing}) async {
    final client = _client;
    if (client == null) return;
    await showAppBottomSheet(
      context,
      title: existing != null ? 'Modifier la note' : 'Nouvelle note',
      child: _NoteForm(
        clientId: client.id,
        existing: existing,
        onSaved: () {
          Navigator.of(context).pop();
          _load();
        },
      ),
    );
  }

  Future<void> _deleteNote(NoteClient note) async {
    final confirme = await confirmDelete(context, nom: note.objet.isEmpty ? 'cette note' : note.objet, typeElement: 'cette note');
    if (!confirme) return;
    await _noteRepo.delete(note);
    if (!mounted) return;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final client = _client;
    return Scaffold(
      appBar: AppBar(
        title: Text(client?.nom ?? 'Client'),
        actions: [
          if (client != null) IconButton(onPressed: _openEdit, icon: const Icon(Icons.edit_outlined)),
        ],
      ),
      floatingActionButton: client == null ? null : FabRound(onPressed: () => _openNoteForm(), icon: Icons.note_add_outlined),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : client == null
              ? const EmptyState(icon: Icons.error_outline, text: 'Ce client est introuvable (peut-être supprimé).')
              : RefreshIndicator(
                  color: AppColors.gold,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      Center(
                        child: Column(
                          children: [
                            AppAvatar(name: client.nom, size: 64),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(999)),
                              child: Text(client.code.isEmpty ? '—' : client.code,
                                  style: const TextStyle(color: AppColors.background, fontWeight: FontWeight.w700, fontSize: 12)),
                            ),
                            const SizedBox(height: 8),
                            Text(client.nom, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 18), textAlign: TextAlign.center),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: _InfoBadge(text: client.typeClient, color: AppColors.info)),
                                Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: StatutBadge(statut: client.statut)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _FieldRow(label: 'Téléphone', value: client.telephone.isEmpty ? '—' : client.telephone, icon: Icons.phone_outlined),
                      _FieldRow(label: 'Adresse', value: client.adresse.isEmpty ? '—' : client.adresse, icon: Icons.location_on_outlined),
                      _FieldRow(label: 'NIF', value: client.nif.isEmpty ? '—' : client.nif, icon: Icons.badge_outlined),
                      _FieldRow(
                        label: '1er contact',
                        value: client.datePremierContact.isEmpty ? '—' : client.datePremierContact.split('T').first,
                        icon: Icons.calendar_today_outlined,
                      ),
                      const SizedBox(height: 20),
                      Text('ACTIVITÉ', style: TextStyle(color: AppColors.gold, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                      const SizedBox(height: 10),
                      AppCard(
                        child: Column(
                          children: [
                            _StatLine(label: 'Devis', value: '$_nbDevis'),
                            _StatLine(label: 'Factures', value: '$_nbFactures'),
                            _StatLine(label: 'Total facturé TTC', value: fmtFcfa(_totalTtc)),
                            _StatLine(label: 'Total encaissé', value: fmtFcfa(_totalEncaisse)),
                            _StatLine(label: 'Solde dû', value: fmtFcfa(_solde), highlight: _solde > 0),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('NOTES', style: TextStyle(color: AppColors.gold, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                          Text('${_notes.length}', style: TextStyle(color: context.textFaint, fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_notes.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text('Aucune note pour ce client. Touche le bouton + pour en ajouter une.',
                              style: TextStyle(color: context.textFaint, fontSize: 13)),
                        )
                      else
                        ...[
                          for (final n in _notes) ...[
                            AppCard(
                              onTap: () => _openNoteForm(existing: n),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(n.objet.isEmpty ? '(sans objet)' : n.objet,
                                            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                                      ),
                                      InkWell(
                                        onTap: () => _deleteNote(n),
                                        child: const Padding(
                                          padding: EdgeInsets.all(2),
                                          child: Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (n.contenu.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(n.contenu, style: TextStyle(color: context.textMuted, fontSize: 13), maxLines: 4, overflow: TextOverflow.ellipsis),
                                  ],
                                  const SizedBox(height: 8),
                                  Text(
                                    [
                                      if (n.dateNote.isNotEmpty) n.dateNote.split('T').first,
                                      if (n.redigePar.isNotEmpty) n.redigePar,
                                    ].join(' · '),
                                    style: TextStyle(color: context.textFaint, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                        ],
                      const SizedBox(height: 28),
                      TextButton(
                        onPressed: _delete,
                        style: TextButton.styleFrom(foregroundColor: AppColors.danger, padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                        child: const Text('Supprimer ce client', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  final String text;
  final Color color;
  const _InfoBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(text, style: TextStyle(color: context.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _FieldRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _FieldRow({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: context.textFaint),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: context.textFaint, fontSize: 11)),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(color: context.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatLine extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _StatLine({required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: context.textMuted, fontSize: 12.5)),
          Text(value, style: TextStyle(color: highlight ? AppColors.danger : context.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Formulaire d'ajout / modification d'une note client (objet, contenu,
/// rédigé par) — équivalent de devis_factures.py `_open_note_form`.
class _NoteForm extends StatefulWidget {
  final int clientId;
  final NoteClient? existing;
  final VoidCallback onSaved;
  const _NoteForm({required this.clientId, this.existing, required this.onSaved});

  @override
  State<_NoteForm> createState() => _NoteFormState();
}

class _NoteFormState extends State<_NoteForm> {
  final _repo = NoteClientRepository();
  final _objetCtrl = TextEditingController();
  final _contenuCtrl = TextEditingController();
  final _redigeParCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final n = widget.existing;
    _objetCtrl.text = n?.objet ?? '';
    _contenuCtrl.text = n?.contenu ?? '';
    _redigeParCtrl.text = n?.redigePar ?? '';
  }

  @override
  void dispose() {
    _objetCtrl.dispose();
    _contenuCtrl.dispose();
    _redigeParCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final objet = _objetCtrl.text.trim();
    if (objet.isEmpty) {
      showFormError(context, "Indique l'objet de la note.");
      return;
    }
    setState(() => _saving = true);
    try {
      // La création de note ne supporte pas la modification — pour une
      // note existante on la supprime puis on recrée avec les nouvelles
      // valeurs (NoteClientRepository n'expose pas de update()).
      if (widget.existing != null) {
        await _repo.delete(widget.existing!);
      }
      await _repo.create(
        clientId: widget.clientId,
        objet: objet,
        contenu: _contenuCtrl.text.trim(),
        redigePar: _redigeParCtrl.text.trim(),
      );
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
        Text('Objet *', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(controller: _objetCtrl, decoration: const InputDecoration(hintText: 'Ex : Appel de suivi commande')),
        const SizedBox(height: 14),
        Text('Contenu', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(controller: _contenuCtrl, minLines: 3, maxLines: 6, decoration: const InputDecoration(hintText: 'Détails de la note…')),
        const SizedBox(height: 14),
        Text('Rédigé par', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(controller: _redigeParCtrl, decoration: const InputDecoration(hintText: 'Facultatif')),
        const SizedBox(height: 22),
        GoldButton(
          label: _saving ? 'Enregistrement…' : 'Enregistrer',
          onPressed: _saving ? () {} : _save,
        ),
      ],
    );
  }
}
