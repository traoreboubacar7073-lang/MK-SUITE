import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mk_suite/data/database.dart';
import 'package:mk_suite/data/repository.dart';
import 'package:mk_suite/services/sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('mk-collision-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => dir.path);
  });
  tearDownAll(() async {
    await (await AppDatabase.instance.database).close();
    await dir.delete(recursive: true);
  });
  test('Un devis existant garde son numéro même si le numéro distant est déjà pris', () async {
    final db = await AppDatabase.instance.database;
    final year = DateTime.now().year;
    await db.insert('devis', {'numero': 'DV-$year-108', 'sync_id': 'doc-a', 'updated_at': 100});
    await db.insert('devis', {'numero': 'DV-$year-109', 'sync_id': 'doc-b', 'updated_at': 100});
    await db.insert('lignes_devis', {'devis_numero': 'DV-$year-109', 'sync_id': 'line-b',
      'quantite': 1, 'description': 'Vitre', 'prix_unitaire': 100, 'total_ligne': 100, 'updated_at': 100});
    final packet = jsonDecode(jsonEncode(await exportAll(db))) as Map<String, dynamic>;
    final parent = (packet['devis'] as List).firstWhere((r) => r['sync_id'] == 'doc-b');
    parent['numero'] = 'DV-$year-108';
    parent['updated_at'] = 200;
    final line = (packet['lignes_devis'] as List).single;
    line['devis_numero'] = 'DV-$year-108';
    line['sync_id'] = 'remote-line-b';
    line['quantite'] = 2;
    for (var i = 0; i < 3; i++) {
      await importAll(db, packet);
    }
    final documents = await db.query('devis', where: 'sync_id = ?', whereArgs: ['doc-b']);
    expect(documents.single['numero'], 'DV-$year-109');
    final lines = await db.query('lignes_devis', where: 'devis_numero = ?', whereArgs: ['DV-$year-109']);
    expect(lines.length, 1);
    expect(lines.single['quantite'], 2);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    // An imported older number can be inserted last. It must not rewind numbering.
    await db.insert('devis', {'numero': 'DV-$year-107', 'sync_id': 'doc-c', 'updated_at': 100});
    expect(await nextNumero(db, 'DV', 'devis'), 'DV-$year-110');
  });
  test('Les messages distinguent une erreur réseau d’un paquet invalide', () {
    expect(syncErrorMessage(const SocketException('test')), contains('Wi-Fi'));
    expect(syncErrorMessage(const FormatException('test')), contains('incomplètes'));
  });
}
