import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Une adresse IP déjà utilisée pour la synchronisation, avec la date de sa
/// dernière utilisation (sert à trier les plus récentes en premier).
class SyncPeer {
  final String ip;
  final String derniereUtilisation;
  const SyncPeer({required this.ip, required this.derniereUtilisation});

  factory SyncPeer.fromMap(Map<String, dynamic> m) =>
      SyncPeer(ip: (m['ip'] ?? '') as String, derniereUtilisation: (m['derniereUtilisation'] ?? '') as String);

  Map<String, dynamic> toMap() => {'ip': ip, 'derniereUtilisation': derniereUtilisation};
}

/// Mémorise les adresses IP déjà utilisées pour la synchronisation Wi-Fi,
/// pour ne plus jamais avoir à les retaper — pendant, côté téléphone, de
/// `modules/sync_peers.py` côté ordinateur.
///
/// Stocké via shared_preferences (une simple clé/valeur locale à l'appareil)
/// plutôt que dans la base sqflite : c'est une préférence propre à CE
/// téléphone, qui n'a aucune raison de se propager à l'ordinateur lors
/// d'une synchronisation — contrairement à toutes les vraies données
/// métier (clients, devis, factures...).
class SyncPeersService {
  SyncPeersService._();

  static const _cle = 'mk_suite_sync_peers';
  static const maxPeers = 6;

  static Future<List<SyncPeer>> charger() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cle);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded.whereType<Map>().map((m) => SyncPeer.fromMap(Map<String, dynamic>.from(m))).toList();
    } catch (_) {
      return [];
    }
  }

  /// Ajoute (ou fait remonter en tête si déjà présente) une adresse IP
  /// utilisée avec succès — à appeler après une vérification ou une
  /// synchronisation réussie, jamais après un échec.
  static Future<void> enregistrer(String ip) async {
    final propre = ip.trim();
    if (propre.isEmpty) return;
    final actuelles = await charger();
    final filtrees = actuelles.where((p) => p.ip != propre).toList();
    filtrees.insert(0, SyncPeer(ip: propre, derniereUtilisation: DateTime.now().toIso8601String()));
    final limitees = filtrees.take(maxPeers).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cle, jsonEncode(limitees.map((p) => p.toMap()).toList()));
  }

  static Future<void> supprimer(String ip) async {
    final actuelles = await charger();
    final filtrees = actuelles.where((p) => p.ip != ip).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cle, jsonEncode(filtrees.map((p) => p.toMap()).toList()));
  }
}
