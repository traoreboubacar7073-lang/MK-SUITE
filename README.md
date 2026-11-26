# MK Suite

Application mobile Flutter de gestion MK Entreprise : clients, devis, factures, reçus, dépenses, budget, fournisseurs, paie, vitres, synchronisation locale et sauvegarde.

## Version 1.1.0 — en validation

Le module Calcul Vitres accepte les mesures en centimètres et propose un scanner photo avec vérification manuelle. Les repères N1, N2… sont distincts des quantités ×2, ×3… et sont conservés dans l’historique et le PDF. Voir [le fonctionnement du scanner](docs/SCAN_VITRES.md). La compatibilité de synchronisation avec le logiciel ordinateur doit être mise à jour avant utilisation.

## Première évolution

Un assistant hors ligne propose un bilan des soldes, les dépenses du mois et des brouillons de relance. Les calculs sont déterministes ; aucune IA distante ni transmission de données n'est activée.

Voir [la revue et la feuille de route](docs/AUDIT_ET_EVOLUTION.md), ainsi que [les résultats et limites de validation](docs/VALIDATION.md).

## Développement

Avec Flutter installé :

```sh
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --release
```

Sauvegarder les données avant toute installation de test. La migration SQLite passe du schéma 1 ou 2 au schéma 3 ; une rétrogradation vers une ancienne application n'est pas prise en charge. Tester d'abord sur une copie, notamment la synchronisation avec l'ordinateur.
