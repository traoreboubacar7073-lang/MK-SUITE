# Guide d'utilisation — MK Suite

Logiciel de gestion pour MK Entreprise (Bamako, Mali). Ce guide couvre tous les modules,
dans l'ordre du menu de gauche.

---

## 🏠 Tableau de bord

La première chose que tu vois en ouvrant le logiciel.

- **4 indicateurs en haut** : chiffre d'affaires du mois, dépenses du mois, factures impayées,
  nombre de clients actifs.
- **⚠️ Alertes** (n'apparaît que s'il y a quelque chose à signaler) : factures en retard de
  paiement depuis plus de 30 jours, devis qui expirent dans moins de 7 jours ou déjà expirés.
- **Graphique** : évolution du chiffre d'affaires sur les 6 derniers mois.
- **Activité récente** : dernières factures et derniers clients ajoutés.
- **💾 Sauvegarder mes données** (bouton en haut à droite) : crée une copie complète de ta
  base de données à l'endroit de ton choix (clé USB, dossier partagé...). **À faire
  régulièrement** — c'est ta seule protection contre la perte de données.

---

## 👥 Clients

- **+ Nouveau client** : nom, téléphone, adresse, type (Particulier / Entreprise-Chantier),
  statut. Un code `CL-001`, `CL-002`... est généré automatiquement.
- Clique sur un client pour voir sa fiche : coordonnées, nombre de devis/factures, total
  facturé, total encaissé, solde dû.
- **✏️ Modifier** / **Supprimer** disponibles depuis la fiche.
- Barre de recherche en haut : cherche par nom, téléphone ou code.

---

## 📋 Devis & Factures

Quatre onglets en haut : **Devis**, **Factures**, **Reçus**, **Notes**.

### Devis
- **+ Nouveau devis** : choisis le client, l'objet, la validité (en jours), puis remplis les
  lignes (Qté / Description / Prix unitaire).
- **Astuce clavier** : dans les lignes, appuie sur **Entrée** pour passer au champ suivant, et
  sur la dernière ligne, Entrée crée automatiquement une nouvelle ligne — comme dans Excel.
- Une fois un devis marqué **"Accepté"**, un bouton **🔄 Convertir en facture** apparaît : il
  crée la facture avec les mêmes lignes et applique la TVA 18% automatiquement.
- **✏️ Modifier** permet de tout changer (client, lignes, validité) après coup.

### Factures
- Mêmes principes que les devis, avec en plus : réduction (%), avance reçue, mode de paiement.
- Le **reste à payer** et le **statut** (Impayée / Partielle / Payée) se calculent tout seuls.
- Bouton **💰 Enregistrer un paiement** : tape le montant reçu, le solde se met à jour.

### Reçus et Notes
- Mêmes principes : créer, modifier, supprimer, générer un PDF.

### PDF
Chaque devis, facture, reçu ou note a un bouton **📄 Générer le PDF** — ça reprend l'en-tête
MK Entreprise (logo, coordonnées, N° fiscal) et s'ouvre automatiquement une fois créé.

---

## 🚚 Sourcing

Pour les commandes de matériaux achetés à un fournisseur puis revendus à un client.

- **+ Nouvelle commande** : fournisseur, client, désignation, quantité, prix d'achat et prix
  de vente unitaires. La **marge** (vente − achat) × quantité se calcule automatiquement.
- Statuts cliquables : **En cours / Livré / Annulé**.
- **✏️ Modifier** pour ajuster prix ou quantités après coup.
- Totaux globaux (achats, ventes, marge) en haut de la liste.

---

## 💳 Dépenses

Deux onglets : **📋 Registre** (liste complète, recherche et filtre par catégorie) et
**📅 Vue annuelle** (tableau croisé Catégorie × Mois pour voir où part l'argent sur l'année).

- **+ Nouvelle dépense** : date, catégorie (menu déroulant), description, fournisseur/bénéficiaire
  (menu déroulant avec tes 34 fournisseurs habituels), montant, mode de paiement.

---

## 📐 Calcul Vitres

Calculateur : **Surface = Largeur × Hauteur × Quantité**, prix repris automatiquement selon
le type de vitre choisi.

- Tape les dimensions, le montant s'affiche en temps réel.
- **💾 Enregistrer dans l'historique** pour garder une trace.
- **⚙️ Gérer les tarifs** : ajoute un nouveau type de vitre, modifie un prix au m², ou supprime
  un tarif obsolète.
- Chaque ligne de l'historique a un bouton **✕** pour la supprimer individuellement.

---

## 📊 Contrôle Budget

Compare ce que tu as prévu de dépenser à ce que tu as réellement dépensé, catégorie par
catégorie, mois par mois.

- Choisis un mois et une année.
- Tape le **budget alloué** pour chaque catégorie (Entrée ou clique ailleurs pour valider).
- Le logiciel calcule automatiquement les dépenses réelles, l'écart, le % utilisé, et une
  alerte : **OK** (vert), **Attention** (orange, ≥80%), **Dépassé** (rouge, >100%).

---

## 🏭 Fournisseurs

- **+ Nouveau fournisseur** : nom, catégorie de produits, téléphone, adresse.
- Le **total des achats** de chaque fournisseur est calculé automatiquement depuis le
  registre Dépenses (recherche par nom exact du bénéficiaire).
- **✏️ Modifier** / **Supprimer** sur chaque carte.

---

## 👔 Employés & Paie

Deux onglets : **👔 Employés** et **💰 Paie**.

### Employés
- **+ Nouvel employé** : nom, poste, téléphone, salaire mensuel, type de contrat (CDI/CDD/
  Journalier/Stage).
- Clique sur un employé pour modifier ses infos ou le supprimer.

### Paie
- Choisis un mois et une année.
- La liste affiche chaque employé actif avec son salaire dû, les avances déjà versées, et le
  **net à payer** calculé automatiquement.
- Bouton **💰 Payer** : confirme le montant et le mode de paiement → le badge passe à
  **✓ Payé**.
- Total dû / total payé affiché en bas pour le mois sélectionné.

---

## Raccourcis et astuces générales

- **Échap** ferme n'importe quelle fenêtre de formulaire, partout dans le logiciel.
- Toute suppression demande une **confirmation** — impossible de supprimer par erreur en un
  clic.
- Les champs de recherche s'entourent d'un **liseré doré** quand tu cliques dedans.
- Les montants s'affichent toujours en FCFA, avec des espaces entre les milliers
  (ex : `1 250 000 FCFA`).

---

## Où sont mes données ?

Ta base de données est stockée automatiquement dans :
```
C:\Users\TonNom\MK_Suite_Data\mk_entreprise.db
```
C'est un fichier unique. Utilise le bouton **💾 Sauvegarder mes données** régulièrement
(tableau de bord) pour en garder une copie de sécurité ailleurs.

---

## Besoin d'aide ?

Si un écran met du temps à s'afficher, si un bouton ne répond pas comme attendu, ou si tu
repères une donnée incorrecte, note précisément :
1. Le module concerné (nom exact dans le menu)
2. Ce que tu as cliqué
3. Ce qui s'est passé (ou ne s'est pas passé)

Cette précision permet de corriger le problème beaucoup plus vite.
