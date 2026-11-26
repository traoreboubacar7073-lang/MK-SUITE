# MK Suite ordinateur 1.1.2

Le code Windows fourni a été intégré au dépôt dans `desktop/`.

- Synchronisation v2 compatible avec le mobile : contenu complet des devis et factures, conflits signalés et envoi suspendu lorsqu'un conflit local est détecté.
- Modification de ligne : la version du document parent est automatiquement renouvelée.
- Repères N1 conservés lors des échanges et affichés dans l'historique des vitres.
- Saisie des nouvelles dimensions en centimètres ; stockage historique en mètres inchangé.
- Copie SQLite `.before-1.1.2.bak` avant la migration additive des bases existantes.

Fermer MK Suite avant de remplacer l'ancien EXE. La base reste dans `MK_Suite_Data/mk_entreprise.db` du dossier utilisateur Windows. Faire également une sauvegarde depuis le logiciel avant la mise à jour. Aucun historique client n'est distribué dans le nouvel EXE.

Les doublons anciens ne sont pas retirés automatiquement : des lignes répétées peuvent être légitimes. Vérifier les documents concernés avant de les modifier et resynchroniser.

Compilation Windows : workflow GitHub « Vérifier et compiler MK Suite Windows ». L'exécutable est proposé uniquement après réussite de la compilation. L'exécution sur le PC et l'échange physique avec le téléphone restent à vérifier.

Les coordonnées des documents PDF sont maintenant locales : dans Sauvegarde, « Importer les coordonnées entreprise… » permet de charger le fichier privé `profil_entreprise.json`. Ce fichier doit être conservé séparément des sauvegardes de la base. Sans profil importé, les documents n'affichent pas les coordonnées de l'entreprise.
