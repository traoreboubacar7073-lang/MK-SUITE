import 'package:flutter/material.dart';
import '../data/repository.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

/// Icône + couleur + libellé par `module` — repris des mêmes couleurs que le
/// tiroir de navigation (main_shell.dart, `drawerItems`) pour qu'un élément
/// de la corbeille se reconnaisse d'un coup d'œil. `devis`, `factures`,
/// `recus` et `notes` n'ont pas chacun leur propre entrée de tiroir (ils
/// vivent tous sous "Devis & Factures" / "Clients" côté ordinateur) : on leur
/// donne quand même une icône distincte tout en gardant la couleur de leur
/// module parent.
class _ModuleInfo {
  final String label;
  final IconData icon;
  final Color color;
  const _ModuleInfo(this.label, this.icon, this.color);
}

const Map<String, _ModuleInfo> _moduleInfo = {
  'clients': _ModuleInfo('Clients', Icons.people_outline, AppColors.info),
  'notes': _ModuleInfo('Notes client', Icons.sticky_note_2_outlined, AppColors.info),
  'devis': _ModuleInfo('Devis', Icons.description_outlined, AppColors.gold),
  'factures': _ModuleInfo('Factures', Icons.receipt_long_outlined, AppColors.gold),
  'recus': _ModuleInfo('Reçus', Icons.receipt_outlined, AppColors.gold),
  'sourcing': _ModuleInfo('Sourcing', Icons.local_shipping_outlined, AppColors.teal),
  'depenses': _ModuleInfo('Dépenses', Icons.account_balance_wallet_outlined, AppColors.danger),
  'fournisseurs': _ModuleInfo('Fournisseurs', Icons.factory_outlined, AppColors.purple),
  'employes': _ModuleInfo('Employés', Icons.badge_outlined, AppColors.pink),
  'vitres': _ModuleInfo('Calcul Vitres', Icons.crop_square_outlined, AppColors.indigo),
};

_ModuleInfo _infoFor(String module) =>
    _moduleInfo[module] ?? _ModuleInfo(module.isEmpty ? 'Autre' : module, Icons.delete_outline, AppColors.textFaint);

/// "il y a X jours" à partir de `date_suppression` — retombe sur `deletedAt`
/// (epoch ms) si jamais la date ISO ne se parse pas.
DateTime _deletedDate(CorbeilleItem item) {
  return DateTime.tryParse(item.dateSuppression) ?? DateTime.fromMillisecondsSinceEpoch(item.deletedAt);
}

String _relativeLabel(DateTime deleted) {
  final jours = DateTime.now().difference(deleted).inDays;
  if (jours <= 0) return "aujourd'hui";
  if (jours == 1) return 'hier';
  return 'il y a $jours jours';
}

class CorbeilleScreen extends StatefulWidget {
  const CorbeilleScreen({super.key});

  @override
  State<CorbeilleScreen> createState() => _CorbeilleScreenState();
}

class _CorbeilleScreenState extends State<CorbeilleScreen> {
  final _repo = CorbeilleRepository();
  List<CorbeilleItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await _repo.all();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _restore(CorbeilleItem item) async {
    await _repo.restore(item.id);
    if (!mounted) return;
    showFormSuccess(context, '« ${item.libelle} » a été restauré.');
    _load();
  }

  Future<void> _deleteForever(CorbeilleItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Supprimer définitivement ?', style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: Text(
          '« ${item.libelle} » sera effacé pour toujours, sans aucune possibilité de récupération.',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler', style: TextStyle(color: AppColors.textMuted))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer définitivement', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repo.deleteForever(item.id);
    if (!mounted) return;
    showFormSuccess(context, '« ${item.libelle} » a été supprimé définitivement.');
    _load();
  }

  /// Regroupe par module en conservant l'ordre d'apparition — `_items` est
  /// déjà trié par date de suppression décroissante (voir CorbeilleRepository.all),
  /// donc le premier élément rencontré pour un module donne au groupe entier
  /// sa place (le module le plus récemment touché apparaît en premier).
  Map<String, List<CorbeilleItem>> get _grouped {
    final map = <String, List<CorbeilleItem>>{};
    for (final item in _items) {
      map.putIfAbsent(item.module, () => []).add(item);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped;

    return Scaffold(
      appBar: AppBar(title: const Text('Corbeille')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
            : _items.isEmpty
                ? const EmptyState(icon: Icons.delete_outline, text: 'La corbeille est vide.')
                : RefreshIndicator(
                    color: AppColors.gold,
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: context.cardBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: context.cardBorder),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline, size: 18, color: context.textFaint),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Tout élément supprimé reste ici 30 jours avant d\'être effacé pour de bon. '
                                  'Tu peux le restaurer à tout moment.',
                                  style: TextStyle(color: context.textMuted, fontSize: 12, height: 1.35),
                                ),
                              ),
                            ],
                          ),
                        ),
                        for (final entry in grouped.entries) ...[
                          _GroupHeader(module: entry.key, count: entry.value.length),
                          const SizedBox(height: 8),
                          for (final item in entry.value) ...[
                            _CorbeilleCard(
                              item: item,
                              onRestore: () => _restore(item),
                              onDeleteForever: () => _deleteForever(item),
                            ),
                            const SizedBox(height: 10),
                          ],
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String module;
  final int count;
  const _GroupHeader({required this.module, required this.count});

  @override
  Widget build(BuildContext context) {
    final info = _infoFor(module);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          IconBadge(icon: info.icon, color: info.color, size: 28),
          const SizedBox(width: 10),
          Text(info.label.toUpperCase(),
              style: const TextStyle(color: AppColors.gold, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          const SizedBox(width: 6),
          Text('($count)', style: TextStyle(color: context.textFaint, fontSize: 11.5)),
        ],
      ),
    );
  }
}

class _CorbeilleCard extends StatelessWidget {
  final CorbeilleItem item;
  final VoidCallback onRestore;
  final VoidCallback onDeleteForever;

  const _CorbeilleCard({required this.item, required this.onRestore, required this.onDeleteForever});

  @override
  Widget build(BuildContext context) {
    final deleted = _deletedDate(item);
    final joursDepuis = DateTime.now().difference(deleted).inDays;
    final joursRestants = (30 - joursDepuis).clamp(0, 30);
    final urgent = joursRestants <= 5;
    final delaiTexte = joursRestants == 0
        ? 'sera supprimée automatiquement aujourd\'hui'
        : 'sera supprimée automatiquement dans $joursRestants jour${joursRestants > 1 ? 's' : ''}';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.libelle.isEmpty ? 'Élément sans nom' : item.libelle,
            style: TextStyle(color: context.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text('Supprimé ${_relativeLabel(deleted)}', style: TextStyle(color: context.textMuted, fontSize: 12)),
          const SizedBox(height: 2),
          Text(
            delaiTexte,
            style: TextStyle(color: urgent ? AppColors.danger : context.textFaint, fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onRestore,
                icon: const Icon(Icons.restore, size: 17, color: AppColors.success),
                label: const Text('Restaurer', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600, fontSize: 12.5)),
              ),
              TextButton.icon(
                onPressed: onDeleteForever,
                icon: const Icon(Icons.delete_forever_outlined, size: 17, color: AppColors.danger),
                label: const Text('Supprimer', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600, fontSize: 12.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
