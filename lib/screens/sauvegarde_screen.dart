import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard;
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import '../services/backup_service.dart';

/// Sauvegarde — exporte toutes les données de l'application (clients,
/// devis, factures, reçus, dépenses, employés...) dans un fichier partageable,
/// et permet de restaurer une sauvegarde précédente. Pendant, côté
/// téléphone, de `modules/sauvegarde.py` côté ordinateur.
class SauvegardeScreen extends StatefulWidget {
  const SauvegardeScreen({super.key});

  @override
  State<SauvegardeScreen> createState() => _SauvegardeScreenState();
}

class _SauvegardeScreenState extends State<SauvegardeScreen> {
  bool _exportEnCours = false;

  Future<void> _exporter() async {
    setState(() => _exportEnCours = true);
    try {
      await BackupService.partagerSauvegarde();
    } catch (_) {
      if (mounted) showFormError(context, 'Impossible de générer la sauvegarde.');
    } finally {
      if (mounted) setState(() => _exportEnCours = false);
    }
  }

  Future<void> _restaurer() async {
    await showAppBottomSheet(
      context,
      title: 'Restaurer une sauvegarde',
      child: _RestaurationForm(onSuccess: () => Navigator.of(context).pop()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sauvegarde')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            const ScreenHeader(eyebrow: 'Protection des données', title: 'Sauvegarde'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [Icon(Icons.save_outlined, color: AppColors.gold, size: 20), SizedBox(width: 8), Text('Exporter une sauvegarde', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 14))]),
                  const SizedBox(height: 8),
                  Text(
                    'Enregistre une copie complète de toutes tes données (clients, devis, factures, reçus, dépenses, employés...) dans un fichier que tu peux partager où tu veux — WhatsApp, email, Google Drive, clé USB via un gestionnaire de fichiers.',
                    style: TextStyle(color: context.textFaint, fontSize: 12.5),
                  ),
                  const SizedBox(height: 14),
                  GoldButton(label: _exportEnCours ? 'Préparation…' : 'Enregistrer une sauvegarde', icon: Icons.ios_share, onPressed: _exportEnCours ? () {} : _exporter),
                ],
              ),
            ),
            const SizedBox(height: 14),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [Icon(Icons.restore_outlined, color: AppColors.danger, size: 20), SizedBox(width: 8), Text('Restaurer une sauvegarde', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700, fontSize: 14))]),
                  const SizedBox(height: 8),
                  Text(
                    "Remplace TOUTES les données actuelles par celles d'une sauvegarde précédemment exportée. À utiliser avec précaution : les données présentes sur ce téléphone avant la restauration seront perdues.",
                    style: TextStyle(color: context.textFaint, fontSize: 12.5),
                  ),
                  const SizedBox(height: 14),
                  GhostButton(label: 'Restaurer depuis un fichier', onPressed: _restaurer),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RestaurationForm extends StatefulWidget {
  final VoidCallback onSuccess;
  const _RestaurationForm({required this.onSuccess});

  @override
  State<_RestaurationForm> createState() => _RestaurationFormState();
}

class _RestaurationFormState extends State<_RestaurationForm> {
  final _texteCtrl = TextEditingController();
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _texteCtrl.dispose();
    super.dispose();
  }

  Future<void> _collerDepuisPressePapier() async {
    final data = await Clipboard.getData('text/plain');
    if (!mounted) return;
    if (data?.text != null) {
      setState(() => _texteCtrl.text = data!.text!);
    }
  }

  Future<void> _confirmerEtRestaurer() async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Restaurer cette sauvegarde ?', style: TextStyle(color: context.textPrimary, fontSize: 16)),
        content: Text(
          "Toutes les données actuelles de l'application seront remplacées par celles-ci. Cette action ne peut pas être annulée.",
          style: TextStyle(color: context.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Annuler', style: TextStyle(color: context.textMuted))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restaurer', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (confirme != true) return;

    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final reussi = await BackupService.restaurerDepuisTexte(_texteCtrl.text);
      if (!mounted) return;
      if (reussi) {
        showFormSuccess(context, 'Sauvegarde restaurée avec succès.');
        widget.onSuccess();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _erreur = "Ce contenu n'a pas pu être lu — vérifie qu'il s'agit bien d'une sauvegarde MK Suite complète.");
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Ouvre le fichier de sauvegarde exporté (dans tes fichiers, Google Drive, WhatsApp, email...), copie tout son contenu, puis colle-le ci-dessous.",
          style: TextStyle(color: context.textFaint, fontSize: 12.5),
        ),
        const SizedBox(height: 12),
        GhostButton(label: 'Coller depuis le presse-papier', onPressed: _collerDepuisPressePapier),
        const SizedBox(height: 12),
        TextField(
          controller: _texteCtrl,
          maxLines: 8,
          style: TextStyle(color: context.textPrimary, fontSize: 12),
          decoration: const InputDecoration(hintText: '{ "application": "MK Suite", ... }'),
        ),
        if (_erreur != null) ...[
          const SizedBox(height: 8),
          Text(_erreur!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
        ],
        const SizedBox(height: 18),
        GoldButton(label: _enCours ? 'Restauration…' : 'Restaurer maintenant', onPressed: _enCours ? () {} : _confirmerEtRestaurer),
      ],
    );
  }
}
