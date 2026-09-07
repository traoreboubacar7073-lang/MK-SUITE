import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/whatsapp_service.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  const AppCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.cardBorder),
          ),
          child: child,
        ),
      ),
    );
  }
}

class StatutBadge extends StatelessWidget {
  final String statut;
  const StatutBadge({super.key, required this.statut});

  @override
  Widget build(BuildContext context) {
    final color = StatutColors.of(statut);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        statut,
        // Texte toujours en blanc (couleur de premier plan du thème sombre
        // unique de MK Suite) plutôt que dans la couleur d'accent du statut,
        // qui serait parfois peu lisible en texte plein sur le fond teinté.
        style: TextStyle(color: context.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class GoldButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  const GoldButton({super.key, required this.label, required this.onPressed, this.icon});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[Icon(icon, size: 19), const SizedBox(width: 8)],
            Text(label),
          ],
        ),
      ),
    );
  }
}

class GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const GhostButton({super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      ),
    );
  }
}

/// Bouton "Envoyer par WhatsApp" — couleur dédiée (vert WhatsApp) pour se
/// distinguer clairement des actions dorées habituelles de l'app, utilisé
/// sur les fiches devis/facture/reçu.
class WhatsappButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const WhatsappButton({super.key, this.label = 'Envoyer par WhatsApp', required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF25D366),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.chat_bubble_outline, size: 19),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

class AppAvatar extends StatelessWidget {
  final String name;
  final double size;
  const AppAvatar({super.key, required this.name, this.size = 44});

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    final letters = parts.take(2).map((p) => p.isNotEmpty ? p[0].toUpperCase() : '').join();
    return letters.isEmpty ? '?' : letters;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.goldGradient),
      alignment: Alignment.center,
      child: Text(
        _initials,
        style: TextStyle(color: AppColors.background, fontWeight: FontWeight.w700, fontSize: size * 0.38),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const EmptyState({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: context.textFaint),
            const SizedBox(height: 12),
            Text(text, style: TextStyle(color: context.textFaint, fontSize: 14), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

void showFormError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: AppColors.danger),
  );
}

void showFormSuccess(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: AppColors.success),
  );
}

Future<bool> confirmDelete(BuildContext context, {required String nom, String? typeElement}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Supprimer ${typeElement ?? "cet élément"} ?', style: const TextStyle(color: AppColors.textPrimary, fontSize: 16)),
      content: Text('« $nom » sera déplacé dans la corbeille et pourra être restauré pendant 30 jours.', style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler', style: TextStyle(color: AppColors.textMuted))),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600))),
      ],
    ),
  );
  return result ?? false;
}

class ScreenHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final Widget? action;

  const ScreenHeader({super.key, required this.eyebrow, required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(eyebrow.toUpperCase(), style: const TextStyle(color: AppColors.gold, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                const SizedBox(height: 3),
                Text(title, style: Theme.of(context).textTheme.headlineMedium),
              ],
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class FabRound extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  const FabRound({super.key, required this.onPressed, this.icon = Icons.add});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 42,
        height: 42,
        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.goldGradient),
        child: const Icon(Icons.add, color: AppColors.background, size: 22),
      ),
    );
  }
}

/// Sélecteur relié à un catalogue existant (ex : fournisseurs, catégories)
/// avec une option "+ Autre" pour saisir librement une valeur absente du
/// catalogue.
class CatalogPickerField extends StatefulWidget {
  final List<String> options;
  final String? initialValue;
  final String hintText;
  final String customHintText;
  final ValueChanged<String?> onChanged;
  const CatalogPickerField({
    super.key, required this.options, this.initialValue, this.hintText = 'Choisir…',
    this.customHintText = 'Saisir une valeur personnalisée', required this.onChanged,
  });

  @override
  State<CatalogPickerField> createState() => _CatalogPickerFieldState();
}

class _CatalogPickerFieldState extends State<CatalogPickerField> {
  static const _customKey = '__autre__';
  String? _selected;
  late TextEditingController _customCtrl;

  @override
  void initState() {
    super.initState();
    _customCtrl = TextEditingController();
    final initial = widget.initialValue;
    if (initial != null && initial.isNotEmpty) {
      if (widget.options.contains(initial)) {
        _selected = initial;
      } else {
        _selected = _customKey;
        _customCtrl.text = initial;
      }
    }
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: _selected,
          dropdownColor: AppColors.surface,
          isExpanded: true,
          hint: Text(widget.hintText, style: TextStyle(color: context.textFaint)),
          items: [
            for (final o in widget.options)
              DropdownMenuItem(value: o, child: Text(o, style: TextStyle(color: context.textPrimary), overflow: TextOverflow.ellipsis)),
            const DropdownMenuItem(value: _customKey, child: Text('+ Autre (saisir)', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w600))),
          ],
          onChanged: (v) {
            setState(() => _selected = v);
            widget.onChanged(v == _customKey ? _customCtrl.text.trim() : v);
          },
        ),
        if (_selected == _customKey) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _customCtrl,
            decoration: InputDecoration(hintText: widget.customHintText),
            onChanged: (v) => widget.onChanged(v.trim()),
          ),
        ],
      ],
    );
  }
}

Future<T?> showAppBottomSheet<T>(BuildContext context, {required String title, required Widget child}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text(title, style: Theme.of(ctx).textTheme.titleLarge)),
                      IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close, color: AppColors.textPrimary, size: 20)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  child,
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Fenêtre d'envoi WhatsApp réutilisable — message pré-rédigé (modifiable)
/// puis ouverture directe de la conversation du client. `onOuvert`, si
/// fourni, se déclenche juste après l'ouverture réussie de WhatsApp (avant
/// la fermeture de cette fenêtre) — utilisé pour enchaîner sur le partage
/// natif du PDF (voir les écrans détail devis/facture/reçu), puisque
/// WhatsApp ne permet jamais à une app tierce de joindre un fichier toute
/// seule : l'utilisateur retape sur WhatsApp dans le sélecteur de partage
/// qui s'ouvre juste après pour terminer l'envoi.
class WhatsappMessageSheet extends StatefulWidget {
  final String telephone;
  final String messageInitial;
  final String introTexte;
  final VoidCallback? onOuvert;
  const WhatsappMessageSheet({super.key, required this.telephone, required this.messageInitial, required this.introTexte, this.onOuvert});

  @override
  State<WhatsappMessageSheet> createState() => _WhatsappMessageSheetState();
}

class _WhatsappMessageSheetState extends State<WhatsappMessageSheet> {
  late final TextEditingController _messageCtrl;
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    _messageCtrl = TextEditingController(text: widget.messageInitial);
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _ouvrir() async {
    setState(() => _envoi = true);
    final ok = await WhatsappService.ouvrirConversation(numero: widget.telephone, message: _messageCtrl.text.trim());
    if (!mounted) return;
    setState(() => _envoi = false);
    if (ok) {
      widget.onOuvert?.call();
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible d'ouvrir WhatsApp — vérifiez que l'application est installée.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${widget.introTexte} (${widget.telephone}).', style: TextStyle(color: context.textFaint, fontSize: 12.5)),
        const SizedBox(height: 14),
        Text('Message', style: TextStyle(color: context.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(controller: _messageCtrl, maxLines: 5, decoration: const InputDecoration()),
        const SizedBox(height: 18),
        GoldButton(
          label: _envoi ? 'Ouverture…' : (widget.onOuvert != null ? 'Ouvrir WhatsApp, puis joindre le PDF' : 'Ouvrir WhatsApp'),
          icon: Icons.chat_bubble_outline,
          onPressed: _envoi ? () {} : _ouvrir,
        ),
        const SizedBox(height: 10),
        GhostButton(label: 'Ne pas envoyer maintenant', onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }
}

/// Grande icône ronde colorée avec un badge au centre — utilisée pour les
/// indicateurs du tableau de bord et les en-têtes de page.
class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const IconBadge({super.key, required this.icon, this.color = AppColors.gold, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(size / 2)),
      alignment: Alignment.center,
      child: Icon(icon, color: AppColors.background, size: size * 0.46),
    );
  }
}
