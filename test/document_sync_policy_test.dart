import 'package:flutter_test/flutter_test.dart';
import 'package:mk_suite/services/document_sync_policy.dart';

void main() {
  Map<String, dynamic> line(String id) => {
    'sync_id': id,
    'quantite': 2,
    'description': 'Fenêtre',
    'prix_unitaire': 1500,
    'total_ligne': 3000,
  };
  test('Même contenu et version : les identifiants différents ne doublent pas les lignes', () {
    expect(
      documentSyncDecision(
        localRevision: 10,
        remoteRevision: 10,
        localLines: [line('local')],
        remoteLines: [line('remote')],
      ),
      DocumentSyncDecision.keep,
    );
  });
  test('Les répétitions sont comparées sans déduplication destructive', () {
    expect(
      documentSyncDecision(
        localRevision: 10,
        remoteRevision: 10,
        localLines: [line('a'), line('b')],
        remoteLines: [line('c')],
      ),
      DocumentSyncDecision.conflict,
    );
  });
  test('La version récente remplace le contenu, y compris une suppression', () {
    expect(
      documentSyncDecision(
        localRevision: 10,
        remoteRevision: 11,
        localLines: [line('a')],
        remoteLines: [],
      ),
      DocumentSyncDecision.replace,
    );
  });
}
