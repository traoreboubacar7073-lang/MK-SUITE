import 'package:flutter/material.dart';
import '../data/repository.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import '../services/pdf_service.dart';

/// Calcul Vitres — calculateur de surface (largeur × hauteur × quantité) ×
/// prix/m² selon le type de vitre choisi, exactement comme l'onglet Excel
/// d'origine (voir modules/calcul_vitres.py côté ordinateur).
///
/// Comme sur l'ordinateur, la saisie est un bloc de calcul ÉPHÉMÈRE : on
/// ajoute plusieurs lignes à la suite, les totaux se recalculent en direct
/// à chaque frappe, et RIEN n'est enregistré tant qu'on n'appuie pas sur
/// « Enregistrer toutes les lignes » — qui les verse alors dans l'historique
/// des commandes (table commandes_vitres) et repart sur une saisie neuve
/// (_save_all_lines côté ordinateur). Le PDF, lui, peut être généré à tout
/// moment à partir des lignes actuellement saisies — enregistrées ou pas —
/// exactement comme _export_pdf/_current_lines_data côté ordinateur, qui
/// ne touchent jamais la base.
class VitresScreen extends StatefulWidget {
  const VitresScreen({super.key});

  @override
  State<VitresScreen> createState() => _VitresScreenState();
}

/// Une ligne de saisie du calculateur — purement locale à l'écran tant
/// qu'elle n'est pas enregistrée.
class _LigneCalc {
  String? typeVitre;
  final TextEditingController largeurCtrl = TextEditingController();
  final TextEditingController hauteurCtrl = TextEditingController();
  final TextEditingController quantiteCtrl = TextEditingController(text: '1');
  final TextEditingController nouveauPrixCtrl = TextEditingController();

  void dispose() {
    largeurCtrl.dispose();
    hauteurCtrl.dispose();
    quantiteCtrl.dispose();
    nouveauPrixCtrl.dispose();
  }
}

class _VitresScreenState extends State<VitresScreen> {
  final _tarifRepo = TarifVitreRepository();
  final _commandeRepo = CommandeVitreRepository();

  bool _loading = true;
  bool _saving = false;
  bool _generatingPdf = false;
  List<TarifVitre> _tarifs = [];
  List<CommandeVitre> _historique = [];
  final List<_LigneCalc> _lignes = [];

  Map<String, double> get _tarifsMap => {for (final t in _tarifs) t.typeVitre: t.prixM2};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    for (final l in _lignes) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAll() async {
    final tarifs = await _tarifRepo.all();
    final historique = await _commandeRepo.all();
    if (!mounted) return;
    setState(() {
      _tarifs = tarifs;
      _historique = historique;
      _loading = false;
      if (_lignes.isEmpty) {
        for (var i = 0; i < 3; i++) {
          _addLigne();
        }
      }
    });
  }

  void _addLigne() {
    final l = _LigneCalc();
    l.typeVitre = _lignes.isNotEmpty ? _lignes.last.typeVitre : (_tarifs.isNotEmpty ? _tarifs.first.typeVitre : null);
    _lignes.add(l);
  }

  bool _estNouveauType(_LigneCalc l) => l.typeVitre != null && l.typeVitre!.isNotEmpty && !_tarifsMap.containsKey(l.typeVitre);

  double _prixDeLaLigne(_LigneCalc l) {
    if (l.typeVitre == null || l.typeVitre!.isEmpty) return 0;
    final connu = _tarifsMap[l.typeVitre];
    if (connu != null) return connu;
    return double.tryParse(l.nouveauPrixCtrl.text.replaceAll(',', '.')) ?? 0;
  }

  double _largeur(_LigneCalc l) => double.tryParse(l.largeurCtrl.text.replaceAll(',', '.')) ?? 0;
  double _hauteur(_LigneCalc l) => double.tryParse(l.hauteurCtrl.text.replaceAll(',', '.')) ?? 0;
  int _quantite(_LigneCalc l) => int.tryParse(l.quantiteCtrl.text.trim()) ?? 0;
  double _surface(_LigneCalc l) => _largeur(l) * _hauteur(l) * _quantite(l);
  double _montant(_LigneCalc l) => _surface(l) * _prixDeLaLigne(l);

  double get _surfaceTotale => _lignes.fold(0.0, (s, l) => s + _surface(l));
  double get _montantTotal => _lignes.fold(0.0, (s, l) => s + _montant(l));

  List<_LigneCalc> get _lignesValides => _lignes.where((l) => _surface(l) > 0).toList();

  Future<void> _enregistrer() async {
    final valides = _lignesValides;
    if (valides.isEmpty) {
      showFormError(context, "Saisis au moins une ligne (largeur, hauteur et quantité) avant d'enregistrer.");
      return;
    }
    setState(() => _saving = true);
    try {
      // Les types encore inconnus sont d'abord ajoutés au tarif de
      // référence (comme le « + Autre » du sélecteur) pour que le prix
      // saisi ici devienne réutilisable la prochaine fois.
      for (final l in valides) {
        if (_estNouveauType(l)) {
          await _tarifRepo.upsert(l.typeVitre!, _prixDeLaLigne(l));
        }
      }
      final tarifs = await _tarifRepo.all();
      final tarifsMap = {for (final t in tarifs) t.typeVitre: t.prixM2};
      for (final l in valides) {
        await _commandeRepo.create(
          typeVitre: l.typeVitre!,
          largeur: _largeur(l),
          hauteur: _hauteur(l),
          quantite: _quantite(l),
          prixUnitaire: tarifsMap[l.typeVitre] ?? _prixDeLaLigne(l),
        );
      }
      // Repartir sur une saisie neuve, prête pour le prochain lot de vitres.
      for (final l in _lignes) {
        l.dispose();
      }
      _lignes.clear();
      for (var i = 0; i < 3; i++) {
        _addLigne();
      }
      final historique = await _commandeRepo.all();
      if (!mounted) return;
      setState(() {
        _tarifs = tarifs;
        _historique = historique;
        _saving = false;
      });
      showFormSuccess(context, '${valides.length} ligne(s) enregistrée(s) dans l\'historique.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showFormError(context, "Une erreur est survenue pendant l'enregistrement.");
    }
  }

  List<CommandeVitre> _lignesPourPdf() {
    final now = DateTime.now();
    return _lignesValides.map((l) {
      return CommandeVitre(
        id: 0, syncId: '', dateCommande: now.toIso8601String(), typeVitre: l.typeVitre ?? '—',
        largeur: _largeur(l), hauteur: _hauteur(l), quantite: _quantite(l), surface: _surface(l),
        prixUnitaire: _prixDeLaLigne(l), montant: _montant(l), devisNumero: null, factureNumero: null,
        updatedAt: now.millisecondsSinceEpoch,
      );
    }).toList();
  }

  Future<void> _genererPdf({required bool partager}) async {
    if (_lignesValides.isEmpty) {
      showFormError(context, 'Saisis au moins une ligne avant de générer le PDF.');
      return;
    }
    setState(() => _generatingPdf = true);
    try {
      final bytes = await PdfService.vitresPdf(_lignesPourPdf(), _surfaceTotale, _montantTotal);
      if (!mounted) return;
      if (partager) {
        await PdfService.share(bytes, 'Calcul_Vitres.pdf');
      } else {
        await PdfService.preview(bytes, 'Calcul Vitres');
      }
    } catch (_) {
      if (mounted) showFormError(context, 'Une erreur est survenue pendant la génération du PDF.');
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  Future<void> _supprimerCommande(CommandeVitre c) async {
    final ok = await confirmDelete(context, nom: 'Vitre ${c.typeVitre} (${fmtFcfa(c.montant)})', typeElement: 'cette entrée');
    if (!ok) return;
    await _commandeRepo.delete(c);
    final historique = await _commandeRepo.all();
    if (!mounted) return;
    setState(() => _historique = historique);
  }

  Future<void> _openTarifsManager() async {
    await showAppBottomSheet(
      context,
      title: 'Tarifs des vitres (FCFA / m²)',
      child: _TarifsManagerSheet(repo: _tarifRepo),
    );
    final tarifs = await _tarifRepo.all();
    if (!mounted) return;
    setState(() => _tarifs = tarifs);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calcul Vitres'),
        actions: [
          IconButton(
            tooltip: 'Gérer les tarifs',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openTarifsManager,
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
            : RefreshIndicator(
                color: AppColors.gold,
                onRefresh: _loadAll,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    Text(
                      'Saisis tes vitres à la suite : surface = largeur × hauteur × quantité, prix repris automatiquement selon le type.',
                      style: TextStyle(color: context.textMuted, fontSize: 12.5),
                    ),
                    const SizedBox(height: 16),
                    for (int i = 0; i < _lignes.length; i++) ...[
                      _LigneCard(
                        key: ObjectKey(_lignes[i]),
                        ligne: _lignes[i],
                        options: _tarifs.map((t) => t.typeVitre).toList(),
                        nouveauType: _estNouveauType(_lignes[i]),
                        montant: _montant(_lignes[i]),
                        onChanged: () => setState(() {}),
                        onDelete: () => setState(() {
                          _lignes[i].dispose();
                          _lignes.removeAt(i);
                        }),
                      ),
                      const SizedBox(height: 10),
                    ],
                    GhostButton(label: '+ Ajouter une ligne', onPressed: () => setState(_addLigne)),
                    const SizedBox(height: 16),
                    _TotalsCard(surfaceTotale: _surfaceTotale, montantTotal: _montantTotal),
                    const SizedBox(height: 16),
                    GoldButton(
                      label: _saving ? 'Enregistrement…' : "Enregistrer toutes les lignes",
                      icon: Icons.save_outlined,
                      onPressed: _saving ? () {} : _enregistrer,
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: GhostButton(
                          label: _generatingPdf ? '…' : 'Aperçu / Imprimer',
                          onPressed: _generatingPdf ? () {} : () => _genererPdf(partager: false),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GhostButton(
                          label: 'Partager',
                          onPressed: _generatingPdf ? () {} : () => _genererPdf(partager: true),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 28),
                    Text('Historique des commandes', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 10),
                    if (_historique.isEmpty)
                      const EmptyState(icon: Icons.window_outlined, text: 'Aucune commande enregistrée pour le moment.')
                    else
                      for (final c in _historique) ...[
                        _HistoriqueTile(commande: c, onDelete: () => _supprimerCommande(c)),
                        const SizedBox(height: 8),
                      ],
                  ],
                ),
              ),
      ),
    );
  }
}

/// Une carte de saisie pour une ligne du calculateur : type de vitre,
/// dimensions, quantité, et le montant de la ligne recalculé en direct.
class _LigneCard extends StatelessWidget {
  final _LigneCalc ligne;
  final List<String> options;
  final bool nouveauType;
  final double montant;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  const _LigneCard({
    super.key, required this.ligne, required this.options, required this.nouveauType, required this.montant,
    required this.onChanged, required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: CatalogPickerField(
                  options: options,
                  initialValue: ligne.typeVitre,
                  hintText: 'Type de vitre',
                  customHintText: 'Nouveau type (ex : FUMÉ 6mm)',
                  onChanged: (v) {
                    ligne.typeVitre = v;
                    onChanged();
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.textFaint, size: 20),
                onPressed: onDelete,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _NumField(label: 'Largeur (m)', ctrl: ligne.largeurCtrl, onChanged: onChanged)),
              const SizedBox(width: 8),
              Expanded(child: _NumField(label: 'Hauteur (m)', ctrl: ligne.hauteurCtrl, onChanged: onChanged)),
              const SizedBox(width: 8),
              Expanded(child: _NumField(label: 'Qté', ctrl: ligne.quantiteCtrl, onChanged: onChanged, integer: true)),
            ],
          ),
          if (nouveauType) ...[
            const SizedBox(height: 10),
            _NumField(label: 'Prix / m² (nouveau tarif, FCFA)', ctrl: ligne.nouveauPrixCtrl, onChanged: onChanged),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: Text(fmtFcfa(montant), style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ],
      ),
    );
  }
}

class _NumField extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final VoidCallback onChanged;
  final bool integer;
  const _NumField({required this.label, required this.ctrl, required this.onChanged, this.integer = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: context.textMuted, fontSize: 11)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          keyboardType: TextInputType.numberWithOptions(decimal: !integer),
          decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
          onChanged: (_) => onChanged(),
        ),
      ],
    );
  }
}

class _TotalsCard extends StatelessWidget {
  final double surfaceTotale;
  final double montantTotal;
  const _TotalsCard({required this.surfaceTotale, required this.montantTotal});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: AppColors.surfaceHover, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SURFACE TOTALE', style: TextStyle(color: context.textMuted, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
              const SizedBox(height: 4),
              Text('${surfaceTotale.toStringAsFixed(3)} m²', style: TextStyle(color: context.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('MONTANT TOTAL', style: TextStyle(color: context.textMuted, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
              const SizedBox(height: 4),
              Text(fmtFcfa(montantTotal), style: const TextStyle(color: AppColors.gold, fontSize: 17, fontWeight: FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistoriqueTile extends StatelessWidget {
  final CommandeVitre commande;
  final VoidCallback onDelete;
  const _HistoriqueTile({required this.commande, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final c = commande;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.typeVitre, style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 13.5)),
                const SizedBox(height: 3),
                Text(
                  '${c.largeur.toStringAsFixed(2)} × ${c.hauteur.toStringAsFixed(2)} m  ×${c.quantite}  ·  ${c.surface.toStringAsFixed(3)} m²',
                  style: TextStyle(color: context.textMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(fmtFcfa(c.montant), style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w700, fontSize: 13.5)),
              const SizedBox(height: 4),
              InkWell(
                onTap: onDelete,
                child: const Icon(Icons.close, color: AppColors.textFaint, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Gestion du tarif de référence (tarifs_vitres) : modification du prix en
/// place, suppression, et ajout d'un nouveau type — même écran que
/// open_tarifs_manager côté ordinateur, en feuille modale sur mobile.
class _TarifsManagerSheet extends StatefulWidget {
  final TarifVitreRepository repo;
  const _TarifsManagerSheet({required this.repo});

  @override
  State<_TarifsManagerSheet> createState() => _TarifsManagerSheetState();
}

class _TarifsManagerSheetState extends State<_TarifsManagerSheet> {
  List<TarifVitre> _tarifs = [];
  bool _loading = true;
  final _newTypeCtrl = TextEditingController();
  final _newPrixCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _newTypeCtrl.dispose();
    _newPrixCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final tarifs = await widget.repo.all();
    if (!mounted) return;
    setState(() {
      _tarifs = tarifs;
      _loading = false;
    });
  }

  Future<void> _majPrix(TarifVitre t, double prix) async {
    await widget.repo.upsert(t.typeVitre, prix);
    await _load();
  }

  Future<void> _supprimer(TarifVitre t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Supprimer ce tarif ?', style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: const Text('Cette action est définitive.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler', style: TextStyle(color: AppColors.textMuted))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok != true) return;
    await widget.repo.delete(t);
    await _load();
  }

  Future<void> _ajouter() async {
    final nom = _newTypeCtrl.text.trim();
    if (nom.isEmpty) return;
    final prix = double.tryParse(_newPrixCtrl.text.replaceAll(',', '.')) ?? 0;
    await widget.repo.upsert(nom, prix);
    _newTypeCtrl.clear();
    _newPrixCtrl.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator(color: AppColors.gold)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_tarifs.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: EmptyState(icon: Icons.list_alt, text: 'Aucun tarif enregistré pour le moment.'),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _tarifs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (ctx, i) {
                final t = _tarifs[i];
                return _TarifRow(
                  key: ValueKey(t.id),
                  tarif: t,
                  onPrixChanged: (p) => _majPrix(t, p),
                  onDelete: () => _supprimer(t),
                );
              },
            ),
          ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(controller: _newTypeCtrl, decoration: const InputDecoration(hintText: 'Nouveau type (ex : FUMÉ 6mm)')),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(controller: _newPrixCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'Prix/m²')),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GoldButton(label: '+ Ajouter ce tarif', onPressed: _ajouter),
      ],
    );
  }
}

/// Une ligne du gestionnaire de tarifs, avec son propre champ prix
/// éditable en place (validé sur soumission/perte de focus).
class _TarifRow extends StatefulWidget {
  final TarifVitre tarif;
  final ValueChanged<double> onPrixChanged;
  final VoidCallback onDelete;
  const _TarifRow({super.key, required this.tarif, required this.onPrixChanged, required this.onDelete});

  @override
  State<_TarifRow> createState() => _TarifRowState();
}

class _TarifRowState extends State<_TarifRow> {
  late final TextEditingController _ctrl;

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _fmt(widget.tarif.prixM2));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final prix = double.tryParse(_ctrl.text.replaceAll(',', '.'));
    if (prix != null) widget.onPrixChanged(prix);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: AppColors.surfaceHover, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Expanded(child: Text(widget.tarif.typeVitre, style: TextStyle(color: context.textPrimary, fontSize: 13))),
          SizedBox(
            width: 90,
            child: TextField(
              controller: _ctrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
              onSubmitted: (_) => _submit(),
              onEditingComplete: _submit,
            ),
          ),
          IconButton(icon: const Icon(Icons.close, color: AppColors.textFaint, size: 18), onPressed: widget.onDelete),
        ],
      ),
    );
  }
}
