import 'dart:math';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Base de données locale MK Suite — reprend fidèlement le schéma de la
/// version ordinateur (mk_entreprise.db), avec deux colonnes ajoutées sur
/// CHAQUE table pour permettre la synchronisation Wi-Fi avec l'ordinateur :
///
/// - `sync_id` : identifiant unique généré une seule fois, à la création
///   d'une ligne, et jamais modifié ensuite. C'est LA clé utilisée pour
///   reconnaître "la même ligne" entre les deux appareils lors d'une
///   synchronisation. Le code/numéro visible à l'écran (CL-001,
///   DV-2026-001...) reste purement un libellé d'affichage : deux clients
///   créés indépendamment sur le téléphone et sur l'ordinateur avant leur
///   toute première synchronisation pourraient en théorie recevoir le même
///   numéro affiché — s'appuyer sur `sync_id` plutôt que sur ce numéro
///   évite que cette coïncidence ne fasse fusionner par erreur deux
///   enregistrements différents.
/// - `updated_at` (entier, horodatage en millisecondes) : mis à jour à
///   chaque création/modification d'une ligne, sert à décider quelle
///   version d'une donnée modifiée des deux côtés doit l'emporter
///   (la plus récente).
///
/// Voir lib/services/sync_service.dart pour la logique de fusion qui
/// utilise ces colonnes.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();
  static Database? _db;

  static const int schemaVersion = 1;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = join(dir.path, 'mk_entreprise.db');
    return openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        for (final stmt in _createStatements) {
          await db.execute(stmt);
        }
        await _seed(db);
      },
    );
  }

  static final List<String> _createStatements = [
    '''CREATE TABLE clients (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sync_id TEXT UNIQUE,
      code TEXT UNIQUE,
      nom TEXT NOT NULL,
      type_client TEXT DEFAULT 'Particulier',
      telephone TEXT DEFAULT '',
      adresse TEXT DEFAULT '',
      nif TEXT DEFAULT '',
      date_premier_contact TEXT,
      statut TEXT DEFAULT 'Actif',
      updated_at INTEGER NOT NULL DEFAULT 0
    )''',
    '''CREATE TABLE fournisseurs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sync_id TEXT UNIQUE,
      nom TEXT NOT NULL UNIQUE,
      categorie_produits TEXT DEFAULT '',
      contact TEXT DEFAULT '',
      telephone TEXT DEFAULT '',
      adresse TEXT DEFAULT '',
      updated_at INTEGER NOT NULL DEFAULT 0
    )''',
    '''CREATE TABLE devis (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sync_id TEXT UNIQUE,
      numero TEXT UNIQUE NOT NULL,
      date_devis TEXT,
      client_id INTEGER,
      objet TEXT DEFAULT '',
      montant_ht REAL DEFAULT 0,
      statut TEXT DEFAULT 'En attente',
      validite_jours INTEGER DEFAULT 30,
      date_limite TEXT,
      converti_facture TEXT,
      appliquer_tva INTEGER DEFAULT 1,
      updated_at INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (client_id) REFERENCES clients(id)
    )''',
    '''CREATE TABLE lignes_devis (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sync_id TEXT UNIQUE,
      devis_numero TEXT,
      quantite REAL,
      description TEXT DEFAULT '',
      prix_unitaire REAL,
      total_ligne REAL,
      updated_at INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (devis_numero) REFERENCES devis(numero) ON DELETE CASCADE
    )''',
    '''CREATE TABLE factures (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sync_id TEXT UNIQUE,
      numero TEXT UNIQUE NOT NULL,
      date_facture TEXT,
      devis_numero TEXT,
      client_id INTEGER,
      description TEXT DEFAULT '',
      montant_ht REAL DEFAULT 0,
      reduction_pct REAL DEFAULT 0,
      montant_ht_net REAL DEFAULT 0,
      tva REAL DEFAULT 0,
      montant_ttc REAL DEFAULT 0,
      avance_recue REAL DEFAULT 0,
      reste_a_payer REAL DEFAULT 0,
      statut TEXT DEFAULT 'Impayée',
      mode_paiement TEXT DEFAULT '',
      updated_at INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (client_id) REFERENCES clients(id)
    )''',
    '''CREATE TABLE lignes_facture (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sync_id TEXT UNIQUE,
      facture_numero TEXT,
      quantite REAL,
      description TEXT DEFAULT '',
      prix_unitaire REAL,
      total_ligne REAL,
      updated_at INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (facture_numero) REFERENCES factures(numero) ON DELETE CASCADE
    )''',
    '''CREATE TABLE recus (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sync_id TEXT UNIQUE,
      numero TEXT UNIQUE NOT NULL,
      date_recu TEXT,
      client_id INTEGER,
      facture_numero TEXT,
      motif TEXT DEFAULT '',
      montant_recu REAL DEFAULT 0,
      mode_paiement TEXT DEFAULT '',
      recu_par TEXT DEFAULT '',
      updated_at INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (client_id) REFERENCES clients(id)
    )''',
    '''CREATE TABLE notes_client (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sync_id TEXT UNIQUE,
      numero TEXT UNIQUE,
      date_note TEXT,
      client_id INTEGER,
      objet TEXT DEFAULT '',
      contenu TEXT DEFAULT '',
      redige_par TEXT DEFAULT '',
      updated_at INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (client_id) REFERENCES clients(id)
    )''',
    '''CREATE TABLE depenses (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sync_id TEXT UNIQUE,
      date_depense TEXT,
      categorie TEXT DEFAULT '',
      description TEXT DEFAULT '',
      beneficiaire TEXT DEFAULT '',
      montant REAL,
      mode_paiement TEXT DEFAULT 'Espèces',
      justificatif TEXT DEFAULT 'Non',
      updated_at INTEGER NOT NULL DEFAULT 0
    )''',
    '''CREATE TABLE budget_categories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sync_id TEXT UNIQUE,
      categorie TEXT,
      mois TEXT,
      annee INTEGER,
      budget_prevu REAL DEFAULT 0,
      updated_at INTEGER NOT NULL DEFAULT 0
    )''',
    '''CREATE TABLE tarifs_vitres (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sync_id TEXT UNIQUE,
      type_vitre TEXT UNIQUE,
      prix_m2 REAL,
      updated_at INTEGER NOT NULL DEFAULT 0
    )''',
    '''CREATE TABLE commandes_vitres (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sync_id TEXT UNIQUE,
      date_commande TEXT,
      type_vitre TEXT,
      largeur REAL,
      hauteur REAL,
      quantite INTEGER,
      surface REAL,
      prix_unitaire REAL,
      montant REAL,
      devis_numero TEXT,
      facture_numero TEXT,
      updated_at INTEGER NOT NULL DEFAULT 0
    )''',
    '''CREATE TABLE sourcing_commandes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sync_id TEXT UNIQUE,
      numero TEXT UNIQUE,
      date_commande TEXT,
      fournisseur_id INTEGER,
      client_id INTEGER,
      designation TEXT DEFAULT '',
      quantite REAL DEFAULT 1,
      prix_achat_unitaire REAL DEFAULT 0,
      prix_vente_unitaire REAL DEFAULT 0,
      statut TEXT DEFAULT 'En cours',
      date_livraison_prevue TEXT,
      notes TEXT DEFAULT '',
      updated_at INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (fournisseur_id) REFERENCES fournisseurs(id),
      FOREIGN KEY (client_id) REFERENCES clients(id)
    )''',
    '''CREATE TABLE employes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sync_id TEXT UNIQUE,
      code TEXT UNIQUE,
      nom TEXT NOT NULL,
      poste TEXT DEFAULT '',
      telephone TEXT DEFAULT '',
      date_embauche TEXT,
      type_contrat TEXT DEFAULT 'CDI',
      salaire_mensuel REAL,
      statut TEXT DEFAULT 'Actif',
      updated_at INTEGER NOT NULL DEFAULT 0
    )''',
    '''CREATE TABLE paie (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sync_id TEXT UNIQUE,
      mois TEXT,
      annee INTEGER,
      employe_id INTEGER,
      salaire_du REAL DEFAULT 0,
      avances_versees REAL DEFAULT 0,
      net_a_payer REAL DEFAULT 0,
      date_paiement TEXT,
      mode_paiement TEXT DEFAULT '',
      statut TEXT DEFAULT 'En attente',
      updated_at INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (employe_id) REFERENCES employes(id)
    )''',
    // Corbeille : toute suppression y passe d'abord (avec les lignes liées,
    // en JSON) avant d'être vraiment effacée. `deleted_at` et `origine_key`
    // permettent de propager une suppression vers l'autre appareil lors
    // d'une synchronisation (voir sync_service.dart) ; `restaure` masque un
    // élément déjà restauré sans effacer son historique.
    '''CREATE TABLE corbeille (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sync_id TEXT UNIQUE,
      table_origine TEXT NOT NULL,
      id_origine INTEGER,
      origine_key TEXT,
      libelle TEXT DEFAULT '',
      module TEXT DEFAULT '',
      donnees_json TEXT,
      date_suppression TEXT,
      deleted_at INTEGER NOT NULL DEFAULT 0,
      restaure INTEGER NOT NULL DEFAULT 0
    )''',
    'CREATE INDEX idx_depenses_beneficiaire ON depenses(beneficiaire)',
    'CREATE INDEX idx_depenses_categorie ON depenses(categorie)',
    'CREATE INDEX idx_depenses_date ON depenses(date_depense)',
    'CREATE INDEX idx_devis_client ON devis(client_id)',
    'CREATE INDEX idx_factures_client ON factures(client_id)',
    'CREATE INDEX idx_lignes_devis_numero ON lignes_devis(devis_numero)',
    'CREATE INDEX idx_lignes_facture_numero ON lignes_facture(facture_numero)',
    'CREATE INDEX idx_recus_client ON recus(client_id)',
    'CREATE INDEX idx_notes_client ON notes_client(client_id)',
    'CREATE INDEX idx_sourcing_fournisseur ON sourcing_commandes(fournisseur_id)',
    'CREATE INDEX idx_sourcing_client ON sourcing_commandes(client_id)',
    'CREATE INDEX idx_paie_employe ON paie(employe_id)',
  ];

  /// Fournisseurs habituels + tarifs de vitres par défaut — mêmes valeurs
  /// que la version ordinateur (`_seed_fournisseurs` dans db_manager.py),
  /// pour que Boubacar retrouve directement ses repères connus.
  static Future<void> _seed(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final fournisseursPrincipaux = [
      ['Métal Balaya', 'Fer, tôle, profilés métalliques'],
      ['Vitrerie Sidibé', 'Vitrerie'],
      ['Métallique Dioussou', 'Métallique'],
      ['Eagle Alu', 'Aluminium'],
    ];
    for (final f in fournisseursPrincipaux) {
      await db.insert('fournisseurs', {'sync_id': newSyncId(), 'nom': f[0], 'categorie_produits': f[1], 'updated_at': now});
    }
    const fournisseursListeComplete = [
      'Adama', 'Alu Trader', 'Alulux', 'Apollo Fer Mali', 'Bk Holdind', 'Boto Seal',
      'Camara Décor', 'Crochet', 'D Métal Ahmed', 'Donsen', 'EDM', 'Etasyf', 'FBF Store',
      'Faladie', 'Fougan', 'Guinna', 'Hamari', 'Hamari Dicko', 'Kassim', 'Kone Inox',
      'Ladji', 'Mairie', 'Metal Djitoumou', 'Q Ballayira', 'Quincaillerie Al Firdaws',
      'Quincaillerie Sall et Fils', "Quincaillerie de l'Espoir", 'SM Distribution',
      'Tolmali', 'Vita Lux',
    ];
    for (final nom in fournisseursListeComplete) {
      await db.insert('fournisseurs', {'sync_id': newSyncId(), 'nom': nom, 'updated_at': now}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    final tarifs = [
      ['ANT 4mm', 9000], ['ANT 5mm', 11000], ['CLAIR 4mm', 9000],
      ['CLAIR 5mm', 12500], ['Imprimé 5mm', 14000],
    ];
    for (final t in tarifs) {
      await db.insert('tarifs_vitres', {'sync_id': newSyncId(), 'type_vitre': t[0], 'prix_m2': t[1], 'updated_at': now});
    }
  }
}

/// Horodatage courant en millisecondes — utilisé pour `updated_at` à
/// chaque écriture, et pour comparer les versions lors d'une synchronisation.
int nowMs() => DateTime.now().millisecondsSinceEpoch;

/// Génère un identifiant unique (v4, sans dépendance externe) — utilisé
/// comme `sync_id` pour les tables sans clé métier naturelle.
String newSyncId() {
  final r = Random();
  const chars = '0123456789abcdef';
  String hex(int n) => List.generate(n, (_) => chars[r.nextInt(16)]).join();
  return '${hex(8)}-${hex(4)}-4${hex(3)}-${(8 + r.nextInt(4)).toRadixString(16)}${hex(3)}-${hex(12)}';
}
