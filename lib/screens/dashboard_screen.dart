import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../data/repository.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import 'clients_screen.dart';
import 'devis_factures_screen.dart';
import 'sourcing_screen.dart';
import 'depenses_screen.dart';
import 'vitres_screen.dart';
import 'budget_screen.dart';
import 'fournisseurs_screen.dart';
import 'employes_screen.dart';
import 'corbeille_screen.dart';

/// Tableau de bord — mirroir fidèle de modules/dashboard.py côté ordinateur :
/// 4 indicateurs clés du mois, évolution du chiffre d'affaires sur 6 mois
/// et activité récente (dernières factures / derniers clients). Les
/// alertes intelligentes (factures en retard, devis qui expirent bientôt)
/// sont affichées via la cloche de notifications de la barre du haut
/// (voir main_shell.dart / services/notifications_service.dart), pas ici.
/// La sauvegarde manuelle de la base ("Sauvegarder mes données") est
/// reprise elle aussi, adaptée au mobile : au lieu d'un dialogue
/// "Enregistrer sous" façon bureau, on ouvre la feuille de partage native
/// du téléphone (vers Drive, WhatsApp, l'app Fichiers...).
const List<String> _joursSemaine = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const List<String> _moisNoms = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];
const List<String> _moisAbrev = ['Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Jun', 'Jul', 'Aoû', 'Sep', 'Oct', 'Nov', 'Déc'];

String _moisKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

class _Activite {
  final IconData icon;
  final Color color;
  final String titre;
  final String sousTitre;
  final VoidCallback onTap;
  const _Activite({required this.icon, required this.color, required this.titre, required this.sousTitre, required this.onTap});
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  List<Client> _clients = [];
  List<Facture> _factures = [];
  List<Depense> _depenses = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final clients = await ClientRepository().all();
    final factures = await FactureRepository().all();
    final depenses = await DepenseRepository().all();
    if (!mounted) return;
    setState(() {
      _clients = clients;
      _factures = factures;
      _depenses = depenses;
      _loading = false;
    });
  }

  // Recharge les chiffres au retour d'un écran poussé depuis le tableau de
  // bord (nouveau client créé, facture encaissée...) pour qu'ils restent à
  // jour sans action supplémentaire de l'utilisateur.
  void _push(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen)).then((_) => _load());
  }

  String get _dateFr {
    final now = DateTime.now();
    final jour = _joursSemaine[now.weekday - 1];
    final mois = _moisNoms[now.month - 1];
    return '$jour ${now.day.toString().padLeft(2, '0')} $mois ${now.year}';
  }

  double get _caMois {
    final key = _moisKey(DateTime.now());
    return _factures.where((f) => f.dateFacture.startsWith(key)).fold<double>(0, (s, f) => s + f.montantTtc);
  }

  double get _depensesMois {
    final key = _moisKey(DateTime.now());
    return _depenses.where((d) => d.dateDepense.startsWith(key)).fold<double>(0, (s, d) => s + d.montant);
  }

  double get _facturesImpayees => _factures.where((f) => f.statut != 'Payée').fold<double>(0, (s, f) => s + f.resteAPayer);

  int get _nbClients => _clients.length;

  /// Activité récente — dernières factures puis derniers clients, comme
  /// _build_activity_feed() côté ordinateur (les deux listes étant déjà
  /// triées par id décroissant par le dépôt de données).
  List<_Activite> _buildActivites() {
    final activites = <_Activite>[];
    for (final f in _factures.take(4)) {
      activites.add(_Activite(
        icon: Icons.description_outlined,
        color: AppColors.gold,
        titre: 'Facture ${f.numero}',
        sousTitre: fmtFcfa(f.montantTtc),
        onTap: () => _push(const DevisFacturesScreen()),
      ));
    }
    for (final c in _clients.take(3)) {
      activites.add(_Activite(
        icon: Icons.person_add_alt_1_outlined,
        color: AppColors.info,
        titre: 'Nouveau client',
        sousTitre: c.nom,
        onTap: () => _push(const ClientsScreen()),
      ));
    }
    return activites.take(6).toList();
  }

  /// Chiffre d'affaires facturé (montant TTC) des 6 derniers mois, y
  /// compris le mois en cours — même logique que _build_chart() côté
  /// ordinateur (mais calculée par mois calendaire exact plutôt que par
  /// pas de 30 jours, pour éviter les décalages).
  List<MapEntry<String, double>> _revenus6Mois() {
    final now = DateTime.now();
    final result = <MapEntry<String, double>>[];
    for (int i = 5; i >= 0; i--) {
      int mois = now.month - i;
      int annee = now.year;
      while (mois <= 0) {
        mois += 12;
        annee -= 1;
      }
      final key = '${annee.toString().padLeft(4, '0')}-${mois.toString().padLeft(2, '0')}';
      final total = _factures.where((f) => f.dateFacture.startsWith(key)).fold<double>(0, (s, f) => s + f.montantTtc);
      result.add(MapEntry(_moisAbrev[mois - 1], total));
    }
    return result;
  }

  Future<void> _backupData() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dbPath = p.join(dir.path, 'mk_entreprise.db');
      if (!await File(dbPath).exists()) {
        if (mounted) showFormError(context, 'Aucune base de données trouvée à sauvegarder.');
        return;
      }
      final now = DateTime.now();
      final nomFichier =
          'MK_Suite_Sauvegarde_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.db';
      await Share.shareXFiles(
        [XFile(dbPath, name: nomFichier)],
        subject: 'Sauvegarde MK Suite',
        text: 'Sauvegarde de la base de données MK Suite — à conserver sur une clé USB, Google Drive...',
      );
    } catch (e) {
      if (mounted) showFormError(context, 'Échec de la sauvegarde : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.gold));
    }

    final activites = _buildActivites();
    final revenus = _revenus6Mois();

    return RefreshIndicator(
      color: AppColors.gold,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          ScreenHeader(
            eyebrow: 'MK Entreprise',
            title: 'Tableau de bord',
            action: _BackupButton(onTap: _backupData),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Text('Bienvenue • $_dateFr', style: TextStyle(color: context.textMuted, fontSize: 12.5)),
          ),

          // ---- Indicateurs clés ----
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.3,
            children: [
              _KpiCard(
                icon: Icons.payments_outlined,
                color: AppColors.gold,
                value: fmtFcfaCompact(_caMois),
                label: "Chiffre d'affaires",
                sousLabel: 'Factures émises ce mois',
                onTap: () => _push(const DevisFacturesScreen()),
              ),
              _KpiCard(
                icon: Icons.trending_down_rounded,
                color: AppColors.danger,
                value: fmtFcfaCompact(_depensesMois),
                label: 'Dépenses',
                sousLabel: 'Total des sorties (mois)',
                onTap: () => _push(const DepensesScreen()),
              ),
              _KpiCard(
                icon: Icons.warning_amber_rounded,
                color: AppColors.warning,
                value: fmtFcfaCompact(_facturesImpayees),
                label: 'Factures impayées',
                sousLabel: 'À recouvrer',
                onTap: () => _push(const DevisFacturesScreen()),
              ),
              _KpiCard(
                icon: Icons.people_alt_outlined,
                color: AppColors.info,
                value: '$_nbClients',
                label: 'Clients actifs',
                sousLabel: 'Base client totale',
                onTap: () => _push(const ClientsScreen()),
              ),
            ],
          ),

          const SizedBox(height: 22),
          _SectionTitle(
            title: "Évolution du chiffre d'affaires",
            onVoirTout: () => _push(const DevisFacturesScreen()),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('6 derniers mois', style: TextStyle(color: context.textFaint, fontSize: 11)),
                const SizedBox(height: 14),
                _CaChart(data: revenus),
              ],
            ),
          ),

          const SizedBox(height: 22),
          _SectionTitle(title: 'Activité récente', onVoirTout: () => _push(const DevisFacturesScreen())),
          const SizedBox(height: 12),
          if (activites.isEmpty)
            const AppCard(
              child: EmptyState(
                icon: Icons.inbox_outlined,
                text: 'Aucune activité pour le moment.\nCommence par ajouter un client ou créer un devis.',
              ),
            )
          else
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(
                children: [
                  for (int i = 0; i < activites.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: context.cardBorder),
                    _ActiviteRow(activite: activites[i]),
                  ],
                ],
              ),
            ),

          const SizedBox(height: 22),
          Text('Accès rapides', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.78,
            children: [
              _AccesRapideTile(icon: Icons.people_outline, label: 'Clients', color: AppColors.info, onTap: () => _push(const ClientsScreen())),
              _AccesRapideTile(icon: Icons.description_outlined, label: 'Devis &\nFactures', color: AppColors.gold, onTap: () => _push(const DevisFacturesScreen())),
              _AccesRapideTile(icon: Icons.local_shipping_outlined, label: 'Sourcing', color: AppColors.teal, onTap: () => _push(const SourcingScreen())),
              _AccesRapideTile(icon: Icons.account_balance_wallet_outlined, label: 'Dépenses', color: AppColors.danger, onTap: () => _push(const DepensesScreen())),
              _AccesRapideTile(icon: Icons.crop_square_outlined, label: 'Calcul\nVitres', color: AppColors.indigo, onTap: () => _push(const VitresScreen())),
              _AccesRapideTile(icon: Icons.bar_chart_rounded, label: 'Contrôle\nBudget', color: AppColors.success, onTap: () => _push(const BudgetScreen())),
              _AccesRapideTile(icon: Icons.factory_outlined, label: 'Fournisseurs', color: AppColors.purple, onTap: () => _push(const FournisseursScreen())),
              _AccesRapideTile(icon: Icons.badge_outlined, label: 'Employés /\nPaie', color: AppColors.pink, onTap: () => _push(const EmployesScreen())),
              _AccesRapideTile(icon: Icons.delete_outline, label: 'Corbeille', color: AppColors.textFaint, onTap: () => _push(const CorbeilleScreen())),
            ],
          ),
        ],
      ),
    );
  }
}

class _BackupButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackupButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.cardBorder),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.backup_outlined, size: 16, color: AppColors.gold),
            SizedBox(width: 6),
            Text('Sauvegarder', style: TextStyle(color: AppColors.gold, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final String sousLabel;
  final VoidCallback onTap;
  const _KpiCard({
    required this.icon, required this.color, required this.value,
    required this.label, required this.sousLabel, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              IconBadge(icon: icon, color: color, size: 32),
              const Spacer(),
              Icon(Icons.chevron_right, size: 16, color: context.textFaint),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(color: context.textPrimary, fontSize: 16.5, fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(color: context.textMuted, fontSize: 11.5, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(sousLabel, style: TextStyle(color: context.textFaint, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final VoidCallback onVoirTout;
  const _SectionTitle({required this.title, required this.onVoirTout});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(title, style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
        ),
        GestureDetector(
          onTap: onVoirTout,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Voir tout', style: TextStyle(color: AppColors.gold, fontSize: 12.5, fontWeight: FontWeight.w600)),
              Icon(Icons.chevron_right, color: AppColors.gold, size: 16),
            ],
          ),
        ),
      ],
    );
  }
}


class _ActiviteRow extends StatelessWidget {
  final _Activite activite;
  const _ActiviteRow({required this.activite});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: activite.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: activite.color.withOpacity(0.16), shape: BoxShape.circle),
              child: Icon(activite.icon, size: 15, color: activite.color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(activite.titre, style: TextStyle(color: context.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(activite.sousTitre, style: TextStyle(color: context.textMuted, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: context.textFaint),
          ],
        ),
      ),
    );
  }
}

/// Petit graphique en barres — équivalent mobile-friendly du graphique
/// matplotlib de la version ordinateur (_build_chart), sans dépendance de
/// tracé supplémentaire.
class _CaChart extends StatelessWidget {
  final List<MapEntry<String, double>> data;
  const _CaChart({required this.data});

  double _barHeight(double value, double maxVal) {
    if (maxVal <= 0) return 4.0;
    final h = 4.0 + (value / maxVal * 84.0);
    return h.clamp(4.0, 88.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final maxVal = data.map((e) => e.value).fold<double>(0, (a, b) => b > a ? b : a);
    return SizedBox(
      height: 130,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final e in data)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      height: _barHeight(e.value, maxVal),
                      decoration: BoxDecoration(
                        gradient: e.value > 0 ? AppColors.goldGradient : null,
                        color: e.value > 0 ? null : context.cardBorder,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(e.key, style: TextStyle(color: context.textFaint, fontSize: 10.5)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AccesRapideTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _AccesRapideTile({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.cardBorder),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, size: 17, color: color),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.textPrimary, fontSize: 10.5, fontWeight: FontWeight.w500, height: 1.2),
            ),
          ],
        ),
      ),
    );
  }
}
