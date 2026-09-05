import 'package:flutter/material.dart';
import '../data/repository.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

/// Module Sourcing — équivalent de SourcingView côté ordinateur
/// (modules/sourcing.py) : achat de marchandise chez un fournisseur pour
/// la revente à un client, avec calcul automatique de la marge
/// ((prix vente - prix achat) x quantité). Liste + formulaire ajout/
/// modification en feuille de fond + changement de statut rapide.
const List<String> statutsSourcing = ['En cours', 'Livré', 'Annulé'];

String fmtQuantite(double q) => q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toString();

const List<String> _moisAbbrSourcing = [
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
];

String fmtDateCourte(DateTime d) => '${d.day.toString().padLeft(2, '0')} ${_moisAbbrSourcing[d.month - 1]} ${d.year}';

class SourcingScreen extends StatefulWidget {
  const SourcingScreen({super.key});

  @override
  State<SourcingScreen> createState() => _SourcingScreenState();
}

class _SourcingScreenState extends State<SourcingScreen> {
  final _repo = SourcingRepository();
  final _fournisseurRepo = FournisseurRepository();
  final _clientRepo = ClientRepository();

  List<SourcingCommande> _commandes = [];
  List<Fournisseur> _fournisseurs = [];
  List<Client> _clients = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final commandes = await _repo.all();
    final fournisseurs = await _fournisseurRepo.all();
    final clients = await _clientRepo.all();
    if (!mounted) return;
    setState(() {
      _commandes = commandes;
      _fournisseurs = fournisseurs;
      _clients = clients;
      _loading = false;
    });
  }

  String? _fournisseurNom(int? id) {
    if (id == null) return null;
    for (final f in _fournisseurs) {
      if (f.id == id) return f.nom;
    }
    return null;
  }

  String? _clientNom(int? id) {
    if (id == null) return null;
    for (final c in _clients) {
      if (c.id == id) return c.nom;
    }
    return null;
  }

  void _openAdd() async {
    await showAppBottomSheet(
      context,
      title: 'Nouvelle commande de sourcing',
      child: _SourcingForm(
        fournisseurs: _fournisseurs,
        clients: _clients,
        onSaved: () {
          Navigator.of(context).pop();
          _load();
        },
      ),
    );
  }

  void _openEdit(SourcingCommande s) async {
    await showAppBottomSheet(
      context,
      title: 'Modifier la commande',
      child: _SourcingForm(
        fournisseurs: _fournisseurs,
        clients: _clients,
        existing: s,
        onSaved: () {
          Navigator.of(context).pop();
          _load();
        },
      ),
    );
  }

  void _openDetail(SourcingCommande s) async {
    await showAppBottomSheet(
      context,
      title: s.numero,
      child: _SourcingDetail(
        commande: s,
        fournisseurNom: _fournisseurNom(s.fournisseurId),
        clientNom: _clientNom(s.clientId),
        onEdit: () {
          Navigator.of(context).pop();
          _openEdit(s);
        },
        onStatutChange: (statut) async {
          await _repo.updateStatut(s.id, statut);
          if (!mounted) return;
          Navigator.of(context).pop();
          _load();
        },
        onDelete: () async {
          final confirme = await confirmDelete(
            context,
            nom: '${s.numero} — ${s.designation}',
            typeElement: 'cette commande de sourcing',
          );
          if (!confirme) return;
          await _repo.delete(s);
          if (!mounted) return;
          Navigator.of(context).pop();
          _load();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalAchat = _commandes.fold<double>(0, (s, c) => s + c.totalAchat);
    final totalVente = _commandes.fold<double>(0, (s, c) => s + c.totalVente);
    final marge = totalVente - totalAchat;

    return Scaffold(
      appBar: AppBar(title: const Text('Sourcing')),
      floatingActionButton: FabRound(onPressed: _openAdd),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
            : RefreshIndicator(
                onRefresh: _load,
                color: AppColors.gold,
                child: _commandes.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 80),
                          EmptyState(
                            icon: Icons.local_shipping_outlined,
                            text: "Aucune commande de sourcing pour le moment.\nAppuie sur + pour commencer.",
                          ),
                        ],
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                        children: [
                          Text(
                            'Achat fournisseur → revente client, marge calculée automatiquement.',
                            style: TextStyle(color: context.textMuted, fontSize: 12.5),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(child: _totalCard(context, 'TOTAL ACHATS', totalAchat, context.textPrimary)),
                              const SizedBox(width: 10),
                              Expanded(child: _totalCard(context, 'TOTAL VENTES', totalVente, AppColors.info)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _totalCard(
                                  context,
                                  'MARGE TOTALE',
                                  marge,
                                  marge >= 0 ? AppColors.success : AppColors.danger,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          for (final s in _commandes) ...[
                            _SourcingRow(
                              commande: s,
                              fournisseurNom: _fournisseurNom(s.fournisseurId),
                              clientNom: _clientNom(s.clientId),
                              onTap: () => _openDetail(s),
                            ),
                            const SizedBox(height: 10),
                          ],
                        ],
                      ),
              ),
      ),
    );
  }

  Widget _totalCard(BuildContext context, String label, double value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: context.textFaint, fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.6),
          ),
          const SizedBox(height: 4),
          Text(fmtFcfaCompact(value), style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }
}

class _SourcingRow extends StatelessWidget {
  final SourcingCommande commande;
  final String? fournisseurNom;
  final String? clientNom;
  final VoidCallback onTap;

  const _SourcingRow({required this.commande, required this.fournisseurNom, required this.clientNom, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = commande;
    return AppCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: AppColors.surfaceHover, borderRadius: BorderRadius.circular(6)),
            child: Text(
              s.numero,
              style: const TextStyle(color: AppColors.gold, fontSize: 10.5, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.designation.isEmpty ? '—' : s.designation,
                  style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '${fournisseurNom ?? "?"} → ${clientNom ?? "?"} · marge ${fmtFcfa(s.marge)}',
                  style: TextStyle(color: context.textFaint, fontSize: 11.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatutBadge(statut: s.statut),
        ],
      ),
    );
  }
}

class _SourcingDetail extends StatelessWidget {
  final SourcingCommande commande;
  final String? fournisseurNom;
  final String? clientNom;
  final VoidCallback onEdit;
  final void Function(String statut) onStatutChange;
  final VoidCallback onDelete;

  const _SourcingDetail({
    required this.commande,
    required this.fournisseurNom,
    required this.clientNom,
    required this.onEdit,
    required this.onStatutChange,
    required this.onDelete,
  });

  Widget _infoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: context.textMuted, fontSize: 12.5)),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              style: TextStyle(color: context.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = commande;
    final livraison = (s.dateLivraisonPrevue != null && s.dateLivraisonPrevue!.length >= 10)
        ? s.dateLivraisonPrevue!.substring(0, 10)
        : '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.designation.isEmpty ? '—' : s.designation,
          style: TextStyle(color: context.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        StatutBadge(statut: s.statut),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(color: AppColors.surfaceHover, borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              _infoRow(context, 'Fournisseur', fournisseurNom ?? '—'),
              _infoRow(context, 'Client', clientNom ?? '—'),
              _infoRow(context, 'Quantité', fmtQuantite(s.quantite)),
              _infoRow(context, 'Prix achat unit.', fmtFcfa(s.prixAchatUnitaire)),
              _infoRow(context, 'Prix vente unit.', fmtFcfa(s.prixVenteUnitaire)),
              _infoRow(context, 'Livraison prévue', livraison),
            ],
          ),
        ),
        if (s.notes.trim().isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('Notes', style: TextStyle(color: context.textMuted, fontSize: 12)),
          const SizedBox(height: 4),
          Text(s.notes, style: TextStyle(color: context.textPrimary, fontSize: 13)),
        ],
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: s.marge >= 0 ? AppColors.success : AppColors.danger,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              const Text('MARGE TOTALE', style: TextStyle(color: AppColors.background, fontSize: 11, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                fmtFcfa(s.marge),
                style: const TextStyle(color: AppColors.background, fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text('Changer le statut', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final st in statutsSourcing)
              ChoiceChip(
                label: Text(st),
                selected: s.statut == st,
                onSelected: (_) {
                  if (s.statut != st) onStatutChange(st);
                },
                selectedColor: AppColors.gold,
                backgroundColor: context.cardBg,
                labelStyle: TextStyle(
                  color: s.statut == st ? Colors.black : context.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                side: BorderSide(color: context.cardBorder),
              ),
          ],
        ),
        const SizedBox(height: 18),
        GhostButton(label: 'Modifier cette commande', onPressed: onEdit),
        const SizedBox(height: 10),
        TextButton(
          onPressed: onDelete,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.danger,
            padding: EdgeInsets.zero,
            alignment: Alignment.centerLeft,
          ),
          child: const Text('Supprimer cette commande', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

class _SourcingForm extends StatefulWidget {
  final List<Fournisseur> fournisseurs;
  final List<Client> clients;
  final SourcingCommande? existing;
  final VoidCallback onSaved;

  const _SourcingForm({required this.fournisseurs, required this.clients, this.existing, required this.onSaved});

  @override
  State<_SourcingForm> createState() => _SourcingFormState();
}

class _SourcingFormState extends State<_SourcingForm> {
  final _repo = SourcingRepository();
  final _designationCtrl = TextEditingController();
  final _quantiteCtrl = TextEditingController(text: '1');
  final _prixAchatCtrl = TextEditingController(text: '0');
  final _prixVenteCtrl = TextEditingController(text: '0');
  final _notesCtrl = TextEditingController();

  int? _fournisseurId;
  int? _clientId;
  String _statut = 'En cours';
  DateTime? _dateLivraison;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    if (s != null) {
      _designationCtrl.text = s.designation;
      _quantiteCtrl.text = fmtQuantite(s.quantite);
      _prixAchatCtrl.text = fmtQuantite(s.prixAchatUnitaire);
      _prixVenteCtrl.text = fmtQuantite(s.prixVenteUnitaire);
      _notesCtrl.text = s.notes;
      _fournisseurId = s.fournisseurId;
      _clientId = s.clientId;
      _statut = s.statut;
      if (s.dateLivraisonPrevue != null && s.dateLivraisonPrevue!.isNotEmpty) {
        _dateLivraison = DateTime.tryParse(s.dateLivraisonPrevue!);
      }
    }
  }

  @override
  void dispose() {
    _designationCtrl.dispose();
    _quantiteCtrl.dispose();
    _prixAchatCtrl.dispose();
    _prixVenteCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateLivraison ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null) setState(() => _dateLivraison = picked);
  }

  Future<void> _save() async {
    final designation = _designationCtrl.text.trim();
    if (designation.isEmpty) {
      showFormError(context, "Indique la désignation avant d'enregistrer.");
      return;
    }
    final quantite = double.tryParse(_quantiteCtrl.text.trim().replaceAll(',', '.'));
    final prixAchat = double.tryParse(_prixAchatCtrl.text.trim().replaceAll(',', '.'));
    final prixVente = double.tryParse(_prixVenteCtrl.text.trim().replaceAll(',', '.'));
    if (quantite == null || quantite <= 0) {
      showFormError(context, 'Indique une quantité valide (supérieure à zéro).');
      return;
    }
    if (prixAchat == null || prixAchat < 0 || prixVente == null || prixVente < 0) {
      showFormError(context, "Indique des prix d'achat et de vente valides.");
      return;
    }

    setState(() => _saving = true);
    final dateLivraisonStr = _dateLivraison?.toIso8601String();
    try {
      if (widget.existing != null) {
        final e = widget.existing!;
        final updated = SourcingCommande(
          id: e.id,
          syncId: e.syncId,
          numero: e.numero,
          dateCommande: e.dateCommande,
          fournisseurId: _fournisseurId,
          clientId: _clientId,
          designation: designation,
          quantite: quantite,
          prixAchatUnitaire: prixAchat,
          prixVenteUnitaire: prixVente,
          statut: _statut,
          dateLivraisonPrevue: dateLivraisonStr,
          notes: _notesCtrl.text.trim(),
          updatedAt: e.updatedAt,
        );
        await _repo.update(updated);
      } else {
        await _repo.create(
          fournisseurId: _fournisseurId,
          clientId: _clientId,
          designation: designation,
          quantite: quantite,
          prixAchatUnitaire: prixAchat,
          prixVenteUnitaire: prixVente,
          dateLivraisonPrevue: dateLivraisonStr,
          notes: _notesCtrl.text.trim(),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Désignation *', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: _designationCtrl,
          decoration: const InputDecoration(hintText: 'Ex : Profilés aluminium 6m'),
        ),
        const SizedBox(height: 14),
        Text('Fournisseur (facultatif)', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        DropdownButtonFormField<int?>(
          value: _fournisseurId,
          dropdownColor: AppColors.surface,
          isExpanded: true,
          hint: Text('Aucun', style: TextStyle(color: context.textFaint)),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('Aucun')),
            for (final f in widget.fournisseurs)
              DropdownMenuItem<int?>(
                value: f.id,
                child: Text(f.nom, style: TextStyle(color: context.textPrimary), overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() => _fournisseurId = v),
        ),
        const SizedBox(height: 14),
        Text('Client (facultatif)', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        DropdownButtonFormField<int?>(
          value: _clientId,
          dropdownColor: AppColors.surface,
          isExpanded: true,
          hint: Text('Aucun', style: TextStyle(color: context.textFaint)),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('Aucun')),
            for (final c in widget.clients)
              DropdownMenuItem<int?>(
                value: c.id,
                child: Text(c.nom, style: TextStyle(color: context.textPrimary), overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() => _clientId = v),
        ),
        const SizedBox(height: 14),
        Text('Quantité', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: _quantiteCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Prix d'achat unit. (FCFA)", style: TextStyle(color: context.textMuted, fontSize: 12)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _prixAchatCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Prix de vente unit. (FCFA)', style: TextStyle(color: context.textMuted, fontSize: 12)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _prixVenteCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text('Livraison prévue (facultatif)', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        InkWell(
          onTap: _pickDate,
          child: InputDecorator(
            decoration: InputDecoration(
              suffixIcon: Icon(Icons.calendar_today_outlined, size: 16, color: context.textFaint),
              suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            child: Text(
              _dateLivraison != null ? fmtDateCourte(_dateLivraison!) : 'Choisir une date',
              style: TextStyle(color: _dateLivraison != null ? context.textPrimary : context.textFaint),
            ),
          ),
        ),
        if (widget.existing != null) ...[
          const SizedBox(height: 14),
          Text('Statut', style: TextStyle(color: context.textMuted, fontSize: 12)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _statut,
            dropdownColor: AppColors.surface,
            items: [
              for (final st in statutsSourcing) DropdownMenuItem(value: st, child: Text(st, style: TextStyle(color: context.textPrimary))),
            ],
            onChanged: (v) => setState(() => _statut = v ?? 'En cours'),
          ),
        ],
        const SizedBox(height: 14),
        Text('Notes (facultatif)', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: _notesCtrl,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Notes internes…'),
        ),
        const SizedBox(height: 20),
        GoldButton(label: _saving ? 'Enregistrement…' : 'Enregistrer', onPressed: _saving ? () {} : _save),
      ],
    );
  }
}
