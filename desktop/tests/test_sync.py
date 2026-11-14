from contextlib import closing
import copy
import os
import tempfile
import unittest
from database.db_manager import DatabaseManager
from modules.sync_service import export_all, import_all

class SyncTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.a = DatabaseManager(os.path.join(self.tmp.name, 'a.db'))
        self.b = DatabaseManager(os.path.join(self.tmp.name, 'b.db'))
        c = self.a.conn
        c.execute("INSERT INTO devis(numero,objet) VALUES('DV-1','Test')")
        c.execute("INSERT INTO lignes_devis(devis_numero,quantite,description,prix_unitaire,total_ligne) VALUES('DV-1',2,'Vitre',100,200)")
        c.commit()
    def tearDown(self):
        self.a.conn.close(); self.b.conn.close(); self.tmp.cleanup()
    def test_repeated_exchange_and_new_line_ids(self):
        dump = export_all(self.a)
        import_all(self.b, dump)
        for _ in range(3):
            import_all(self.a, export_all(self.b))
            import_all(self.b, export_all(self.a))
        self.assertEqual(self.b.conn.execute('SELECT count(*) FROM lignes_devis').fetchone()[0], 1)
        changed = copy.deepcopy(dump)
        changed['devis'][0]['updated_at'] += 100
        changed['lignes_devis'][0]['sync_id'] = 'new-line-id'
        changed['lignes_devis'][0]['quantite'] = 4
        import_all(self.b, changed)
        rows = self.b.conn.execute('SELECT * FROM lignes_devis').fetchall()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['quantite'], 4)
        self.assertEqual(export_all(self.b)['devis'][0]['updated_at'], changed['devis'][0]['updated_at'])
    def test_conflict_and_legacy_are_preserved(self):
        dump = export_all(self.a); import_all(self.b, dump)
        dump['lignes_devis'][0]['quantite'] = 9
        self.assertTrue(import_all(self.b, dump).has_conflicts)
        self.assertEqual(self.b.conn.execute('SELECT quantite FROM lignes_devis').fetchone()[0], 2)
        dump['version'] = 1
        with self.assertRaises(ValueError): import_all(self.b, dump)
    def test_empty_snapshot_deletes_all_lines(self):
        dump = export_all(self.a); import_all(self.b, dump)
        dump['devis'][0]['updated_at'] += 100
        dump['lignes_devis'] = []
        import_all(self.b, dump)
        self.assertEqual(self.b.conn.execute('SELECT count(*) FROM lignes_devis').fetchone()[0], 0)
    def test_orphan_rolls_back(self):
        dump = export_all(self.a)
        dump['lignes_devis'][0]['devis_sync_id_ref'] = 'missing'
        with self.assertRaises(ValueError): import_all(self.b, dump)
        self.assertEqual(self.b.conn.execute('SELECT count(*) FROM devis').fetchone()[0], 0)
    def test_parent_revision_and_repere(self):
        before = export_all(self.a)['devis'][0]['updated_at']
        self.a.conn.execute("UPDATE lignes_devis SET quantite=3 WHERE devis_numero='DV-1'")
        self.a.conn.commit()
        self.assertGreater(export_all(self.a)['devis'][0]['updated_at'], before)
        self.a.conn.execute("INSERT INTO commandes_vitres(type_vitre,repere,largeur,hauteur,quantite) VALUES('Clair','N12',1.855,1,2)")
        self.a.conn.commit()
        import_all(self.b, export_all(self.a))
        self.assertEqual(self.b.conn.execute('SELECT repere FROM commandes_vitres').fetchone()[0], 'N12')
    def test_additive_migration_keeps_history_and_backup(self):
        path = os.path.join(self.tmp.name, 'b.db')
        self.b.close()
        import sqlite3
        with closing(sqlite3.connect(path)) as conn:
            conn.execute("DROP TRIGGER IF EXISTS trg_commandes_vitres_sync_ai")
            conn.execute("DROP TRIGGER IF EXISTS trg_commandes_vitres_sync_au")
            conn.execute("ALTER TABLE commandes_vitres DROP COLUMN repere")
            conn.commit()
        self.b = DatabaseManager(path)
        self.assertTrue(os.path.exists(path + '.before-1.1.2.bak'))
        columns = {r[1] for r in self.b.conn.execute('PRAGMA table_info(commandes_vitres)')}
        self.assertIn('repere', columns)

    def test_number_collision_remains_linked_to_original_document(self):
        self.b.conn.execute("INSERT INTO devis(numero,objet) VALUES('DV-1','Local distinct')")
        self.b.conn.commit()
        dump = export_all(self.a)
        import_all(self.b, dump)
        imported = self.b.conn.execute('SELECT * FROM devis WHERE sync_id=?',
                                      (dump['devis'][0]['sync_id'],)).fetchone()
        self.assertNotEqual(imported['numero'], 'DV-1')
        number = imported['numero']
        dump['devis'][0]['updated_at'] += 100
        import_all(self.b, dump)
        imported = self.b.conn.execute('SELECT * FROM devis WHERE sync_id=?',
                                      (dump['devis'][0]['sync_id'],)).fetchone()
        self.assertEqual(imported['numero'], number)
        self.assertEqual(self.b.conn.execute('SELECT devis_numero FROM lignes_devis').fetchone()[0], number)

    def test_legitimate_repeated_lines_not_deduplicated(self):
        dump = export_all(self.a)
        duplicate = copy.deepcopy(dump['lignes_devis'][0]); duplicate['sync_id'] = 'legitimate-second'
        dump['lignes_devis'].append(duplicate)
        import_all(self.b, dump)
        self.assertEqual(self.b.conn.execute('SELECT count(*) FROM lignes_devis').fetchone()[0], 2)

if __name__ == '__main__': unittest.main()
