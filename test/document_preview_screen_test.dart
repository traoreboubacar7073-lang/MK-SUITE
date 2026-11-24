import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mk_suite/screens/document_preview_screen.dart';

void main() {
  testWidgets('Une génération échouée garde la page ouverte et permet un nouvel essai', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(home: DocumentPreviewScreen(
      title: 'Devis test', filename: 'test.pdf',
      loadDocument: () async {
        attempts++;
        throw StateError('synthetic PDF generation error');
      },
    )));
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(find.text('Le PDF n’a pas pu être généré. Le devis reste enregistré.'), findsOneWidget);
    expect(find.text('Devis test'), findsOneWidget);
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Ouvrir l’aperçu ne lance pas l’impression et une erreur de rendu garde le partage accessible', (tester) async {
    const channel = MethodChannel('net.nfet.printing');
    const codec = StandardMethodCodec();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    var generated = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'printingInfo') {
        return {'canPrint': true, 'canShare': true, 'canRaster': true};
      }
      if (call.method == 'rasterPdf') {
        Future<void>(() async {
          await messenger.handlePlatformMessage(channel.name,
            codec.encodeMethodCall(MethodCall('onPageRasterEnd', {
              'job': (call.arguments as Map)['job'],
              'error': 'synthetic renderer error',
            })), (_) {});
        });
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(MaterialApp(home: DocumentPreviewScreen(
      title: 'Devis test', filename: 'test.pdf',
      loadDocument: () async {
        generated++;
        return Uint8List.fromList('%PDF-1.4'.codeUnits);
      },
    )));
    await tester.pumpAndSettle();
    expect(calls, isNot(contains('layoutPdf')));
    expect(calls, contains('rasterPdf'));
    expect(generated, 1);
    expect(find.text('Partager'), findsOneWidget);
    expect(find.textContaining('L’aperçu ne peut pas être affiché.'), findsOneWidget);
    // The printing widget reports its handled renderer error to FlutterError.
    expect(tester.takeException(), 'synthetic renderer error');
    expect(tester.takeException(), isNull);
  });
  testWidgets('Un PDF vide est signalé avant tout appel au moteur natif', (tester) async {
    await tester.pumpWidget(MaterialApp(home: DocumentPreviewScreen(
      title: 'Devis vide', filename: 'test.pdf',
      loadDocument: () async => Uint8List(0),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Réessayer'), findsOneWidget);
    expect(find.text('Imprimer'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
