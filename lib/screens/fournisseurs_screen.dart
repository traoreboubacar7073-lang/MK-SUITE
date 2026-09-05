import 'package:flutter/material.dart';
import '../data/repository.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

/// Module Fournisseurs — mobile.
///
/// Reprend fidèlement modules/fournisseurs.py de la version ordinateur :
/// liste des fournisseurs (nom, catégorie de produits, téléphone, adresse)
/// avec, pour chacun, le total des achats calculé automatiquement à partir
/// du registre des Dépenses (somme des montants où `beneficiaire` correspond
/// exactement au nom du fournisseur) — jamais saisi à la main.
class FournisseursScreen extends StatefulWidget {
  const FournisseursScreen({super.key});

  @override
  State<FournisseursScreen> createState() => _FournisseursScreenState();
}

class _FournisseursScreenState extends State<FournisseursScreen> {
  final _fournisseurRepo = FournisseurRepository();
  final _depenseRepo = DepenseRepository();

  List<Fournisseur> _fournisseurs = [];
  Map<String, double> _totaux = {};
  Map<String, int> _comptes = {};
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => setState(() => _search = _searchCtrl.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Une seule requête groupée sur les dépenses (comme la version
    // ordinateur) plutôt qu'une requête par fournisseur.
    final fournisseurs = await _fournisseurRepo.all();
    final depenses = await _depenseRepo.all();
    final totaux = <String, double>{};
    final comptes = <String, int>{};
    for (final d in depenses) {
      if (d.beneficiaire.isEmpty) continue;
      totaux[d.beneficiaire] = (totaux[d.beneficiaire] ?? 0) + d.montant;
      comptes[d.beneficiaire] = (comptes[d.beneficiaire] ?? 0) + 1;
    }
    if (!mounted) return;
    setState(() {
      _fournisseurs = fournisseurs;
      _totaux = totaux;
      _comptes = comptes;
      _loading = false;
    });
  }

  List<Fournisseur> get _filtered {
    if (_search.isEmpty) return _fournisseurs;
    return _fournisseurs.where((f) {
      return f.nom.toLowerCase().contains(_search) ||
          f.categorieProduits.toLowerCase().contains(_search) ||
          f.telephone.toLowerCase().contains(_search);
    }).toList();
  }

  List<String> get _categoriesExistantes {
    final set = _fournisseurs.map((f) => f.categorieProduits).where((c) => c.isNotEmpty).toSet().toList();
    set.sort();
    return set;
  }

  void _openAdd({Fournisseur? existing}) async {
    await showAppBottomSheet(
      context,
      title: existing != null ? 'Modifier le fournisseur' : 'Nouveau fournisseur',
      child: _FournisseurForm(
        existing: existing,
        categoriesExistantes: _categoriesExistantes,
        onSaved: () {
          Navigator.of(context).pop();
          _load();
        },
      ),
    );
  }

  void _openDetail(Fournisseur f) async {
    await showAppBottomSheet(
      context,
      title: f.nom,
      child: _FournisseurDetail(
        fournisseur: f,
        totalAchats: _totaux[f.nom] ?? 0,
        nombreDepenses: _comptes[f.nom] ?? 0,
        onEdit: () {
          Navigator.of(context).pop();
          _openAdd(existing: f);
        },
        onDelete: () async {
          final confirme = await confirmDelete(context, nom: f.nom, typeElement: 'ce fournisseur');
          if (!confirme) return;
          await _fournisseurRepo.delete(f);
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
      appBar: AppBar(title: const Text('Fournisseurs')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
            : _fournisseurs.isEmpty
                ? const EmptyState(icon: Icons.storefront_outlined, text: 'Aucun fournisseur enregistré.')
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search, size: 20, color: AppColors.textFaint),
                            hintText: 'Rechercher un fournisseur…',
                          ),
                        ),
                      ),
                      Expanded(
                        child: _filtered.isEmpty
                            ? const EmptyState(icon: Icons.search_off, text: 'Aucun fournisseur ne correspond à la recherche.')
                            : ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: _filtered.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (ctx, i) {
                                  final f = _filtered[i];
                                  final total = _totaux[f.nom] ?? 0;
                                  final sousTitre = [
                                    if (f.categorieProduits.isNotEmpty) f.categorieProduits,
                                    if (f.telephone.isNotEmpty) f.telephone,
                                  ].join(' · ');
                                  return AppCard(
                                    onTap: () => _openDetail(f),
                                    child: Row(
                                      children: [
                                        AppAvatar(name: f.nom, size: 42),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(f.nom, style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w600, fontSize: 14.5), overflow: TextOverflow.ellipsis),
                                              const SizedBox(height: 3),
                                              Text(
                                                sousTitre.isEmpty ? '—' : sousTitre,
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
                                            Text(total > 0 ? fmtFcfaCompact(total) : '—', style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 13)),
                                            const SizedBox(height: 2),
                                            Text('achats', style: TextStyle(color: context.textFaint, fontSize: 10)),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAdd(),
        backgroundColor: AppColors.gold,
        child: const Icon(Icons.add, color: Colors.black),
      ),
    );
  }
}

class _FournisseurForm extends StatefulWidget {
  final Fournisseur? existing;
  final List<String> categoriesExistantes;
  final VoidCallback onSaved;
  const _FournisseurForm({this.existing, required this.categoriesExistantes, required this.onSaved});

  @override
  State<_FournisseurForm> createState() => _FournisseurFormState();
}

class _FournisseurFormState extends State<_FournisseurForm> {
  final _repo = FournisseurRepository();
  final _nomCtrl = TextEditingController();
  final _telephoneCtrl = TextEditingController();
  final _adresseCtrl = TextEditingController();
  String? _categorie;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final f = widget.existing;
    if (f != null) {
      _nomCtrl.text = f.nom;
      _telephoneCtrl.text = f.telephone;
      _adresseCtrl.text = f.adresse;
      _categorie = f.categorieProduits.isEmpty ? null : f.categorieProduits;
    }
  }

  @override
  void dispose() {
    _nomCtrl.dispose();
    _telephoneCtrl.dispose();
    _adresseCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nom = _nomCtrl.text.trim();
    if (nom.isEmpty) {
      showFormError(context, 'Indique le nom du fournisseur avant d\'enregistrer.');
      return;
    }
    setState(() => _saving = true);
    try {
      final existing = widget.existing;
      if (existing != null) {
        final updated = Fournisseur(
          id: existing.id,
          syncId: existing.syncId,
          nom: nom,
          categorieProduits: _categorie ?? '',
          contact: existing.contact,
          telephone: _telephoneCtrl.text.trim(),
          adresse: _adresseCtrl.text.trim(),
          updatedAt: existing.updatedAt,
        );
        await _repo.update(updated);
      } else {
        await _repo.create(
          nom: nom,
          categorieProduits: _categorie ?? '',
          telephone: _telephoneCtrl.text.trim(),
          adresse: _adresseCtrl.text.trim(),
        );
      }
      if (!mounted) return;
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().toUpperCase().contains('UNIQUE')
          ? 'Un fournisseur nommé « $nom » existe déjà.'
          : 'Impossible d\'enregistrer ce fournisseur.';
      showFormError(context, msg);
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Nom du fournisseur *', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(controller: _nomCtrl, decoration: const InputDecoration()),
        const SizedBox(height: 14),
        Text('Catégorie de produits', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        CatalogPickerField(
          options: widget.categoriesExistantes,
          initialValue: _categorie,
          hintText: 'Choisir…',
          customHintText: 'Ex : Aluminium, Vitrerie…',
          onChanged: (v) => setState(() => _categorie = v),
        ),
        const SizedBox(height: 14),
        Text('Téléphone', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(controller: _telephoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(hintText: '+223 …')),
        const SizedBox(height: 14),
        Text('Adresse', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(controller: _adresseCtrl, decoration: const InputDecoration()),
        const SizedBox(height: 20),
        GoldButton(
          label: _saving ? 'Enregistrement…' : (widget.existing != null ? 'Enregistrer les modifications' : 'Enregistrer'),
          onPressed: _saving ? () {} : _save,
        ),
      ],
    );
  }
}

class _FournisseurDetail extends StatelessWidget {
  final Fournisseur fournisseur;
  final double totalAchats;
  final int nombreDepenses;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _FournisseurDetail({
    required this.fournisseur,
    required this.totalAchats,
    required this.nombreDepenses,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          fournisseur.categorieProduits.isEmpty ? 'Catégorie non renseignée' : fournisseur.categorieProduits,
          style: const TextStyle(color: AppColors.gold, fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow(label: 'Téléphone', value: fournisseur.telephone.isEmpty ? '—' : fournisseur.telephone),
              _DetailRow(label: 'Adresse', value: fournisseur.adresse.isEmpty ? '—' : fournisseur.adresse, last: true),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              const Text('TOTAL ACHATS', style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(fmtFcfa(totalAchats), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700, fontSize: 20)),
              const SizedBox(height: 4),
              Text('$nombreDepenses dépense${nombreDepenses > 1 ? 's' : ''} enregistrée${nombreDepenses > 1 ? 's' : ''}', style: const TextStyle(color: Colors.black87, fontSize: 11)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GhostButton(label: 'Modifier ce fournisseur', onPressed: onEdit),
        const SizedBox(height: 10),
        TextButton(
          onPressed: onDelete,
          style: TextButton.styleFrom(foregroundColor: AppColors.danger, padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
          child: const Text('Supprimer ce fournisseur', style: TextStyle(fontWeight: FontWeight.w600)),
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
