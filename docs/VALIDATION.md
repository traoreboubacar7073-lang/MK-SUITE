# Validation du premier lot

- PASS : analyse syntaxique par `dart format` des nouveaux fichiers Dart, tests et fichiers de données/services modifiés.
- PASS : `git diff --check`.
- PASS : exécution de 28 instructions SQL extraites du schéma réel dans SQLite avec clés étrangères activées.
- PASS : migration de la colonne `corbeille.updated_at` et reprise de `deleted_at`.
- PASS : suppression en ordre inverse et réimport des données relationnelles avec conservation des lignes de devis ; `PRAGMA foreign_key_check` vide.

## Non exécuté

`flutter analyze`, `flutter test`, compilation APK et recette visuelle Android : non exécutés. Le contrôle automatique a rejeté la commande d'installation des dépendances Flutter à cause d'une tentative inattendue d'accès au service de métadonnées cloud, susceptible d'exposer des informations sensibles. Aucun contournement tenté. Les tests Dart ajoutés ne sont donc pas présentés comme réussis.

La vérification SQL ne remplace pas l'exécution des méthodes Dart. Les tests de régression sont prêts dans `test/`, et le workflow GitHub les exécute avant compilation lorsqu'il est lancé dans un environnement autorisé et correctement équipé.

Les modifications sont locales, non poussées sur GitHub, non installées sur un téléphone. Aucune IA distante n'est connectée. La version ordinateur demeure hors périmètre faute de sources dans ce dépôt.

## Version 1.1.0 — scanner vitres

- PASS : huit scénarios exécutés par assertions Dart sur le parseur réel (dont 185,5 cm → 1,855 m ; surface de deux pièces 185,5 × 100 cm → 3,71 m²).
- PASS : séparation des repères et quantités, conservation des repères répétés, rejet des lignes incomplètes ou ambiguës.
- PASS : création et migration SQL v3 avec conservation des anciennes dimensions en mètres.
- Version applicative portée à 1.1.0+2.
- Branche de travail : feature/scanner-vitres-cm.

La reconnaissance native de l'image, l'interface sur téléphone et les tests Flutter n'ont pas été exécutés. Aucun nouveau lancement de la commande de dépendances précédemment rejetée.

## Complément devis / synchronisation

- PASS : sept scénarios de décision de synchronisation exécutés directement en Dart.
- PASS : vérification syntaxique des fichiers modifiés par dart format et git diff --check.
- Tests d’intégration ajoutés mais NON exécutés : édition devis, refus d’édition périmée, import répété et conflits.
- Protocole v2 désormais requis ; ancien ordinateur non compatible tant que ses sources exactes ne sont pas adaptées. Voir DEVIS_ET_SYNCHRONISATION.md.
