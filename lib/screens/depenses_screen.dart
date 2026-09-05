import 'package:flutter/material.dart';
import '../data/repository.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

/// Catégories de dépenses — reprises telles quelles de la version
/// ordinateur (ui/reference_lists.py, CATEGORIE_DEPENSE) pour que le
/// formulaire mobile propose exactement les mêmes options.
const List<String> categorieDepense = [
  'Matériaux (fer, alu, inox)', 'Vitres / Verre', 'Transport / Livraison',
  "Salaires / Main d'œuvre", 'Loyer / Atelier', 'Électricité / Eau', 'Carburant',
  'Entretien matériel', 'Communication / Téléphone', 'Divers / Imprévus',
  'Accessoires', 'Autres',
];

/// Modes de paiement — repris de MODE_PAIEMENT (ui/reference_lists.py).
const List<String> modePaiementDepense = [
  'Espèces', 'Mobile Money (Orange Money)', 'Virement Bancaire', 'Chèque',
];

const List<String> _moisAbrev = [
  'Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Jun', 'Jul', 'Aoû', 'Sep', 'Oct', 'Nov', 'Déc',
];

DateTime? _parseDepenseDate(String s) {
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

String _fmtDate(String s) {
  final d = _parseDepenseDate(s);
  if (d == null) return s;
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class DepensesScreen extends StatefulWidget {
  const DepensesScreen({super.key});

  @override
  State<DepensesScreen> createState() => _DepensesScreenState();
}

class _DepensesScreenState extends State<DepensesScreen> {
  final _depenseRepo = DepenseRepository();
  final _fournisseurRepo = FournisseurRepository();

  List<Depense> _depenses = [];
  List<String> _fournisseursNoms = [];
  bool _loading = true;

  bool _vueAnnuelle = false;
  final _searchCtrl = TextEditingController();
  String _search = '';
  String _categorieFiltre = 'Toutes';

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => setState(() => _search = _searchCtrl.text.trim()));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final depenses = await _depenseRepo.all();
    final fournisseurs = await _fournisseurRepo.noms();
    if (!mounted) return;
    setState(() {
      _depenses = depenses;
      _fournisseursNoms = fournisseurs;
      _loading = false;
    });
  }

  List<String> get _categoriesOptions {
    final extras = _depenses.map((d) => d.categorie).where((c) => c.isNotEmpty && !categorieDepense.contains(c)).toSet().toList()..sort();
    return [...categorieDepense, ...extras];
  }

  List<Depense> get _filtered {
    return _depenses.where((d) {
      if (_categorieFiltre != 'Toutes' && d.categorie != _categorieFiltre) return false;
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        if (!d.beneficiaire.toLowerCase().contains(q) && !d.description.toLowerCase().contains(q)) return false;
      }
      return true;
    }).toList();
  }

  double get _totalFiltre => _filtered.fold(0.0, (s, d) => s + d.montant);

  double get _totalCeMois {
    final now = DateTime.now();
    double total = 0;
    for (final d in _depenses) {
      final date = _parseDepenseDate(d.dateDepense);
      if (date != null && date.year == now.year && date.month == now.month) total += d.montant;
    }
    return total;
  }

  void _openAdd() async {
    await showAppBottomSheet(
      context,
      title: 'Nouvelle dépense',
      child: _DepenseForm(
        fournisseurs: _fournisseursNoms,
        onSaved: () {
          Navigator.of(context).pop();
          _load();
        },
      ),
    );
  }

  void _openDetail(Depense d) async {
    await showAppBottomSheet(
      context,
      title: d.categorie.isEmpty ? 'Dépense' : d.categorie,
      child: _DepenseDetail(
        depense: d,
        onDelete: () async {
          final confirme = await confirmDelete(context, nom: d.description.isEmpty ? d.categorie : d.description, typeElement: 'cette dépense');
          if (!confirme) return;
          await _depenseRepo.delete(d);
          if (!mounted) return;
          Navigator.of(context).pop();
          _load();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dépenses')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _TabSwitch(
                      vueAnnuelle: _vueAnnuelle,
                      onChanged: (v) => setState(() => _vueAnnuelle = v),
                    ),
                  ),
                  Expanded(
                    child: _vueAnnuelle
                        ? _VueAnnuelle(depenses: _depenses)
                        : _buildRegistre(context),
                  ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAdd,
        backgroundColor: AppColors.gold,
        child: const Icon(Icons.add, color: Colors.black),
      ),
    );
  }

  Widget _buildRegistre(BuildContext context) {
    final filtered = _filtered;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      children: [
        Row(
          children: [
            Expanded(child: _MiniTotal(label: 'Total affiché', value: fmtFcfaCompact(_totalFiltre), color: AppColors.danger)),
            const SizedBox(width: 8),
            Expanded(child: _MiniTotal(label: 'Ce mois-ci', value: fmtFcfaCompact(_totalCeMois), color: AppColors.info)),
            const SizedBox(width: 8),
            Expanded(child: _MiniTotal(label: 'Entrées', value: '${filtered.length}', color: AppColors.gold)),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _searchCtrl,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search, size: 20, color: AppColors.textFaint),
            hintText: 'Rechercher (bénéficiaire, description...)',
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _CategorieChip(label: 'Toutes', selected: _categorieFiltre == 'Toutes', onTap: () => setState(() => _categorieFiltre = 'Toutes')),
              for (final c in _categoriesOptions)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _CategorieChip(label: c, selected: _categorieFiltre == c, onTap: () => setState(() => _categorieFiltre = c)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          const EmptyState(icon: Icons.account_balance_wallet_outlined, text: 'Aucune dépense trouvée.')
        else
          ...filtered.map((d) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  onTap: () => _openDetail(d),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d.categorie.isEmpty ? 'Sans catégorie' : d.categorie,
                                style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w600, fontSize: 14.5),
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 3),
                            Text(
                              [
                                if (d.beneficiaire.isNotEmpty) d.beneficiaire,
                                _fmtDate(d.dateDepense),
                              ].join(' · '),
                              style: TextStyle(color: context.textFaint, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (d.description.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(d.description, style: TextStyle(color: context.textMuted, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('-${fmtFcfa(d.montant)}', style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700, fontSize: 13.5)),
                    ],
                  ),
                ),
              )),
      ],
    );
  }
}

class _TabSwitch extends StatelessWidget {
  final bool vueAnnuelle;
  final ValueChanged<bool> onChanged;
  const _TabSwitch({required this.vueAnnuelle, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: context.cardBorder)),
      child: Row(
        children: [
          Expanded(child: _TabSwitchButton(label: '📋 Registre', selected: !vueAnnuelle, onTap: () => onChanged(false))),
          Expanded(child: _TabSwitchButton(label: '📅 Vue annuelle', selected: vueAnnuelle, onTap: () => onChanged(true))),
        ],
      ),
    );
  }
}

class _TabSwitchButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TabSwitchButton({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(color: selected ? AppColors.gold : Colors.transparent, borderRadius: BorderRadius.circular(8)),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(color: selected ? Colors.black : context.textMuted, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, fontSize: 12.5)),
      ),
    );
  }
}

class _CategorieChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CategorieChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.gold.withOpacity(0.18) : context.cardBg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? AppColors.gold : context.cardBorder),
        ),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(color: selected ? AppColors.gold : context.textMuted, fontSize: 12.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
      ),
    );
  }
}

class _MiniTotal extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniTotal({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: context.cardBorder)),
      child: Column(
        children: [
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(color: context.textFaint, fontSize: 9.5), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// Vue annuelle : tableau catégorie × mois, identique dans l'esprit à la
/// version ordinateur (grille avec totaux par mois et total général),
/// pour l'année en cours.
class _VueAnnuelle extends StatelessWidget {
  final List<Depense> depenses;
  const _VueAnnuelle({required this.depenses});

  @override
  Widget build(BuildContext context) {
    final annee = DateTime.now().year;
    // totaux[categorie][moisIndex 0-11]
    final totaux = {for (final c in categorieDepense) c: List<double>.filled(12, 0.0)};
    for (final d in depenses) {
      final date = _parseDepenseDate(d.dateDepense);
      if (date == null || date.year != annee) continue;
      final ligne = totaux[d.categorie];
      if (ligne == null) continue; // catégorie hors liste de référence — comme sur la version ordinateur
      ligne[date.month - 1] += d.montant;
    }
    final totauxMensuels = List<double>.filled(12, 0.0);
    double grandTotal = 0;
    for (final ligne in totaux.values) {
      for (int m = 0; m < 12; m++) {
        totauxMensuels[m] += ligne[m];
      }
    }
    for (final t in totauxMensuels) {
      grandTotal += t;
    }

    const colW = 64.0;
    const catW = 168.0;
    const totalW = 84.0;

    TextStyle headStyle = const TextStyle(color: AppColors.gold, fontSize: 10, fontWeight: FontWeight.w700);

    Widget cell(String text, double width, {TextStyle? style, Alignment align = Alignment.centerRight}) {
      return Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
        alignment: align,
        child: Text(text, style: style, overflow: TextOverflow.ellipsis),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Année analysée : $annee', style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      color: AppColors.sidebar,
                      child: Row(
                        children: [
                          cell('CATÉGORIE', catW, style: headStyle, align: Alignment.centerLeft),
                          for (final m in _moisAbrev) cell(m.toUpperCase(), colW, style: headStyle),
                          cell('TOTAL', totalW, style: headStyle),
                        ],
                      ),
                    ),
                    for (int i = 0; i < categorieDepense.length; i++)
                      Container(
                        color: i.isEven ? context.cardBg : AppColors.background,
                        child: Row(
                          children: [
                            cell(categorieDepense[i], catW, style: TextStyle(color: context.textPrimary, fontSize: 11), align: Alignment.centerLeft),
                            for (final v in totaux[categorieDepense[i]]!)
                              cell(v == 0 ? '—' : fmtFcfa(v), colW, style: TextStyle(color: v == 0 ? context.textFaint : context.textPrimary, fontSize: 10)),
                            cell(
                              fmtFcfa(totaux[categorieDepense[i]]!.fold(0.0, (s, v) => s + v)),
                              totalW,
                              style: const TextStyle(color: AppColors.gold, fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(6)),
                      child: Row(
                        children: [
                          cell('TOTAL MENSUEL', catW, style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w700), align: Alignment.centerLeft),
                          for (final v in totauxMensuels)
                            cell(v == 0 ? '—' : fmtFcfa(v), colW, style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w700)),
                          cell(fmtFcfa(grandTotal), totalW, style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w700)),
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
  }
}

class _DepenseForm extends StatefulWidget {
  final List<String> fournisseurs;
  final VoidCallback onSaved;
  const _DepenseForm({required this.fournisseurs, required this.onSaved});

  @override
  State<_DepenseForm> createState() => _DepenseFormState();
}

class _DepenseFormState extends State<_DepenseForm> {
  final _repo = DepenseRepository();
  final _descriptionCtrl = TextEditingController();
  final _montantCtrl = TextEditingController();
  String _categorie = categorieDepense.first;
  String? _beneficiaire;
  String _modePaiement = 'Espèces';
  bool _justificatif = false;
  bool _saving = false;

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    _montantCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final raw = _montantCtrl.text.trim().replaceAll(' ', '').replaceAll(',', '.');
    final montant = double.tryParse(raw);
    if (montant == null || montant <= 0) {
      showFormError(context, 'Indique un montant valide avant d\'enregistrer.');
      return;
    }
    setState(() => _saving = true);
    await _repo.create(
      categorie: _categorie,
      description: _descriptionCtrl.text.trim(),
      beneficiaire: _beneficiaire ?? '',
      montant: montant,
      modePaiement: _modePaiement,
      justificatif: _justificatif ? 'Oui' : 'Non',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Catégorie *', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _categorie,
          dropdownColor: AppColors.surface,
          isExpanded: true,
          items: [for (final c in categorieDepense) DropdownMenuItem(value: c, child: Text(c, style: TextStyle(color: context.textPrimary), overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _categorie = v ?? categorieDepense.first),
        ),
        const SizedBox(height: 14),
        Text('Description', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(controller: _descriptionCtrl, decoration: const InputDecoration(hintText: 'Objet de la dépense')),
        const SizedBox(height: 14),
        Text('Fournisseur / Bénéficiaire', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        CatalogPickerField(
          options: widget.fournisseurs,
          initialValue: _beneficiaire,
          hintText: 'Choisir…',
          customHintText: 'Nom du bénéficiaire',
          onChanged: (v) => setState(() => _beneficiaire = v),
        ),
        const SizedBox(height: 14),
        Text('Montant (FCFA) *', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(controller: _montantCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration()),
        const SizedBox(height: 14),
        Text('Mode de paiement', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _modePaiement,
          dropdownColor: AppColors.surface,
          isExpanded: true,
          items: [for (final m in modePaiementDepense) DropdownMenuItem(value: m, child: Text(m, style: TextStyle(color: context.textPrimary), overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _modePaiement = v ?? 'Espèces'),
        ),
        const SizedBox(height: 10),
        SwitchListTile(
          value: _justificatif,
          onChanged: (v) => setState(() => _justificatif = v),
          activeColor: AppColors.gold,
          contentPadding: EdgeInsets.zero,
          title: Text('Justificatif disponible', style: TextStyle(color: context.textPrimary, fontSize: 13)),
        ),
        const SizedBox(height: 12),
        GoldButton(label: _saving ? 'Enregistrement…' : 'Enregistrer', onPressed: _saving ? () {} : _save),
      ],
    );
  }
}

class _DepenseDetail extends StatelessWidget {
  final Depense depense;
  final VoidCallback onDelete;
  const _DepenseDetail({required this.depense, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              const Text('MONTANT', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(fmtFcfa(depense.montant), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow(label: 'Date', value: _fmtDate(depense.dateDepense)),
              _DetailRow(label: 'Description', value: depense.description.isEmpty ? '—' : depense.description),
              _DetailRow(label: 'Fournisseur / Bénéficiaire', value: depense.beneficiaire.isEmpty ? '—' : depense.beneficiaire),
              _DetailRow(label: 'Mode de paiement', value: depense.modePaiement.isEmpty ? '—' : depense.modePaiement),
              _DetailRow(label: 'Justificatif', value: depense.justificatif, last: true),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: onDelete,
          style: TextButton.styleFrom(foregroundColor: AppColors.danger, padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
          child: const Text('Supprimer cette dépense', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool last;
  const _DetailRow({required this.label, required this.value, this.last = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: context.textFaint, fontSize: 11)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(color: context.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
