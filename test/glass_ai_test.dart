import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mk_suite/services/glass_ai_client.dart';
import 'package:mk_suite/services/glass_photo_processing.dart';
import 'package:mk_suite/services/glass_measurement_parser.dart';

Map<String, dynamic> fixture() => {
  'unit': 'cm', 'row_count': 7, 'warnings': <String>[],
  'rows': [
    for (final spec in [
      [121.5, 61, 4, 'N4'], [88, 48, 2, 'N2'], [87, 47.5, 2, 'N1'],
      [87, null, 2, 'N3'], [33.5, 63.5, 2, 'N5'], [24.5, 48.5, 2, 'N7'], [25, 46.5, 2, 'N6'],
    ]) {'width_cm': spec[0], 'height_cm': spec[1], 'quantity': spec[2], 'reference': spec[3],
      'uncertain': spec[1] == null, 'note': spec[1] == null ? 'Chiffre surchargé' : '', 'source_text': ''},
  ],
};

void main() {
  test('Sept lignes transcrites restent dans leur ordre, sans inventer le chiffre illisible', () {
    // This tests structured-data interpretation, not optical recognition.
    final result = GlassAiResult.fromJson(fixture());
    expect(result.rowCount, 7);
    expect(result.text.split('\n').length, 7);
    expect(result.warnings.single, contains('Ligne 4'));
    final parsed = GlassMeasurementParser.parse(result.text);
    expect(parsed.invalidLines, [4]);
    expect(parsed.measurements.map((m) => m.reference), ['N4', 'N2', 'N1', 'N5', 'N7', 'N6']);
    expect(parsed.measurements.first.widthCm, 121.5);
    expect(parsed.measurements.first.quantity, 4);
  });
  test('Les unités incohérentes et quantités fractionnaires sont refusées', () {
    final wrongUnit = fixture()..['unit'] = 'm';
    expect(() => GlassAiResult.fromJson(wrongUnit), throwsFormatException);
    final data = fixture();
    (data['rows'] as List).first['quantity'] = 2.5;
    expect(() => GlassAiResult.fromJson(data), throwsFormatException);
  });
  test('Les doublons visibles et champs manquants ne sont ni retirés ni complétés', () {
    final data = fixture();
    final rows = data['rows'] as List;
    rows.add(Map<String, dynamic>.from(rows.first));
    data['row_count'] = rows.length;
    expect(GlassAiResult.fromJson(data).rowCount, 8);
    data['row_count'] = 7;
    expect(() => GlassAiResult.fromJson(data), throwsFormatException);
  });
  test('Le code de connexion ne peut pas partir sur HTTP public ni vers une URL avec identifiants', () {
    expect(GlassAiClient.serviceUri('192.168.1.16').toString(), 'http://192.168.1.16:8642/glass/recognize');
    expect(GlassAiClient.serviceUri('https://scanner.example').scheme, 'https');
    for (final uri in ['http://example.com', 'http://8.8.8.8', 'https://user:pass@example.com', 'https://example.com?token=x']) {
      expect(() => GlassAiClient.serviceUri(uri), throwsFormatException);
    }
  });
  test('Le recadrage conserve la géométrie et rejette les zones inversées', () {
    final source = img.Image(width: 400, height: 600);
    final bytes = Uint8List.fromList(img.encodeJpg(source));
    final result = cropGlassPhoto({'bytes': bytes, 'crop': [0.25, 0.25, 0.75, 0.75]});
    final decoded = img.decodeImage(result)!;
    expect(decoded.width, 200);
    expect(decoded.height, 300);
    expect(() => cropGlassPhoto({'bytes': bytes, 'crop': [0.8, 0.0, 0.2, 1.0]}), throwsFormatException);
  });
}
