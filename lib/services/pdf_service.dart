import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/models.dart';

/// Génération des documents PDF (devis, facture, reçu, note, calcul
/// vitres) — reproduit la mise en page de la version ordinateur
/// (modules/pdf_generator.py, ReportLab) avec le package `pdf` (le
/// téléphone n'a pas ReportLab, mais l'apparence finale est la même :
/// en-tête MK Entreprise, tableau des lignes, totaux, pied de page).
class PdfService {
  PdfService._();

  static const _entreprise = {
    'nom': 'MK ENTREPRISE',
    'activite': 'BTP - Prestation de services : Aluminium - Volet - Inox - Alu Gobonne et toute construction métallique',
    'adresse': 'Banankabougou, derrière le Lycée Ibrahim Ly — Bamako, Mali',
    'telephones': '76 28 80 88 / 79 50 03 45 / 70 73 87 78',
    'email': 'etsmetalliquekoniba@gmail.com',
    'immatriculation': '32509196793048R',
    'numFiscal': '086165538C',
    'compteBancaire': '020401488282-10 (BDM SA)',
  };

  static final _gold = PdfColor.fromHex('#B8952E');
  static final _dark = PdfColor.fromHex('#0B1220');
  static final _grey = PdfColor.fromHex('#5A6478');
  static final _lightGrid = PdfColor.fromHex('#DDDDDD');
  static final _zebra = PdfColor.fromHex('#F5F5F5');
  static final _danger = PdfColor.fromHex('#E5484D');
  static final _success = PdfColor.fromHex('#3DD68C');

  static pw.MemoryImage? _logoCache;

  static Future<pw.MemoryImage?> _logo() async {
    if (_logoCache != null) return _logoCache;
    try {
      final data = await rootBundle.load('assets/images/logo.png');
      _logoCache = pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      _logoCache = null;
    }
    return _logoCache;
  }

  static String _money(num v) {
    final rounded = v.round();
    final digits = rounded.abs().toString();
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return '${rounded < 0 ? '-' : ''}$buffer';
  }

  static String _date(String? iso) {
    if (iso == null || iso.length < 10) return '—';
    // Les dates sont stockées en ISO ("2026-09-03T12:00:00") -> "03/09/2026".
    final d = iso.substring(0, 10).split('-');
    return d.length == 3 ? '${d[2]}/${d[1]}/${d[0]}' : iso.substring(0, 10);
  }

  // ---------------------------------------------------------------------
  // Montant en toutes lettres (pour le reçu) — même algorithme que
  // number_to_french_words côté ordinateur.
  // ---------------------------------------------------------------------
  static const _unites = ['', 'un', 'deux', 'trois', 'quatre', 'cinq', 'six', 'sept', 'huit', 'neuf'];
  static const _teens = ['dix', 'onze', 'douze', 'treize', 'quatorze', 'quinze', 'seize', 'dix-sept', 'dix-huit', 'dix-neuf'];
  static const _tens = ['', '', 'vingt', 'trente', 'quarante', 'cinquante', 'soixante', 'soixante-dix', 'quatre-vingt', 'quatre-vingt-dix'];

  static String _threeDigits(int n) {
    if (n == 0) return '';
    final hundreds = n ~/ 100;
    final rest = n % 100;
    final parts = <String>[];
    if (hundreds > 0) parts.add(hundreds == 1 ? 'cent' : '${_unites[hundreds]} cent');
    if (rest > 0) {
      if (rest < 10) {
        parts.add(_unites[rest]);
      } else if (rest < 20) {
        parts.add(_teens[rest - 10]);
      } else {
        final tens = rest ~/ 10;
        final units = rest % 10;
        var word = _tens[tens];
        if (tens == 7 || tens == 9) {
          word = '${_tens[tens - 1]}-${_teens[units]}';
        } else if (units > 0) {
          word += '-${_unites[units]}';
        }
        parts.add(word);
      }
    }
    return parts.join(' ');
  }

  static String numberToFrenchWords(num amount) {
    var n = amount.round();
    if (n == 0) return 'ZÉRO';
    final millions = n ~/ 1000000;
    var reste = n % 1000000;
    final milliers = reste ~/ 1000;
    final unites = reste % 1000;
    final parts = <String>[];
    if (millions > 0) parts.add('${_threeDigits(millions)} million${millions > 1 ? 's' : ''}');
    if (milliers > 0) parts.add(milliers == 1 ? 'mille' : '${_threeDigits(milliers)} mille');
    if (unites > 0) parts.add(_threeDigits(unites));
    return parts.join(' ').toUpperCase();
  }

  // ---------------------------------------------------------------------
  // Blocs communs
  // ---------------------------------------------------------------------

  static pw.Widget _header(pw.MemoryImage? logo, String docType, String numero, String dateStr) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (logo != null) pw.Container(width: 45, height: 45, child: pw.Image(logo)),
            if (logo != null) pw.SizedBox(width: 10),
            pw.Expanded(
              flex: 3,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(_entreprise['nom']!, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: _dark)),
                  pw.SizedBox(height: 2),
                  pw.Text(_entreprise['activite']!, style: pw.TextStyle(fontSize: 7.5, color: _grey)),
                  pw.Text(_entreprise['adresse']!, style: pw.TextStyle(fontSize: 7.5, color: _grey)),
                  pw.Text('Tél : ${_entreprise['telephones']}  |  Email : ${_entreprise['email']}', style: pw.TextStyle(fontSize: 7.5, color: _grey)),
                  pw.Text(
                    "Certificat d'immatriculation : ${_entreprise['immatriculation']}  |  N° Fiscale : ${_entreprise['numFiscal']}",
                    style: pw.TextStyle(fontSize: 7.5, color: _grey),
                  ),
                ],
              ),
            ),
            pw.Expanded(
              flex: 2,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(docType, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _gold)),
                  pw.SizedBox(height: 8),
                  pw.Text('N° : $numero', style: const pw.TextStyle(fontSize: 10)),
                  pw.Text('Date : $dateStr', style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Divider(thickness: 1.2, color: _gold),
        pw.SizedBox(height: 10),
      ],
    );
  }

  static pw.Widget _clientBlock(String title, String nom, String tel, {String? extraLabel, String? extraValue, String? nif}) {
    pw.Widget row(String label, String value) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Row(
            children: [
              pw.SizedBox(width: 110, child: pw.Text(label, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _dark))),
              pw.Expanded(child: pw.Text(value, style: pw.TextStyle(fontSize: 9.5, color: _dark))),
            ],
          ),
        );
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _gold)),
        pw.SizedBox(height: 4),
        row('Nom du client :', nom.isEmpty ? '—' : nom),
        row('Téléphone :', tel.isEmpty ? '—' : tel),
        if (extraLabel != null) row(extraLabel, (extraValue == null || extraValue.isEmpty) ? '—' : extraValue),
        if (nif != null && nif.isNotEmpty) row('NIF :', nif),
        pw.SizedBox(height: 12),
      ],
    );
  }

  static pw.Widget _footerNote(String text) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 16),
        pw.Divider(thickness: 0.6, color: PdfColor.fromHex('#CCCCCC')),
        pw.SizedBox(height: 6),
        pw.Text(text, style: pw.TextStyle(fontSize: 8, color: _grey, fontStyle: pw.FontStyle.italic)),
      ],
    );
  }

  static pw.Widget _linesTable(List<LigneDocument> lignes) {
    final headers = ['Qté', 'Description', 'Prix Unit. (FCFA)', 'Total (FCFA)'];
    final data = lignes
        .map((l) => [
              l.quantite.toStringAsFixed(l.quantite == l.quantite.roundToDouble() ? 0 : 2),
              l.description,
              _money(l.prixUnitaire),
              _money(l.totalLigne),
            ])
        .toList();
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
      headerDecoration: pw.BoxDecoration(color: _dark),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellAlignments: {0: pw.Alignment.center, 1: pw.Alignment.centerLeft, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight},
      border: pw.TableBorder.all(color: _lightGrid, width: 0.5),
      oddRowDecoration: pw.BoxDecoration(color: _zebra),
      cellPadding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      columnWidths: const {0: pw.FlexColumnWidth(1), 1: pw.FlexColumnWidth(4.5), 2: pw.FlexColumnWidth(2), 3: pw.FlexColumnWidth(2)},
    );
  }

  // ---------------------------------------------------------------------
  // Documents publics
  // ---------------------------------------------------------------------

  static Future<Uint8List> devisPdf(Devis d, Client? client, List<LigneDocument> lignes) async {
    final logo = await _logo();
    final totalHt = lignes.isEmpty ? d.montantHt : lignes.fold<double>(0, (s, l) => s + l.totalLigne);
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(18 * PdfPageFormat.mm, 15 * PdfPageFormat.mm, 18 * PdfPageFormat.mm, 15 * PdfPageFormat.mm),
      build: (context) => [
        _header(logo, 'DEVIS', d.numero, _date(d.dateDevis)),
        _clientBlock('DOIT À :', client?.nom ?? '—', client?.telephone ?? '—', extraLabel: 'Adresse / Chantier :', extraValue: client?.adresse, nif: client?.nif),
        if (d.objet.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(bottom: 10), child: pw.Text('Objet : ${d.objet}', style: const pw.TextStyle(fontSize: 9.5))),
        _linesTable(lignes),
        pw.SizedBox(height: 4),
        pw.Container(
          decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _gold, width: 1))),
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Montant HT (FCFA)', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.Text(_money(totalHt), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          "Validité de l'offre : ${d.validiteJours} jours (jusqu'au ${_date(d.dateLimite)})",
          style: pw.TextStyle(fontSize: 9, color: _grey),
        ),
        _footerNote('Ce devis est valable pour la durée indiquée ci-dessus. Pour toute question, contactez-nous aux coordonnées en en-tête.'),
      ],
    ));
    return doc.save();
  }

  static Future<Uint8List> facturePdf(Facture f, Client? client, List<LigneDocument> lignes) async {
    final logo = await _logo();
    final resteImpaye = f.resteAPayer > 0;
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(18 * PdfPageFormat.mm, 15 * PdfPageFormat.mm, 18 * PdfPageFormat.mm, 15 * PdfPageFormat.mm),
      build: (context) {
        pw.Widget totalRow(String label, String value, {bool bold = false, PdfColor? color}) => pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(label, style: pw.TextStyle(fontSize: bold ? 12 : 10, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color)),
                  pw.Text(value, style: pw.TextStyle(fontSize: bold ? 12 : 10, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color)),
                ],
              ),
            );
        return [
          _header(logo, 'FACTURE', f.numero, _date(f.dateFacture)),
          _clientBlock('DOIT À :', client?.nom ?? '—', client?.telephone ?? '—', extraLabel: 'Adresse / Chantier :', extraValue: client?.adresse, nif: client?.nif),
          if (f.description.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(bottom: 10), child: pw.Text('Objet : ${f.description}', style: const pw.TextStyle(fontSize: 9.5))),
          _linesTable(lignes),
          pw.SizedBox(height: 6),
          pw.Container(
            decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _gold, width: 1))),
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Column(
              children: [
                totalRow('Montant HT', _money(f.montantHt)),
                if (f.reductionPct > 0) totalRow('Réduction (${f.reductionPct.toStringAsFixed(0)}%)', '-${_money(f.montantHt - f.montantHtNet)}'),
                totalRow('TVA (18%)', f.tva > 0 ? _money(f.tva) : 'Non applicable'),
                pw.Divider(thickness: 0.8, color: PdfColor.fromHex('#CCCCCC')),
                totalRow('Montant TTC', _money(f.montantTtc), bold: true),
                totalRow('Avance reçue', _money(f.avanceRecue)),
                totalRow('Reste à payer', _money(f.resteAPayer), bold: true, color: resteImpaye ? _danger : _success),
              ],
            ),
          ),
          pw.SizedBox(height: 6),
          if (f.modePaiement.isNotEmpty) pw.Text('Mode de paiement : ${f.modePaiement} — Statut : ${f.statut}', style: pw.TextStyle(fontSize: 9, color: _grey)),
          _footerNote('Compte Bancaire : ${_entreprise['compteBancaire']} — Merci de votre confiance.'),
        ];
      },
    ));
    return doc.save();
  }

  static Future<Uint8List> recuPdf(Recu r, Client? client) async {
    final logo = await _logo();
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(18 * PdfPageFormat.mm, 15 * PdfPageFormat.mm, 18 * PdfPageFormat.mm, 15 * PdfPageFormat.mm),
      build: (context) => [
        _header(logo, 'REÇU', r.numero, _date(r.dateRecu)),
        _clientBlock('REÇU DE :', client?.nom ?? '—', client?.telephone ?? '—', extraLabel: 'Reçu pour :', extraValue: r.motif),
        if (r.factureNumero != null) pw.Padding(padding: const pw.EdgeInsets.only(bottom: 10), child: pw.Text('N° Facture liée : ${r.factureNumero}', style: const pw.TextStyle(fontSize: 9.5))),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: pw.BoxDecoration(color: _dark),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('MONTANT REÇU', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _gold)),
              pw.Text('${_money(r.montantRecu)} FCFA', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _gold)),
            ],
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Text('Arrêté le présent reçu à la somme de : ${numberToFrenchWords(r.montantRecu)} FRANCS CFA', style: const pw.TextStyle(fontSize: 9.5)),
        pw.SizedBox(height: 6),
        pw.Text('Mode de paiement : ${r.modePaiement.isEmpty ? '—' : r.modePaiement}', style: const pw.TextStyle(fontSize: 9.5)),
        if (r.recuPar.isNotEmpty) pw.Text('Reçu par : ${r.recuPar}', style: const pw.TextStyle(fontSize: 9.5)),
        _footerNote('Ce reçu confirme la bonne réception du paiement indiqué ci-dessus. Pour toute question, contactez-nous aux numéros indiqués en en-tête.'),
      ],
    ));
    return doc.save();
  }

  static Future<Uint8List> notePdf(NoteClient n, Client? client) async {
    final logo = await _logo();
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(18 * PdfPageFormat.mm, 15 * PdfPageFormat.mm, 18 * PdfPageFormat.mm, 15 * PdfPageFormat.mm),
      build: (context) => [
        _header(logo, 'NOTE', n.numero.isEmpty ? '—' : n.numero, _date(n.dateNote)),
        _clientBlock('DESTINATAIRE :', client?.nom ?? '—', client?.telephone ?? '—'),
        if (n.objet.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(bottom: 10), child: pw.Text('Objet : ${n.objet}', style: const pw.TextStyle(fontSize: 9.5))),
        pw.Text('NOTE :', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _gold)),
        pw.SizedBox(height: 6),
        pw.Text(n.contenu, style: const pw.TextStyle(fontSize: 10, lineSpacing: 3)),
        if (n.redigePar.isNotEmpty) _footerNote('Rédigé par : ${n.redigePar}'),
      ],
    ));
    return doc.save();
  }

  static Future<Uint8List> vitresPdf(List<CommandeVitre> lignes, double totalSurface, double totalMontant) async {
    final logo = await _logo();
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(18 * PdfPageFormat.mm, 15 * PdfPageFormat.mm, 18 * PdfPageFormat.mm, 15 * PdfPageFormat.mm),
      build: (context) => [
        _header(logo, 'CALCUL VITRES', 'CV-${DateTime.now().millisecondsSinceEpoch}', _date(DateTime.now().toIso8601String())),
        pw.TableHelper.fromTextArray(
          headers: ['Type de vitre', 'Largeur (m)', 'Hauteur (m)', 'Qté', 'Surface (m²)', 'Montant (FCFA)'],
          data: lignes
              .map((l) => [l.typeVitre, l.largeur.toStringAsFixed(2), l.hauteur.toStringAsFixed(2), l.quantite.toString(), l.surface.toStringAsFixed(3), _money(l.montant)])
              .toList(),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
          headerDecoration: pw.BoxDecoration(color: _dark),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellAlignment: pw.Alignment.center,
          border: pw.TableBorder.all(color: _lightGrid, width: 0.5),
          oddRowDecoration: pw.BoxDecoration(color: _zebra),
          cellPadding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        ),
        pw.SizedBox(height: 14),
        pw.Container(
          decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _gold, width: 1))),
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Column(
            children: [
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text('Surface totale', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                pw.Text('${totalSurface.toStringAsFixed(3)} m²', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              ]),
              pw.SizedBox(height: 4),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text('Montant total', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _gold)),
                pw.Text('${_money(totalMontant)} FCFA', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _gold)),
              ]),
            ],
          ),
        ),
        _footerNote('Document généré automatiquement par MK Suite — Calcul Vitres.'),
      ],
    ));
    return doc.save();
  }

  // ---------------------------------------------------------------------
  // Aperçu / impression / partage — via le package `printing`.
  // ---------------------------------------------------------------------

  /// Ouvre l'aperçu d'impression natif du téléphone (permet aussi
  /// d'imprimer directement sur une imprimante Wi-Fi/Bluetooth).
  static Future<void> preview(Uint8List bytes, String title) =>
      Printing.layoutPdf(onLayout: (format) async => bytes, name: title);

  /// Partage le PDF (WhatsApp, email, Bluetooth...) — le principal moyen
  /// d'envoyer un devis/facture/reçu à un client sur le terrain.
  static Future<void> share(Uint8List bytes, String filename) => Printing.sharePdf(bytes: bytes, filename: filename);
}
