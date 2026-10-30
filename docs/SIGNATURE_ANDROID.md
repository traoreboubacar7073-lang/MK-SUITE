# Signature Android et publication

Les mots de passe de signature et le fichier JKS ont été retirés de cette branche. La clé locale existante n’a pas été remplacée. Les anciennes versions publiques de ces fichiers peuvent rester accessibles dans l’historique du dépôt ; leur retrait du dernier état n’efface pas cet historique.

Le workflow produit désormais un APK **debug**, destiné à la recette, avec l’identifiant séparé `com.mkentreprise.mk_suite.debug`. Il s’installe à côté de l’application de production et possède ses propres données. Il ne met pas à jour l’application de production. La compilation et la coexistence réelle restent à vérifier sur Android. Ne pas désinstaller l’application de production pour tester cette version.

Pour compiler une mise à jour release, configurer dans un environnement sécurisé la même clé qu’auparavant et les variables MK_KEYSTORE_PATH, MK_KEYSTORE_PASSWORD, MK_KEY_PASSWORD, MK_KEY_ALIAS. Ne jamais les transmettre dans une conversation ou les committer. Le fournisseur d’intégration doit les injecter via ses secrets. Le code utilise uniquement ces variables et n’intègre aucun mot de passe.

Compte tenu de l’exposition antérieure, la stratégie de sécurisation de la clé et de l’historique doit être examinée avec le propriétaire sans changer arbitrairement l’identité de signature, nécessaire aux mises à jour existantes.
