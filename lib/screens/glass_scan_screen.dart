import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../services/glass_measurement_parser.dart';
import '../services/glass_ai_client.dart';
import 'glass_crop_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Process large photos outside the UI isolate; keep the original for review.
Uint8List prepareGlassPhoto(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  var image = img.bakeOrientation(decoded);
  if (image.width > 2600 || image.height > 2600) {
    image = img.copyResize(image, width: image.width >= image.height ? 2600 : null,
        height: image.height > image.width ? 2600 : null);
  }
  image = img.grayscale(image);
  image = img.adjustColor(image, contrast: 1.35);
  return Uint8List.fromList(img.encodeJpg(image, quality: 98));
}

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
  final _aiAddress = TextEditingController();
  final _aiToken = TextEditingController();
  bool _useAi = true;
  Uint8List? _aiPhoto;
  List<String> _aiWarnings = [];
  int? _aiRowCount;
  String? _type;
  String? _path;
  String? _error;
  bool _busy = true;
  bool _checked = false;
  List<String> _readings = [];
  int _reading = 0;
  GlassParseResult get _result => GlassMeasurementParser.parse(_text.text);

  @override
  void initState() {
    super.initState();
    _loadAiAddress();
    _recover();
  }

  Future<void> _loadAiAddress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted || _aiAddress.text.isNotEmpty) return;
      _aiAddress.text = prefs.getString('glass_ai_address') ?? '';
    } catch (_) {
      // Address can always be entered manually.
    }
  }

  Future<void> _prepareAiPhoto(XFile photo) async {
    if (!mounted) return;
    final bytes = await photo.readAsBytes();
    if (!mounted) return;
    final cropped = await Navigator.of(context).push<Uint8List>(MaterialPageRoute(
      builder: (_) => GlassCropScreen(bytes: bytes),
    ));
    if (cropped == null || !mounted) return;
    setState(() {
      _path = null;
      _aiPhoto = cropped;
      _aiWarnings = [];
      _aiRowCount = null;
      _readings = [];
      _text.clear();
      _checked = false;
      _error = null;
    });
  }

  Future<void> _readAi() async {
    if (_busy || _aiPhoto == null) return;
    setState(() { _busy = true; _error = null; _checked = false; });
    try {
      final result = await GlassAiClient.recognize(_aiPhoto!, _aiAddress.text, _aiToken.text);
      if (!mounted) return;
      setState(() {
        _text.text = result.text;
        _aiWarnings = result.warnings;
        _aiRowCount = result.rowCount;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('glass_ai_address', _aiAddress.text.trim());
    } catch (error) {
      if (mounted) setState(() => _error = error is FormatException
          ? error.message.toString()
          : 'Lecture IA impossible. Vérifiez l’adresse, le serveur de l’ordinateur et Internet.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recognize(XFile photo) async {
    if (_useAi) {
      await _prepareAiPhoto(photo);
    } else {
      await _recognizeOffline(photo);
    }
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
    _aiAddress.dispose();
    _aiToken.dispose();
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

  Future<void> _recognizeOffline(XFile photo) async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _path = photo.path;
      _text.clear();
      _error = null;
      _checked = false;
      _readings = [];
      _aiPhoto = null;
      _aiWarnings = [];
      _aiRowCount = null;
    });
    Directory? temporary;
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final original = await recognizer.processImage(InputImage.fromFilePath(photo.path));
      RecognizedText? enhanced;
      try {
      temporary = await Directory.systemTemp.createTemp('mk-glass-');
      final enhancedPath = '${temporary.path}/enhanced.jpg';
      final bytes = await compute(prepareGlassPhoto, await photo.readAsBytes());
      await File(enhancedPath).writeAsBytes(bytes);
        enhanced = await recognizer.processImage(InputImage.fromFilePath(enhancedPath));
      } catch (_) {
        // Retain the successful original reading if enhancement is unavailable.
      }
      String assemble(RecognizedText recognized) {
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
        return text;
      }
      final readings = [assemble(original)];
      if (enhanced != null && assemble(enhanced) != readings.first) {
        readings.add(assemble(enhanced));
      }
      if (!mounted) return;
      setState(() {
        _readings = readings;
        _reading = 0;
        _text.text = readings.first;
        _error = readings.every((t) => t.trim().isEmpty)
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
      if (temporary != null) {
        try { await temporary.delete(recursive: true); } catch (_) {}
      }
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
        result.invalidLines.isEmpty &&
        (_aiRowCount == null || result.measurements.length == _aiRowCount);
    return Scaffold(
      appBar: AppBar(title: const Text('Scanner les dimensions')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Mesures en cm · N1 = repère · ×2 = quantité'),
          SwitchListTile(
            title: const Text('Lecture IA du manuscrit'),
            subtitle: const Text('Internet via votre service configuré. La lecture locale reste disponible.'),
            value: _useAi,
            onChanged: _busy ? null : (value) => setState(() {
              _useAi = value; _text.clear(); _checked = false; _readings = [];
              _aiPhoto = null; _path = null; _aiWarnings = []; _aiRowCount = null; _error = null;
            }),
          ),
          if (_useAi) ...[
            const Text('La zone choisie est envoyée au service IA uniquement avec le bouton de lecture. Vérifiez chaque mesure ; une lecture IA peut se tromper.'),
            ExpansionTile(title: const Text('Connexion au scanner IA'), children: [
              TextField(controller: _aiAddress, enabled: !_busy,
                decoration: const InputDecoration(labelText: 'Adresse affichée sur l’ordinateur', hintText: '192.168.1.16:8642')),
              TextField(controller: _aiToken, enabled: !_busy, obscureText: true,
                enableSuggestions: false, autocorrect: false,
                decoration: const InputDecoration(labelText: 'Code de connexion du scanner', helperText: 'Ce code n’est pas votre clé API. Il n’est pas enregistré sur le téléphone.')),
              const Padding(padding: EdgeInsets.all(8), child: Text('Sur Windows : Synchronisation → Configurer le scanner IA, puis démarrer le serveur. Le PC doit rester allumé et connecté à Internet.')),
            ]),
          ],
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
          if (_aiPhoto != null) ...[
            SizedBox(height: 240, child: Image.memory(_aiPhoto!, fit: BoxFit.contain)),
            FilledButton.icon(onPressed: _busy ? null : _readAi,
              icon: const Icon(Icons.auto_awesome),
              label: Text(_busy ? 'Lecture IA en cours…' : 'Lire les dimensions avec l’IA')),
          ],
          if (_aiRowCount != null)
            Text('$_aiRowCount ligne(s) repérée(s) sur la photo : conservez ce nombre lors de la vérification.'),
          for (final warning in _aiWarnings)
            Padding(padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(warning, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (_aiRowCount != null && _result.measurements.length != _aiRowCount)
            const Text('Corrigez toutes les lignes, y compris celles marquées « ? », avant de les importer.'),
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
          if (_readings.length > 1)
            DropdownButtonFormField<int>(
              value: _reading,
              decoration: const InputDecoration(labelText: 'Comparer les lectures de la photo'),
              items: [for (var i = 0; i < _readings.length; i++)
                DropdownMenuItem(value: i, child: Text(
                  '${i == 0 ? "Photo originale" : "Contraste renforcé"} : ${GlassMeasurementParser.parse(_readings[i]).measurements.length} ligne(s) reconnue(s)'))],
              onChanged: _busy ? null : (i) { if (i != null) setState(() {
                _reading = i; _text.text = _readings[i]; _checked = false;
              }); },
            ),
          if (_path != null && result.measurements.isEmpty && !_busy)
            const Text('Aucune dimension exploitable. Comparez les lectures puis corrigez le texte ci-dessous. Le lecteur hors ligne ne garantit pas la reconnaissance manuscrite.'),
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
