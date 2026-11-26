import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/glass_photo_processing.dart';

class GlassCropScreen extends StatefulWidget {
  final Uint8List bytes;
  const GlassCropScreen({super.key, required this.bytes});
  @override
  State<GlassCropScreen> createState() => _GlassCropScreenState();
}

class _GlassCropScreenState extends State<GlassCropScreen> {
  Rect _crop = const Rect.fromLTRB(0, 0, 1, 1);
  Offset? _start;
  bool _busy = false;
  late final Future<Map<String, dynamic>> _oriented;

  @override
  void initState() {
    super.initState();
    _oriented = compute(prepareGlassPreview, widget.bytes);
  }

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await compute(cropGlassPhoto, {
        'bytes': widget.bytes,
        'crop': [_crop.left, _crop.top, _crop.right, _crop.bottom],
      });
      if (mounted) Navigator.pop(context, bytes);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de préparer cette zone. Choisissez une autre photo.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cadrer les dimensions')),
    body: FutureBuilder<Map<String, dynamic>>(future: _oriented, builder: (context, snapshot) {
      if (snapshot.hasError) return const Center(child: Text('Photo illisible. Revenez choisir une autre image.'));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final data = snapshot.data!;
      final bytes = data['bytes'] as Uint8List;
      return Column(children: [
        const Padding(padding: EdgeInsets.all(12), child: Text(
          'Tracez un rectangle autour de TOUTES les lignes, avec les quantités et les repères N. Évitez le clavier et les grandes zones vides.')),
        Expanded(child: LayoutBuilder(builder: (context, constraints) {
          final size = Size((data['width'] as int).toDouble(), (data['height'] as int).toDouble());
          final fitted = applyBoxFit(BoxFit.contain, size, constraints.biggest).destination;
          final imageRect = Alignment.center.inscribe(fitted, Offset.zero & constraints.biggest);
          Offset normalized(Offset point) => Offset(
            ((point.dx - imageRect.left) / imageRect.width).clamp(0.0, 1.0).toDouble(),
            ((point.dy - imageRect.top) / imageRect.height).clamp(0.0, 1.0).toDouble());
          return GestureDetector(
            onPanStart: _busy ? null : (details) {
              _start = normalized(details.localPosition);
            },
            onPanUpdate: _busy ? null : (details) {
              if (_start == null) return;
              final end = normalized(details.localPosition);
              setState(() => _crop = Rect.fromPoints(_start!, end));
            },
            child: Stack(fit: StackFit.expand, children: [
              Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
              IgnorePointer(child: CustomPaint(painter: _CropPainter(imageRect, _crop))),
            ]),
          );
        })),
        SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(12), child: Wrap(
          spacing: 12, children: [
            OutlinedButton(onPressed: _busy ? null : () => setState(() => _crop = const Rect.fromLTRB(0, 0, 1, 1)),
                child: const Text('Toute la photo')),
            FilledButton(onPressed: _busy || _crop.width < .02 || _crop.height < .02
                ? null : _confirm,
                child: Text(_busy ? 'Préparation…' : 'Utiliser cette zone')),
          ],
        ))),
      ]);
    }),
  );
}

class _CropPainter extends CustomPainter {
  final Rect imageRect;
  final Rect normalized;
  _CropPainter(this.imageRect, this.normalized);
  @override
  void paint(Canvas canvas, Size size) {
    final selection = Rect.fromLTRB(
      imageRect.left + normalized.left * imageRect.width,
      imageRect.top + normalized.top * imageRect.height,
      imageRect.left + normalized.right * imageRect.width,
      imageRect.top + normalized.bottom * imageRect.height);
    final shade = Path()..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)..addRect(selection);
    canvas.drawPath(shade, Paint()..color = Colors.black54);
    canvas.drawRect(selection, Paint()..color = Colors.amber..strokeWidth = 3..style = PaintingStyle.stroke);
  }
  @override
  bool shouldRepaint(covariant _CropPainter old) => old.normalized != normalized || old.imageRect != imageRect;
}
