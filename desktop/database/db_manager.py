"""
MK Suite - Gestionnaire de base de données
Base de données locale SQLite - fonctionne 100% hors ligne
"""
import sqlite3
import os
import sys
import json
import threading
import time
import uuid
from datetime import datetime
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from resource_path import resource_path


SCHEMA_SQL = """
-- ===== CLIENTS (ID format CL-001) =====
CREATE TABLE IF NOT EXISTS clients (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sync_id TEXT,                                -- identité stable pour la synchro Wi-Fi (voir sync_service.py)
    code TEXT UNIQUE,                          -- CL-001
    nom TEXT NOT NULL,                          -- Nom complet / Raison sociale
    type_client TEXT DEFAULT 'Particulier',      -- Particulier / Entreprise / Chantier
    telephone TEXT,
    adresse TEXT,
    nif TEXT,                                    -- Numero d'Identification Fiscale (entreprises)
    date_premier_contact TEXT DEFAULT CURRENT_TIMESTAMP,
    statut TEXT DEFAULT 'Actif',
    updated_at INTEGER DEFAULT 0
);

-- ===== FOURNISSEURS =====
CREATE TABLE IF NOT EXISTS fournisseurs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sync_id TEXT,
    nom TEXT NOT NULL UNIQUE,
    categorie_produits TEXT,
    contact TEXT,
    telephone TEXT,
    adresse TEXT,
    updated_at INTEGER DEFAULT 0
);

-- ===== DEVIS (numéro format DV-2026-001) =====
CREATE TABLE IF NOT EXISTS devis (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sync_id TEXT,
    numero TEXT UNIQUE NOT NULL,
    date_devis TEXT DEFAULT CURRENT_TIMESTAMP,
    client_id INTEGER,
    objet TEXT,
    montant_ht REAL DEFAULT 0,
    statut TEXT DEFAULT 'En attente',            -- En attente / Accepté / Refusé
    validite_jours INTEGER DEFAULT 30,
    date_limite TEXT,
    converti_facture TEXT,
    appliquer_tva INTEGER DEFAULT 1,
    updated_at INTEGER DEFAULT 0,
    FOREIGN KEY (client_id) REFERENCES clients(id)
);

CREATE TABLE IF NOT EXISTS lignes_devis (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sync_id TEXT,
    devis_numero TEXT,
    quantite REAL,
    description TEXT,
    prix_unitaire REAL,
    total_ligne REAL,
    updated_at INTEGER DEFAULT 0,
    FOREIGN KEY (devis_numero) REFERENCES devis(numero) ON DELETE CASCADE
);

-- ===== FACTURES (numéro format FA-2026-001) =====
CREATE TABLE IF NOT EXISTS factures (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sync_id TEXT,
    numero TEXT UNIQUE NOT NULL,
    date_facture TEXT DEFAULT CURRENT_TIMESTAMP,
    devis_numero TEXT,
    client_id INTEGER,
    description TEXT,
    montant_ht REAL DEFAULT 0,
    reduction_pct REAL DEFAULT 0,
    montant_ht_net REAL DEFAULT 0,
    tva REAL DEFAULT 0,                          -- TVA 18%
    montant_ttc REAL DEFAULT 0,
    avance_recue REAL DEFAULT 0,
    reste_a_payer REAL DEFAULT 0,
    statut TEXT DEFAULT 'Impayée',                -- Impayée / Partielle / Payée
    mode_paiement TEXT,
    updated_at INTEGER DEFAULT 0,
    FOREIGN KEY (client_id) REFERENCES clients(id)
);

CREATE TABLE IF NOT EXISTS lignes_facture (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sync_id TEXT,
    facture_numero TEXT,
    quantite REAL,
    description TEXT,
    prix_unitaire REAL,
    total_ligne REAL,
    updated_at INTEGER DEFAULT 0,
    FOREIGN KEY (facture_numero) REFERENCES factures(numero) ON DELETE CASCADE
);

-- ===== REÇUS =====
CREATE TABLE IF NOT EXISTS recus (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sync_id TEXT,
    numero TEXT UNIQUE NOT NULL,                  -- RC-2026-001
    date_recu TEXT DEFAULT CURRENT_TIMESTAMP,
    client_id INTEGER,
    facture_numero TEXT,
    motif TEXT,
    montant_recu REAL DEFAULT 0,
    mode_paiement TEXT,
    recu_par TEXT,
    updated_at INTEGER DEFAULT 0,
    FOREIGN KEY (client_id) REFERENCES clients(id)
);

-- ===== NOTES CLIENT =====
CREATE TABLE IF NOT EXISTS notes_client (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sync_id TEXT,
    numero TEXT UNIQUE,
    date_note TEXT DEFAULT CURRENT_TIMESTAMP,
    client_id INTEGER,
    objet TEXT,
    contenu TEXT,
    redige_par TEXT,
    updated_at INTEGER DEFAULT 0,
    FOREIGN KEY (client_id) REFERENCES clients(id)
);

-- ===== DÉPENSES =====
CREATE TABLE IF NOT EXISTS depenses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sync_id TEXT,
    date_depense TEXT DEFAULT CURRENT_TIMESTAMP,
    categorie TEXT,
    description TEXT,
    beneficiaire TEXT,                            -- Fournisseur / Bénéficiaire
    montant REAL,
    mode_paiement TEXT DEFAULT 'Espèces',
    justificatif TEXT DEFAULT 'Non',
    updated_at INTEGER DEFAULT 0
);

-- ===== BUDGET (contrôle mensuel par catégorie) =====
CREATE TABLE IF NOT EXISTS budget_categories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sync_id TEXT,
    categorie TEXT,
    mois TEXT,
    annee INTEGER,
    budget_prevu REAL DEFAULT 0,
    updated_at INTEGER DEFAULT 0
);

-- ===== CALCUL VITRES =====
CREATE TABLE IF NOT EXISTS tarifs_vitres (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sync_id TEXT,
    type_vitre TEXT UNIQUE,
    prix_m2 REAL,
    updated_at INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS commandes_vitres (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sync_id TEXT,
    date_commande TEXT DEFAULT CURRENT_TIMESTAMP,
    type_vitre TEXT,
    largeur REAL,
    hauteur REAL,
    quantite INTEGER,
    surface REAL,
    prix_unitaire REAL,
    montant REAL,
    devis_numero TEXT,
    facture_numero TEXT,
    updated_at INTEGER DEFAULT 0
);

-- ===== SOURCING (achat fournisseur -> vente client, marge calculée) =====
CREATE TABLE IF NOT EXISTS sourcing_commandes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sync_id TEXT,
    numero TEXT UNIQUE,                            -- SRC-2026-001
    date_commande TEXT DEFAULT CURRENT_TIMESTAMP,
    fournisseur_id INTEGER,
    client_id INTEGER,
    designation TEXT,
    quantite REAL DEFAULT 1,
    prix_achat_unitaire REAL DEFAULT 0,
    prix_vente_unitaire REAL DEFAULT 0,
    statut TEXT DEFAULT 'En cours',                 -- En cours / Livré / Annulé
    date_livraison_prevue TEXT,
    notes TEXT,
    updated_at INTEGER DEFAULT 0,
    FOREIGN KEY (fournisseur_id) REFERENCES fournisseurs(id),
    FOREIGN KEY (client_id) REFERENCES clients(id)
);

-- ===== PERSONNEL (ID format EMP-01) =====
CREATE TABLE IF NOT EXISTS employes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sync_id TEXT,
    code TEXT UNIQUE,                              -- EMP-01
    nom TEXT NOT NULL,
    poste TEXT,
    telephone TEXT,
    date_embauche TEXT,
    type_contrat TEXT DEFAULT 'CDI',                -- CDI / CDD / Journalier
    salaire_mensuel REAL,
    statut TEXT DEFAULT 'Actif',
    updated_at INTEGER DEFAULT 0
);

-- ===== PAIE =====
CREATE TABLE IF NOT EXISTS paie (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sync_id TEXT,
    mois TEXT,
    annee INTEGER,
    employe_id INTEGER,
    salaire_du REAL DEFAULT 0,
    avances_versees REAL DEFAULT 0,
    net_a_payer REAL DEFAULT 0,
    date_paiement TEXT,
    mode_paiement TEXT,
    statut TEXT DEFAULT 'En attente',
    updated_at INTEGER DEFAULT 0,
    FOREIGN KEY (employe_id) REFERENCES employes(id)
);

-- ===== CORBEILLE =====
-- Toute suppression passe d'abord ici (avec les lignes liées, en JSON) avant d'etre
-- vraiment effacee. Restauration possible pendant 30 jours, purge automatique ensuite.
-- `origine_key` (= sync_id de la ligne supprimée), `deleted_at` et `restaure` servent à
-- propager suppressions ET restaurations à l'autre appareil lors d'une synchro Wi-Fi
-- (voir sync_service.py) — un élément restauré passe restaure=1 au lieu d'être effacé
-- de la corbeille tout de suite, pour que l'autre appareil apprenne la restauration.
CREATE TABLE IF NOT EXISTS corbeille (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sync_id TEXT,
    table_origine TEXT NOT NULL,
    id_origine INTEGER,
    origine_key TEXT,
    libelle TEXT,
    module TEXT,
    donnees_json TEXT,
    date_suppression TEXT DEFAULT CURRENT_TIMESTAMP,
    deleted_at INTEGER DEFAULT 0,
    restaure INTEGER DEFAULT 0
);

-- ===== INDEX DE PERFORMANCE =====
-- Accélèrent les recherches et regroupements fréquents (dépenses par fournisseur/catégorie/date,
-- lignes de devis/facture par numéro, documents par client) — essentiel avec 1000+ dépenses.
CREATE INDEX IF NOT EXISTS idx_depenses_beneficiaire ON depenses(beneficiaire);
CREATE INDEX IF NOT EXISTS idx_depenses_categorie ON depenses(categorie);
CREATE INDEX IF NOT EXISTS idx_depenses_date ON depenses(date_depense);
CREATE INDEX IF NOT EXISTS idx_devis_client ON devis(client_id);
CREATE INDEX IF NOT EXISTS idx_factures_client ON factures(client_id);
CREATE INDEX IF NOT EXISTS idx_lignes_devis_numero ON lignes_devis(devis_numero);
CREATE INDEX IF NOT EXISTS idx_lignes_facture_numero ON lignes_facture(facture_numero);
CREATE INDEX IF NOT EXISTS idx_recus_client ON recus(client_id);
CREATE INDEX IF NOT EXISTS idx_notes_client ON notes_client(client_id);
CREATE INDEX IF NOT EXISTS idx_sourcing_fournisseur ON sourcing_commandes(fournisseur_id);
CREATE INDEX IF NOT EXISTS idx_sourcing_client ON sourcing_commandes(client_id);
CREATE INDEX IF NOT EXISTS idx_paie_employe ON paie(employe_id);
"""


def now_ms():
    """Horodatage epoch en millisecondes — utilisé pour `updated_at`
    (résolution de conflit "dernière modification l'emporte" lors d'une
    synchronisation Wi-Fi, voir sync_service.py) et pour `deleted_at` côté
    corbeille. Même unité que `nowMs()` côté téléphone (database.dart)."""
    return int(time.time() * 1000)


def new_sync_id():
    """UUID v4 — identité stable et jamais réutilisée d'une ligne, unique
    entre TOUS les appareils (généré une seule fois, à la création),
    utilisée comme clé de rapprochement lors d'une synchronisation Wi-Fi.
    Jamais le numéro/code affiché à l'écran (CL-001, DV-2026-001...), qui
    reste un simple libellé et pourrait en théorie être généré
    indépendamment des deux côtés pour deux enregistrements différents."""
    return str(uuid.uuid4())


# Toutes les tables qui participent à la synchronisation Wi-Fi (voir
# sync_service.py) ont besoin d'un `sync_id` (identité stable) et d'un
# `updated_at` (résolution de conflit) — utilisé à la fois par le schéma
# des nouvelles installations (SCHEMA_SQL ci-dessus) et par la migration
# des bases déjà existantes (_migrate_missing_columns ci-dessous).
SYNC_TABLES = [
    "clients", "fournisseurs", "devis", "lignes_devis", "factures", "lignes_facture",
    "recus", "notes_client", "depenses", "budget_categories", "tarifs_vitres",
    "commandes_vitres", "sourcing_commandes", "employes", "paie", "corbeille",
]


def get_db_path():
    """Stocke la base de données dans le dossier utilisateur, à côté de l'exécutable"""
    app_data = Path.home() / "MK_Suite_Data"
    app_data.mkdir(exist_ok=True)
    return str(app_data / "mk_entreprise.db")


class DatabaseManager:
    def __init__(self, db_path=None):
        self.db_path = db_path or get_db_path()
        # Snapshot the existing database before any additive schema migration.
        if os.path.isfile(self.db_path):
            backup = self.db_path + '.before-1.1.2.bak'
            if not os.path.exists(backup):
                with sqlite3.connect(self.db_path) as source, sqlite3.connect(backup) as target:
                    source.backup(target)
        self._load_seed_if_first_run()
        # check_same_thread=False : la synchronisation Wi-Fi (modules/sync_service.py)
        # fait tourner un petit serveur HTTP dans un thread à part (pour ne jamais
        # geler l'interface CustomTkinter pendant un échange) et doit pouvoir utiliser
        # cette MÊME connexion — plutôt que d'en ouvrir une seconde vers le même
        # fichier (source classique de "database is locked"), on partage celle-ci et
        # on sérialise nous-mêmes tout accès concurrent avec `self.lock` ci-dessous.
        self.conn = sqlite3.connect(self.db_path, check_same_thread=False)
        self.conn.row_factory = sqlite3.Row
        self.conn.execute("PRAGMA foreign_keys = ON")
        # RLock (et non Lock) : plusieurs méthodes de cette classe s'appellent entre
        # elles depuis le même thread (ex. move_to_corbeille -> self.execute plusieurs
        # fois) ; un Lock simple s'y bloquerait lui-même.
        self.lock = threading.RLock()
        # Désactivé explicitement (déjà la valeur par défaut de SQLite, mais le
        # rendre explicite documente l'intention) : les triggers sync_* ci-dessous
        # sont conçus pour être sans risque même récursifs (leurs clauses WHEN les
        # arrêtent d'elles-mêmes), mais on ne prend pas le risque inutilement.
        self.conn.execute("PRAGMA recursive_triggers = OFF")
        # Fonctions SQL utilisées par les triggers sync_* (voir _create_sync_triggers) —
        # doivent être enregistrées AVANT toute insertion (donc avant _create_tables/
        # _seed_fournisseurs, qui peuvent déclencher ces triggers immédiatement).
        self.conn.create_function("SYNC_UUID", 0, lambda: new_sync_id())
        self.conn.create_function("SYNC_NOW_MS", 0, lambda: now_ms())
        self.sync_importing = False
        self.conn.create_function("SYNC_IMPORTING", 0, lambda: int(self.sync_importing))
        self._migrate_if_needed()
        self._create_tables()
        self._seed_fournisseurs()

    def _load_seed_if_first_run(self):
        """Au tout premier lancement (aucune base locale, ou base encore vide), copie
        automatiquement les données déjà importées depuis le classeur Excel MK Entreprise,
        pour que Boubacar retrouve directement tout son historique."""
        seed_path = resource_path("database", "seed_data.db")
        if not os.path.exists(seed_path):
            return
        needs_seed = False
        if not os.path.exists(self.db_path):
            needs_seed = True
        else:
            try:
                test_conn = sqlite3.connect(self.db_path)
                tcur = test_conn.cursor()
                tcur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='clients'")
                if tcur.fetchone():
                    tcur.execute("SELECT COUNT(*) FROM clients")
                    if tcur.fetchone()[0] == 0:
                        needs_seed = True
                else:
                    needs_seed = True
                test_conn.close()
            except sqlite3.Error:
                needs_seed = True
        if needs_seed:
            import shutil
            shutil.copy(seed_path, self.db_path)

    SCHEMA_VERSION = 2

    def _migrate_if_needed(self):
        """Si une ancienne version du schéma est détectée (v1, structure différente),
        on sauvegarde les anciennes tables et on repart sur la nouvelle structure —
        évite les erreurs 'no such column' après une mise à jour de MK Suite."""
        cur = self.conn.cursor()
        current_version = cur.execute("PRAGMA user_version").fetchone()[0]
        if current_version < self.SCHEMA_VERSION:
            cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='clients'")
            if cur.fetchone():
                cur.execute("PRAGMA table_info(clients)")
                cols = [c[1] for c in cur.fetchall()]
                if "code" not in cols:
                    # Ancienne structure détectée : on renomme au lieu de supprimer
                    check_cur = self.conn.cursor()
                    for t in ["clients", "fournisseurs", "devis", "devis_lignes", "factures",
                              "facture_lignes", "depenses", "employes", "paiements_salaire",
                              "sourcing_commandes", "budget_categories"]:
                        check_cur.execute(
                            "SELECT name FROM sqlite_master WHERE type='table' AND name=?", (t,))
                        if check_cur.fetchone():
                            cur.execute(f"ALTER TABLE {t} RENAME TO _old_{t}")
            cur.execute(f"PRAGMA user_version = {self.SCHEMA_VERSION}")
            self.conn.commit()

    def _create_tables(self):
        cur = self.conn.cursor()

        cur.executescript(SCHEMA_SQL)
        self.conn.commit()
        self._migrate_missing_columns()
        self._create_sync_triggers()

    def _create_sync_triggers(self):
        """Tamponne automatiquement `sync_id` et `updated_at` sur CHAQUE
        insertion/modification, pour CHAQUE table synchronisable — sans avoir
        à modifier un seul des nombreux appels `INSERT`/`UPDATE` déjà
        existants dans les modules (clients.py, devis_factures.py, etc.).
        C'est le pendant, côté ordinateur, de ce que fait directement le code
        Dart du téléphone à chaque `create()`/`update()` de son dépôt de
        données — ici, on obtient le même résultat via des triggers SQLite,
        plus sûr qu'une relecture manuelle de tout le code existant.

        - Trigger APRÈS INSERT : si `sync_id` est vide, en génère un neuf ;
          si `updated_at` vaut 0 (valeur par défaut), le tamponne à l'instant
          présent.
        - Trigger APRÈS MODIFICATION : si le code appelant n'a pas déjà
          changé `updated_at` lui-même (`NEW.updated_at IS OLD.updated_at`),
          le tamponne à l'instant présent — c'est ce qui permet la résolution
          de conflit "dernière modification l'emporte" lors d'une synchro.
        """
        cur = self.conn.cursor()
        for table in SYNC_TABLES:
            cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name=?", (table,))
            if not cur.fetchone():
                continue
            cur.executescript(f"""
                DROP TRIGGER IF EXISTS trg_{table}_sync_ai;
                DROP TRIGGER IF EXISTS trg_{table}_sync_au;
                CREATE TRIGGER trg_{table}_sync_ai AFTER INSERT ON {table}
                WHEN SYNC_IMPORTING() = 0
                BEGIN
                    UPDATE {table} SET sync_id = SYNC_UUID()
                        WHERE id = NEW.id AND (sync_id IS NULL OR sync_id = '');
                    UPDATE {table} SET updated_at = SYNC_NOW_MS()
                        WHERE id = NEW.id AND (updated_at IS NULL OR updated_at = 0);
                END;
                CREATE TRIGGER IF NOT EXISTS trg_{table}_sync_au AFTER UPDATE ON {table}
                WHEN NEW.updated_at IS OLD.updated_at AND SYNC_IMPORTING() = 0
                BEGIN
                    UPDATE {table} SET updated_at = SYNC_NOW_MS() WHERE id = NEW.id;
                END;
            """)
        for parent, lines, fk in (("devis", "lignes_devis", "devis_numero"),
                                  ("factures", "lignes_facture", "facture_numero")):
            for event, record in (("INSERT", "NEW"), ("UPDATE", "NEW"), ("DELETE", "OLD")):
                cur.executescript(f"""
                    CREATE TRIGGER IF NOT EXISTS trg_{lines}_parent_{event.lower()}
                    AFTER {event} ON {lines} WHEN SYNC_IMPORTING() = 0
                    BEGIN
                        UPDATE {parent} SET updated_at = MAX(updated_at + 1, SYNC_NOW_MS())
                        WHERE numero = {record}.{fk};
                    END;
                """)
        self.conn.commit()

    def _migrate_missing_columns(self):
        """Ajoute automatiquement toute colonne présente dans le schéma actuel du code
        mais absente d'une base créée par une version antérieure — évite les erreurs
        'no such column' après une mise à jour, sans jamais toucher aux données existantes."""
        required_columns = {
            "devis": [("appliquer_tva", "INTEGER DEFAULT 1")],
            "commandes_vitres": [("repere", "TEXT NOT NULL DEFAULT ''")],
            "clients": [("nif", "TEXT")],
        }
        cur = self.conn.cursor()
        for table, columns in required_columns.items():
            cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name=?", (table,))
            if not cur.fetchone():
                continue
            cur.execute(f"PRAGMA table_info({table})")
            existing = {row[1] for row in cur.fetchall()}
            for col_name, col_type in columns:
                if col_name not in existing:
                    cur.execute(f"ALTER TABLE {table} ADD COLUMN {col_name} {col_type}")
        self.conn.commit()
        self._migrate_sync_columns()

    def _migrate_sync_columns(self):
        """Ajoute `sync_id`/`updated_at` (et, pour la corbeille, `origine_key`/
        `deleted_at`/`restaure`) à toute base créée avant l'introduction de la
        synchronisation Wi-Fi, puis attribue un `sync_id` aux lignes déjà
        existantes qui n'en ont pas encore (générées avant cette mise à jour).

        NOTE technique : SQLite interdit d'ajouter directement une colonne
        UNIQUE via ALTER TABLE ADD COLUMN sur une table qui contient déjà des
        lignes — `sync_id` est donc ajoutée comme simple colonne TEXT, puis
        l'unicité est assurée séparément par un INDEX UNIQUE (qui, lui,
        s'ajoute sans problème après coup, et ignore les valeurs NULL)."""
        cur = self.conn.cursor()
        for table in SYNC_TABLES:
            cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name=?", (table,))
            if not cur.fetchone():
                continue
            cur.execute(f"PRAGMA table_info({table})")
            existing = {row[1] for row in cur.fetchall()}
            if "sync_id" not in existing:
                cur.execute(f"ALTER TABLE {table} ADD COLUMN sync_id TEXT")
            if "updated_at" not in existing:
                cur.execute(f"ALTER TABLE {table} ADD COLUMN updated_at INTEGER DEFAULT 0")
            if table == "corbeille":
                if "origine_key" not in existing:
                    cur.execute("ALTER TABLE corbeille ADD COLUMN origine_key TEXT")
                if "deleted_at" not in existing:
                    cur.execute("ALTER TABLE corbeille ADD COLUMN deleted_at INTEGER DEFAULT 0")
                if "restaure" not in existing:
                    cur.execute("ALTER TABLE corbeille ADD COLUMN restaure INTEGER DEFAULT 0")

            # Comble les sync_id manquants (lignes créées avant cette mise à
            # jour) avant de poser l'index unique, sinon deux NULL passeraient
            # (autorisé par SQLite) mais deux lignes fraîchement comblées avec
            # le même id ne le seraient pas — donc un UUID différent par ligne.
            rows = cur.execute(f"SELECT id FROM {table} WHERE sync_id IS NULL OR sync_id = ''").fetchall()
            for row in rows:
                cur.execute(f"UPDATE {table} SET sync_id = ? WHERE id = ?", (new_sync_id(), row[0]))

            cur.execute(f"CREATE UNIQUE INDEX IF NOT EXISTS idx_{table}_sync_id ON {table}(sync_id)")
        self.conn.commit()

    def _seed_fournisseurs(self):
        cur = self.conn.cursor()
        cur.execute("SELECT COUNT(*) FROM fournisseurs")
        if cur.fetchone()[0] == 0:
            fournisseurs = [
                ("Métal Balaya", "Fer, tôle, profilés métalliques", "", "", ""),
                ("Vitrerie Sidibé", "Vitrerie", "", "", ""),
                ("Métallique Dioussou", "Métallique", "", "", ""),
                ("Eagle Alu", "Aluminium", "", "", ""),
            ]
            cur.executemany(
                "INSERT INTO fournisseurs (nom, categorie_produits, contact, telephone, adresse) VALUES (?,?,?,?,?)",
                fournisseurs
            )
            self.conn.commit()

        # Complète avec tous les fournisseurs référencés dans le volet déroulant "Listes" du classeur Excel
        fournisseurs_liste_complete = [
            "Adama", "Alu Trader", "Alulux", "Apollo Fer Mali", "Bk Holdind", "Boto Seal",
            "Camara Décor", "Crochet", "D Métal Ahmed", "Donsen", "EDM", "Etasyf", "FBF Store",
            "Faladie", "Fougan", "Guinna", "Hamari", "Hamari Dicko", "Kassim", "Kone Inox",
            "Ladji", "Mairie", "Metal Djitoumou", "Q Ballayira", "Quincaillerie Al Firdaws",
            "Quincaillerie Sall et Fils", "Quincaillerie de l'Espoir", "SM Distribution",
            "Tolmali", "Vita Lux",
        ]
        for nom in fournisseurs_liste_complete:
            cur.execute("INSERT OR IGNORE INTO fournisseurs (nom) VALUES (?)", (nom,))
        self.conn.commit()

        cur.execute("SELECT COUNT(*) FROM tarifs_vitres")
        if cur.fetchone()[0] == 0:
            tarifs = [
                ("ANT 4mm", 9000), ("ANT 5mm", 11000), ("CLAIR 4mm", 9000),
                ("CLAIR 5mm", 12500), ("Imprimé 5mm", 14000),
            ]
            cur.executemany(
                "INSERT INTO tarifs_vitres (type_vitre, prix_m2) VALUES (?,?)", tarifs)
            self.conn.commit()

    # ---------- Utilitaires génériques ----------
    # Chaque méthode prend `self.lock` : la connexion est partagée entre le
    # thread de l'interface et celui du serveur de synchronisation (voir le
    # commentaire sur check_same_thread dans __init__) — sans ce verrou, deux
    # requêtes lancées en même temps depuis deux threads pourraient
    # entremêler leurs opérations sur le même curseur/connexion sqlite3.
    def execute(self, query, params=()):
        with self.lock:
            cur = self.conn.cursor()
            cur.execute(query, params)
            self.conn.commit()
            return cur.lastrowid

    def fetchall(self, query, params=()):
        with self.lock:
            cur = self.conn.cursor()
            cur.execute(query, params)
            return cur.fetchall()

    def fetchone(self, query, params=()):
        with self.lock:
            cur = self.conn.cursor()
            cur.execute(query, params)
            return cur.fetchone()

    def next_numero(self, prefix, table, column="numero", with_year=True, width=3):
        """Génère un numéro auto-incrémenté, ex: DV-2026-001, FA-2026-001, RC-2026-001"""
        with self.lock:
            cur = self.conn.cursor()
            if with_year:
                year = datetime.now().year
                like_pattern = f"{prefix}-{year}-%"
            else:
                like_pattern = f"{prefix}-%"
            cur.execute(f"SELECT {column} FROM {table} WHERE {column} LIKE ? ORDER BY id DESC LIMIT 1",
                         (like_pattern,))
            row = cur.fetchone()
            if row:
                last_num = int(row[0].split("-")[-1])
                new_num = last_num + 1
            else:
                new_num = 1
            if with_year:
                return f"{prefix}-{year}-{new_num:0{width}d}"
            return f"{prefix}-{new_num:0{width}d}"

    def next_code(self, prefix, table, column="code", width=3):
        """Génère un code simple type CL-001, EMP-01 (sans année)"""
        return self.next_numero(prefix, table, column, with_year=False, width=width)

    # ---------- Corbeille ----------
    # Table -> (table des lignes liées, colonne de jointure, colonne "numero" du parent)
    _LIGNES_LIEES = {
        "devis": ("lignes_devis", "devis_numero", "numero"),
        "factures": ("lignes_facture", "facture_numero", "numero"),
    }

    def move_to_corbeille(self, table, row_id, libelle, module):
        """Déplace un enregistrement (et ses lignes liées s'il y en a) vers la corbeille
        au lieu de le supprimer directement. Restaurable pendant 30 jours.

        `origine_key` retient le `sync_id` de la ligne supprimée (jamais son
        code/numéro métier) : c'est exactement ce que sync_service.py (et
        son pendant côté téléphone) recherchent ensuite via `WHERE sync_id
        = ?` pour propager la suppression à l'autre appareil — un code/
        numéro à cet endroit ne correspondrait jamais à aucune ligne et la
        suppression ne se propagerait donc jamais lors d'une synchro."""
        row = self.fetchone(f"SELECT * FROM {table} WHERE id=?", (row_id,))
        if not row:
            return False
        data = dict(row)
        origine_key = data.get("sync_id")

        lignes_data, lignes_table = None, None
        if table in self._LIGNES_LIEES:
            lignes_table, fk_col, numero_col = self._LIGNES_LIEES[table]
            numero_val = data.get(numero_col)
            if numero_val:
                lignes_data = [dict(r) for r in
                                self.fetchall(f"SELECT * FROM {lignes_table} WHERE {fk_col}=?", (numero_val,))]

        payload = {"data": data, "lignes": lignes_data, "lignes_table": lignes_table}
        now = now_ms()
        self.execute(
            "INSERT INTO corbeille (table_origine, id_origine, origine_key, libelle, module, "
            "donnees_json, date_suppression, deleted_at, restaure) VALUES (?,?,?,?,?,?,?,?,0)",
            (table, row_id, origine_key, libelle, module, json.dumps(payload, ensure_ascii=False),
             datetime.now().isoformat(), now))

        if lignes_data is not None:
            lignes_table, fk_col, numero_col = self._LIGNES_LIEES[table]
            self.execute(f"DELETE FROM {lignes_table} WHERE {fk_col}=?", (data.get(numero_col),))
        self.execute(f"DELETE FROM {table} WHERE id=?", (row_id,))
        return True

    def get_corbeille(self):
        """Éléments actuellement dans la corbeille — les éléments restaurés
        (`restaure=1`) ne sont volontairement PAS supprimés tout de suite de
        cette table (voir `restore_from_corbeille`), donc on les exclut ici
        pour que l'écran Corbeille continue d'afficher exactement la même
        liste qu'avant l'introduction de la synchro."""
        return self.fetchall("SELECT * FROM corbeille WHERE restaure = 0 ORDER BY date_suppression DESC")

    def restore_from_corbeille(self, corbeille_id):
        """Remet un élément de la corbeille dans sa table d'origine, avec ses lignes.

        Contrairement à l'ancien comportement (suppression immédiate de la
        ligne corbeille), on la marque `restaure=1` avec un `updated_at`
        renouvelé et on la LAISSE en base : c'est ce qui permet à une
        restauration faite ici de se propager à l'autre appareil au prochain
        échange Wi-Fi (sync_service.py) — une suppression immédiate priverait
        l'autre appareil de toute preuve que cet élément a été restauré, et
        une synchro ultérieure risquerait de le supprimer à nouveau là-bas."""
        row = self.fetchone("SELECT * FROM corbeille WHERE id=?", (corbeille_id,))
        if not row:
            return False
        payload = json.loads(row["donnees_json"])
        data = payload["data"]
        table = row["table_origine"]

        columns = list(data.keys())
        placeholders = ",".join(["?"] * len(columns))
        col_names = ",".join(columns)
        values = tuple(data[c] for c in columns)
        try:
            self.execute(f"INSERT INTO {table} ({col_names}) VALUES ({placeholders})", values)
        except sqlite3.IntegrityError:
            # Le numero/code existe deja (reutilise entre-temps) : on force un nouvel id
            columns_sans_id = [c for c in columns if c != "id"]
            placeholders = ",".join(["?"] * len(columns_sans_id))
            col_names = ",".join(columns_sans_id)
            values = tuple(data[c] for c in columns_sans_id)
            self.execute(f"INSERT INTO {table} ({col_names}) VALUES ({placeholders})", values)

        if payload.get("lignes") and payload.get("lignes_table"):
            for ligne in payload["lignes"]:
                lcols = [c for c in ligne.keys() if c != "id"]
                lplaceholders = ",".join(["?"] * len(lcols))
                lcol_names = ",".join(lcols)
                lvalues = tuple(ligne[c] for c in lcols)
                self.execute(f"INSERT INTO {payload['lignes_table']} ({lcol_names}) VALUES ({lplaceholders})",
                             lvalues)

        self.execute("UPDATE corbeille SET restaure = 1, updated_at = ? WHERE id = ?",
                     (now_ms(), corbeille_id))
        return True

    def delete_from_corbeille(self, corbeille_id):
        """Suppression définitive et immédiate d'un élément de la corbeille —
        irréversible, y compris pour la synchronisation (cet élément ne sera
        plus jamais renvoyé à l'autre appareil ; s'il l'avait déjà reçu, il
        restera de son côté jusqu'à ce qu'il soit aussi supprimé là-bas)."""
        self.execute("DELETE FROM corbeille WHERE id=?", (corbeille_id,))
        return True

    def purge_corbeille_ancienne(self, jours=30):
        """Supprime définitivement tout ce qui traine en corbeille depuis plus de `jours`."""
        from datetime import timedelta
        seuil = (datetime.now() - timedelta(days=jours)).isoformat()
        self.execute("DELETE FROM corbeille WHERE date_suppression < ?", (seuil,))

    def close(self):
        self.conn.close()
