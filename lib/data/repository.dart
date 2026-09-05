import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'database.dart';
import '../models/models.dart';

/// Génère un numéro auto-incrémenté par année, ex : DV-2026-001,
/// FA-2026-001, RC-2026-001, SRC-2026-001 — même logique que
/// `next_numero()` côté ordinateur (database/db_manager.py).
/// `db` accepte aussi bien une `Database` qu'une `Transaction` (sync_service.dart
/// génère des numéros/codes DANS la transaction de fusion) — `DatabaseExecutor`
/// est l'interface commune aux deux.
Future<String> nextNumero(DatabaseExecutor db, String prefix, String table, {String column = 'numero', bool withYear = true, int width = 3}) async {
  final year = DateTime.now().year;
  final like = withYear ? '$prefix-$year-%' : '$prefix-%';
  final rows = await db.query(table, columns: [column], where: '$column LIKE ?', whereArgs: [like], orderBy: 'id DESC', limit: 1);
  int newNum = 1;
  if (rows.isNotEmpty) {
    final last = (rows.first[column] as String).split('-').last;
    newNum = (int.tryParse(last) ?? 0) + 1;
  }
  final numStr = newNum.toString().padLeft(width, '0');
  return withYear ? '$prefix-$year-$numStr' : '$prefix-$numStr';
}

/// Code simple sans année, ex : CL-001, EMP-01.
Future<String> nextCode(DatabaseExecutor db, String prefix, String table, {String column = 'code', int width = 3}) =>
    nextNumero(db, prefix, table, column: column, withYear: false, width: width);

/// Déplace un enregistrement vers la corbeille au lieu de le supprimer
/// directement — restaurable pendant 30 jours. `origineKey` DOIT être le
/// `sync_id` de la ligne supprimée (jamais un code/numéro métier) : c'est
/// exactement ce que sync_service.dart recherche ensuite via `WHERE
/// sync_id = ?` pour propager la suppression à l'autre appareil (voir la
/// boucle de "tombstones" dans importAll) — un code/numéro à cet endroit
/// ne correspondrait jamais à aucune ligne et la suppression ne se
/// propagerait donc jamais.
Future<void> moveToCorbeille(
  Database db, {
  required String table,
  required int rowId,
  required String libelle,
  required String module,
  required String? origineKey,
  String? lignesTable,
  String? lignesFkColumn,
  String? numeroValue,
}) async {
  final rows = await db.query(table, where: 'id = ?', whereArgs: [rowId]);
  if (rows.isEmpty) return;
  final data = Map<String, dynamic>.from(rows.first);

  List<Map<String, dynamic>>? lignesData;
  if (lignesTable != null && lignesFkColumn != null && numeroValue != null) {
    final lignes = await db.query(lignesTable, where: '$lignesFkColumn = ?', whereArgs: [numeroValue]);
    lignesData = lignes.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  final payload = {'data': data, 'lignes': lignesData, 'lignes_table': lignesTable};
  final now = nowMs();
  await db.insert('corbeille', {
    'sync_id': newSyncId(),
    'table_origine': table,
    'id_origine': rowId,
    'origine_key': origineKey,
    'libelle': libelle,
    'module': module,
    'donnees_json': jsonEncode(payload),
    'date_suppression': DateTime.now().toIso8601String(),
    'deleted_at': now,
    'restaure': 0,
    'updated_at': now,
  });

  if (lignesData != null && lignesTable != null && lignesFkColumn != null && numeroValue != null) {
    await db.delete(lignesTable, where: '$lignesFkColumn = ?', whereArgs: [numeroValue]);
  }
  await db.delete(table, where: 'id = ?', whereArgs: [rowId]);
}

class CorbeilleRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<CorbeilleItem>> all() async {
    final db = await _db;
    final rows = await db.query('corbeille', where: 'restaure = 0', orderBy: 'date_suppression DESC');
    return rows.map(CorbeilleItem.fromMap).toList();
  }

  /// Remet un élément de la corbeille dans sa table d'origine, avec ses
  /// lignes liées éventuelles — et lui donne un `updated_at` tout neuf pour
  /// qu'une synchronisation ultérieure ne le supprime pas de nouveau.
  Future<void> restore(int corbeilleId) async {
    final db = await _db;
    final rows = await db.query('corbeille', where: 'id = ?', whereArgs: [corbeilleId]);
    if (rows.isEmpty) return;
    final payload = jsonDecode(rows.first['donnees_json'] as String) as Map<String, dynamic>;
    final data = Map<String, dynamic>.from(payload['data'] as Map);
    final table = rows.first['table_origine'] as String;
    data.remove('id');
    data['updated_at'] = nowMs();

    try {
      await db.insert(table, data);
    } on DatabaseException {
      // Le numéro/code existe déjà (réutilisé entre-temps sur cet appareil) —
      // on force simplement un nouvel identifiant automatique.
      final withoutUnique = Map<String, dynamic>.from(data);
      await db.insert(table, withoutUnique, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    if (payload['lignes'] != null && payload['lignes_table'] != null) {
      final lignesTable = payload['lignes_table'] as String;
      for (final ligne in (payload['lignes'] as List)) {
        final l = Map<String, dynamic>.from(ligne as Map);
        l.remove('id');
        l['updated_at'] = nowMs();
        await db.insert(lignesTable, l, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }

    // `updated_at` doit être renouvelé ici : c'est ce qui permet à une
    // restauration faite sur UN appareil de se propager à l'autre lors de la
    // prochaine synchronisation (voir sync_service.dart, fusion de la table
    // `corbeille`) — sans ça, la ligne corbeille resterait figée à son
    // `updated_at` de suppression et le passage "restaure=1" ne serait
    // jamais vu comme plus récent côté distant.
    await db.update('corbeille', {'restaure': 1, 'updated_at': nowMs()}, where: 'id = ?', whereArgs: [corbeilleId]);
  }

  Future<void> deleteForever(int corbeilleId) async {
    final db = await _db;
    await db.delete('corbeille', where: 'id = ?', whereArgs: [corbeilleId]);
  }

  Future<void> purgeExpired({int jours = 30}) async {
    final db = await _db;
    final seuil = DateTime.now().subtract(Duration(days: jours)).toIso8601String();
    await db.delete('corbeille', where: 'date_suppression < ? AND restaure = 0', whereArgs: [seuil]);
  }
}

class ClientRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<Client>> all() async {
    final db = await _db;
    final rows = await db.query('clients', orderBy: 'id DESC');
    return rows.map(Client.fromMap).toList();
  }

  Future<Client?> byId(int id) async {
    final db = await _db;
    final rows = await db.query('clients', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Client.fromMap(rows.first);
  }

  Future<Client> create({required String nom, String typeClient = 'Particulier', String telephone = '', String adresse = '', String nif = ''}) async {
    final db = await _db;
    final code = await nextCode(db, 'CL', 'clients');
    final now = nowMs();
    final id = await db.insert('clients', {
      'sync_id': newSyncId(), 'code': code, 'nom': nom, 'type_client': typeClient, 'telephone': telephone, 'adresse': adresse,
      'nif': nif, 'date_premier_contact': DateTime.now().toIso8601String(), 'statut': 'Actif', 'updated_at': now,
    });
    return (await byId(id))!;
  }

  Future<void> update(Client c) async {
    final db = await _db;
    final map = c.toMap()..['updated_at'] = nowMs();
    await db.update('clients', map, where: 'id = ?', whereArgs: [c.id]);
  }

  Future<void> delete(Client c) async {
    final db = await _db;
    await moveToCorbeille(db, table: 'clients', rowId: c.id, libelle: c.nom, module: 'clients', origineKey: c.syncId);
  }
}

class FournisseurRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<Fournisseur>> all() async {
    final db = await _db;
    final rows = await db.query('fournisseurs', orderBy: 'nom ASC');
    return rows.map(Fournisseur.fromMap).toList();
  }

  Future<List<String>> noms() async => (await all()).map((f) => f.nom).toList();

  Future<Fournisseur> create({required String nom, String categorieProduits = '', String contact = '', String telephone = '', String adresse = ''}) async {
    final db = await _db;
    final now = nowMs();
    final id = await db.insert('fournisseurs', {
      'sync_id': newSyncId(), 'nom': nom, 'categorie_produits': categorieProduits, 'contact': contact, 'telephone': telephone, 'adresse': adresse, 'updated_at': now,
    });
    final rows = await db.query('fournisseurs', where: 'id = ?', whereArgs: [id]);
    return Fournisseur.fromMap(rows.first);
  }

  Future<void> update(Fournisseur f) async {
    final db = await _db;
    final map = f.toMap()..['updated_at'] = nowMs();
    await db.update('fournisseurs', map, where: 'id = ?', whereArgs: [f.id]);
  }

  Future<void> delete(Fournisseur f) async {
    final db = await _db;
    await moveToCorbeille(db, table: 'fournisseurs', rowId: f.id, libelle: f.nom, module: 'fournisseurs', origineKey: f.syncId);
  }

  /// Total des achats effectués auprès de ce fournisseur, recherché dans
  /// le registre des dépenses par nom exact du bénéficiaire — même
  /// méthode que la version ordinateur.
  Future<double> totalAchats(String nomFournisseur) async {
    final db = await _db;
    final rows = await db.rawQuery('SELECT COALESCE(SUM(montant),0) AS total FROM depenses WHERE beneficiaire = ?', [nomFournisseur]);
    return (rows.first['total'] as num).toDouble();
  }
}

class DevisRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<Devis>> all() async {
    final db = await _db;
    final rows = await db.query('devis', orderBy: 'id DESC');
    return rows.map(Devis.fromMap).toList();
  }

  Future<List<LigneDocument>> lignes(String numero) async {
    final db = await _db;
    final rows = await db.query('lignes_devis', where: 'devis_numero = ?', whereArgs: [numero]);
    return rows.map((m) => LigneDocument.fromMap(m, parentKeyColumn: 'devis_numero')).toList();
  }

  Future<Devis> create({
    required int clientId, required String objet, required int validiteJours, required bool appliquerTva,
    required List<({double quantite, String description, double prixUnitaire})> lignes,
  }) async {
    final db = await _db;
    final numero = await nextNumero(db, 'DV', 'devis');
    final now = nowMs();
    final montantHt = lignes.fold<double>(0, (s, l) => s + l.quantite * l.prixUnitaire);
    final dateLimite = DateTime.now().add(Duration(days: validiteJours)).toIso8601String();
    await db.insert('devis', {
      'sync_id': newSyncId(), 'numero': numero, 'date_devis': DateTime.now().toIso8601String(), 'client_id': clientId, 'objet': objet,
      'montant_ht': montantHt, 'statut': 'En attente', 'validite_jours': validiteJours, 'date_limite': dateLimite,
      'converti_facture': null, 'appliquer_tva': appliquerTva ? 1 : 0, 'updated_at': now,
    });
    for (final l in lignes) {
      await db.insert('lignes_devis', {
        'sync_id': newSyncId(), 'devis_numero': numero, 'quantite': l.quantite, 'description': l.description,
        'prix_unitaire': l.prixUnitaire, 'total_ligne': l.quantite * l.prixUnitaire, 'updated_at': now,
      });
    }
    final rows = await db.query('devis', where: 'numero = ?', whereArgs: [numero]);
    return Devis.fromMap(rows.first);
  }

  Future<void> updateStatut(String numero, String statut) async {
    final db = await _db;
    await db.update('devis', {'statut': statut, 'updated_at': nowMs()}, where: 'numero = ?', whereArgs: [numero]);
  }

  Future<void> delete(Devis d) async {
    final db = await _db;
    await moveToCorbeille(
      db, table: 'devis', rowId: d.id, libelle: d.numero, module: 'devis', origineKey: d.syncId,
      lignesTable: 'lignes_devis', lignesFkColumn: 'devis_numero', numeroValue: d.numero,
    );
  }

  /// Crée une facture reprenant les mêmes lignes que le devis, avec TVA
  /// 18% appliquée automatiquement si `appliquerTva` est vrai.
  Future<Facture> convertirEnFacture(Devis d, {int? clientIdOverride}) async {
    final db = await _db;
    final lignesDevis = await lignes(d.numero);
    final numero = await nextNumero(db, 'FA', 'factures');
    final now = nowMs();
    const tvaTaux = 0.18;
    final montantHt = d.montantHt;
    final tva = d.appliquerTva ? montantHt * tvaTaux : 0.0;
    final montantTtc = montantHt + tva;
    await db.insert('factures', {
      'sync_id': newSyncId(), 'numero': numero, 'date_facture': DateTime.now().toIso8601String(), 'devis_numero': d.numero,
      'client_id': clientIdOverride ?? d.clientId, 'description': d.objet, 'montant_ht': montantHt,
      'reduction_pct': 0, 'montant_ht_net': montantHt, 'tva': tva, 'montant_ttc': montantTtc,
      'avance_recue': 0, 'reste_a_payer': montantTtc, 'statut': 'Impayée', 'mode_paiement': '', 'updated_at': now,
    });
    for (final l in lignesDevis) {
      await db.insert('lignes_facture', {
        'sync_id': newSyncId(), 'facture_numero': numero, 'quantite': l.quantite, 'description': l.description,
        'prix_unitaire': l.prixUnitaire, 'total_ligne': l.totalLigne, 'updated_at': now,
      });
    }
    await db.update('devis', {'statut': 'Accepté', 'converti_facture': numero, 'updated_at': now}, where: 'numero = ?', whereArgs: [d.numero]);
    final rows = await db.query('factures', where: 'numero = ?', whereArgs: [numero]);
    return Facture.fromMap(rows.first);
  }
}

class FactureRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<Facture>> all() async {
    final db = await _db;
    final rows = await db.query('factures', orderBy: 'id DESC');
    return rows.map(Facture.fromMap).toList();
  }

  Future<List<LigneDocument>> lignes(String numero) async {
    final db = await _db;
    final rows = await db.query('lignes_facture', where: 'facture_numero = ?', whereArgs: [numero]);
    return rows.map((m) => LigneDocument.fromMap(m, parentKeyColumn: 'facture_numero')).toList();
  }

  /// Enregistre un paiement reçu — met à jour l'avance, le reste à payer,
  /// et le statut (Impayée / Partielle / Payée), recalculés automatiquement.
  Future<void> enregistrerPaiement(Facture f, double montant, String modePaiement) async {
    final db = await _db;
    final nouvelleAvance = f.avanceRecue + montant;
    final reste = (f.montantTtc - nouvelleAvance).clamp(0, double.infinity);
    final statut = reste <= 0 ? 'Payée' : (nouvelleAvance > 0 ? 'Partielle' : 'Impayée');
    await db.update('factures', {
      'avance_recue': nouvelleAvance, 'reste_a_payer': reste, 'statut': statut, 'mode_paiement': modePaiement, 'updated_at': nowMs(),
    }, where: 'id = ?', whereArgs: [f.id]);
  }

  Future<void> delete(Facture f) async {
    final db = await _db;
    await moveToCorbeille(
      db, table: 'factures', rowId: f.id, libelle: f.numero, module: 'factures', origineKey: f.syncId,
      lignesTable: 'lignes_facture', lignesFkColumn: 'facture_numero', numeroValue: f.numero,
    );
  }
}

class RecuRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<Recu>> all() async {
    final db = await _db;
    final rows = await db.query('recus', orderBy: 'id DESC');
    return rows.map(Recu.fromMap).toList();
  }

  Future<Recu> create({required int clientId, String? factureNumero, required String motif, required double montant, required String modePaiement, String recuPar = ''}) async {
    final db = await _db;
    final numero = await nextNumero(db, 'RC', 'recus');
    final now = nowMs();
    final id = await db.insert('recus', {
      'sync_id': newSyncId(), 'numero': numero, 'date_recu': DateTime.now().toIso8601String(), 'client_id': clientId, 'facture_numero': factureNumero,
      'motif': motif, 'montant_recu': montant, 'mode_paiement': modePaiement, 'recu_par': recuPar, 'updated_at': now,
    });
    final rows = await db.query('recus', where: 'id = ?', whereArgs: [id]);
    return Recu.fromMap(rows.first);
  }

  Future<void> delete(Recu r) async {
    final db = await _db;
    await moveToCorbeille(db, table: 'recus', rowId: r.id, libelle: r.numero, module: 'recus', origineKey: r.syncId);
  }
}

class NoteClientRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<NoteClient>> all() async {
    final db = await _db;
    final rows = await db.query('notes_client', orderBy: 'id DESC');
    return rows.map(NoteClient.fromMap).toList();
  }

  Future<NoteClient> create({required int clientId, required String objet, required String contenu, String redigePar = ''}) async {
    final db = await _db;
    final numero = await nextNumero(db, 'NT', 'notes_client');
    final now = nowMs();
    final id = await db.insert('notes_client', {
      'sync_id': newSyncId(), 'numero': numero, 'date_note': DateTime.now().toIso8601String(), 'client_id': clientId, 'objet': objet,
      'contenu': contenu, 'redige_par': redigePar, 'updated_at': now,
    });
    final rows = await db.query('notes_client', where: 'id = ?', whereArgs: [id]);
    return NoteClient.fromMap(rows.first);
  }

  Future<void> delete(NoteClient n) async {
    final db = await _db;
    await moveToCorbeille(db, table: 'notes_client', rowId: n.id, libelle: n.objet, module: 'notes', origineKey: n.syncId);
  }
}

class DepenseRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<Depense>> all() async {
    final db = await _db;
    final rows = await db.query('depenses', orderBy: 'id DESC');
    return rows.map(Depense.fromMap).toList();
  }

  Future<Depense> create({required String categorie, required String description, required String beneficiaire, required double montant, String modePaiement = 'Espèces', String justificatif = 'Non'}) async {
    final db = await _db;
    final now = nowMs();
    final syncId = newSyncId();
    final id = await db.insert('depenses', {
      'sync_id': syncId, 'date_depense': DateTime.now().toIso8601String(), 'categorie': categorie, 'description': description,
      'beneficiaire': beneficiaire, 'montant': montant, 'mode_paiement': modePaiement, 'justificatif': justificatif, 'updated_at': now,
    });
    final rows = await db.query('depenses', where: 'id = ?', whereArgs: [id]);
    return Depense.fromMap(rows.first);
  }

  Future<void> delete(Depense d) async {
    final db = await _db;
    await moveToCorbeille(db, table: 'depenses', rowId: d.id, libelle: d.description, module: 'depenses', origineKey: d.syncId);
  }
}

class BudgetRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<BudgetCategorie>> forMoisAnnee(String mois, int annee) async {
    final db = await _db;
    final rows = await db.query('budget_categories', where: 'mois = ? AND annee = ?', whereArgs: [mois, annee]);
    return rows.map(BudgetCategorie.fromMap).toList();
  }

  Future<void> setBudget(String categorie, String mois, int annee, double montant) async {
    final db = await _db;
    final existing = await db.query('budget_categories', where: 'categorie = ? AND mois = ? AND annee = ?', whereArgs: [categorie, mois, annee]);
    final now = nowMs();
    if (existing.isEmpty) {
      await db.insert('budget_categories', {'sync_id': newSyncId(), 'categorie': categorie, 'mois': mois, 'annee': annee, 'budget_prevu': montant, 'updated_at': now});
    } else {
      await db.update('budget_categories', {'budget_prevu': montant, 'updated_at': now}, where: 'id = ?', whereArgs: [existing.first['id']]);
    }
  }

  /// Dépenses réelles par catégorie pour un mois/année donné.
  Future<Map<String, double>> depensesReellesParCategorie(String mois, int annee) async {
    final db = await _db;
    final debut = DateTime(annee, _moisIndex(mois) + 1, 1);
    final fin = DateTime(annee, _moisIndex(mois) + 2, 1);
    final rows = await db.rawQuery(
      'SELECT categorie, COALESCE(SUM(montant),0) AS total FROM depenses WHERE date_depense >= ? AND date_depense < ? GROUP BY categorie',
      [debut.toIso8601String(), fin.toIso8601String()],
    );
    return {for (final r in rows) (r['categorie'] as String? ?? ''): (r['total'] as num).toDouble()};
  }

  int _moisIndex(String mois) {
    const noms = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
    final i = noms.indexOf(mois.toLowerCase());
    return i == -1 ? 0 : i;
  }
}

class TarifVitreRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<TarifVitre>> all() async {
    final db = await _db;
    final rows = await db.query('tarifs_vitres', orderBy: 'type_vitre ASC');
    return rows.map(TarifVitre.fromMap).toList();
  }

  /// Ajoute un nouveau tarif, ou met à jour le prix d'un tarif existant
  /// (même `type_vitre`) — en conservant son identité (`id`/`sync_id`)
  /// plutôt que de le recréer, pour que la synchronisation reconnaisse
  /// bien qu'il s'agit du même tarif modifié et non d'un nouveau.
  Future<void> upsert(String typeVitre, double prixM2) async {
    final db = await _db;
    final now = nowMs();
    final existing = await db.query('tarifs_vitres', where: 'type_vitre = ?', whereArgs: [typeVitre]);
    if (existing.isEmpty) {
      await db.insert('tarifs_vitres', {'sync_id': newSyncId(), 'type_vitre': typeVitre, 'prix_m2': prixM2, 'updated_at': now});
    } else {
      await db.update('tarifs_vitres', {'prix_m2': prixM2, 'updated_at': now}, where: 'id = ?', whereArgs: [existing.first['id']]);
    }
  }

  Future<void> delete(TarifVitre t) async {
    final db = await _db;
    await db.delete('tarifs_vitres', where: 'id = ?', whereArgs: [t.id]);
  }
}

class CommandeVitreRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<CommandeVitre>> all() async {
    final db = await _db;
    final rows = await db.query('commandes_vitres', orderBy: 'id DESC');
    return rows.map(CommandeVitre.fromMap).toList();
  }

  Future<CommandeVitre> create({required String typeVitre, required double largeur, required double hauteur, required int quantite, required double prixUnitaire}) async {
    final db = await _db;
    final surface = largeur * hauteur * quantite;
    final montant = surface * prixUnitaire;
    final now = nowMs();
    final id = await db.insert('commandes_vitres', {
      'sync_id': newSyncId(), 'date_commande': DateTime.now().toIso8601String(), 'type_vitre': typeVitre, 'largeur': largeur,
      'hauteur': hauteur, 'quantite': quantite, 'surface': surface, 'prix_unitaire': prixUnitaire, 'montant': montant, 'updated_at': now,
    });
    final rows = await db.query('commandes_vitres', where: 'id = ?', whereArgs: [id]);
    return CommandeVitre.fromMap(rows.first);
  }

  Future<void> delete(CommandeVitre c) async {
    final db = await _db;
    final montantTxt = c.montant.toStringAsFixed(0);
    await moveToCorbeille(
      db, table: 'commandes_vitres', rowId: c.id,
      libelle: 'Vitre ${c.typeVitre} ($montantTxt FCFA)', module: 'vitres', origineKey: c.syncId,
    );
  }
}

class SourcingRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<SourcingCommande>> all() async {
    final db = await _db;
    final rows = await db.query('sourcing_commandes', orderBy: 'id DESC');
    return rows.map(SourcingCommande.fromMap).toList();
  }

  Future<SourcingCommande> create({
    required int? fournisseurId, required int? clientId, required String designation, required double quantite,
    required double prixAchatUnitaire, required double prixVenteUnitaire, String? dateLivraisonPrevue, String notes = '',
  }) async {
    final db = await _db;
    final numero = await nextNumero(db, 'SRC', 'sourcing_commandes');
    final now = nowMs();
    final id = await db.insert('sourcing_commandes', {
      'sync_id': newSyncId(), 'numero': numero, 'date_commande': DateTime.now().toIso8601String(), 'fournisseur_id': fournisseurId, 'client_id': clientId,
      'designation': designation, 'quantite': quantite, 'prix_achat_unitaire': prixAchatUnitaire, 'prix_vente_unitaire': prixVenteUnitaire,
      'statut': 'En cours', 'date_livraison_prevue': dateLivraisonPrevue, 'notes': notes, 'updated_at': now,
    });
    final rows = await db.query('sourcing_commandes', where: 'id = ?', whereArgs: [id]);
    return SourcingCommande.fromMap(rows.first);
  }

  Future<void> updateStatut(int id, String statut) async {
    final db = await _db;
    await db.update('sourcing_commandes', {'statut': statut, 'updated_at': nowMs()}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> update(SourcingCommande s) async {
    final db = await _db;
    final map = s.toMap()..['updated_at'] = nowMs();
    await db.update('sourcing_commandes', map, where: 'id = ?', whereArgs: [s.id]);
  }

  Future<void> delete(SourcingCommande s) async {
    final db = await _db;
    await moveToCorbeille(db, table: 'sourcing_commandes', rowId: s.id, libelle: s.numero, module: 'sourcing', origineKey: s.syncId);
  }
}

class EmployeRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<Employe>> all() async {
    final db = await _db;
    final rows = await db.query('employes', orderBy: 'id DESC');
    return rows.map(Employe.fromMap).toList();
  }

  Future<Employe> create({required String nom, String poste = '', String telephone = '', String? dateEmbauche, String typeContrat = 'CDI', required double salaireMensuel}) async {
    final db = await _db;
    final code = await nextCode(db, 'EMP', 'employes', width: 2);
    final now = nowMs();
    final id = await db.insert('employes', {
      'sync_id': newSyncId(), 'code': code, 'nom': nom, 'poste': poste, 'telephone': telephone, 'date_embauche': dateEmbauche,
      'type_contrat': typeContrat, 'salaire_mensuel': salaireMensuel, 'statut': 'Actif', 'updated_at': now,
    });
    final rows = await db.query('employes', where: 'id = ?', whereArgs: [id]);
    return Employe.fromMap(rows.first);
  }

  Future<void> update(Employe e) async {
    final db = await _db;
    final map = e.toMap()..['updated_at'] = nowMs();
    await db.update('employes', map, where: 'id = ?', whereArgs: [e.id]);
  }

  Future<void> delete(Employe e) async {
    final db = await _db;
    await moveToCorbeille(db, table: 'employes', rowId: e.id, libelle: e.nom, module: 'employes', origineKey: e.syncId);
  }
}

class PaieRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<Paie>> forMoisAnnee(String mois, int annee) async {
    final db = await _db;
    final rows = await db.query('paie', where: 'mois = ? AND annee = ?', whereArgs: [mois, annee]);
    return rows.map(Paie.fromMap).toList();
  }

  /// Assure qu'une ligne de paie existe pour cet employé ce mois-ci
  /// (créée avec le salaire de base si absente), puis la retourne.
  Future<Paie> ensureLigne(Employe emp, String mois, int annee) async {
    final db = await _db;
    final existing = await db.query('paie', where: 'employe_id = ? AND mois = ? AND annee = ?', whereArgs: [emp.id, mois, annee]);
    if (existing.isNotEmpty) return Paie.fromMap(existing.first);
    final now = nowMs();
    final id = await db.insert('paie', {
      'sync_id': newSyncId(), 'mois': mois, 'annee': annee, 'employe_id': emp.id, 'salaire_du': emp.salaireMensuel,
      'avances_versees': 0, 'net_a_payer': emp.salaireMensuel, 'date_paiement': null, 'mode_paiement': '', 'statut': 'En attente', 'updated_at': now,
    });
    final rows = await db.query('paie', where: 'id = ?', whereArgs: [id]);
    return Paie.fromMap(rows.first);
  }

  Future<void> payer(Paie p, {required double montant, required String modePaiement}) async {
    final db = await _db;
    final avances = p.avancesVersees + montant;
    final net = (p.salaireDu - avances).clamp(0, double.infinity);
    await db.update('paie', {
      'avances_versees': avances, 'net_a_payer': net, 'date_paiement': DateTime.now().toIso8601String(),
      'mode_paiement': modePaiement, 'statut': net <= 0 ? 'Payé' : 'En attente', 'updated_at': nowMs(),
    }, where: 'id = ?', whereArgs: [p.id]);
  }
}
