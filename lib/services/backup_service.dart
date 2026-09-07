import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import '../data/database.dart';

/// Sauvegarde et restauration complètes des données de l'application —
/// toutes les tables sont exportées dans un seul fichier JSON lisible, que
/// l'on peut partager (WhatsApp, email, Google Drive, clé USB via un
/// gestionnaire de fichiers...) et réimporter plus tard, y compris sur un
/// autre téléphone. C'est le filet de sécurité si le téléphone est perdu,
/// cassé, ou si l'application est supprimée par erreur.
///
/// Pendant, côté téléphone, de `modules/sauvegarde.py` côté ordinateur, en
/// version JSON plutôt que copie brute du fichier .db : sur mobile, aucune
/// application tierce n'a un accès direct au fichier SQLite de MK Suite (au
/// contraire de l'ordinateur, où c'est un simple fichier dans le dossier de
/// l'utilisateur), donc l'export doit passer par le sélecteur de partage
/// natif — un export JSON texte est aussi ce qui rend une restauration par
/// copier-coller possible, sans sélecteur de fichier natif supplémentaire.
class BackupService {
  BackupService._();

  static const String _application = 'MK Suite';

  static const List<String> _tables = [
    'clients', 'fournisseurs', 'devis', 'lignes_devis', 'factures', 'lignes_facture',
    'recus', 'notes_client', 'depenses', 'budget_categories', 'tarifs_vitres',
    'commandes_vitres', 'sourcing_commandes', 'employes', 'paie', 'corbeille',
  ];

  static Future<Map<String, dynamic>> _exportData() async {
    final db = await AppDatabase.instance.database;
    final Map<String, dynamic> data = {
      'application': _application,
      'dateExport': DateTime.now().toIso8601String(),
    };
    for (final table in _tables) {
      try {
        data[table] = await db.query(table);
      } catch (_) {
        data[table] = [];
      }
    }
    return data;
  }

  /// Génère le fichier de sauvegarde et ouvre le sélecteur de partage
  /// natif du téléphone pour l'envoyer où l'utilisateur le souhaite.
  static Future<void> partagerSauvegarde() async {
    final data = await _exportData();
    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
    final dir = await getTemporaryDirectory();
    final horodatage = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final file = File('${dir.path}/mk-suite-sauvegarde-$horodatage.json');
    await file.writeAsString(jsonStr);
    await Share.shareXFiles([XFile(file.path)], text: 'Sauvegarde MK Suite du $horodatage');
  }

  /// Restaure les données à partir du contenu texte d'une sauvegarde
  /// (collé depuis le presse-papier ou saisi directement) — plutôt que de
  /// passer par un sélecteur de fichier natif, pour rester fiable sur
  /// toutes les configurations sans dépendance supplémentaire.
  static Future<bool> restaurerDepuisTexte(String contenuJson) async {
    final texte = contenuJson.trim();
    if (texte.isEmpty) return false;
    final Map<String, dynamic> data = jsonDecode(texte) as Map<String, dynamic>;
    if (!data.containsKey('application') || data['application'] != _application) {
      throw const FormatException('Ce contenu ne correspond pas à une sauvegarde MK Suite.');
    }
    await _restaurerDonnees(data);
    return true;
  }

  static Future<void> _restaurerDonnees(Map<String, dynamic> data) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      for (final table in _tables) {
        if (!data.containsKey(table)) continue;
        final rows = data[table];
        if (rows is! List) continue;
        await txn.delete(table);
        for (final row in rows) {
          if (row is Map) {
            await txn.insert(table, Map<String, dynamic>.from(row), conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
      }
    });
  }
}
