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
  DrawerItem('Sourcing', Icons.local_shipping_outlined, AppColors.teal, (_) => const SourcingScreen()),
  DrawerItem('Dépenses', Icons.account_balance_wallet_outlined, AppColors.danger, (_) => const DepensesScreen()),
  DrawerItem('Calcul Vitres', Icons.crop_square_outlined, AppColors.indigo, (_) => const VitresScreen()),
  DrawerItem('Contrôle Budget', Icons.bar_chart_rounded, AppColors.success, (_) => const BudgetScreen()),
  DrawerItem('Fournisseurs', Icons.factory_outlined, AppColors.purple, (_) => const FournisseursScreen()),
  DrawerItem('Employés / Paie', Icons.badge_outlined, AppColors.pink, (_) => const EmployesScreen()),
  DrawerItem('Corbeille', Icons.delete_outline, AppColors.textFaint, (_) => const CorbeilleScreen()),
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
