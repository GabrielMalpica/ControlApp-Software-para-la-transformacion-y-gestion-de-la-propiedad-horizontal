import 'package:flutter/services.dart';
import 'package:flutter_application_1/model/plan_esperanza_model.dart';
import 'package:flutter_application_1/utils/evidence_utils.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

Future<Uint8List> buildPlanEsperanzaInformePdf(InformeResponse informe) async {
  final fontRegular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
  );
  final fontBold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
  );
  final logoImage = pw.MemoryImage(await _loadPlanEsperanzaLogoBytes());
  final evidenceImageByRaw = await _preloadEvidenceImages(
    informe.ubicaciones
        .expand((u) => u.subzonas)
        .expand((s) => s.areas)
        .map((a) => a.urlFoto)
        .whereType<String>(),
  );

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(20),
      theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
      header: (_) => _header(
        title: 'Informe Plan Esperanza',
        detallePrincipal: informe.conjuntoNombre,
        detalleSecundario: 'NIT: ${informe.conjuntoNit}',
        detalleTerciario:
            'Fecha del plan: ${_formatDate(informe.fechaInicio)}${informe.fechaFin != null ? '  |  Cierre: ${_formatDate(informe.fechaFin)}' : ''}',
        logoImage: logoImage,
      ),
      build: (_) => [
        for (final ubic in informe.ubicaciones) ...[
          _sectionTitle(ubic.ubicacionNombre),
          for (final subz in ubic.subzonas) ...[
            _subTitle(subz.subzonaNombre),
            _buildInformeTable(subz.areas, evidenceImageByRaw),
            pw.SizedBox(height: 8),
          ],
        ],
      ],
    ),
  );
  return doc.save();
}

Future<Uint8List> buildPlanEsperanzaHistoricoPdf(
  HistoricoResponse historico, {
  required String conjuntoNombre,
}) async {
  final fontRegular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
  );
  final fontBold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
  );
  final logoImage = pw.MemoryImage(await _loadPlanEsperanzaLogoBytes());
  final evidenceImageByRaw = await _preloadEvidenceImages(
    historico.ubicaciones
        .expand((u) => u.subzonas)
        .expand((s) => s.areas)
        .expand((a) => a.entradas)
        .map((e) => e.urlFoto)
        .whereType<String>(),
  );
  final fechasPlanes = historico.planes
      .map((p) => _formatDate(p.fechaInicio))
      .join(', ');

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(20),
      theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
      header: (_) => _header(
        title: 'Historico Plan Esperanza',
        detallePrincipal: conjuntoNombre,
        detalleSecundario: '${historico.planes.length} plan(es)',
        detalleTerciario: fechasPlanes.isEmpty
            ? null
            : 'Planes mostrados: $fechasPlanes',
        logoImage: logoImage,
      ),
      build: (_) => [
        for (final ubic in historico.ubicaciones) ...[
          _sectionTitle(ubic.ubicacionNombre),
          for (final subz in ubic.subzonas) ...[
            _subTitle(subz.subzonaNombre),
            for (final area in subz.areas) ...[
              _areaLabel(area.elementoNombre),
              _buildHistoricoTable(area.entradas, evidenceImageByRaw),
              pw.SizedBox(height: 8),
            ],
          ],
        ],
      ],
    ),
  );
  return doc.save();
}

pw.Widget _header({
  required String title,
  required String detallePrincipal,
  String? detalleSecundario,
  String? detalleTerciario,
  required pw.MemoryImage logoImage,
}) {
  return pw.Column(
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  detallePrincipal,
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (detalleSecundario != null)
                  pw.Text(
                    detalleSecundario,
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                if (detalleTerciario != null)
                  pw.Text(
                    detalleTerciario,
                    style: const pw.TextStyle(fontSize: 9),
                  ),
              ],
            ),
          ),
          pw.SizedBox(width: 12),
          pw.SizedBox(
            height: 64,
            child: pw.Image(logoImage, fit: pw.BoxFit.contain),
          ),
        ],
      ),
      pw.SizedBox(height: 8),
      pw.Divider(),
    ],
  );
}

pw.Widget _sectionTitle(String text) {
  return pw.Container(
    width: double.infinity,
    margin: const pw.EdgeInsets.only(top: 8, bottom: 4),
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: pw.BoxDecoration(
      color: PdfColor.fromHex('#E6F4EC'),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 11,
        fontWeight: pw.FontWeight.bold,
        color: PdfColor.fromHex('#0C6B43'),
      ),
    ),
  );
}

pw.Widget _subTitle(String text) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(left: 2, top: 6, bottom: 4),
    child: pw.Text(
      text,
      style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
    ),
  );
}

pw.Widget _areaLabel(String text) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(left: 2, top: 4, bottom: 4),
    child: pw.Text(
      text,
      style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
    ),
  );
}

pw.Widget _buildInformeTable(
  List<AreaInforme> areas,
  Map<String, pw.ImageProvider?> evidenceImageByRaw,
) {
  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.6),
    columnWidths: const {
      0: pw.FlexColumnWidth(2.1),
      1: pw.FlexColumnWidth(0.8),
      2: pw.FlexColumnWidth(2.2),
      3: pw.FlexColumnWidth(2.2),
      4: pw.FlexColumnWidth(1.4),
    },
    children: [
      _tableHeader(['Area', 'Calif.', 'Observaciones', 'Checklist', 'Foto']),
      for (final area in areas)
        pw.TableRow(
          verticalAlignment: pw.TableCellVerticalAlignment.middle,
          children: [
            _tableCell(area.elementoNombre),
            _tableCell(_rating(area.valoracion), align: pw.TextAlign.center),
            _tableCell(_safeText(area.observaciones)),
            _tableCell(_checklistText(area.checklist)),
            _imageCell(evidenceImageByRaw[area.urlFoto ?? '']),
          ],
        ),
    ],
  );
}

pw.Widget _buildHistoricoTable(
  List<TimelineEntry> entradas,
  Map<String, pw.ImageProvider?> evidenceImageByRaw,
) {
  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.6),
    columnWidths: const {
      0: pw.FlexColumnWidth(1.1),
      1: pw.FlexColumnWidth(0.8),
      2: pw.FlexColumnWidth(2.1),
      3: pw.FlexColumnWidth(2.1),
      4: pw.FlexColumnWidth(1.4),
    },
    children: [
      _tableHeader(['Fecha', 'Calif.', 'Observaciones', 'Checklist', 'Foto']),
      for (final entry in entradas)
        pw.TableRow(
          verticalAlignment: pw.TableCellVerticalAlignment.middle,
          children: [
            _tableCell(_formatDate(entry.fecha)),
            _tableCell(_rating(entry.valoracion), align: pw.TextAlign.center),
            _tableCell(_safeText(entry.observaciones)),
            _tableCell(_checklistText(entry.checklist)),
            _imageCell(evidenceImageByRaw[entry.urlFoto ?? '']),
          ],
        ),
    ],
  );
}

pw.TableRow _tableHeader(List<String> values) {
  return pw.TableRow(
    decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F2F6F4')),
    children: values
        .map(
          (value) => pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text(
              value,
              style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.center,
            ),
          ),
        )
        .toList(),
  );
}

pw.Widget _tableCell(String value, {pw.TextAlign align = pw.TextAlign.left}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(6),
    child: pw.Text(value.isEmpty ? '-' : value, style: const pw.TextStyle(fontSize: 8), textAlign: align),
  );
}

pw.Widget _imageCell(pw.ImageProvider? image) {
  if (image == null) return _tableCell('- ', align: pw.TextAlign.center);
  return pw.Padding(
    padding: const pw.EdgeInsets.all(4),
    child: pw.Center(
      child: pw.Container(
        width: 86,
        height: 58,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.ClipRRect(
          horizontalRadius: 4,
          verticalRadius: 4,
          child: pw.Image(image, fit: pw.BoxFit.cover),
        ),
      ),
    ),
  );
}

String _checklistText(List<ChecklistItem> items) {
  if (items.isEmpty) return '-';
  return items
      .map((item) => '${item.completado ? '[x]' : '[ ]'} ${item.texto}')
      .join('\n');
}

String _safeText(String? value) {
  final text = value?.trim() ?? '';
  return text.isEmpty ? '-' : text;
}

String _rating(double? value) {
  if (value == null) return '-';
  return '${value.toStringAsFixed(0)}/5';
}

String _formatDate(DateTime? dt) {
  if (dt == null) return '-';
  return '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}';
}

Future<Map<String, pw.ImageProvider?>> _preloadEvidenceImages(
  Iterable<String> raws,
) async {
  final uniqueRaws = raws
      .map((raw) => raw.trim())
      .where((raw) => raw.isNotEmpty)
      .toSet()
      .toList();
  final imageCache = <String, pw.ImageProvider>{};
  final entries = await Future.wait(
    uniqueRaws.map(
      (raw) async => MapEntry(raw, await _loadEvidenceImage(raw, imageCache)),
    ),
  );
  return Map<String, pw.ImageProvider?>.fromEntries(entries);
}

Future<pw.ImageProvider?> _loadEvidenceImage(
  String raw,
  Map<String, pw.ImageProvider> imageCache,
) async {
  for (final url in _pdfEvidenceUrlCandidates(raw)) {
    if (imageCache.containsKey(url)) return imageCache[url];
    try {
      final image = await networkImage(url);
      imageCache[url] = image;
      return image;
    } catch (_) {}
  }
  return null;
}

List<String> _pdfEvidenceUrlCandidates(String raw) {
  final driveId = extractDriveId(raw);
  if (driveId != null) {
    return <String>[
      'https://drive.google.com/thumbnail?id=$driveId&sz=w1000',
      'https://lh3.googleusercontent.com/d/$driveId=w1000',
      'https://drive.usercontent.google.com/download?id=$driveId&export=view',
    ];
  }
  final urls = evidenceUrlCandidates(raw);
  return urls.length <= 3 ? urls : urls.take(3).toList();
}

Future<Uint8List> _loadPlanEsperanzaLogoBytes() async {
  final logo = await rootBundle.load('assets/logo_cronograma.png');
  return logo.buffer.asUint8List();
}
