import 'package:flutter/material.dart';
import '../data/repository.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import 'devis_detail_screen.dart';
import 'devis_form_sheet.dart';
import 'facture_detail_screen.dart';
import 'recu_form_sheet.dart';

/// Module Devis & Factures — trois onglets (Devis / Factures / Reçus), un
/// miroir fidèle des règles métier de `modules/devis_factures.py` côté
/// ordinateur : création de devis avec lignes, conversion devis → facture,
/// encaissement de paiements (avec émission facultative d'un reçu), export
/// PDF (aperçu + partage) sur chaque type de document.
///
/// Écran racine du module (poussé par main_shell.dart) : possède son propre
/// Scaffold, avec un bouton flottant unique pour créer un nouveau devis — la
/// couche de données ne permettant pas de créer une facture sans passer par
/// un devis (voir le rapport de fin de tâche), et les reçus indépendants se
/// créant depuis l'onglet Reçus.
class DevisFacturesScreen extends StatefulWidget {
  const DevisFacturesScreen({super.key});

  @override
  State<DevisFacturesScreen> createState() => _DevisFacturesScreenState();
}

class _DevisFacturesScreenState extends State<DevisFacturesScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _devisRepo = DevisRepository();
  final _factureRepo = FactureRepository();
  final _recuRepo = RecuRepository();
  final _clientRepo = ClientRepository();

  List<Devis> _devis = [];
  List<Facture> _factures = [];
  List<Recu> _recus = [];
  List<Client> _clients = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final devis = await _devisRepo.all();
    final factures = await _factureRepo.all();
    final recus = await _recuRepo.all();
    final clients = await _clientRepo.all();
    if (!mounted) return;
    setState(() {
      _devis = devis;
      _factures = factures;
      _recus = recus;
      _clients = clients;
      _loading = false;
    });
  }

  Client? _clientFor(int? id) {
    if (id == null) return null;
    for (final c in _clients) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> _openNewDevis() async {
    await showAppBottomSheet(
      context,
      title: 'Nouveau devis',
      child: DevisFormSheet(
        clients: _clients,
        onSaved: () {
          Navigator.of(context).pop();
          _tabController.animateTo(0);
          _load();
        },
      ),
    );
  }

  Future<void> _openNewRecu() async {
    await showAppBottomSheet(
      context,
      title: 'Nouveau reçu',
      child: RecuFormSheet(
        clients: _clients,
        factures: _factures,
        onSaved: () {
          Navigator.of(context).pop();
          _load();
        },
      ),
    );
  }

  Future<void> _openDevisDetail(Devis d) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => DevisDetailScreen(devis: d, client: _clientFor(d.clientId))));
    _load();
  }

  Future<void> _openFactureDetail(Facture f) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => FactureDetailScreen(facture: f, client: _clientFor(f.clientId))));
    _load();
  }

  Future<void> _openRecuDetail(Recu r) async {
    await showAppBottomSheet(
      context,
      title: r.numero,
      child: RecuDetailSheet(
        recu: r,
        client: _clientFor(r.clientId),
        onDeleted: () {
          Navigator.of(context).pop();
          _load();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Devis & Factures'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.gold,
          labelColor: AppColors.gold,
          unselectedLabelColor: AppColors.textMuted,
          tabs: const [Tab(text: 'Devis'), Tab(text: 'Factures'), Tab(text: 'Reçus')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : TabBarView(
              controller: _tabController,
              children: [
                _DevisTab(devis: _devis, clientFor: _clientFor, onTap: _openDevisDetail),
                _FacturesTab(factures: _factures, clientFor: _clientFor, onTap: _openFactureDetail),
                _RecusTab(recus: _recus, clientFor: _clientFor, onTap: _openRecuDetail, onAdd: _openNewRecu),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openNewDevis,
        backgroundColor: AppColors.gold,
        tooltip: 'Nouveau devis',
        child: const Icon(Icons.add, color: Colors.black),
      ),
    );
  }
}

/// Petite barre de recherche partagée entre les onglets Devis et Factures —
/// filtre côté client sur le numéro et le nom de client, comme la recherche
/// du desktop.
class _SearchField extends StatelessWidget {
  final ValueChanged<String> onChanged;
  final String hint;
  const _SearchField({required this.onChanged, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        onChanged: onChanged,
        style: TextStyle(color: context.textPrimary, fontSize: 13.5),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.textFaint),
          hintText: hint,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

class _DevisTab extends StatefulWidget {
  final List<Devis> devis;
  final Client? Function(int?) clientFor;
  final ValueChanged<Devis> onTap;
  const _DevisTab({required this.devis, required this.clientFor, required this.onTap});

  @override
  State<_DevisTab> createState() => _DevisTabState();
}

class _DevisTabState extends State<_DevisTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final rows = q.isEmpty
        ? widget.devis
        : widget.devis.where((d) {
            final client = widget.clientFor(d.clientId);
            return d.numero.toLowerCase().contains(q) || (client?.nom.toLowerCase().contains(q) ?? false);
          }).toList();

    return Column(
      children: [
        _SearchField(hint: 'Rechercher un numéro, un client…', onChanged: (v) => setState(() => _query = v)),
        Expanded(
          child: rows.isEmpty
              ? const EmptyState(icon: Icons.description_outlined, text: 'Aucun devis trouvé.')
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final d = rows[i];
                    final client = widget.clientFor(d.clientId);
                    return AppCard(
                      onTap: () => widget.onTap(d),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(d.numero, style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 13)),
                                    const SizedBox(height: 2),
                                    Text(client?.nom ?? 'Client non renseigné', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w500, fontSize: 14), overflow: TextOverflow.ellipsis),
                                    if (d.objet.isNotEmpty) Text(d.objet, style: TextStyle(color: context.textFaint, fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                              StatutBadge(statut: d.statut),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(d.dateDevis.split('T').first, style: TextStyle(color: context.textFaint, fontSize: 11)),
                              Text(fmtFcfa(d.montantHt), style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 14)),
                            ],
                          ),
                          if (d.convertiFacture != null) ...[
                            const SizedBox(height: 4),
                            Text('✓ Converti en ${d.convertiFacture}', style: const TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.w600)),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _FacturesTab extends StatefulWidget {
  final List<Facture> factures;
  final Client? Function(int?) clientFor;
  final ValueChanged<Facture> onTap;
  const _FacturesTab({required this.factures, required this.clientFor, required this.onTap});

  @override
  State<_FacturesTab> createState() => _FacturesTabState();
}

class _FacturesTabState extends State<_FacturesTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final rows = q.isEmpty
        ? widget.factures
        : widget.factures.where((f) {
            final client = widget.clientFor(f.clientId);
            return f.numero.toLowerCase().contains(q) || (client?.nom.toLowerCase().contains(q) ?? false);
          }).toList();

    return Column(
      children: [
        _SearchField(hint: 'Rechercher un numéro, un client…', onChanged: (v) => setState(() => _query = v)),
        if (widget.factures.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text(
              'Les factures se créent en convertissant un devis « Accepté » (bouton « Convertir en facture » sur sa fiche).',
              style: TextStyle(color: context.textFaint, fontSize: 11.5),
              textAlign: TextAlign.center,
            ),
          ),
        Expanded(
          child: rows.isEmpty
              ? const EmptyState(icon: Icons.receipt_long_outlined, text: 'Aucune facture trouvée.')
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final f = rows[i];
                    final client = widget.clientFor(f.clientId);
                    return AppCard(
                      onTap: () => widget.onTap(f),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(f.numero, style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 13)),
                                    const SizedBox(height: 2),
                                    Text(client?.nom ?? 'Client non renseigné', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w500, fontSize: 14), overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                              StatutBadge(statut: f.statut),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(f.dateFacture.split('T').first, style: TextStyle(color: context.textFaint, fontSize: 11)),
                              Text(fmtFcfa(f.montantTtc), style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 14)),
                            ],
                          ),
                          if (f.resteAPayer > 0) ...[
                            const SizedBox(height: 4),
                            Text('Reste à payer : ${fmtFcfa(f.resteAPayer)}', style: const TextStyle(color: AppColors.danger, fontSize: 11.5, fontWeight: FontWeight.w600)),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _RecusTab extends StatefulWidget {
  final List<Recu> recus;
  final Client? Function(int?) clientFor;
  final ValueChanged<Recu> onTap;
  final VoidCallback onAdd;
  const _RecusTab({required this.recus, required this.clientFor, required this.onTap, required this.onAdd});

  @override
  State<_RecusTab> createState() => _RecusTabState();
}

class _RecusTabState extends State<_RecusTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final rows = q.isEmpty
        ? widget.recus
        : widget.recus.where((r) {
            final client = widget.clientFor(r.clientId);
            return r.numero.toLowerCase().contains(q) || (client?.nom.toLowerCase().contains(q) ?? false);
          }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  style: TextStyle(color: context.textPrimary, fontSize: 13.5),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search, size: 20, color: AppColors.textFaint),
                    hintText: 'Rechercher un numéro, un client…',
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: widget.onAdd,
                tooltip: 'Nouveau reçu',
                icon: const Icon(Icons.add_circle, color: AppColors.gold, size: 28),
              ),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? const EmptyState(icon: Icons.receipt_outlined, text: 'Aucun reçu trouvé.')
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final r = rows[i];
                    final client = widget.clientFor(r.clientId);
                    return AppCard(
                      onTap: () => widget.onTap(r),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.numero, style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 13)),
                                const SizedBox(height: 2),
                                Text(client?.nom ?? 'Client non renseigné', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w500, fontSize: 14), overflow: TextOverflow.ellipsis),
                                Text(
                                  r.factureNumero != null ? '${r.motif.isEmpty ? "Paiement" : r.motif} · ${r.factureNumero}' : (r.motif.isEmpty ? '—' : r.motif),
                                  style: TextStyle(color: context.textFaint, fontSize: 11.5),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Text(fmtFcfa(r.montantRecu), style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 14)),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
