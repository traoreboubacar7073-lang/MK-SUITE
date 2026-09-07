import 'package:flutter/material.dart';
import '../data/repository.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import 'client_detail_screen.dart';
import 'devis_detail_screen.dart';
import 'facture_detail_screen.dart';
import 'recu_form_sheet.dart';
import 'fournisseurs_screen.dart';
import 'employes_screen.dart';
import 'sourcing_screen.dart';
import 'depenses_screen.dart';

/// Recherche globale — cherche en même temps parmi les clients, devis,
/// factures, reçus, fournisseurs, employés, commandes sourcing et
/// dépenses. Pendant, côté téléphone, de la recherche globale de la
/// version ordinateur (modules/recherche_globale.py) : un résultat touché
/// ouvre directement la fiche correspondante plutôt que de simplement
/// filtrer une liste.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  List<Client> _clients = [];
  List<Devis> _devis = [];
  List<Facture> _factures = [];
  List<Recu> _recus = [];
  List<Fournisseur> _fournisseurs = [];
  List<Employe> _employes = [];
  List<SourcingCommande> _sourcing = [];
  List<Depense> _depenses = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadAll();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  Future<void> _loadAll() async {
    final clients = await ClientRepository().all();
    final devis = await DevisRepository().all();
    final factures = await FactureRepository().all();
    final recus = await RecuRepository().all();
    final fournisseurs = await FournisseurRepository().all();
    final employes = await EmployeRepository().all();
    final sourcing = await SourcingRepository().all();
    final depenses = await DepenseRepository().all();
    if (!mounted) return;
    setState(() {
      _clients = clients;
      _devis = devis;
      _factures = factures;
      _recus = recus;
      _fournisseurs = fournisseurs;
      _employes = employes;
      _sourcing = sourcing;
      _depenses = depenses;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Client? _clientFor(int? id) {
    if (id == null) return null;
    for (final c in _clients) {
      if (c.id == id) return c;
    }
    return null;
  }

  String get _q => _query.toLowerCase();

  List<Client> get _clientResults => _q.isEmpty
      ? []
      : _clients.where((c) => c.nom.toLowerCase().contains(_q) || c.telephone.toLowerCase().contains(_q) || c.code.toLowerCase().contains(_q)).take(6).toList();

  List<Devis> get _devisResults => _q.isEmpty
      ? []
      : _devis.where((d) => d.numero.toLowerCase().contains(_q) || d.objet.toLowerCase().contains(_q) || (_clientFor(d.clientId)?.nom.toLowerCase().contains(_q) ?? false)).take(6).toList();

  List<Facture> get _factureResults => _q.isEmpty
      ? []
      : _factures.where((f) => f.numero.toLowerCase().contains(_q) || f.description.toLowerCase().contains(_q) || (_clientFor(f.clientId)?.nom.toLowerCase().contains(_q) ?? false)).take(6).toList();

  List<Recu> get _recuResults => _q.isEmpty
      ? []
      : _recus.where((r) => r.numero.toLowerCase().contains(_q) || r.motif.toLowerCase().contains(_q) || (_clientFor(r.clientId)?.nom.toLowerCase().contains(_q) ?? false)).take(6).toList();

  List<Fournisseur> get _fournisseurResults =>
      _q.isEmpty ? [] : _fournisseurs.where((f) => f.nom.toLowerCase().contains(_q) || f.categorieProduits.toLowerCase().contains(_q)).take(6).toList();

  List<Employe> get _employeResults =>
      _q.isEmpty ? [] : _employes.where((e) => e.nom.toLowerCase().contains(_q) || e.poste.toLowerCase().contains(_q)).take(6).toList();

  List<SourcingCommande> get _sourcingResults =>
      _q.isEmpty ? [] : _sourcing.where((s) => s.numero.toLowerCase().contains(_q) || s.designation.toLowerCase().contains(_q)).take(6).toList();

  List<Depense> get _depenseResults => _q.isEmpty
      ? []
      : _depenses.where((d) => d.categorie.toLowerCase().contains(_q) || d.beneficiaire.toLowerCase().contains(_q) || d.description.toLowerCase().contains(_q)).take(6).toList();

  Future<void> _openClient(Client c) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ClientDetailScreen(clientId: c.id)));
  }

  Future<void> _openDevis(Devis d) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => DevisDetailScreen(devis: d, client: _clientFor(d.clientId))));
  }

  Future<void> _openFacture(Facture f) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => FactureDetailScreen(facture: f, client: _clientFor(f.clientId))));
  }

  Future<void> _openRecu(Recu r) async {
    await showAppBottomSheet(
      context,
      title: r.numero,
      child: RecuDetailSheet(recu: r, client: _clientFor(r.clientId), onDeleted: () => Navigator.of(context).pop()),
    );
  }

  void _openFournisseurs() => Navigator.push(context, MaterialPageRoute(builder: (_) => const FournisseursScreen()));
  void _openEmployes() => Navigator.push(context, MaterialPageRoute(builder: (_) => const EmployesScreen()));
  void _openSourcing() => Navigator.push(context, MaterialPageRoute(builder: (_) => const SourcingScreen()));
  void _openDepenses() => Navigator.push(context, MaterialPageRoute(builder: (_) => const DepensesScreen()));

  @override
  Widget build(BuildContext context) {
    final totalResults = _clientResults.length +
        _devisResults.length +
        _factureResults.length +
        _recuResults.length +
        _fournisseurResults.length +
        _employeResults.length +
        _sourcingResults.length +
        _depenseResults.length;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            style: TextStyle(color: context.textPrimary, fontSize: 15),
            decoration: const InputDecoration(
              hintText: 'Client, devis, facture, reçu…',
              prefixIcon: Icon(Icons.search, size: 20),
              contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 14),
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : _query.isEmpty
              ? const EmptyState(icon: Icons.search, text: 'Recherche dans tous les modules :\nclients, devis, factures, reçus…')
              : totalResults == 0
                  ? EmptyState(icon: Icons.search_off, text: 'Aucun résultat pour « $_query ».')
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (_clientResults.isNotEmpty)
                          ..._section(context, 'Clients', Icons.people_outline, [
                            for (final c in _clientResults)
                              _ResultTile(title: c.nom, subtitle: c.telephone.isEmpty ? 'Sans téléphone' : c.telephone, onTap: () => _openClient(c)),
                          ]),
                        if (_devisResults.isNotEmpty)
                          ..._section(context, 'Devis', Icons.description_outlined, [
                            for (final d in _devisResults)
                              _ResultTile(
                                title: '${d.numero} — ${_clientFor(d.clientId)?.nom ?? "Client non renseigné"}',
                                subtitle: fmtFcfa(d.montantHt),
                                trailing: StatutBadge(statut: d.statut),
                                onTap: () => _openDevis(d),
                              ),
                          ]),
                        if (_factureResults.isNotEmpty)
                          ..._section(context, 'Factures', Icons.receipt_long_outlined, [
                            for (final f in _factureResults)
                              _ResultTile(
                                title: '${f.numero} — ${_clientFor(f.clientId)?.nom ?? "Client non renseigné"}',
                                subtitle: fmtFcfa(f.montantTtc),
                                trailing: StatutBadge(statut: f.statut),
                                onTap: () => _openFacture(f),
                              ),
                          ]),
                        if (_recuResults.isNotEmpty)
                          ..._section(context, 'Reçus', Icons.receipt_outlined, [
                            for (final r in _recuResults)
                              _ResultTile(
                                title: '${r.numero} — ${_clientFor(r.clientId)?.nom ?? "Client non renseigné"}',
                                subtitle: fmtFcfa(r.montantRecu),
                                onTap: () => _openRecu(r),
                              ),
                          ]),
                        if (_fournisseurResults.isNotEmpty)
                          ..._section(context, 'Fournisseurs', Icons.factory_outlined, [
                            for (final f in _fournisseurResults)
                              _ResultTile(title: f.nom, subtitle: f.categorieProduits.isEmpty ? '—' : f.categorieProduits, onTap: _openFournisseurs),
                          ]),
                        if (_employeResults.isNotEmpty)
                          ..._section(context, 'Employés', Icons.badge_outlined, [
                            for (final e in _employeResults) _ResultTile(title: e.nom, subtitle: e.poste.isEmpty ? '—' : e.poste, onTap: _openEmployes),
                          ]),
                        if (_sourcingResults.isNotEmpty)
                          ..._section(context, 'Sourcing', Icons.local_shipping_outlined, [
                            for (final s in _sourcingResults) _ResultTile(title: s.numero, subtitle: s.designation, onTap: _openSourcing),
                          ]),
                        if (_depenseResults.isNotEmpty)
                          ..._section(context, 'Dépenses', Icons.account_balance_wallet_outlined, [
                            for (final d in _depenseResults)
                              _ResultTile(
                                title: d.categorie.isEmpty ? 'Dépense' : d.categorie,
                                subtitle: d.beneficiaire.isEmpty ? d.description : d.beneficiaire,
                                trailing: Text(fmtFcfa(d.montant), style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700, fontSize: 12.5)),
                                onTap: _openDepenses,
                              ),
                          ]),
                      ],
                    ),
    );
  }

  List<Widget> _section(BuildContext context, String label, IconData icon, List<Widget> tiles) {
    return [
      Row(
        children: [
          Icon(icon, size: 14, color: AppColors.gold),
          const SizedBox(width: 6),
          Text(label.toUpperCase(), style: const TextStyle(color: AppColors.gold, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
        ],
      ),
      const SizedBox(height: 8),
      ...tiles.map((t) => Padding(padding: const EdgeInsets.only(bottom: 8), child: t)),
      const SizedBox(height: 12),
    ];
  }
}

class _ResultTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback onTap;
  const _ResultTile({required this.title, required this.subtitle, this.trailing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w500, fontSize: 14), overflow: TextOverflow.ellipsis),
                Text(subtitle, style: TextStyle(color: context.textFaint, fontSize: 12), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
