# Scanner une feuille de vitres

Première implémentation Android, non compilée et non testée sur téléphone.

## Convention de Boubacar

`42 × 92,5 × 2 N1` représente une vitre de 42 cm par 92,5 cm, quantité 2, repère N1. La surface totale de cette ligne est 0,777 m². Le repère ne participe pas au calcul et plusieurs lignes portant le même repère sont conservées.

## Utilisation prévue

Calcul Vitres → Scanner les dimensions → Photographier ou Galerie → choisir le type de vitre → comparer/corriger le texte avec la photo → cocher la vérification → Ajouter au calcul. La liste existante est conservée. L'enregistrement reste une action distincte.

La saisie manuelle du calculateur est maintenant en **cm**. Les dimensions restent stockées en mètres pour préserver les calculs et les données historiques. Les repères sont conservés dans les commandes et ajoutés au PDF. Le PDF affiche les dimensions en cm.

## Reconnaissance et limites

Lecture locale via ML Kit Text Recognition latin, prise de photo via image_picker. Aucune API IA distante ni clé nécessaire. Le manuscrit de la photo de référence n'a pas été passé au moteur natif ici ; son taux de reconnaissance est inconnu. Une photo nette et de face reste nécessaire, et le texte reconnu est toujours vérifiable et modifiable.

Les fragments OCR sont regroupés par position verticale. Une feuille inclinée ou des chiffres mal reconnus peuvent désaligner les lignes : l'écran ne promet aucune certitude et exige la vérification du nombre de lignes, des repères, des dimensions et des quantités. Une ligne non comprise bloque l'import jusqu'à correction ou retrait explicite. Aucun remplacement automatique de O par 0 ou d'un chiffre douteux n'est effectué. Le formulaire fonctionne également en saisie manuelle si l'OCR échoue. Un nouvel essai efface le texte de l'essai précédent pour éviter un mélange de photos.

## Compatibilité

Schéma SQLite v3 : nouvelle colonne `commandes_vitres.repere`, vide pour les anciennes commandes. Migration v1 → v2 → v3 ou v2 → v3. Dimensions historiques non transformées. La sauvegarde inclut ce repère. **La version ordinateur doit être adaptée pour accepter cette colonne avant de synchroniser avec elle** ; ses sources sont absentes du dépôt. Une ancienne version mobile ne doit pas recevoir cette sauvegarde ou ces données de synchronisation.

Android minimum API 24 pour image_picker ; compileSdk déjà fixé à 36. Pas de permission de stockage générale ajoutée. Le plugin image_picker utilise l'application de capture système. La photo reste temporaire, non ajoutée à la sauvegarde. La récupération après interruption Android est prévue à l'ouverture du scanner ; si l'utilisateur revient au tableau de bord, il faut rouvrir le scanner.

## Vérifications réalisées

- Parsing syntaxique Dart via le formateur.
- Assertions Dart exécutées sur le parseur réel : cm vers m², virgules, quantité distincte du repère, repères répétés, rejet de lignes ambiguës.
- Schéma et migration SQL v3 vérifiés en SQLite.
- Vérification git des espaces et conflits.

Non réalisés : résolution des deux nouveaux plugins, analyse complète Flutter, tests Flutter, compilation APK, permissions/caméra réelles, OCR de la photo, inspection visuelle du PDF. Le blocage de dépendances déjà documenté dans VALIDATION.md n'a pas été contourné.

Sources techniques consultées :
- https://pub.dev/packages/image_picker
- https://pub.dev/packages/google_mlkit_text_recognition
- https://developers.google.com/ml-kit/vision/text-recognition/v2/android
