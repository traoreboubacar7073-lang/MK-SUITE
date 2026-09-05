import 'package:flutter/material.dart';
import '../data/repository.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

/// Module Contrôle Budget — reprend exactement la logique de la version
/// ordinateur (modules/budget.py) : pour chaque catégorie de dépense, on
/// compare le budget alloué (table budget_categories) aux dépenses réelles
/// du mois (table depenses) et on affiche l'écart, le % utilisé et une
/// alerte (OK / Attention / Dépassé), mois par mois.
///
/// IMPORTANT — convention des mois : `BudgetRepository._moisIndex` compare
/// en minuscules (`mois.toLowerCase()`), donc on stocke et on interroge
/// toujours avec des noms de mois français en minuscules ('janvier',
/// 'février', … 'décembre') pour que `forMoisAnnee` (comparaison exacte
/// `mois = ?`) et `depensesReellesParCategorie` restent cohérents.
const List<String> _moisNoms = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];

String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// Catégories de dépense de référence — identique à
/// ui/reference_lists.py::CATEGORIE_DEPENSE côté ordinateur.
const List<String> _categoriesReference = [
  "Matériaux (fer, alu, inox)",
  "Vitres / Verre",
  "Transport / Livraison",
  "Salaires / Main d'œuvre",
  "Loyer / Atelier",
  "Électricité / Eau",
  "Carburant",
  "Entretien matériel",
  "Communication / Téléphone",
  "Divers / Imprévus",
  "Accessoires",
  "Autres",
];

class _AlerteInfo {
  final String label;
  final Color color;
  const _AlerteInfo(this.label, this.color);
}

/// Même seuils que budget.py : pas de budget saisi → neutre ; < 80 % → OK ;
/// 80-100 % → Attention ; > 100 % → Dépassé.
_AlerteInfo _alerte(double budget, double pct) {
  if (budget <= 0 && pct == 0) return const _AlerteInfo('—', AppColors.textFaint);
  if (pct < 80) return const _AlerteInfo('OK', AppColors.success);
  if (pct <= 100) return const _AlerteInfo('Attention', AppColors.warning);
  return const _AlerteInfo('Dépassé', AppColors.danger);
}

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  final _budgetRepo = BudgetRepository();
  final _depenseRepo = DepenseRepository();

  int _moisIdx = DateTime.now().month - 1;
  int _annee = DateTime.now().year;
  bool _loading = true;

  Map<String, double> _budgetMap = {};
  Map<String, double> _reelMap = {};
  List<String> _categories = [..._categoriesReference];
  List<String> _categoriesConnues = [..._categoriesReference];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _moisCourant => _moisNoms[_moisIdx];

  Future<void> _load() async {
    setState(() => _loading = true);
    final mois = _moisCourant;
    final rows = await _budgetRepo.forMoisAnnee(mois, _annee);
    final reel = await _budgetRepo.depensesReellesParCategorie(mois, _annee);
    final toutesDepenses = await _depenseRepo.all();

    final budgetMap = {for (final r in rows) r.categorie: r.budgetPrevu};

    // Catégories affichées : la liste de référence + toute catégorie ayant
    // déjà un budget ou une dépense ce mois-ci (au cas où elle ne serait
    // pas dans la liste de référence).
    final cats = <String>[..._categoriesReference];
    for (final k in budgetMap.keys) {
      if (!cats.contains(k)) cats.add(k);
    }
    for (final k in reel.keys) {
      if (!cats.contains(k)) cats.add(k);
    }

    // Catégories connues (pour le sélecteur « + Autre ») : référence +
    // toutes celles déjà utilisées un jour dans le registre des dépenses.
    final connues = <String>[..._categoriesReference];
    for (final d in toutesDepenses) {
      if (d.categorie.isNotEmpty && !connues.contains(d.categorie)) connues.add(d.categorie);
    }

    if (!mounted) return;
    setState(() {
      _budgetMap = budgetMap;
      _reelMap = reel;
      _categories = cats;
      _categoriesConnues = connues;
      _loading = false;
    });
  }

  Future<void> _editBudget(String categorie) async {
    final current = _budgetMap[categorie] ?? 0;
    final ctrl = TextEditingController(text: current > 0 ? current.round().toString() : '');
    final saved = await showAppBottomSheet<bool>(
      context,
      title: 'Budget — $categorie',
      child: _BudgetForm(moisLabel: _capitalize(_moisCourant), annee: _annee, controller: ctrl),
    );
    if (saved != true) return;
    final valeur = double.tryParse(ctrl.text.trim().replaceAll(' ', '').replaceAll(',', '.')) ?? 0;
    await _budgetRepo.setBudget(categorie, _moisCourant, _annee, valeur);
    if (!mounted) return;
    showFormSuccess(context, 'Budget mis à jour pour $categorie.');
    _load();
  }

  Future<void> _ajouterCategorie() async {
    final disponibles = _categoriesConnues.where((c) => !_categories.contains(c)).toList();
    final options = disponibles.isNotEmpty ? disponibles : _categoriesConnues;
    String? categorieChoisie;
    final ctrl = TextEditingController();
    final saved = await showAppBottomSheet<bool>(
      context,
      title: 'Nouvelle ligne de budget',
      child: StatefulBuilder(
        builder: (ctx, setSheetState) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Catégorie', style: TextStyle(color: ctx.textMuted, fontSize: 12)),
            const SizedBox(height: 6),
            CatalogPickerField(
              options: options,
              hintText: 'Choisir une catégorie…',
              onChanged: (v) => setSheetState(() => categorieChoisie = v),
            ),
            const SizedBox(height: 14),
            Text('Budget alloué — ${_capitalize(_moisCourant)} $_annee', style: TextStyle(color: ctx.textMuted, fontSize: 12)),
            const SizedBox(height: 6),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(hintText: '0', suffixText: 'FCFA'),
            ),
            const SizedBox(height: 22),
            GoldButton(label: 'Enregistrer', onPressed: () => Navigator.of(ctx).pop(true)),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final categorie = (categorieChoisie ?? '').trim();
    if (categorie.isEmpty) {
      if (!mounted) return;
      showFormError(context, 'Choisis (ou saisis) une catégorie.');
      return;
    }
    final valeur = double.tryParse(ctrl.text.trim().replaceAll(' ', '').replaceAll(',', '.')) ?? 0;
    await _budgetRepo.setBudget(categorie, _moisCourant, _annee, valeur);
    if (!mounted) return;
    showFormSuccess(context, 'Ligne de budget ajoutée pour $categorie.');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    double totalBudget = 0;
    double totalReel = 0;
    for (final c in _categories) {
      totalBudget += _budgetMap[c] ?? 0;
      totalReel += _reelMap[c] ?? 0;
    }
    final ecartTotal = totalBudget - totalReel;

    return Scaffold(
      appBar: AppBar(title: const Text('Contrôle Budget')),
      floatingActionButton: FabRound(onPressed: _ajouterCategorie),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
            : RefreshIndicator(
                color: AppColors.gold,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    const ScreenHeader(
                      eyebrow: 'Suivi mensuel',
                      title: 'Contrôle Budget',
                    ),
                    Text(
                      'Compare le budget alloué aux dépenses réelles, mois par mois.',
                      style: TextStyle(color: context.textMuted, fontSize: 12.5),
                    ),
                    const SizedBox(height: 18),
                    _MoisAnneeSelecteur(
                      moisIdx: _moisIdx,
                      annee: _annee,
                      onMoisChanged: (v) {
                        setState(() => _moisIdx = v);
                        _load();
                      },
                      onAnneeChanged: (v) {
                        setState(() => _annee = v);
                        _load();
                      },
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(child: _TotalTile(label: 'Budget du mois', valeur: totalBudget, color: AppColors.gold)),
                        const SizedBox(width: 10),
                        Expanded(child: _TotalTile(label: 'Dépenses réelles', valeur: totalReel, color: AppColors.danger)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _TotalTile(
                            label: 'Écart',
                            valeur: ecartTotal,
                            color: ecartTotal >= 0 ? AppColors.success : AppColors.danger,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    if (_categories.isEmpty)
                      const EmptyState(icon: Icons.pie_chart_outline_rounded, text: 'Aucune catégorie de dépense.')
                    else
                      for (final categorie in _categories) ...[
                        _BudgetCategorieCard(
                          categorie: categorie,
                          budget: _budgetMap[categorie] ?? 0,
                          reel: _reelMap[categorie] ?? 0,
                          onTap: () => _editBudget(categorie),
                        ),
                        const SizedBox(height: 10),
                      ],
                  ],
                ),
              ),
      ),
    );
  }
}

class _MoisAnneeSelecteur extends StatelessWidget {
  final int moisIdx;
  final int annee;
  final ValueChanged<int> onMoisChanged;
  final ValueChanged<int> onAnneeChanged;

  const _MoisAnneeSelecteur({
    required this.moisIdx,
    required this.annee,
    required this.onMoisChanged,
    required this.onAnneeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<int>(
            value: moisIdx,
            dropdownColor: AppColors.surface,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Mois analysé'),
            items: [
              for (int i = 0; i < _moisNoms.length; i++)
                DropdownMenuItem(value: i, child: Text(_capitalize(_moisNoms[i]), style: TextStyle(color: context.textPrimary))),
            ],
            onChanged: (v) {
              if (v != null) onMoisChanged(v);
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: AppColors.surfaceHover,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.cardBorder),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () => onAnneeChanged(annee - 1),
                  icon: const Icon(Icons.chevron_left_rounded, color: AppColors.textMuted, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                Text('$annee', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w700, fontSize: 14.5)),
                IconButton(
                  onPressed: () => onAnneeChanged(annee + 1),
                  icon: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TotalTile extends StatelessWidget {
  final String label;
  final double valeur;
  final Color color;
  const _TotalTile({required this.label, required this.valeur, required this.color});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: TextStyle(color: context.textFaint, fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          const SizedBox(height: 6),
          Text(
            fmtFcfa(valeur),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _BudgetCategorieCard extends StatelessWidget {
  final String categorie;
  final double budget;
  final double reel;
  final VoidCallback onTap;

  const _BudgetCategorieCard({
    required this.categorie,
    required this.budget,
    required this.reel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ecart = budget - reel;
    final pct = budget > 0 ? (reel / budget * 100) : 0.0;
    final info = _alerte(budget, pct);
    final ecartColor = ecart >= 0 ? AppColors.success : AppColors.danger;

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(categorie, style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: info.color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: info.color.withOpacity(0.4)),
                ),
                child: Text(info.label, style: TextStyle(color: info.color, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 6),
              Icon(Icons.edit_outlined, size: 17, color: context.textFaint),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: budget > 0 ? (reel / budget).clamp(0.0, 1.0) : 0.0,
              minHeight: 7,
              backgroundColor: AppColors.surfaceHover,
              valueColor: AlwaysStoppedAnimation<Color>(info.color),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _MiniStat(label: 'Alloué', valeur: fmtFcfa(budget), color: context.textPrimary),
              _MiniStat(label: 'Réel', valeur: fmtFcfa(reel), color: context.textPrimary),
              _MiniStat(label: 'Écart', valeur: fmtFcfa(ecart), color: ecartColor),
              _MiniStat(label: '% utilisé', valeur: '${pct.toStringAsFixed(0)} %', color: context.textMuted),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String valeur;
  final Color color;
  const _MiniStat({required this.label, required this.valeur, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: context.textFaint, fontSize: 9.5)),
        const SizedBox(height: 2),
        Text(valeur, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _BudgetForm extends StatelessWidget {
  final String moisLabel;
  final int annee;
  final TextEditingController controller;
  const _BudgetForm({required this.moisLabel, required this.annee, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Budget alloué — $moisLabel $annee', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: '0', suffixText: 'FCFA'),
        ),
        const SizedBox(height: 22),
        GoldButton(label: 'Enregistrer', onPressed: () => Navigator.of(context).pop(true)),
      ],
    );
  }
}
