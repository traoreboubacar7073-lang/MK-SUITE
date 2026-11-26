import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Crop original, oriented pixels once; never enlarge or threshold handwriting.
/// [crop] is a normalized [left, top, right, bottom] rectangle.
Uint8List cropGlassPhoto(Map<String, dynamic> input) {
  final decoded = img.decodeImage(input['bytes'] as Uint8List);
  if (decoded == null) throw const FormatException('Photo illisible');
  var image = img.bakeOrientation(decoded);
  final crop = (input['crop'] as List).cast<double>();
  if (crop.length != 4 || crop.any((v) => !v.isFinite || v < 0 || v > 1) ||
      crop[2] <= crop[0] || crop[3] <= crop[1]) {
    throw const FormatException('Zone invalide');
  }
  final x = (crop[0] * image.width).floor();
  final y = (crop[1] * image.height).floor();
  final right = (crop[2] * image.width).ceil().clamp(x + 1, image.width).toInt();
  final bottom = (crop[3] * image.height).ceil().clamp(y + 1, image.height).toInt();
  image = img.copyCrop(image, x: x, y: y, width: right - x, height: bottom - y);
  if (image.width > 2200 || image.height > 2200) {
    image = img.copyResize(image, width: image.width >= image.height ? 2200 : null,
        height: image.height > image.width ? 2200 : null);
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 94));
}

Map<String, dynamic> prepareGlassPreview(Uint8List bytes) {
  final preview = cropGlassPhoto({'bytes': bytes, 'crop': [0.0, 0.0, 1.0, 1.0]});
  final decoded = img.decodeImage(preview)!;
  return {'bytes': preview, 'width': decoded.width, 'height': decoded.height};
}
