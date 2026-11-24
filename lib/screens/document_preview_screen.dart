import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../services/pdf_service.dart';

/// Viewing a document must not automatically launch Android's print activity.
/// Generate once per attempt and reuse the bytes for viewing, sharing and print.
class DocumentPreviewScreen extends StatefulWidget {
  final String title;
  final String filename;
  final Future<Uint8List> Function() loadDocument;

  const DocumentPreviewScreen({
    super.key,
    required this.title,
    required this.filename,
    required this.loadDocument,
  });

  @override
  State<DocumentPreviewScreen> createState() => _DocumentPreviewScreenState();
}

class _DocumentPreviewScreenState extends State<DocumentPreviewScreen> {
  late Future<Uint8List> _document;
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    _document = Future.sync(widget.loadDocument);
  }

  Future<void> _action(Uint8List bytes, {required bool print}) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      if (print) {
        await PdfService.preview(bytes, widget.title);
      } else {
        await PdfService.share(bytes, widget.filename);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        print ? 'Impossible d’ouvrir l’impression. Vous pouvez partager le PDF.'
            : 'Impossible de partager le PDF. Réessayez.',
      )));
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: FutureBuilder<Uint8List>(
      future: _document,
      builder: (context, snapshot) {
        if (snapshot.hasError || (snapshot.hasData && snapshot.data!.isEmpty)) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Le PDF n’a pas pu être généré. Le devis reste enregistré.'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => setState(() => _document = Future.sync(widget.loadDocument)),
                child: const Text('Réessayer'),
              ),
            ]),
          ));
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final bytes = snapshot.data!;
        return Column(children: [
          Expanded(child: PdfPreview(
            build: (_) async => bytes,
            initialPageFormat: PdfPageFormat.a4,
            dpi: 72,
            maxPageWidth: 600,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            useActions: false,
            allowPrinting: false,
            allowSharing: false,
            onError: (_, __) => const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('L’aperçu ne peut pas être affiché. Utilisez « Partager » pour ouvrir le PDF avec un lecteur. Le devis reste enregistré.'),
            )),
          )),
          SafeArea(top: false, child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 12, children: [
              OutlinedButton.icon(
                onPressed: _acting ? null : () => _action(bytes, print: true),
                icon: const Icon(Icons.print), label: const Text('Imprimer'),
              ),
              FilledButton.icon(
                onPressed: _acting ? null : () => _action(bytes, print: false),
                icon: const Icon(Icons.share), label: const Text('Partager'),
              ),
            ]),
          )),
        ]);
      },
    ),
  );
}
