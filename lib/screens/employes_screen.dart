import 'package:flutter/material.dart';
import '../data/repository.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

/// Module Employés & Paie — reprend la logique de la version ordinateur
/// (modules/employes.py) : un onglet « Employés » (fiches du personnel) et
/// un onglet « Paie » qui, pour un mois/année choisi, montre pour chaque
/// employé actif le salaire dû, les avances déjà versées ce mois-ci et le
/// net à payer, avec une action pour enregistrer un paiement/avance.

/// Types de contrat — reference_lists.py::TYPE_CONTRAT.
const List<String> typeContratOptions = ['CDI', 'CDD', 'Journalier', 'Stage'];

/// Statuts d'un employé — reference_lists.py::STATUT_ACTIF_INACTIF.
const List<String> statutEmployeOptions = ['Actif', 'Inactif'];

/// Modes de paiement — reference_lists.py::MODE_PAIEMENT (identiques à
/// ceux utilisés pour les dépenses).
const List<String> modePaiementPaie = [
  'Espèces', 'Mobile Money (Orange Money)', 'Virement Bancaire', 'Chèque',
];

/// Noms de mois français en minuscules. IMPORTANT — convention des mois :
/// `PaieRepository.forMoisAnnee` / `ensureLigne` comparent `mois` par
/// égalité stricte (`mois = ?`), et `BudgetRepository._moisIndex` compare
/// déjà en minuscules ailleurs dans l'appli. On stocke et on interroge donc
/// systématiquement avec des noms de mois français en minuscules
/// ('janvier', 'février', … 'décembre') pour rester cohérent avec le reste
/// de MK Suite mobile (voir budget_screen.dart).
const List<String> _moisNoms = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];

String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

String _fmtDateCourte(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Couleur associée à un statut de paie. Le thème partagé (StatutColors)
/// connaît déjà 'En attente' (warning) mais pas 'Payé' — on complète
/// localement plutôt que de modifier le fichier de thème partagé.
Color _paieStatutColor(String statut) {
  if (statut == 'Payé') return AppColors.success;
  if (statut == 'En attente') return AppColors.warning;
  return AppColors.textFaint;
}

class EmployesScreen extends StatefulWidget {
  const EmployesScreen({super.key});

  @override
  State<EmployesScreen> createState() => _EmployesScreenState();
}

class _EmployesScreenState extends State<EmployesScreen> {
  final _employeRepo = EmployeRepository();
  final _paieRepo = PaieRepository();

  int _tab = 0; // 0 = Employés, 1 = Paie du mois
  bool _loading = true;
  List<Employe> _employes = [];

  int _moisIdx = DateTime.now().month - 1;
  int _annee = DateTime.now().year;
  bool _loadingPaie = false;
  Map<int, Paie> _paieParEmploye = {};

  @override
  void initState() {
    super.initState();
    _loadEmployes();
  }

  String get _moisCourant => _moisNoms[_moisIdx];

  List<Employe> get _employesTries {
    final list = [..._employes];
    list.sort((a, b) => a.code.compareTo(b.code));
    return list;
  }

  List<Employe> get _employesActifs => _employesTries.where((e) => e.statut == 'Actif').toList();

  Future<void> _loadEmployes() async {
    setState(() => _loading = true);
    final rows = await _employeRepo.all();
    if (!mounted) return;
    setState(() {
      _employes = rows;
      _loading = false;
    });
    if (_tab == 1) _loadPaie();
  }

  Future<void> _loadPaie() async {
    setState(() => _loadingPaie = true);
    final mois = _moisCourant;
    final annee = _annee;
    final map = <int, Paie>{};
    for (final emp in _employesActifs) {
      final p = await _paieRepo.ensureLigne(emp, mois, annee);
      map[emp.id] = p;
    }
    if (!mounted) return;
    setState(() {
      _paieParEmploye = map;
      _loadingPaie = false;
    });
  }

  void _switchTab(int tab) {
    setState(() => _tab = tab);
    if (tab == 1) _loadPaie();
  }

  void _openAddEmploye({Employe? existing}) async {
    await showAppBottomSheet(
      context,
      title: existing != null ? "Modifier l'employé" : 'Nouvel employé',
      child: _EmployeForm(
        existing: existing,
        onSaved: () {
          Navigator.of(context).pop();
          _loadEmployes();
        },
        onDeleted: () {
          Navigator.of(context).pop();
          _loadEmployes();
        },
      ),
    );
  }

  void _openPayer(Employe emp, Paie p) async {
    await showAppBottomSheet(
      context,
      title: 'Payer ${emp.nom}',
      child: _PaieForm(
        employe: emp,
        paie: p,
        moisLabel: '${_capitalize(_moisCourant)} $_annee',
        onSaved: () {
          Navigator.of(context).pop();
          _loadPaie();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Employés / Paie')),
      floatingActionButton: FabRound(onPressed: () => _openAddEmploye()),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _TabSwitch(tab: _tab, onChanged: _switchTab),
                  ),
                  Expanded(
                    child: _tab == 0 ? _buildEmployesTab(context) : _buildPaieTab(context),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildEmployesTab(BuildContext context) {
    final actifs = _employesActifs;
    final masse = actifs.fold(0.0, (s, e) => s + e.salaireMensuel);
    return RefreshIndicator(
      color: AppColors.gold,
      onRefresh: _loadEmployes,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          Row(
            children: [
              Expanded(child: _MiniTotal(label: 'Masse salariale mensuelle', value: fmtFcfaCompact(masse), color: AppColors.gold)),
              const SizedBox(width: 8),
              Expanded(child: _MiniTotal(label: 'Employés actifs', value: '${actifs.length}', color: AppColors.info)),
            ],
          ),
          const SizedBox(height: 18),
          if (_employesTries.isEmpty)
            const EmptyState(icon: Icons.badge_outlined, text: 'Aucun employé enregistré.')
          else
            for (final e in _employesTries) ...[
              AppCard(
                onTap: () => _openAddEmploye(existing: e),
                child: Row(
                  children: [
                    AppAvatar(name: e.nom, size: 42),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(child: Text(e.nom, style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w600, fontSize: 14.5), overflow: TextOverflow.ellipsis)),
                              const SizedBox(width: 6),
                              Text(e.code, style: const TextStyle(color: AppColors.gold, fontSize: 10.5, fontWeight: FontWeight.w700)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [if (e.poste.isNotEmpty) e.poste, e.typeContrat].join(' · '),
                            style: TextStyle(color: context.textFaint, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(fmtFcfa(e.salaireMensuel), style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 13)),
                        const SizedBox(height: 4),
                        StatutBadge(statut: e.statut),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  Widget _buildPaieTab(BuildContext context) {
    final actifs = _employesActifs;
    double totalNet = 0;
    double totalDeja = 0;
    for (final emp in actifs) {
      final p = _paieParEmploye[emp.id];
      if (p == null) continue;
      totalNet += p.netAPayer;
      totalDeja += p.avancesVersees;
    }
    return RefreshIndicator(
      color: AppColors.gold,
      onRefresh: _loadPaie,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          _MoisAnneeSelecteur(
            moisIdx: _moisIdx,
            annee: _annee,
            onMoisChanged: (v) {
              setState(() => _moisIdx = v);
              _loadPaie();
            },
            onAnneeChanged: (v) {
              setState(() => _annee = v);
              _loadPaie();
            },
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _MiniTotal(label: 'Net dû (mois)', value: fmtFcfaCompact(totalNet), color: AppColors.gold)),
              const SizedBox(width: 8),
              Expanded(child: _MiniTotal(label: 'Déjà versé', value: fmtFcfaCompact(totalDeja), color: AppColors.success)),
            ],
          ),
          const SizedBox(height: 18),
          if (_loadingPaie)
            const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator(color: AppColors.gold)))
          else if (actifs.isEmpty)
            const EmptyState(icon: Icons.payments_outlined, text: 'Aucun employé actif.')
          else
            for (final emp in actifs) ...[
              _PaieRow(
                employe: emp,
                paie: _paieParEmploye[emp.id],
                onPayer: () {
                  final p = _paieParEmploye[emp.id];
                  if (p != null) _openPayer(emp, p);
                },
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _TabSwitch extends StatelessWidget {
  final int tab;
  final ValueChanged<int> onChanged;
  const _TabSwitch({required this.tab, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: context.cardBorder)),
      child: Row(
        children: [
          Expanded(child: _TabSwitchButton(label: '👔 Employés', selected: tab == 0, onTap: () => onChanged(0))),
          Expanded(child: _TabSwitchButton(label: '💰 Paie du mois', selected: tab == 1, onTap: () => onChanged(1))),
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
            decoration: const InputDecoration(labelText: 'Mois de paie'),
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

class _MiniStat extends StatelessWidget {
  final String label;
  final String valeur;
  final bool gold;
  const _MiniStat({required this.label, required this.valeur, this.gold = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: context.textFaint, fontSize: 9.5)),
        const SizedBox(height: 2),
        Text(valeur, style: TextStyle(color: gold ? AppColors.gold : context.textPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _PaieRow extends StatelessWidget {
  final Employe employe;
  final Paie? paie;
  final VoidCallback onPayer;
  const _PaieRow({required this.employe, required this.paie, required this.onPayer});

  @override
  Widget build(BuildContext context) {
    final p = paie;
    final salaireDu = p?.salaireDu ?? employe.salaireMensuel;
    final avances = p?.avancesVersees ?? 0.0;
    final net = p?.netAPayer ?? salaireDu;
    final statut = p?.statut ?? 'En attente';
    final color = _paieStatutColor(statut);
    final paye = statut == 'Payé';

    return AppCard(
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
                    Text(employe.nom, style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                    if (employe.poste.isNotEmpty)
                      Text(employe.poste, style: TextStyle(color: context.textFaint, fontSize: 11.5)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: color.withOpacity(0.4)),
                ),
                child: Text(statut, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _MiniStat(label: 'Salaire dû', valeur: fmtFcfa(salaireDu)),
              _MiniStat(label: 'Avances versées', valeur: fmtFcfa(avances)),
              _MiniStat(label: 'Net à payer', valeur: fmtFcfa(net), gold: true),
            ],
          ),
          if (!paye) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: p == null ? null : onPayer,
                icon: const Icon(Icons.payments_outlined, size: 17),
                label: const Text('Enregistrer un paiement'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmployeForm extends StatefulWidget {
  final Employe? existing;
  final VoidCallback onSaved;
  final VoidCallback onDeleted;
  const _EmployeForm({this.existing, required this.onSaved, required this.onDeleted});

  @override
  State<_EmployeForm> createState() => _EmployeFormState();
}

class _EmployeFormState extends State<_EmployeForm> {
  final _repo = EmployeRepository();
  final _nomCtrl = TextEditingController();
  final _posteCtrl = TextEditingController();
  final _telephoneCtrl = TextEditingController();
  final _salaireCtrl = TextEditingController();
  String _typeContrat = 'CDI';
  String _statut = 'Actif';
  DateTime? _dateEmbauche;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nomCtrl.text = e.nom;
      _posteCtrl.text = e.poste;
      _telephoneCtrl.text = e.telephone;
      _salaireCtrl.text = e.salaireMensuel == e.salaireMensuel.roundToDouble() ? e.salaireMensuel.toStringAsFixed(0) : e.salaireMensuel.toString();
      _typeContrat = typeContratOptions.contains(e.typeContrat) ? e.typeContrat : 'CDI';
      _statut = statutEmployeOptions.contains(e.statut) ? e.statut : 'Actif';
      if (e.dateEmbauche != null && e.dateEmbauche!.isNotEmpty) {
        _dateEmbauche = DateTime.tryParse(e.dateEmbauche!);
      }
    }
  }

  @override
  void dispose() {
    _nomCtrl.dispose();
    _posteCtrl.dispose();
    _telephoneCtrl.dispose();
    _salaireCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateEmbauche() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateEmbauche ?? now,
      firstDate: DateTime(now.year - 40),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) setState(() => _dateEmbauche = picked);
  }

  Future<void> _save() async {
    final nom = _nomCtrl.text.trim();
    if (nom.isEmpty) {
      showFormError(context, "Indique le nom de l'employé avant d'enregistrer.");
      return;
    }
    final raw = _salaireCtrl.text.trim().replaceAll(' ', '').replaceAll(',', '.');
    final salaire = double.tryParse(raw);
    if (salaire == null || salaire < 0) {
      showFormError(context, 'Indique un salaire mensuel valide.');
      return;
    }
    setState(() => _saving = true);
    final dateEmbaucheStr = _dateEmbauche?.toIso8601String();
    if (widget.existing != null) {
      final e = widget.existing!;
      final updated = Employe(
        id: e.id,
        syncId: e.syncId,
        code: e.code,
        nom: nom,
        poste: _posteCtrl.text.trim(),
        telephone: _telephoneCtrl.text.trim(),
        dateEmbauche: dateEmbaucheStr,
        typeContrat: _typeContrat,
        salaireMensuel: salaire,
        statut: _statut,
        updatedAt: e.updatedAt,
      );
      await _repo.update(updated);
    } else {
      await _repo.create(
        nom: nom,
        poste: _posteCtrl.text.trim(),
        telephone: _telephoneCtrl.text.trim(),
        dateEmbauche: dateEmbaucheStr,
        typeContrat: _typeContrat,
        salaireMensuel: salaire,
      );
    }
    if (!mounted) return;
    setState(() => _saving = false);
    widget.onSaved();
  }

  Future<void> _delete() async {
    final e = widget.existing;
    if (e == null) return;
    final confirme = await confirmDelete(context, nom: e.nom, typeElement: 'cet employé');
    if (!confirme) return;
    await _repo.delete(e);
    if (!mounted) return;
    widget.onDeleted();
  }

  @override
  Widget build(BuildContext context) {
    final estNouveau = widget.existing == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!estNouveau) ...[
          Text('Code : ${widget.existing!.code}', style: const TextStyle(color: AppColors.gold, fontSize: 11.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
        ],
        Text('Nom complet *', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(controller: _nomCtrl, decoration: const InputDecoration()),
        const SizedBox(height: 14),
        Text('Poste', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(controller: _posteCtrl, decoration: const InputDecoration(hintText: 'Ex : Soudeur, Vitrier…')),
        const SizedBox(height: 14),
        Text('Téléphone', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(controller: _telephoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration()),
        const SizedBox(height: 14),
        Text('Salaire mensuel (FCFA) *', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(controller: _salaireCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration()),
        const SizedBox(height: 14),
        Text('Type de contrat', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _typeContrat,
          dropdownColor: AppColors.surface,
          isExpanded: true,
          items: [for (final t in typeContratOptions) DropdownMenuItem(value: t, child: Text(t, style: TextStyle(color: context.textPrimary)))],
          onChanged: (v) => setState(() => _typeContrat = v ?? 'CDI'),
        ),
        const SizedBox(height: 14),
        Text("Date d'embauche (facultatif)", style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        InkWell(
          onTap: _pickDateEmbauche,
          child: InputDecorator(
            decoration: InputDecoration(
              suffixIcon: Icon(Icons.calendar_today_outlined, size: 16, color: context.textFaint),
              suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            child: Text(
              _dateEmbauche != null ? _fmtDateCourte(_dateEmbauche!) : 'Choisir une date',
              style: TextStyle(color: _dateEmbauche != null ? context.textPrimary : context.textFaint),
            ),
          ),
        ),
        // Le statut n'est modifiable qu'à l'édition : EmployeRepository.create()
        // insère toujours 'Actif' (pas de paramètre statut), donc afficher ce
        // sélecteur pour un nouvel employé serait trompeur — voir le rapport
        // de fin de tâche pour ce point.
        if (!estNouveau) ...[
          const SizedBox(height: 14),
          Text('Statut', style: TextStyle(color: context.textMuted, fontSize: 12)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _statut,
            dropdownColor: AppColors.surface,
            isExpanded: true,
            items: [for (final s in statutEmployeOptions) DropdownMenuItem(value: s, child: Text(s, style: TextStyle(color: context.textPrimary)))],
            onChanged: (v) => setState(() => _statut = v ?? 'Actif'),
          ),
        ],
        const SizedBox(height: 20),
        GoldButton(label: _saving ? 'Enregistrement…' : (estNouveau ? 'Enregistrer' : 'Enregistrer les modifications'), onPressed: _saving ? () {} : _save),
        if (!estNouveau) ...[
          const SizedBox(height: 10),
          TextButton(
            onPressed: _delete,
            style: TextButton.styleFrom(foregroundColor: AppColors.danger, padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
            child: const Text('Supprimer cet employé', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ],
    );
  }
}

class _PaieForm extends StatefulWidget {
  final Employe employe;
  final Paie paie;
  final String moisLabel;
  final VoidCallback onSaved;
  const _PaieForm({required this.employe, required this.paie, required this.moisLabel, required this.onSaved});

  @override
  State<_PaieForm> createState() => _PaieFormState();
}

class _PaieFormState extends State<_PaieForm> {
  final _repo = PaieRepository();
  late final TextEditingController _montantCtrl;
  String _mode = 'Espèces';
  bool _saving = false;

  double get _reste => widget.paie.netAPayer;

  @override
  void initState() {
    super.initState();
    // Pré-rempli avec le reste à payer : un simple appui sur « Confirmer »
    // solde donc le mois, comme le bouton « 💰 Payer » côté ordinateur ; le
    // montant reste modifiable pour n'enregistrer qu'une avance partielle.
    final reste = _reste;
    _montantCtrl = TextEditingController(text: reste == reste.roundToDouble() ? reste.toStringAsFixed(0) : reste.toString());
  }

  @override
  void dispose() {
    _montantCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmer() async {
    final raw = _montantCtrl.text.trim().replaceAll(' ', '').replaceAll(',', '.');
    final montant = double.tryParse(raw);
    if (montant == null || montant <= 0) {
      showFormError(context, 'Indique un montant à payer valide.');
      return;
    }
    setState(() => _saving = true);
    await _repo.payer(widget.paie, montant: montant, modePaiement: _mode);
    if (!mounted) return;
    setState(() => _saving = false);
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.moisLabel, style: const TextStyle(color: AppColors.gold, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(12)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _MiniStat(label: 'Salaire dû', valeur: fmtFcfa(widget.paie.salaireDu)),
              _MiniStat(label: 'Déjà versé', valeur: fmtFcfa(widget.paie.avancesVersees)),
              _MiniStat(label: 'Reste à payer', valeur: fmtFcfa(_reste), gold: true),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Montant versé (FCFA) *', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(controller: _montantCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration()),
        const SizedBox(height: 4),
        Text('Un montant inférieur au reste à payer est enregistré comme une avance.', style: TextStyle(color: context.textFaint, fontSize: 11, fontStyle: FontStyle.italic)),
        const SizedBox(height: 14),
        Text('Mode de paiement', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _mode,
          dropdownColor: AppColors.surface,
          isExpanded: true,
          items: [for (final m in modePaiementPaie) DropdownMenuItem(value: m, child: Text(m, style: TextStyle(color: context.textPrimary), overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _mode = v ?? 'Espèces'),
        ),
        const SizedBox(height: 20),
        GoldButton(label: _saving ? 'Enregistrement…' : '✓ Confirmer le paiement', onPressed: _saving ? () {} : _confirmer),
      ],
    );
  }
}
