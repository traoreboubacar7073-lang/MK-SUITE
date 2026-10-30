import 'package:flutter_test/flutter_test.dart';
import 'package:mk_suite/services/glass_measurement_parser.dart';

void main() {
  test('185,5 cm correspond à 1,855 m sans arrondi intermédiaire', () {
    final r = GlassMeasurementParser.parse('185,5 x 100 x 2 N12');
    expect(r.invalidLines, isEmpty);
    expect(r.measurements.single.widthM, closeTo(1.855, 0.000000001));
    expect(r.measurements.single.areaM2, closeTo(3.71, 0.000000001));
  });
  test('Centimètres, décimales, quantité et repère indépendants', () {
    final r = GlassMeasurementParser.parse(
      '42 × 92,5 × 2 N1\n44,5 x 87.5 x 2 N4',
    );
    expect(r.invalidLines, isEmpty);
    expect(r.measurements.first.reference, 'N1');
    expect(r.measurements.first.quantity, 2);
    expect(r.measurements.first.areaM2, closeTo(0.777, 0.000001));
    expect(r.measurements.last.reference, 'N4');
  });
  test('Un repère répété ne supprime pas une ligne', () {
    final r = GlassMeasurementParser.parse('42 x 92 x 2 N3\n37 x 92 x 2 N3');
    expect(r.measurements.length, 2);
  });
  test('Aucune quantité inventée ni correction hasardeuse', () {
    final r = GlassMeasurementParser.parse(
      '42 x 92 N2\n42 x 92 x O N1\n0 x 92 x 2 N3\n42 x 92 x 2 N12',
    );
    expect(r.invalidLines, [1, 2, 3]);
    expect(r.measurements.single.quantity, 2);
    expect(r.measurements.single.reference, 'N12');
  });
}
