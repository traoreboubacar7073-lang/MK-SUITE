import 'package:flutter/material.dart';
import '../data/repository.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import 'client_detail_screen.dart';
import 'client_form_sheet.dart';

/// Liste des clients — équivalent de ClientsView côté ordinateur : liste
/// recherchable (nom, téléphone, code) avec un filtre optionnel par type
/// de client, une fiche détail au tap, et un formulaire d'ajout/modification
/// en feuille de fond (bottom sheet).
class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final _repo = ClientRepository();
  List<Client> _clients = [];
  bool _loading = true;
  String _search = '';
  String _typeFiltre = 'Tous';

  static const _typeFiltres = ['Tous', 'Particulier', 'Entreprise', 'Chantier'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final clients = await _repo.all();
    if (!mounted) return;
    setState(() {
      _clients = clients;
      _loading = false;
    });
  }

  List<Client> get _filtered {
    var list = _clients;
    if (_typeFiltre != 'Tous') {
      list = list.where((c) => c.typeClient == _typeFiltre).toList();
    }
    if (_search.trim().isNotEmpty) {
      final q = _search.trim().toLowerCase();
      list = list
          .where((c) =>
              c.nom.toLowerCase().contains(q) ||
              c.telephone.toLowerCase().contains(q) ||
              c.code.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  void _openAddSheet() async {
    await showAppBottomSheet(
      context,
      title: 'Nouveau client',
      child: ClientFormSheet(
        onSaved: () {
          Navigator.of(context).pop();
          _load();
        },
      ),
    );
  }

  void _openDetail(Client client) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ClientDetailScreen(clientId: client.id)),
    );
    // Le client a pu être modifié ou supprimé depuis la fiche détail.
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      appBar: AppBar(title: const Text('Clients')),
      floatingActionButton: FabRound(onPressed: _openAddSheet),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Rechercher un client (nom, téléphone, code…)',
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _typeFiltres.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) {
                    final t = _typeFiltres[i];
                    final selected = t == _typeFiltre;
                    return ChoiceChip(
                      label: Text(t),
                      selected: selected,
                      onSelected: (_) => setState(() => _typeFiltre = t),
                      selectedColor: AppColors.gold,
                      backgroundColor: context.cardBg,
                      labelStyle: TextStyle(
                        color: selected ? AppColors.background : context.textMuted,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                      side: BorderSide(color: selected ? AppColors.gold : context.cardBorder),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
                    : filtered.isEmpty
                        ? EmptyState(
                            icon: Icons.people_outline,
                            text: _clients.isEmpty
                                ? "Aucun client pour le moment. Touche le bouton + pour créer le premier."
                                : "Aucun client ne correspond à ta recherche.",
                          )
                        : RefreshIndicator(
                            color: AppColors.gold,
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.only(bottom: 90),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (ctx, i) {
                                final c = filtered[i];
                                return AppCard(
                                  onTap: () => _openDetail(c),
                                  child: Row(
                                    children: [
                                      AppAvatar(name: c.nom),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    c.nom,
                                                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (c.code.isNotEmpty) ...[
                                                  const SizedBox(width: 6),
                                                  Text(c.code, style: TextStyle(color: context.textFaint, fontSize: 11)),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              c.telephone.isEmpty ? 'Sans téléphone' : c.telephone,
                                              style: TextStyle(color: context.textFaint, fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(c.typeClient, style: const TextStyle(color: AppColors.gold, fontSize: 11, fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 6),
                                          StatutBadge(statut: c.statut),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
