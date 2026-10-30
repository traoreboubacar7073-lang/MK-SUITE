import 'package:flutter_test/flutter_test.dart';
import 'package:mk_suite/models/models.dart';
import 'package:mk_suite/services/assistant_service.dart';

void main() {
  test('Le bilan vide ne prétend pas calculer un bénéfice', () {
    final bilan = AssistantService.bilan([], [], DateTime(2026, 10, 30));
    expect(bilan, contains('0 facture(s)'));
    expect(bilan, contains('Aucune facture à relancer'));
    expect(bilan, contains('ne constituent pas un calcul de bénéfice'));
  });
  test('Le bilan filtre les dépenses par année et mois', () {
    Depense depense(String date, double montant) =>
        Depense.fromMap({'id': 1, 'date_depense': date, 'montant': montant});
    final bilan = AssistantService.bilan([], [
      depense('2026-10-01', 150),
      depense('2025-10-01', 999),
      depense('2026-09-30', 888),
      depense('invalide', 777),
    ], DateTime(2026, 10, 30));
    expect(bilan, contains('ce mois : 150 FCFA'));
  });
  test('Relance fondée sur le solde réel sans inventer une échéance', () {
    final facture = Facture.fromMap({
      'id': 1,
      'numero': 'FA-001',
      'montant_ttc': 1000,
      'avance_recue': 600,
      'reste_a_payer': 400,
    });
    final texte = AssistantService.relance(facture, 'Traoré');
    expect(texte, contains('Bonjour Traoré'));
    expect(texte, contains('400 FCFA'));
    expect(texte, isNot(contains('1000 FCFA')));
  });
}
