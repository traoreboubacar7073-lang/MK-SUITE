import 'package:flutter/material.dart';
import '../data/repository.dart';
import '../theme/app_theme.dart';

/// Une alerte à afficher dans la cloche de notifications de la barre du
/// haut — remplace l'ancien encart "Alertes" qui vivait dans le tableau de
/// bord (comme sur Winner Style : la cloche + un badge de compte, plutôt
/// qu'un bloc fixe sur l'écran d'accueil).
class AlertItem {
  final String titre;
  final String detail;
  final IconData icon;
  final Color color;
  const AlertItem({required this.titre, required this.detail, required this.icon, required this.color});
}

DateTime? _parseDateAlert(String? s) {
  if (s == null || s.isEmpty) return null;
  return DateTime.tryParse(s);
}

String _fmtDateCourtAlert(String? s) {
  final d = _parseDateAlert(s);
  if (d == null) return '—';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

/// Rassemble les mêmes alertes que _build_alerts() côté ordinateur :
/// factures encore dues émises il y a plus de 30 jours, et devis "En
/// attente" dont la date limite est dépassée ou dans moins de 7 jours.
/// Combinées, 6 au maximum.
Future<List<AlertItem>> computeAlerts() async {
  final clients = await ClientRepository().all();
  final nomClient = {for (final c in clients) c.id: c.nom};
  final factures = await FactureRepository().all();
  final devis = await DevisRepository().all();

  final now = DateTime.now();
  final seuilRetard = now.subtract(const Duration(days: 30));
  final alerts = <AlertItem>[];

  final facturesRetard = factures.where((f) {
    final d = _parseDateAlert(f.dateFacture);
    return f.resteAPayer > 0 && d != null && d.isBefore(seuilRetard);
  }).toList()
    ..sort((a, b) => (_parseDateAlert(a.dateFacture) ?? now).compareTo(_parseDateAlert(b.dateFacture) ?? now));

  for (final f in facturesRetard.take(5)) {
    final nom = nomClient[f.clientId] ?? 'Client ?';
    alerts.add(AlertItem(
      titre: 'Facture ${f.numero} en retard',
      detail: '$nom — ${fmtFcfa(f.resteAPayer)} dus',
      icon: Icons.error_outline,
      color: AppColors.danger,
    ));
  }

  final limiteProche = now.add(const Duration(days: 7));
  final aujourdhui = DateTime(now.year, now.month, now.day);
  final devisProches = devis.where((d) {
    if (d.statut != 'En attente' || d.dateLimite == null) return false;
    final dl = _parseDateAlert(d.dateLimite);
    return dl != null && !dl.isAfter(limiteProche);
  }).toList()
    ..sort((a, b) => (_parseDateAlert(a.dateLimite) ?? now).compareTo(_parseDateAlert(b.dateLimite) ?? now));

  for (final d in devisProches.take(5)) {
    final dl = _parseDateAlert(d.dateLimite);
    if (dl == null) continue;
    final expire = dl.isBefore(aujourdhui);
    final nom = nomClient[d.clientId] ?? 'Client ?';
    alerts.add(AlertItem(
      titre: 'Devis ${d.numero} ${expire ? "expiré" : "expire bientôt"}',
      detail: '$nom — limite le ${_fmtDateCourtAlert(d.dateLimite)}',
      icon: expire ? Icons.block : Icons.schedule,
      color: expire ? AppColors.danger : AppColors.warning,
    ));
  }

  return alerts.take(6).toList();
}
