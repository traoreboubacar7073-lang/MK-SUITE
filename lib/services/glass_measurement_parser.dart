/// Units on paper are centimetres. References and quantities are independent.
class GlassMeasurement {
  final double widthCm;
  final double heightCm;
  final int quantity;
  final String reference;
  const GlassMeasurement(
    this.widthCm,
    this.heightCm,
    this.quantity,
    this.reference,
  );
  double get widthM => widthCm / 100;
  double get heightM => heightCm / 100;
  double get areaM2 => widthM * heightM * quantity;
}

class GlassParseResult {
  final List<GlassMeasurement> measurements;
  final List<int> invalidLines;
  const GlassParseResult(this.measurements, this.invalidLines);
}

class GlassMeasurementParser {
  // Strict full-line matching: N12 is never interpreted as a quantity.
  static final _pattern = RegExp(
    r'^\s*(\d+(?:[.,]\d+)?)\s*[x×*]\s*(\d+(?:[.,]\d+)?)\s*[x×*]\s*(\d+)\s*[nN]\s*[°ºoO]?\s*(\d+)\s*$',
    caseSensitive: false,
  );

  static GlassParseResult parse(String text) {
    final measurements = <GlassMeasurement>[];
    final invalid = <int>[];
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) continue;
      // Normalize separators, never guess digits or missing quantities.
      var line = lines[i].replaceAll(RegExp(r'[✕✖Хх]'), 'x')
          .replaceAll(RegExp(r'(?<=\d)\s*[,،]\s*(?=\d)'), ',')
          .replaceAll(RegExp(r'\s*(?:cm|CM)\b'), '')
          .replaceAll(RegExp(r'\s*[-–—:;]\s*(?=[nN])'), ' ')
          .trim();
      // A reference may be written before the dimensions.
      final leading = RegExp(r'^[nN]\s*[°ºoO]?\s*(\d+)\s*[:;\-–—]?\s+(.+)$').firstMatch(line);
      if (leading != null) line = '${leading[2]} N${leading[1]}';
      final match = _pattern.firstMatch(line);
      if (match == null) {
        invalid.add(i + 1);
        continue;
      }
      final width = double.tryParse(match[1]!.replaceAll(',', '.'));
      final height = double.tryParse(match[2]!.replaceAll(',', '.'));
      final quantity = int.tryParse(match[3]!);
      if (width == null ||
          height == null ||
          quantity == null ||
          !width.isFinite ||
          !height.isFinite ||
          width <= 0 ||
          height <= 0 ||
          quantity <= 0 ||
          !(width / 100 * (height / 100) * quantity).isFinite) {
        invalid.add(i + 1);
        continue;
      }
      measurements.add(
        GlassMeasurement(width, height, quantity, 'N${match[4]}'),
      );
    }
    return GlassParseResult(measurements, invalid);
  }
}
