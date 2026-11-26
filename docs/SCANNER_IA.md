# Scanner manuscrit — MK Suite 1.2.0

Le scanner local reste disponible, mais il ne garantit pas la lecture des chiffres manuscrits. Le mode IA lit une photo recadrée via le modèle de vision configuré sur l'ordinateur. La photo n'est pas envoyée avant l'action « Lire les dimensions avec l'IA ».

## Configuration Windows et téléphone

1. Mettre à jour les deux appareils et sauvegarder les données.
2. Windows : Synchronisation → Configurer le scanner IA manuscrit.
3. Saisir la clé de son compte API OpenAI et conserver le modèle proposé ou choisir un modèle compatible avec les images et les sorties structurées.
4. Enregistrer puis copier le code de connexion, différent de la clé API. La clé et le code sont protégés localement par Windows DPAPI. Ne pas les publier dans GitHub ou une conversation.
5. Démarrer le serveur Windows. Le PC reste allumé, sur le même Wi-Fi que le téléphone, avec Internet. La synchronisation de gestion reste locale ; seule la zone de photo choisie est envoyée à OpenAI par le scanner IA.
6. Téléphone : Calcul Vitres → Scanner → Connexion au scanner IA. Saisir l'adresse du PC et le code de connexion. Seule l'adresse est mémorisée sur le téléphone.
7. Photographier ou choisir une image, tracer une zone contenant toutes les lignes, les quantités et les repères N, puis lancer la lecture.
8. Comparer le nombre de lignes, corriger les champs « ? », choisir le type de vitre et confirmer avant import.

Les dimensions restent en cm. Les surfaces sont calculées localement en m². Les repères ne donnent jamais les quantités. L'ordre physique et les lignes répétées sont conservés. Un résultat partiel ou incohérent est refusé. Les incertitudes sont signalées et une vérification humaine reste obligatoire.

## Service hébergé ou système sans Windows

Le même serveur peut utiliser `MK_OPENAI_API_KEY`, `MK_SCANNER_TOKEN` (code privé robuste) et `MK_SCANNER_MODEL` (par défaut `gpt-6.2-sol`). Le point d'entrée est `/glass/recognize`. Pour un hébergement extérieur au Wi-Fi privé, configurer HTTPS, un pare-feu et un reverse proxy. Ne pas exposer le serveur de synchronisation entier sur Internet : ne publier que la route scanner nécessaire. Aucune clé API n'est compilée dans l'APK ou l'EXE.

La lecture est limitée à une requête simultanée, une photo JPEG de 5 Mio et un délai fournisseur de 75 secondes. Les répétitions de la même photo disposent d'un cache mémoire de deux minutes. MK Suite ne conserve pas la photo sur le serveur et demande `store=false` au fournisseur ; cela ne constitue pas une promesse sur les politiques de conservation du fournisseur.

## Validation et limites

Les tests simulent les réponses du fournisseur, les erreurs, les appels HTTP locaux et le chiffrement Windows. Ils ne démontrent pas la précision optique sur une photo réelle. La photo manuscrite fournie sert de référence visuelle privée, elle n'est pas publiée dans le dépôt. Le test des sept lignes vérifie uniquement leur interprétation après transcription.

Une clé API valide et un compte autorisé à utiliser le modèle sont nécessaires pour tester la reconnaissance réelle. L'abonnement ChatGPT ne doit pas être supposé fournir cette clé. La vitesse et la qualité réelles doivent être mesurées une fois le service configuré ; aucun taux de précision ni délai de lecture n'est garanti.
