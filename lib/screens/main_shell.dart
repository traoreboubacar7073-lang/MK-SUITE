import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import 'dashboard_screen.dart';
import 'clients_screen.dart';
import 'devis_factures_screen.dart';
import 'sourcing_screen.dart';
import 'depenses_screen.dart';
import 'vitres_screen.dart';
import 'budget_screen.dart';
import 'fournisseurs_screen.dart';
import 'employes_screen.dart';
import 'corbeille_screen.dart';
import 'sync_screen.dart';
import 'rappels_screen.dart';
import 'sauvegarde_screen.dart';
import 'search_screen.dart';
import '../services/notifications_service.dart';

class DrawerItem {
  final String label;
  final IconData icon;
  final Color color;
  final WidgetBuilder builder;
  const DrawerItem(this.label, this.icon, this.color, this.builder);
}

/// Liste complète des modules — même contenu et même ordre que la barre
/// latérale de la version ordinateur (NAV_ITEMS dans main.py), plus
/// "Synchronisation" qui n'existe que sur mobile.
final List<DrawerItem> drawerItems = [
  DrawerItem('Clients', Icons.people_outline, AppColors.info, (_) => const ClientsScreen()),
  DrawerItem('Devis & Factures', Icons.description_outlined, AppColors.gold, (_) => const DevisFacturesScreen()),
  DrawerItem('Rappels impayés', Icons.notifications_active_outlined, AppColors.danger, (_) => const RappelsScreen()),
  DrawerItem('Sourcing', Icons.local_shipping_outlined, AppColors.teal, (_) => const SourcingScreen()),
  DrawerItem('Dépenses', Icons.account_balance_wallet_outlined, AppColors.danger, (_) => const DepensesScreen()),
  DrawerItem('Calcul Vitres', Icons.crop_square_outlined, AppColors.indigo, (_) => const VitresScreen()),
  DrawerItem('Contrôle Budget', Icons.bar_chart_rounded, AppColors.success, (_) => const BudgetScreen()),
  DrawerItem('Fournisseurs', Icons.factory_outlined, AppColors.purple, (_) => const FournisseursScreen()),
  DrawerItem('Employés / Paie', Icons.badge_outlined, AppColors.pink, (_) => const EmployesScreen()),
  DrawerItem('Corbeille', Icons.delete_outline, AppColors.textFaint, (_) => const CorbeilleScreen()),
  DrawerItem('Sauvegarde', Icons.backup_outlined, AppColors.success, (_) => const SauvegardeScreen()),
];

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  // La synchronisation étant la fonctionnalité la plus nouvelle et la plus
  // utile à retrouver vite, elle a sa propre icône dans la barre du haut en
  // plus de sa place dans le menu — pas besoin d'ouvrir le tiroir pour y
  // accéder.
  void _openSync() => Navigator.push(context, MaterialPageRoute(builder: (_) => const SyncScreen()));

  // Même logique : la recherche globale est la fonctionnalité la plus
  // utilisée au quotidien (retrouver un client/devis/facture sans se
  // souvenir du module), donc sa propre icône dans la barre du haut plutôt
  // que seulement dans le tiroir.
  void _openSearch() => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()));

  void _openDrawerItem(DrawerItem item) {
    Navigator.pop(context); // ferme le tiroir
    Navigator.push(context, MaterialPageRoute(builder: item.builder));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _AppDrawer(onSelect: _openDrawerItem, onSync: _openSync),
      appBar: AppBar(
        leadingWidth: 44,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, size: 22),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Row(
          children: [
            Image.asset('assets/images/logo.png', width: 28, height: 28),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('MK SUITE', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.gold, letterSpacing: 0.6)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, size: 22),
            tooltip: 'Recherche globale',
            onPressed: _openSearch,
          ),
          const _NotificationBell(),
          IconButton(
            icon: const Icon(Icons.sync, size: 22),
            tooltip: 'Synchronisation',
            onPressed: _openSync,
          ),
        ],
      ),
      body: const SafeArea(child: DashboardScreen()),
    );
  }
}

class _AppDrawer extends StatelessWidget {
  final void Function(DrawerItem) onSelect;
  final VoidCallback onSync;
  const _AppDrawer({required this.onSelect, required this.onSync});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.sidebar,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                children: [
                  Image.asset('assets/images/logo.png', width: 42, height: 42),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('MK ENTREPRISE', style: TextStyle(color: AppColors.gold, fontSize: 14, fontWeight: FontWeight.w700)),
                        SizedBox(height: 2),
                        Text('ALUMINIUM · VOLET · INOX · ALU GOBONNE',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 9, letterSpacing: 0.8), maxLines: 2),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.border, height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _DrawerTile(
                    icon: Icons.home_outlined,
                    color: AppColors.gold,
                    label: 'Tableau de bord',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.popUntil(context, (route) => route.isFirst);
                    },
                  ),
                  for (final item in drawerItems)
                    _DrawerTile(icon: item.icon, color: item.color, label: item.label, onTap: () => onSelect(item)),
                  const Divider(color: AppColors.border, height: 20, indent: 20, endIndent: 20),
                  _DrawerTile(
                    icon: Icons.sync,
                    color: AppColors.info,
                    label: 'Synchronisation',
                    onTap: () {
                      Navigator.pop(context);
                      onSync();
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(color: AppColors.border, height: 1),
                  const SizedBox(height: 10),
                  Text('MK Entreprise', style: TextStyle(color: context.textMuted, fontSize: 11.5, fontWeight: FontWeight.w700)),
                  Text('Bamako, Mali', style: TextStyle(color: context.textFaint, fontSize: 10.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _DrawerTile({required this.icon, required this.color, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: IconBadge(icon: icon, color: color, size: 34),
      title: Text(label, style: TextStyle(color: context.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600)),
      onTap: onTap,
    );
  }
}

/// Cloche de notifications dans la barre du haut (façon Winner Style) :
/// remplace l'ancien encart "Alertes" du tableau de bord. Un badge affiche
/// le nombre d'alertes en cours ; un appui ouvre la liste dans une feuille
/// coulissante et permet d'aller directement au module concerné.
class _NotificationBell extends StatefulWidget {
  const _NotificationBell();

  @override
  State<_NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<_NotificationBell> {
  List<AlertItem> _alerts = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final alerts = await computeAlerts();
    if (!mounted) return;
    setState(() {
      _alerts = alerts;
      _loaded = true;
    });
  }

  void _openPanel() async {
    await _load();
    if (!mounted) return;
    await showAppBottomSheet(
      context,
      title: 'Notifications',
      child: _alerts.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('Rien à signaler pour le moment.', style: TextStyle(color: AppColors.textFaint, fontSize: 13)),
              ),
            )
          : Column(
              children: [
                for (final a in _alerts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const DevisFacturesScreen()));
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: context.cardBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: context.cardBorder),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(color: a.color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                              child: Icon(a.icon, size: 16, color: a.color),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(a.titre,
                                      style: TextStyle(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
                                      overflow: TextOverflow.ellipsis),
                                  Text(a.detail, style: TextStyle(color: context.textFaint, fontSize: 11.5), overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_none_rounded, size: 22),
          tooltip: 'Notifications',
          onPressed: _openPanel,
        ),
        if (_loaded && _alerts.isNotEmpty)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(999)),
              constraints: const BoxConstraints(minWidth: 16),
              child: Text('${_alerts.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
            ),
          ),
      ],
    );
  }
}
