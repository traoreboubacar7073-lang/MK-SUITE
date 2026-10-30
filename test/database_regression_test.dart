import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mk_suite/data/database.dart';
import 'package:mk_suite/data/repository.dart';
import 'package:mk_suite/services/backup_service.dart';
import 'package:mk_suite/services/sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('mk-suite-test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => dir.path,
        );
  });
  tearDownAll(() async {
    await (await AppDatabase.instance.database).close();
    await dir.delete(recursive: true);
  });

  test(
    'Corbeille, restauration, paiements périmés et sauvegarde relationnelle',
    () async {
      final db = await AppDatabase.instance.database;
      final client = await ClientRepository().create(nom: 'Test');
      var devis = await DevisRepository().create(
        clientId: client.id,
        objet: 'Porte',
        validiteJours: 30,
        appliquerTva: false,
        lignes: [(quantite: 1.0, description: 'Porte', prixUnitaire: 1000.0)],
      );
      final originalNumero = devis.numero;
      final originalSyncId = devis.syncId;
      await DevisRepository().update(
        devis,
        clientId: client.id,
        objet: 'Porte modifiée',
        validiteJours: 45,
        appliquerTva: false,
        lignes: [(quantite: 2.0, description: 'Panneau', prixUnitaire: 500.0)],
      );
      await expectLater(
        DevisRepository().update(
          devis,
          clientId: client.id,
          objet: 'Écrasement périmé',
          validiteJours: 30,
          appliquerTva: false,
          lignes: [(quantite: 1.0, description: 'Ancien', prixUnitaire: 1.0)],
        ),
        throwsStateError,
      );
      devis = (await DevisRepository().all()).single;
      expect(devis.numero, originalNumero);
      expect(devis.syncId, originalSyncId);
      expect(devis.objet, 'Porte modifiée');
      expect(devis.montantHt, 1000);
      await DevisRepository().delete(devis);
      final corbeille = await CorbeilleRepository().all();
      expect(corbeille.length, 1);
      await CorbeilleRepository().restore(corbeille.first.id);
      expect((await DevisRepository().lignes(devis.numero)).length, 1);
      final vitre = await CommandeVitreRepository().create(
        typeVitre: 'CLAIR 5mm',
        repere: 'N1',
        largeur: 0.42,
        hauteur: 0.925,
        quantite: 2,
        prixUnitaire: 10000,
      );
      expect(vitre.repere, 'N1');
      expect(vitre.surface, closeTo(0.777, 0.000001));
      final facture = await DevisRepository().convertirEnFacture(devis);
      await FactureRepository().enregistrerPaiement(facture, 200, 'Espèces');
      await FactureRepository().enregistrerPaiement(facture, 300, 'Espèces');
      expect((await FactureRepository().all()).first.resteAPayer, 500);
      await expectLater(
        FactureRepository().enregistrerPaiement(facture, 501, 'Espèces'),
        throwsArgumentError,
      );
      await expectLater(
        FactureRepository().enregistrerPaiement(facture, double.nan, 'Espèces'),
        throwsArgumentError,
      );
      final tables = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata'",
      )).map((r) => r['name'] as String);
      final backup = <String, dynamic>{'application': 'MK Suite'};
      for (final table in tables) {
        backup[table] = await db.query(table);
      }
      expect(
        await BackupService.restaurerDepuisTexte(jsonEncode(backup)),
        isTrue,
      );
      expect((await FactureRepository().all()).first.resteAPayer, 500);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      backup.remove('clients');
      await expectLater(
        BackupService.restaurerDepuisTexte(jsonEncode(backup)),
        throwsFormatException,
      );
      expect((await ClientRepository().all()).length, 1);
      final packet =
          jsonDecode(jsonEncode(await exportAll(db))) as Map<String, dynamic>;
      final parent = (packet['devis'] as List).single as Map<String, dynamic>;
      parent['updated_at'] = (parent['updated_at'] as int) + 1000;
      final incoming =
          (packet['lignes_devis'] as List).single as Map<String, dynamic>;
      incoming['sync_id'] = 'new-line-on-other-device';
      await importAll(db, packet);
      await importAll(db, packet);
      expect((await DevisRepository().lignes(devis.numero)).length, 1);
      final conflictPacket =
          jsonDecode(jsonEncode(packet)) as Map<String, dynamic>;
      (conflictPacket['lignes_devis'] as List).add({
        ...incoming,
        'sync_id': 'duplicate',
      });
      expect((await importAll(db, conflictPacket)).hasConflicts, isTrue);
      expect((await DevisRepository().lignes(devis.numero)).length, 1);
      final incomplete = {...packet}..remove('lignes_devis');
      await expectLater(importAll(db, incomplete), throwsFormatException);
      await expectLater(
        importAll(db, {...packet, 'version': 1}),
        throwsStateError,
      );
    },
  );
}
