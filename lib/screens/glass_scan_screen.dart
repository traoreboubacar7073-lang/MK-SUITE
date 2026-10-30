import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../services/glass_measurement_parser.dart';

class GlassScanImport {
  final String glassType;
  final List<GlassMeasurement> measurements;
  const GlassScanImport(this.glassType, this.measurements);
}

class GlassScanScreen extends StatefulWidget {
  final List<String> glassTypes;
  const GlassScanScreen({super.key, required this.glassTypes});
  @override
  State<GlassScanScreen> createState() => _GlassScanScreenState();
}

class _GlassScanScreenState extends State<GlassScanScreen> {
  final _text = TextEditingController();
  final _picker = ImagePicker();
  String? _type;
  String? _path;
  String? _error;
  bool _busy = true;
  bool _checked = false;
  GlassParseResult get _result => GlassMeasurementParser.parse(_text.text);

  @override
  void initState() {
    super.initState();
    _recover();
  }

  Future<void> _recover() async {
    try {
      final lost = await _picker.retrieveLostData();
      if (!mounted) return;
      if (lost.files?.isNotEmpty == true) {
        await _recognize(lost.files!.first);
      } else if (lost.exception != null) {
        setState(
          () => _error =
              'La photo précédente n’a pas pu être récupérée. Reprenez-la.',
        );
      }
    } catch (_) {
      // A fresh capture and manual entry remain available.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final photo = await _picker.pickImage(
        source: source,
        imageQuality: 95,
        maxWidth: 3000,
      );
      if (photo != null && mounted) await _recognize(photo);
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'Impossible d’ouvrir la photo. Vérifiez l’accès à l’appareil photo ou choisissez une image.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recognize(XFile photo) async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _path = photo.path;
      _text.clear();
      _error = null;
      _checked = false;
    });
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognized = await recognizer.processImage(
        InputImage.fromFilePath(photo.path),
      );
      // ML Kit may return the reference column in a separate block. Reassemble
      // fragments by vertical position, then left-to-right. Review is required.
      final lines = recognized.blocks.expand((b) => b.lines).toList()
        ..sort(
          (a, b) => a.boundingBox.center.dy.compareTo(b.boundingBox.center.dy),
        );
      final rows = <List<TextLine>>[];
      for (final line in lines) {
        if (rows.isNotEmpty &&
            (rows.last.first.boundingBox.center.dy - line.boundingBox.center.dy)
                    .abs() <=
                rows.last.first.boundingBox.height * 0.55) {
          rows.last.add(line);
        } else {
          rows.add([line]);
        }
      }
      final text = rows
          .map((row) {
            row.sort(
              (a, b) => a.boundingBox.left.compareTo(b.boundingBox.left),
            );
            return row.map((l) => l.text).join(' ');
          })
          .join('\n');
      if (!mounted) return;
      setState(() {
        _text.text = text;
        _error = text.trim().isEmpty
            ? 'Aucun texte détecté. Reprenez une photo nette ou saisissez les mesures.'
            : null;
      });
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'Lecture impossible. Reprenez la photo ou saisissez les mesures ci-dessous.',
        );
    } finally {
      await recognizer.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final canImport =
        !_busy &&
        _checked &&
        _type != null &&
        result.measurements.isNotEmpty &&
        result.invalidLines.isEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Scanner les dimensions')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Mesures en cm · N1 = repère · ×2 = quantité'),
          const SizedBox(height: 8),
          const Text(
            'Photographiez la feuille de face, bien éclairée. La lecture manuscrite peut se tromper ou oublier des lignes : comparez toujours avec la photo.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _pick(ImageSource.camera),
                icon: const Icon(Icons.camera_alt),
                label: const Text('Photographier'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text('Galerie'),
              ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_path != null)
            SizedBox(
              height: 260,
              child: InteractiveViewer(
                maxScale: 6,
                child: Image.file(File(_path!), fit: BoxFit.contain),
              ),
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _type,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Type pour toutes les vitres de cette feuille',
            ),
            items: widget.glassTypes
                .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                .toList(),
            onChanged: _busy ? null : (value) => setState(() => _type = value),
          ),
          if (widget.glassTypes.isEmpty)
            const Text(
              'Ajoutez d’abord un type et son tarif dans le calculateur.',
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            enabled: !_busy,
            minLines: 5,
            maxLines: 16,
            decoration: const InputDecoration(
              labelText: 'Texte reconnu — modifiable',
              helperText: 'Une vitre par ligne : 42 × 92,5 × 2 N1',
            ),
            onChanged: (_) => setState(() => _checked = false),
          ),
          if (result.invalidLines.isNotEmpty)
            Text(
              'Lignes à corriger ou retirer : ${result.invalidLines.join(", ")}. Format : largeur × hauteur × quantité N1.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 16),
          Text(
            '${result.measurements.length} ligne(s) · ${result.measurements.fold<int>(0, (s, m) => s + m.quantity)} pièce(s)',
          ),
          for (final m in result.measurements)
            ListTile(
              dense: true,
              title: Text(
                '${m.reference} : ${m.widthCm} × ${m.heightCm} cm — ${m.quantity} pièce(s)',
              ),
              subtitle: Text('${m.areaM2.toStringAsFixed(4)} m²'),
            ),
          CheckboxListTile(
            value: _checked,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'J’ai comparé chaque mesure, repère et quantité avec la feuille, y compris le nombre de lignes.',
            ),
            onChanged: _busy
                ? null
                : (v) => setState(() => _checked = v ?? false),
          ),
          FilledButton(
            onPressed: canImport
                ? () => Navigator.pop(
                    context,
                    GlassScanImport(_type!, result.measurements),
                  )
                : null,
            child: const Text('Ajouter au calcul'),
          ),
          const Text(
            'Les lignes sont ajoutées au brouillon. Enregistrez-les ensuite depuis le calculateur.',
          ),
        ],
      ),
    );
  }
}
