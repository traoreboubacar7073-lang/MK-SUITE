# Modification des devis et synchronisation sans union des lignes

## État du lot

Toutes les modifications du commit c17a167 restent incluses : corrections de corbeille/sauvegarde/paiement/budget, assistant hors ligne, scanner vitres et centimètres, repères, historique et PDF. Ce lot ajoute l’édition des devis et change le contrat de synchronisation. Rien n’a été publié ni installé.

## Édition mobile

La fiche d’un devis non converti propose « Modifier le devis ». Le formulaire reprend le client, l’objet, la validité, la TVA et les lignes. Les quantités, descriptions et prix sont modifiables ; les lignes peuvent être ajoutées ou retirées. Le numéro et le sync_id du devis sont conservés. Le remplacement des lignes et le recalcul HT sont atomiques. La date limite reste calculée depuis la date d’émission initiale.

La sauvegarde d’une ancienne version du devis est refusée si un autre écran ou une synchronisation l’a modifié entre-temps. Les devis déjà convertis sont verrouillés pour éviter une divergence avec la facture. La création d’un devis et sa conversion en facture sont également transactionnelles ; une seconde conversion est refusée.

## Diagnostic du doublage

Le code précédent faisait une union des lignes par sync_id. Des identifiants régénérés d’un côté pouvaient alors produire deux exemplaires d’un même contenu. Ce mécanisme est présent dans le code mobile ; la cause précise sur les données de l’utilisateur n’est pas confirmée sans les deux versions et une sauvegarde anonymisée.

## Nouveau contrat v2

Un export cohérent en transaction porte `version: 2` et `document_lines_mode: snapshot`. Chaque document est accompagné de son ensemble complet de lignes, avec références au sync_id parent.

- Document distant plus récent : remplacement complet de son contenu, jamais ajout à l’ancienne liste. Une liste vide signifie la suppression explicite de toutes les lignes.
- Document local plus récent : conservation de son contenu, puis propagation vers le pair.
- Même version et même contenu : aucune modification, même si les identifiants des lignes diffèrent. Le nombre de lignes identiques est comparé et conservé.
- Même version mais contenu différent : conflit signalé, contenu local conservé. Le client n’envoie pas automatiquement sa base si un conflit local est détecté. Les autres documents sans conflit peuvent avoir été importés ; il ne s’agit pas d’un rollback global des conflits.
- Paquet incomplet, lignes sans parent, ou ancien protocole : refus avant import destructif. Les anciens appareils doivent être mis à jour. Les nouveaux champs de vitres doivent aussi exister des deux côtés.

Il n’y a pas de suppression automatique des doublons historiques : deux lignes identiques peuvent être intentionnelles. La modification du devis permet de corriger le contenu après comparaison et sauvegarde. Cette correction ne doit être propagée qu’entre appareils compatibles v2.

## Sources ordinateur

Le RAR fourni a été inspecté : il contient une application Python avec modules de gestion et SQLite, mais aucun module de synchronisation ni références à sync_id dans db_manager.py. Il ne correspond donc pas à la version ordinateur qui échange actuellement avec le téléphone. Il faut récupérer les sources exactes de cette version pour implémenter et tester le même contrat côté ordinateur. Aucune correction ordinateur n’est annoncée comme réalisée.

## Validation

Sept scénarios de décision ont été exécutés directement en Dart : nouveau document, version récente, ancienne version, identifiants différents sans doublage, répétitions légitimes, conflit, liste vide. Le formateur Dart valide la syntaxe des fichiers modifiés et git diff --check passe.

Des tests Flutter/SQLite ont été ajoutés pour l’édition sans changement de numéro, le refus d’une édition périmée, deux imports successifs sans doublage, les conflits et les paquets incomplets/anciens. Ils ne sont pas exécutés ici en raison du blocage de dépendances déjà documenté. Le test réel téléphone ↔ ordinateur, la caméra, l’APK et la recette visuelle restent à faire.
