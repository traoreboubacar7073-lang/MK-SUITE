import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import '../data/database.dart';

/// Synchronisation locale Wi-Fi avec la version ordinateur de MK Suite.
///
/// PRINCIPE : aucun serveur internet — téléphone et ordinateur doivent
/// être sur le même réseau Wi-Fi. L'appareil qui lance la synchronisation
/// (`SyncClient.syncWith`) fait DEUX choses avec l'autre appareil (qui
/// doit avoir démarré son serveur local, `SyncServer.start`) :
///   1. il récupère les données de l'autre appareil (GET /export) et les
///      fusionne dans sa propre base ;
///   2. il envoie ses propres données à l'autre appareil (POST /import),
///      qui fait la même fusion de son côté.
/// Après ces deux étapes, les deux appareils ont exactement les mêmes
/// données — peu importe lequel a démarré la synchronisation.
///
/// IDENTITÉ DES LIGNES : chaque ligne de chaque table a un `sync_id`
/// (identifiant unique généré une seule fois, à la création) qui est LA
/// clé de rapprochement entre les deux appareils — jamais le numéro/code
/// affiché à l'écran (CL-001, DV-2026-001...), qui reste un simple
/// libellé et pourrait en théorie être généré indépendamment des deux
/// côtés pour deux enregistrements différents.
///
/// RÈGLE DE FUSION : pour chaque ligne, celle dont `updated_at` (horodatage
/// de dernière modification) est la plus récente l'emporte. Une ligne
/// absente d'un côté est simplement ajoutée — rien n'est jamais perdu par
/// une synchronisation.
///
/// SUPPRESSIONS : une suppression passe toujours par la Corbeille (jamais
/// un DELETE direct). La table `corbeille` est donc synchronisée comme les
/// autres, puis un passage supplémentaire ("tombstones") supprime, sur
/// l'appareil qui reçoit, toute ligne dont la corbeille de l'autre appareil
/// indique une suppression plus récente que sa dernière modification —
/// c'est ce qui fait qu'une suppression faite sur un appareil finit par
/// disparaître de l'autre aussi, au prochain échange.
library sync_service;

const int syncPort = 8642;

class SyncLog {
  final List<String> lines = [];
  int inserted = 0;
  int updated = 0;
  void add(String line) => lines.add(line);
}

// ---------------------------------------------------------------------------
// EXPORT — construit le paquet JSON envoyé à l'autre appareil.
// ---------------------------------------------------------------------------

Future<Map<String, dynamic>> exportAll(Database db) async {
  Future<List<Map<String, dynamic>>> dump(String table) async {
    final rows = await db.query(table);
    return rows.map((r) => Map<String, dynamic>.from(r)..remove('id')).toList();
  }

  // Pour chaque ligne référençant une autre table par identifiant local
  // (client_id, fournisseur_id, employe_id) ou par numéro texte
  // (devis_numero, facture_numero), on ajoute le sync_id correspondant —
  // c'est ce que l'appareil qui reçoit utilisera pour retrouver LA bonne
  // ligne locale, même si les identifiants/numéros ne correspondent pas
  // d'un appareil à l'autre.
  Future<String?> syncIdOf(String table, String column, dynamic value) async {
    if (value == null) return null;
    final rows = await db.query(table, columns: ['sync_id'], where: '$column = ?', whereArgs: [value], limit: 1);
    return rows.isEmpty ? null : rows.first['sync_id'] as String?;
  }

  final clients = await dump('clients');
  final fournisseurs = await dump('fournisseurs');
  final employes = await dump('employes');
  final tarifs = await dump('tarifs_vitres');

  final devis = await dump('devis');
  for (final d in devis) {
    d['client_sync_id_ref'] = await syncIdOf('clients', 'id', d['client_id']);
  }

  final lignesDevis = await dump('lignes_devis');
  for (final l in lignesDevis) {
    l['devis_sync_id_ref'] = await syncIdOf('devis', 'numero', l['devis_numero']);
  }

  final factures = await dump('factures');
  for (final f in factures) {
    f['client_sync_id_ref'] = await syncIdOf('clients', 'id', f['client_id']);
    f['devis_sync_id_ref'] = f['devis_numero'] == null ? null : await syncIdOf('devis', 'numero', f['devis_numero']);
  }

  final lignesFacture = await dump('lignes_facture');
  for (final l in lignesFacture) {
    l['facture_sync_id_ref'] = await syncIdOf('factures', 'numero', l['facture_numero']);
  }

  final recus = await dump('recus');
  for (final r in recus) {
    r['client_sync_id_ref'] = await syncIdOf('clients', 'id', r['client_id']);
    r['facture_sync_id_ref'] = r['facture_numero'] == null ? null : await syncIdOf('factures', 'numero', r['facture_numero']);
  }

  final notes = await dump('notes_client');
  for (final n in notes) {
    n['client_sync_id_ref'] = await syncIdOf('clients', 'id', n['client_id']);
  }

  final depenses = await dump('depenses');
  final budget = await dump('budget_categories');

  final vitres = await dump('commandes_vitres');
  for (final v in vitres) {
    v['devis_sync_id_ref'] = v['devis_numero'] == null ? null : await syncIdOf('devis', 'numero', v['devis_numero']);
    v['facture_sync_id_ref'] = v['facture_numero'] == null ? null : await syncIdOf('factures', 'numero', v['facture_numero']);
  }

  final sourcing = await dump('sourcing_commandes');
  for (final s in sourcing) {
    s['fournisseur_sync_id_ref'] = await syncIdOf('fournisseurs', 'id', s['fournisseur_id']);
    s['client_sync_id_ref'] = await syncIdOf('clients', 'id', s['client_id']);
  }

  final paie = await dump('paie');
  for (final p in paie) {
    p['employe_sync_id_ref'] = await syncIdOf('employes', 'id', p['employe_id']);
  }

  final corbeille = await dump('corbeille');

  return {
    'app': 'mk_suite', 'version': 1, 'exported_at': nowMs(),
    'clients': clients, 'fournisseurs': fournisseurs, 'employes': employes, 'tarifs_vitres': tarifs,
    'devis': devis, 'lignes_devis': lignesDevis, 'factures': factures, 'lignes_facture': lignesFacture,
    'recus': recus, 'notes_client': notes, 'depenses': depenses, 'budget_categories': budget,
    'commandes_vitres': vitres, 'sourcing_commandes': sourcing, 'paie': paie, 'corbeille': corbeille,
  };
}

// ---------------------------------------------------------------------------
// IMPORT — fusionne un paquet reçu dans la base locale.
// ---------------------------------------------------------------------------

Future<SyncLog> importAll(Database rawDb, Map<String, dynamic> dump) async {
  final log = SyncLog();

  // Toute la fusion se fait dans UNE SEULE transaction : si une ligne pose
  // problème en cours de route (contrainte violée, table inattendue...),
  // tout est annulé plutôt que de laisser la base à moitié fusionnée (par
  // exemple des lignes de devis déjà importées mais leur devis parent non
  // encore traité).
  await rawDb.transaction((txn) async {
    final db = txn;

    List<Map<String, dynamic>> rowsOf(String key) => ((dump[key] as List?) ?? []).cast<Map<String, dynamic>>();

    Future<int?> localIdBySyncId(String table, String? syncId) async {
      if (syncId == null) return null;
      final rows = await db.query(table, columns: ['id'], where: 'sync_id = ?', whereArgs: [syncId], limit: 1);
      return rows.isEmpty ? null : rows.first['id'] as int?;
    }

    Future<String?> localNumeroBySyncId(String table, String? syncId, String numeroColumn) async {
      if (syncId == null) return null;
      final rows = await db.query(table, columns: [numeroColumn], where: 'sync_id = ?', whereArgs: [syncId], limit: 1);
      return rows.isEmpty ? null : rows.first[numeroColumn] as String?;
    }

    /// Fusionne une table par `sync_id` : nouvelle ligne -> insertion (en
    /// régénérant un numéro/code local si le champ unique `uniqueField`
    /// entre en collision avec une ligne EXISTANTE différente) ; ligne déjà
    /// connue -> mise à jour seulement si la version distante est plus
    /// récente.
    Future<void> mergeSimple(String table, String key, {String? uniqueField, String? numeroPrefix, bool withYear = true, int width = 3}) async {
      for (final r in rowsOf(key)) {
        final syncId = r['sync_id'] as String?;
        if (syncId == null || syncId.isEmpty) continue;
        final remoteUpdatedAt = (r['updated_at'] ?? 0) as int;
        final localRows = await db.query(table, where: 'sync_id = ?', whereArgs: [syncId]);
        if (localRows.isEmpty) {
          final row = Map<String, dynamic>.from(r);
          row.removeWhere((k, _) => k.endsWith('_sync_id_ref'));
          if (uniqueField != null && row[uniqueField] != null) {
            final collision = await db.query(table, where: '$uniqueField = ?', whereArgs: [row[uniqueField]]);
            if (collision.isNotEmpty) {
              final ancien = row[uniqueField];
              row[uniqueField] = numeroPrefix != null
                  ? await nextNumero(db, numeroPrefix, table, column: uniqueField, withYear: withYear, width: width)
                  : '$ancien-2';
              log.add('$table : "$ancien" existait déjà avec un contenu différent → renommé en "${row[uniqueField]}".');
            }
          }
          await db.insert(table, row);
          log.inserted++;
        } else {
          final localUpdatedAt = (localRows.first['updated_at'] ?? 0) as int;
          if (remoteUpdatedAt > localUpdatedAt) {
            final row = Map<String, dynamic>.from(r);
            row.removeWhere((k, _) => k.endsWith('_sync_id_ref'));
            row.remove('sync_id');
            await db.update(table, row, where: 'sync_id = ?', whereArgs: [syncId]);
            log.updated++;
          }
        }
      }
    }

    /// Même principe que [mergeSimple], mais pour une table qui référence
    /// une autre par identifiant local (`fkColumn`) — résolue ici via le
    /// `sync_id` de la ligne parente. `fkToRefSyncIdField` donne, pour
    /// chaque colonne FK, le nom EXACT du champ `*_sync_id_ref` écrit par
    /// [exportAll] (ex : `client_id` -> `client_sync_id_ref`, `devis_numero`
    /// -> `devis_sync_id_ref`) : les deux ne se déduisent pas l'un de
    /// l'autre par simple manipulation de texte dès que la colonne FK ne se
    /// termine pas par `_id` (cas des colonnes `*_numero`).
    Future<void> mergeWithFk(
      String table,
      String key,
      Map<String, String> fkToRefTable,
      Map<String, String> fkToRefKey,
      Map<String, String> fkToRefSyncIdField, {
      String? uniqueField,
      String? numeroPrefix,
    }) async {
      for (final r in rowsOf(key)) {
        final syncId = r['sync_id'] as String?;
        if (syncId == null || syncId.isEmpty) continue;
        final row = Map<String, dynamic>.from(r);
        for (final fkColumn in fkToRefTable.keys) {
          final refTable = fkToRefTable[fkColumn]!;
          final refKeyField = fkToRefKey[fkColumn]!;
          final refSyncId = row.remove(fkToRefSyncIdField[fkColumn]!) as String?;
          // Pas de repli sur la valeur brute distante : un identifiant/numéro
          // local à l'autre appareil n'a aucun sens ici, on préfère laisser
          // la FK vide (parent introuvable) plutôt que de pointer vers la
          // mauvaise ligne — ou vers une ligne inexistante — chez nous.
          row[fkColumn] = refKeyField == 'id'
              ? await localIdBySyncId(refTable, refSyncId)
              : await localNumeroBySyncId(refTable, refSyncId, refKeyField);
        }
        row.removeWhere((k, _) => k.endsWith('_sync_id_ref'));
        final remoteUpdatedAt = (row['updated_at'] ?? 0) as int;
        final localRows = await db.query(table, where: 'sync_id = ?', whereArgs: [syncId]);
        if (localRows.isEmpty) {
          if (uniqueField != null && row[uniqueField] != null) {
            final collision = await db.query(table, where: '$uniqueField = ?', whereArgs: [row[uniqueField]]);
            if (collision.isNotEmpty) {
              final ancien = row[uniqueField];
              row[uniqueField] = numeroPrefix != null ? await nextNumero(db, numeroPrefix, table, column: uniqueField) : '$ancien-2';
              log.add('$table : "$ancien" existait déjà avec un contenu différent → renommé en "${row[uniqueField]}".');
            }
          }
          await db.insert(table, row);
          log.inserted++;
        } else {
          final localUpdatedAt = (localRows.first['updated_at'] ?? 0) as int;
          if (remoteUpdatedAt > localUpdatedAt) {
            final updateRow = Map<String, dynamic>.from(row)..remove('sync_id');
            await db.update(table, updateRow, where: 'sync_id = ?', whereArgs: [syncId]);
            log.updated++;
          }
        }
      }
    }

    /// Fusionne une table de RÉFÉRENCE pré-remplie indépendamment sur les
    /// deux appareils au tout premier lancement (fournisseurs habituels,
    /// tarifs de vitres) : deux lignes avec la même valeur de `field` (ex.
    /// même nom de fournisseur) mais des `sync_id` différents désignent en
    /// réalité la MÊME entité — on les fusionne directement en une seule
    /// ligne plutôt que d'insérer un doublon puis de le "dédupliquer" après
    /// coup (ce qui déclenchait le renommage anti-collision de
    /// [mergeSimple] et empêchait toute déduplication ultérieure).
    ///
    /// Quand une correspondance par `field` est trouvée, on adopte le
    /// `sync_id` DISTANT sur la ligne locale : c'est ce qui permet aux
    /// lignes plus bas dans ce même paquet qui référencent cette entité
    /// (ex. `sourcing_commandes.fournisseur_id`) de la retrouver via
    /// [localIdBySyncId] alors qu'elles ont été exportées avec le sync_id
    /// distant. Comme [syncWith] importe toujours AVANT d'exporter, les
    /// deux appareils convergent vers ce même sync_id dès le premier
    /// échange complet.
    Future<void> mergeReference(String table, String key, String field) async {
      for (final r in rowsOf(key)) {
        final syncId = r['sync_id'] as String?;
        if (syncId == null || syncId.isEmpty) continue;
        final remoteUpdatedAt = (r['updated_at'] ?? 0) as int;

        final bySyncId = await db.query(table, where: 'sync_id = ?', whereArgs: [syncId]);
        if (bySyncId.isNotEmpty) {
          final localUpdatedAt = (bySyncId.first['updated_at'] ?? 0) as int;
          if (remoteUpdatedAt > localUpdatedAt) {
            final row = Map<String, dynamic>.from(r)..remove('sync_id');
            row.removeWhere((k, _) => k.endsWith('_sync_id_ref'));
            await db.update(table, row, where: 'sync_id = ?', whereArgs: [syncId]);
            log.updated++;
          }
          continue;
        }

        final val = (r[field] as String?)?.trim();
        if (val != null && val.isNotEmpty) {
          final byField = await db.query(table, where: '$field = ?', whereArgs: [val]);
          if (byField.isNotEmpty) {
            final localUpdatedAt = (byField.first['updated_at'] ?? 0) as int;
            final data = <String, dynamic>{'sync_id': syncId};
            if (remoteUpdatedAt > localUpdatedAt) {
              final row = Map<String, dynamic>.from(r)..remove('sync_id');
              row.removeWhere((k, _) => k.endsWith('_sync_id_ref'));
              data.addAll(row);
            }
            await db.update(table, data, where: 'id = ?', whereArgs: [byField.first['id']]);
            continue;
          }
        }

        final row = Map<String, dynamic>.from(r);
        row.removeWhere((k, _) => k.endsWith('_sync_id_ref'));
        await db.insert(table, row);
        log.inserted++;
      }
    }

    // Ordre important : les tables "parentes" d'abord, pour que la
    // résolution des références (client_sync_id_ref, etc.) trouve toujours
    // la ligne déjà fusionnée.
    await mergeSimple('clients', 'clients', uniqueField: 'code', numeroPrefix: 'CL', withYear: false);
    await mergeReference('fournisseurs', 'fournisseurs', 'nom');
    await mergeSimple('employes', 'employes', uniqueField: 'code', numeroPrefix: 'EMP', withYear: false, width: 2);
    await mergeReference('tarifs_vitres', 'tarifs_vitres', 'type_vitre');

    await mergeWithFk('devis', 'devis', {'client_id': 'clients'}, {'client_id': 'id'}, {'client_id': 'client_sync_id_ref'}, uniqueField: 'numero', numeroPrefix: 'DV');
    await mergeWithFk('lignes_devis', 'lignes_devis', {'devis_numero': 'devis'}, {'devis_numero': 'numero'}, {'devis_numero': 'devis_sync_id_ref'});
    await mergeWithFk(
      'factures', 'factures',
      {'client_id': 'clients', 'devis_numero': 'devis'},
      {'client_id': 'id', 'devis_numero': 'numero'},
      {'client_id': 'client_sync_id_ref', 'devis_numero': 'devis_sync_id_ref'},
      uniqueField: 'numero', numeroPrefix: 'FA',
    );
    await mergeWithFk('lignes_facture', 'lignes_facture', {'facture_numero': 'factures'}, {'facture_numero': 'numero'}, {'facture_numero': 'facture_sync_id_ref'});
    await mergeWithFk(
      'recus', 'recus',
      {'client_id': 'clients', 'facture_numero': 'factures'},
      {'client_id': 'id', 'facture_numero': 'numero'},
      {'client_id': 'client_sync_id_ref', 'facture_numero': 'facture_sync_id_ref'},
      uniqueField: 'numero', numeroPrefix: 'RC',
    );
    await mergeWithFk('notes_client', 'notes_client', {'client_id': 'clients'}, {'client_id': 'id'}, {'client_id': 'client_sync_id_ref'}, uniqueField: 'numero', numeroPrefix: 'NT');
    await mergeSimple('depenses', 'depenses');
    await mergeSimple('budget_categories', 'budget_categories');
    await mergeWithFk(
      'commandes_vitres', 'commandes_vitres',
      {'devis_numero': 'devis', 'facture_numero': 'factures'},
      {'devis_numero': 'numero', 'facture_numero': 'numero'},
      {'devis_numero': 'devis_sync_id_ref', 'facture_numero': 'facture_sync_id_ref'},
    );
    await mergeWithFk(
      'sourcing_commandes', 'sourcing_commandes',
      {'fournisseur_id': 'fournisseurs', 'client_id': 'clients'},
      {'fournisseur_id': 'id', 'client_id': 'id'},
      {'fournisseur_id': 'fournisseur_sync_id_ref', 'client_id': 'client_sync_id_ref'},
      uniqueField: 'numero', numeroPrefix: 'SRC',
    );
    await mergeWithFk('paie', 'paie', {'employe_id': 'employes'}, {'employe_id': 'id'}, {'employe_id': 'employe_sync_id_ref'});

    // Corbeille en dernier : d'abord fusionnée comme les autres (ce qui
    // propage aussi bien une nouvelle suppression qu'une restauration —
    // voir CorbeilleRepository.restore, qui renouvelle `updated_at` du
    // côté corbeille pour ça), puis utilisée pour propager les
    // suppressions ("tombstones") vers les tables encore vivantes.
    await mergeSimple('corbeille', 'corbeille');
    final corbeilleRows = await db.query('corbeille', where: 'restaure = 0');
    for (final c in corbeilleRows) {
      final origineKey = c['origine_key'] as String?;
      final table = c['table_origine'] as String?;
      final deletedAt = (c['deleted_at'] ?? 0) as int;
      if (origineKey == null || table == null || deletedAt == 0) continue;
      // `origine_key` est le sync_id de la ligne supprimée (voir moveToCorbeille).
      final still = await db.query(table, where: 'sync_id = ?', whereArgs: [origineKey]);
      if (still.isNotEmpty && ((still.first['updated_at'] ?? 0) as int) < deletedAt) {
        await db.delete(table, where: 'sync_id = ?', whereArgs: [origineKey]);
        log.add('$table : ligne supprimée sur l\'autre appareil, retirée ici aussi.');
      }
    }
  });

  return log;
}

// ---------------------------------------------------------------------------
// SERVEUR — attend une connexion de l'autre appareil sur le même Wi-Fi.
// ---------------------------------------------------------------------------

class SyncServer {
  HttpServer? _server;
  bool get isRunning => _server != null;

  Future<String?> start(Database db) async {
    if (_server != null) return localAddress();
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, syncPort);
    } catch (_) {
      return null;
    }
    _server!.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      try {
        if (request.method == 'GET' && request.uri.path == '/ping') {
          request.response.write(jsonEncode({'app': 'mk_suite'}));
        } else if (request.method == 'GET' && request.uri.path == '/export') {
          final dump = await exportAll(db);
          request.response.write(jsonEncode(dump));
        } else if (request.method == 'POST' && request.uri.path == '/import') {
          final body = await utf8.decoder.bind(request).join();
          final dump = jsonDecode(body) as Map<String, dynamic>;
          final log = await importAll(db, dump);
          request.response.write(jsonEncode({'inserted': log.inserted, 'updated': log.updated, 'lines': log.lines}));
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
      } catch (e) {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write(jsonEncode({'error': e.toString()}));
      }
      await request.response.close();
    });
    return localAddress();
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  /// Adresse IP locale (Wi-Fi) de l'appareil, à afficher pour que l'autre
  /// appareil puisse s'y connecter — cherche une IPv4 privée classique
  /// (192.168.x.x / 10.x.x.x / 172.16-31.x.x), en ignorant les interfaces
  /// virtuelles (loopback, VPN...).
  static Future<String?> localAddress() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      for (final itf in interfaces) {
        for (final addr in itf.addresses) {
          final ip = addr.address;
          if (ip.startsWith('192.168.') || ip.startsWith('10.') || _isPrivate172(ip)) return ip;
        }
      }
      if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
        return interfaces.first.addresses.first.address;
      }
    } catch (_) {}
    return null;
  }

  static bool _isPrivate172(String ip) {
    if (!ip.startsWith('172.')) return false;
    final parts = ip.split('.');
    if (parts.length < 2) return false;
    final second = int.tryParse(parts[1]) ?? 0;
    return second >= 16 && second <= 31;
  }
}

// ---------------------------------------------------------------------------
// CLIENT — se connecte à l'autre appareil pour lancer une synchronisation
// complète dans les deux sens.
// ---------------------------------------------------------------------------

class SyncClient {
  /// Vérifie qu'un appareil MK Suite répond bien à cette adresse, avant de
  /// lancer une vraie synchronisation (évite un message d'erreur confus si
  /// l'adresse est fausse ou si l'autre appareil n'a pas démarré son
  /// serveur).
  static Future<bool> canReach(String host, {int port = syncPort}) async {
    try {
      final res = await http.get(Uri.parse('http://$host:$port/ping')).timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) return false;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['app'] == 'mk_suite';
    } catch (_) {
      return false;
    }
  }

  /// Synchronisation complète avec l'appareil à `host:port` : récupère ses
  /// données et les fusionne ici, puis envoie les nôtres pour qu'il fasse
  /// de même de son côté. Retourne un résumé (ce qui a été ajouté/mis à
  /// jour ici, et les éventuels avertissements comme un numéro renommé).
  static Future<SyncLog> syncWith(Database db, String host, {int port = syncPort}) async {
    final base = 'http://$host:$port';
    final getRes = await http.get(Uri.parse('$base/export')).timeout(const Duration(seconds: 30));
    if (getRes.statusCode != 200) {
      throw Exception("L'autre appareil n'a pas répondu correctement (${getRes.statusCode}).");
    }
    final remoteDump = jsonDecode(getRes.body) as Map<String, dynamic>;
    final log = await importAll(db, remoteDump);

    final localDump = await exportAll(db);
    final postRes = await http
        .post(Uri.parse('$base/import'), headers: {'Content-Type': 'application/json'}, body: jsonEncode(localDump))
        .timeout(const Duration(seconds: 30));
    if (postRes.statusCode != 200) {
      log.add("Nos données ont bien été reçues localement, mais l'envoi vers l'autre appareil a échoué (${postRes.statusCode}) — relance la synchronisation depuis l'un ou l'autre appareil.");
    }
    return log;
  }
}
