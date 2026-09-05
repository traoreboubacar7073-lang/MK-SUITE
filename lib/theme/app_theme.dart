import 'package:flutter/material.dart';

/// Palette de couleurs — reprise exactement de la version ordinateur
/// (ui/theme.py, COLORS) : bleu marine profond + or, l'identité visuelle
/// de MK Entreprise. Contrairement à Winner Style, MK Suite ne propose
/// qu'un thème sombre pour l'instant (comme la version ordinateur), pour
/// garder le même visage des deux côtés.
class AppColors {
  AppColors._();

  static const Color background = Color(0xFF0B1220); // bg_dark
  static const Color sidebar = Color(0xFF0A0E1A); // bg_sidebar
  static const Color surface = Color(0xFF141C2E); // bg_card
  static const Color surfaceHover = Color(0xFF1B2438); // bg_card_hover / bg_input
  static const Color border = Color(0xFF232E45);

  static const Color gold = Color(0xFFD4AF37);
  static const Color goldLight = Color(0xFFE8C766);
  static const Color goldDark = Color(0xFFB8952E);

  static const Color textPrimary = Color(0xFFF4F6F9);
  static const Color textMuted = Color(0xFF8B94A8);
  static const Color textFaint = Color(0xFF5A6478);

  static const Color success = Color(0xFF3DD68C);
  static const Color warning = Color(0xFFF5A623);
  static const Color danger = Color(0xFFE5484D);
  static const Color info = Color(0xFF4A9EFF);

  // Couleurs d'accent supplémentaires — uniquement pour distinguer chaque
  // module d'un coup d'œil dans le menu latéral (icônes), comme demandé
  // pour Winner Style : chaque module a sa propre couleur plutôt qu'une
  // seule couleur or répétée partout.
  static const Color purple = Color(0xFFA78BFA);
  static const Color teal = Color(0xFF2DD4BF);
  static const Color pink = Color(0xFFF472B6);
  static const Color indigo = Color(0xFF818CF8);

  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [goldLight, gold],
  );
}

/// Couleurs associées à chaque statut (devis, facture, sourcing, paie...) —
/// reprend la même logique que la version ordinateur (badges colorés).
class StatutColors {
  StatutColors._();

  static const Map<String, Color> map = {
    'En attente': AppColors.warning,
    'Accepté': AppColors.success,
    'Refusé': AppColors.danger,
    'Impayée': AppColors.danger,
    'Partielle': AppColors.warning,
    'Payée': AppColors.success,
    'En cours': AppColors.info,
    'Livré': AppColors.success,
    'Annulé': AppColors.textFaint,
    'Actif': AppColors.success,
    'Inactif': AppColors.textFaint,
  };

  static Color of(String statut) => map[statut] ?? AppColors.textMuted;
}

/// Petit raccourci pratique — identique dans l'esprit à Winner Style, mais
/// ici les couleurs "thème" ne changent jamais (pas de mode clair) :
/// garder ces getters permet aux écrans d'utiliser le même style d'écriture
/// (`context.textPrimary`, `context.cardBg`...) sans se soucier du thème.
extension ThemeHelpers on BuildContext {
  bool get isDark => true;
  Color get cardBg => AppColors.surface;
  Color get cardBorder => AppColors.border;
  Color get textPrimary => AppColors.textPrimary;
  Color get textMuted => AppColors.textMuted;
  Color get textFaint => AppColors.textFaint;
}

class AppTheme {
  AppTheme._();

  static ThemeData build() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: AppColors.gold,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.gold,
        secondary: AppColors.gold,
        surface: AppColors.surface,
        error: AppColors.danger,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
        fontFamily: 'Segoe UI',
      ).copyWith(
        headlineMedium: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 22),
        titleLarge: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 17),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceHover,
        hintStyle: const TextStyle(color: AppColors.textFaint, fontSize: 13.5),
        labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.gold, width: 1.4)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.gold,
          foregroundColor: AppColors.background,
          padding: const EdgeInsets.symmetric(vertical: 15),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.border),
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      dividerColor: AppColors.border,
      cardColor: AppColors.surface,
      dialogBackgroundColor: AppColors.surface,
      snackBarTheme: const SnackBarThemeData(backgroundColor: AppColors.surfaceHover, contentTextStyle: TextStyle(color: AppColors.textPrimary)),
    );
  }
}

/// Formate un montant en francs CFA (ex : "1 250 000 FCFA") — même
/// convention que la version ordinateur (voir GUIDE_UTILISATION.md).
String fmtFcfa(num amount) {
  final rounded = amount.round();
  final digits = rounded.abs().toString();
  final buffer = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  final sign = rounded < 0 ? '-' : '';
  return '$sign${buffer.toString()} FCFA';
}

/// Version courte d'un montant pour les petites cartes (ex : "2,45M FCFA").
String fmtFcfaCompact(double amount) {
  final abs = amount.abs();
  if (abs >= 1000000) return '${(amount / 1000000).toStringAsFixed(2).replaceAll('.', ',')}M FCFA';
  if (abs >= 1000) return '${(amount / 1000).toStringAsFixed(0)}k FCFA';
  return fmtFcfa(amount);
}
