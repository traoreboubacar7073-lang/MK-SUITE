# MK Suite — revue initiale et première évolution

## Périmètre

Base examinée : dépôt mobile Flutter, commit d1c0309. Le code Python de la version ordinateur est mentionné dans les commentaires mais absent de ce dépôt. Cette revue initiale du schéma, des services et des chemins critiques n'est pas une recette complète de chaque écran sur téléphone. Ne pas remplacer l'application utilisée avant sauvegarde et recette.

## Corrections du premier lot

- Corbeille : ajout de `updated_at` avec migration SQLite v1 vers v2. Les suppressions écrivaient une colonne inexistante.
- Suppression et restauration en transaction : un échec ne laisse plus une opération à moitié effectuée. Suppression du remplacement silencieux d'une ligne existante lors de la restauration ; une collision annule maintenant toute la restauration. Conservation des identifiants pour préserver les relations locales.
- Sauvegarde : un échec d'export ne produit plus silencieusement une table vide. Restauration complète seulement après validation de la présence des tables ; suppression des enfants avant les parents puis réinsertion dans l'ordre inverse, dans une transaction. Un import partiel est refusé au lieu de laisser des données mélangées.
- Paiement : relecture de la facture dans une transaction, refus des montants non finis, négatifs, nuls ou supérieurs au solde courant ; reçu facultatif dans la même transaction. Cela évite les calculs sur une ancienne facture et les paiements sans reçu après un échec d'insertion.
- Budget : dépenses sans allocation signalées « Sans budget » plutôt qu'un indicateur neutre.
- Identifiants de synchronisation : générateur aléatoire sécurisé.
- GitHub Actions : analyse et tests avant compilation APK.

## Nouvelle fonction livrée dans le code

Menu « Assistant MK », utilisable hors connexion :

- bilan des soldes restant à payer ;
- total des dépenses du mois, filtrées par année et mois ;
- priorités de relance par montant restant ;
- brouillon de relance par facture, à vérifier et copier manuellement ;
- actualisation, gestion d'erreur et état de chargement.

Ce module utilise des règles et des modèles de texte. Il ne s'agit pas encore d'une IA conversationnelle et il ne calcule pas le bénéfice réel.

## Points ouverts et ordre proposé

1. **Synchronisation** : HTTP local sans authentification ; ajouter appairage et contrôle d'accès coordonnés avec la version ordinateur. Ne pas exposer le port 8642 à internet. Les suppressions de parents encore référencés peuvent être refusées par les clés étrangères ; définir une politique d'archivage. La purge des tombstones à 30 jours peut faire réapparaître des données si un appareil reste longtemps hors ligne. Les imports de corbeille nécessitent une liste blanche des tables.
2. **Écritures commerciales** : création devis/lignes et conversion devis/facture à rendre atomiques ; empêcher la conversion multiple d'un même devis. Revoir numérotation concurrente et réutilisation après suppression. La création de reçus indépendants ne rapproche pas automatiquement une facture : clarifier l'usage avant modification.
3. **Sauvegarde** : export à rendre cohérent par transaction de lecture, ajout d'une version de format, sélection native de fichier, historique et test sur une copie réelle anonymisée. Pas de restauration automatique des tables inconnues.
4. **Qualité d'interface** : erreurs lisibles, validation uniforme des nombres, états vides, accessibilité, ergonomie tablette ; pas de refonte globale sans recette des modules existants.
5. **Nouveaux modules** : stock et seuils d'alerte, suivi des chantiers et marges, pièces jointes, exports CSV, journal des opérations et rôles. Chaque module doit être compatible avec la version ordinateur et les sauvegardes.

## IA conversationnelle envisagée

Premiers usages : reformuler un devis, rédiger une relance, expliquer le bilan, proposer une liste de tâches. Architecture : application → serveur MK authentifié → fournisseur IA. Les clés du fournisseur restent sur le serveur, jamais dans l'APK. Le modèle ne reçoit que les informations choisies ; aucune modification financière ou communication externe automatique. Les calculs financiers restent effectués et vérifiés localement.

L'activation exige un serveur, une authentification, un fournisseur et un budget d'utilisation. Aucun service payant ni transfert de données n'est activé dans ce lot. Il faut aussi prévoir limites de requêtes, délais, indisponibilité, validation des réponses et confirmation des actions proposées. Le choix du fournisseur et du modèle devra être vérifié dans sa documentation au moment de l'intégration.

## Validation

Tests ajoutés : bilan vide, filtre mensuel, relance sur solde réel ; régression intégrée SQLite couvrant suppression/restauration avec lignes, paiements successifs depuis un objet périmé, rejet du surpaiement et de NaN, restauration relationnelle et rejet d'une sauvegarde incomplète.

Le résultat effectif des vérifications est consigné dans `docs/VALIDATION.md`. Une compilation APK et une recette sur Android restent nécessaires avant diffusion ; le code ordinateur n'a pas été modifié.
