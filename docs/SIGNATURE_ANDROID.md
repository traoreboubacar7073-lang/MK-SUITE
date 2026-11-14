# Une mise à jour de l’application existante

La distribution ne propose plus d’APK debug : seul un APK release signé peut être publié. Le code applicatif conserve `com.mkentreprise.mk_suite` et passe à `1.1.1+3`. Les essais internes peuvent toujours utiliser un identifiant debug séparé, mais leur APK n’est pas livré par ce workflow.

## Conditions nécessaires

L’application installée doit avoir le même identifiant, le même certificat de signature (ou une rotation officiellement compatible) et un numéro de version inférieur. Le ZIP fourni contient une clé release d’origine ; le certificat de l’application effectivement installée n’a pas encore été comparé. La compilation seule ne prouve donc pas la compatibilité de mise à jour.

L’installation par-dessus l’application existante doit préserver ses données locales, sous réserve de migrations correctes. Ne pas désinstaller l’application actuelle. Faire une sauvegarde avant la recette de migration.

## Secrets GitHub

Dans Settings → Secrets and variables → Actions, configurer :

- MK_KEYSTORE_BASE64 : contenu base64 de la clé JKS d’origine.
- MK_KEYSTORE_PASSWORD : mot de passe existant du magasin.
- MK_KEY_PASSWORD : mot de passe existant de la clé.
- MK_KEY_ALIAS : alias existant (par défaut mk-suite).

Aucune de ces valeurs ne doit être publiée dans le dépôt ni envoyée dans une conversation. La clé et ses mots de passe restent ceux de l’application existante. Leur configuration n’a pas été effectuée par ce changement de code.

## Compilation

Une PR exécute l’analyse et les tests. Un lancement manuel du workflow sur cette branche, ou un push sur main après intégration, ajoute la compilation release après les contrôles. Sans secrets, la compilation est arrêtée avec un message explicite ; aucun APK debug de substitution n’est publié. L’APK signé est vérifié puis déposé dans l’artefact mk-suite-mise-a-jour-release.

Avant installation sur le téléphone utilisé, vérifier le certificat et le versionCode de l’APK installé, tester les migrations sur une copie de la base et vérifier la compatibilité de synchronisation ordinateur. L’ancien protocole reste bloqué par les changements de synchronisation du lot précédent.

Les mots de passe et la clé avaient été exposés dans l’historique antérieur du dépôt public. Le retrait du dernier état n’efface pas cet historique. Ne pas remplacer arbitrairement la clé : cela empêcherait la mise à jour des installations existantes.
