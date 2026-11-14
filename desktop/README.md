# MK Suite — Logiciel de gestion MK Entreprise & Sourcing

Logiciel de bureau (Windows) pour la gestion complète de MK Entreprise : clients, devis,
factures, sourcing, dépenses, fournisseurs, paie. Fonctionne **entièrement hors ligne**,
avec une base de données locale (aucune connexion internet requise après installation).

## 🎨 Ce qui est déjà construit (v1)

- Tableau de bord avec indicateurs animés (CA du mois, dépenses, factures impayées, clients)
  et graphique d'évolution du chiffre d'affaires sur 6 mois
- Module Clients complet : recherche instantanée, fiche détaillée, ajout/modification/suppression
- Base de données SQLite avec le schéma complet pour : clients, fournisseurs, devis, factures,
  dépenses, employés/paie, sourcing, budget (déjà pré-remplie avec tes fournisseurs habituels :
  Métal Balaya, Vitrerie Sidibé, Métallique Dioussou, Eagle Alu)
- Design premium : thème bleu nuit + or, cartes animées, interface fluide

## 🚧 Modules restants à construire (v2)

- Devis & Factures (création, numérotation automatique MK-DEV-2026-0001, calcul TVA 18%, export PDF)
- Sourcing (commandes, suivi, calcul de marge automatique)
- Dépenses (saisie, catégories, rapprochement fournisseur)
- Fournisseurs (fiches, historique des commandes)
- Employés / Paie (fiches employés, bulletins mensuels)

## 📦 Installation sur ton ordinateur Windows

### Option A — Automatique (recommandée)
Double-clique simplement sur **`build_exe.bat`**. Ce script :
1. Vérifie que Python 3.14 est installé
2. Installe toutes les dépendances
3. Lance le logiciel une fois pour vérifier que tout va bien
4. Compile automatiquement `MK_Suite.exe` dans le dossier `dist\`

### Option B — Manuelle, étape par étape

#### Étape 1 — Installer Python (si pas déjà fait)
Télécharge Python 3.14 sur https://www.python.org/downloads/
⚠️ Coche bien la case **"Add Python to PATH"** pendant l'installation.

#### Étape 2 — Installer les dépendances
Ouvre une invite de commande (CMD) dans le dossier du projet, puis :
```
py -3.14 -m pip install -r requirements.txt
```

#### Étape 3 — Tester le logiciel
```
py -3.14 main.py
```
Le logiciel doit s'ouvrir directement dans une fenêtre.

#### Étape 4 — Générer le fichier .exe installable
```
py -3.14 -m PyInstaller --name "MK_Suite" --windowed --onefile --icon="assets\icon.ico" --add-data "assets;assets" --add-data "database\seed_data.db;database" --hidden-import "PIL._tkinter_finder" main.py
```
Le fichier `MK_Suite.exe` sera généré dans le dossier `dist/`.
Tu peux alors le copier où tu veux (Bureau, clé USB...) et le lancer en double-cliquant,
**sans avoir besoin de Python installé** sur les autres postes.

## 💾 Où sont stockées les données ?

Toutes tes données (clients, factures, etc.) sont sauvegardées automatiquement dans :
```
C:\Users\TonNom\MK_Suite_Data\mk_entreprise.db
```
C'est un fichier unique — pense à le sauvegarder régulièrement (copie sur clé USB ou cloud)
pour ne jamais perdre tes données.

## 🗂 Structure du projet

```
mk_suite/
├── main.py                  → Point d'entrée de l'application
├── database/
│   └── db_manager.py        → Gestion de la base de données SQLite
├── ui/
│   ├── theme.py              → Couleurs, polices, styles
│   └── widgets.py             → Composants réutilisables (cartes, tableaux...)
├── modules/
│   ├── dashboard.py          → Tableau de bord
│   └── clients.py             → Gestion des clients
└── requirements.txt
```
