import '../models/models.dart';

/// Deterministic local assistance. No model, network request or data mutation.
class AssistantService {
  static String bilan(
    List<Facture> factures,
    List<Depense> depenses,
    DateTime now,
  ) {
    final dues = factures.where((f) => f.resteAPayer > 0).toList()
      ..sort((a, b) => b.resteAPayer.compareTo(a.resteAPayer));
    final total = dues.fold<double>(0, (s, f) => s + f.resteAPayer);
    final mois = depenses.where((d) {
      final date = DateTime.tryParse(d.dateDepense);
      return date != null && date.year == now.year && date.month == now.month;
    });
    final depense = mois.fold<double>(0, (s, d) => s + d.montant);
    return 'Bilan au ${now.day}/${now.month}/${now.year}\n\n'
        '${dues.length} facture(s) avec un solde restant : ${total.toStringAsFixed(0)} FCFA.\n'
        'Dépenses enregistrées ce mois : ${depense.toStringAsFixed(0)} FCFA.\n\n'
        '${dues.isEmpty ? "Aucune facture à relancer." : "Priorité par montant restant :\n${dues.take(5).map((f) => '${f.numero} : ${f.resteAPayer.toStringAsFixed(0)} FCFA').join('\n')}"}\n\n'
        'Ces montants décrivent les données saisies ; ils ne constituent pas un calcul de bénéfice ou de trésorerie.';
  }

  static String relance(Facture facture, String client) =>
      'Bonjour $client,\nNous revenons vers vous concernant la facture '
      '${facture.numero}, dont le solde restant est de '
      '${facture.resteAPayer.toStringAsFixed(0)} FCFA. '
      'Pourriez-vous nous indiquer la date prévue de règlement ? '
      'Si le paiement a déjà été effectué, merci de nous transmettre le justificatif.\n'
      'Merci pour votre confiance.\nMK Entreprise';
}
