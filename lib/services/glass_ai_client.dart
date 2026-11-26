import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class GlassAiResult {
  final String text;
  final List<String> warnings;
  final int rowCount;
  const GlassAiResult(this.text, this.warnings, this.rowCount);

  factory GlassAiResult.fromJson(Map<String, dynamic> result) {
    final rows = result['rows'];
    if (result['unit'] != 'cm' || rows is! List || rows.isEmpty || rows.length > 150 ||
        result['row_count'] != rows.length) {
      throw const FormatException('Nombre de lignes ou unité incohérent');
    }
    final warnings = <String>[];
    final messages = result['warnings'];
    if (messages is! List || messages.any((x) => x is! String)) {
      throw const FormatException('Avertissements invalides');
    }
    warnings.addAll(messages.cast<String>());
    final text = <String>[];
    String dimension(dynamic value) {
      if (value == null) return '?';
      if (value is! num || !value.isFinite || value <= 0 || value > 10000) {
        throw const FormatException('Dimension invalide');
      }
      return value.toString().replaceAll('.', ',');
    }
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row is! Map || row['uncertain'] is! bool || row['note'] is! String) {
        throw const FormatException('Ligne invalide');
      }
      final quantity = row['quantity'];
      if (quantity != null && (quantity is! int || quantity <= 0 || quantity > 10000)) {
        throw const FormatException('Quantité invalide');
      }
      final reference = row['reference'];
      if (reference != null && (reference is! String || !RegExp(r'^N\d+$').hasMatch(reference))) {
        throw const FormatException('Repère invalide');
      }
      text.add('${dimension(row['width_cm'])} x ${dimension(row['height_cm'])} x ${quantity ?? '?'} ${reference ?? 'N?'}');
      if (row['uncertain'] == true || [row['width_cm'], row['height_cm'], quantity, reference].contains(null)) {
        warnings.add('Ligne ${i + 1} à vérifier : ${row['note'].toString().isEmpty ? 'chiffre ou repère incertain' : row['note']}');
      }
    }
    return GlassAiResult(text.join('\n'), warnings, rows.length);
  }
}

class GlassAiClient {
  static Uri serviceUri(String address) {
    var value = address.trim();
    if (!value.contains('://')) value = 'http://$value';
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty ||
        uri.hasQuery || uri.hasFragment || (uri.path.isNotEmpty && uri.path != '/') ||
        !['http', 'https'].contains(uri.scheme)) {
      throw const FormatException('Adresse du service IA invalide');
    }
    if (uri.scheme == 'http') {
      final ip = uri.host.split('.').map(int.tryParse).toList();
      final private = ip.length == 4 && ip.every((n) => n != null && n >= 0 && n <= 255) &&
          (ip[0] == 10 || (ip[0] == 192 && ip[1] == 168) || (ip[0] == 172 && ip[1]! >= 16 && ip[1]! <= 31));
      if (!private) throw const FormatException('Utilisez HTTPS, ou l’adresse Wi-Fi privée de votre ordinateur');
    }
    return uri.replace(port: uri.hasPort ? uri.port : (uri.scheme == 'http' ? 8642 : 443), path: '/glass/recognize');
  }

  static Future<GlassAiResult> recognize(Uint8List bytes, String address, String token) async {
    if (token.trim().isEmpty) throw const FormatException('Indiquez le code de connexion affiché sur l’ordinateur');
    if (bytes.length > 5 * 1024 * 1024) throw const FormatException('Photo trop grande : recadrez la zone');
    final client = http.Client();
    try {
      final request = http.Request('POST', serviceUri(address))
        ..followRedirects = false
        ..headers.addAll({'Content-Type': 'application/json', 'Authorization': 'Bearer ${token.trim()}'})
        ..body = jsonEncode({'image_base64': base64Encode(bytes)});
      final streamed = await client.send(request).timeout(const Duration(seconds: 90));
      final response = await http.Response.fromStream(streamed).timeout(const Duration(seconds: 15));
      Map<String, dynamic> result;
      try { result = jsonDecode(response.body) as Map<String, dynamic>; }
      catch (_) { throw const FormatException('Le service IA a renvoyé une réponse invalide'); }
      if (response.statusCode != 200) {
        throw FormatException(result['error'] is String ? result['error'] : 'Lecture IA indisponible');
      }
      return GlassAiResult.fromJson(result);
    } finally {
      client.close();
    }
  }
}
