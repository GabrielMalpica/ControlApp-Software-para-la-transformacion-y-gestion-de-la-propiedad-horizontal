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
  final logoBytes = await _loadPlanEsperanzaLogoBytes();
  final logoImage = pw.MemoryImage(logoBytes);
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
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(22),
      theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
      header: (_) => _header(
        'Informe Plan Esperanza',
        subtitulo: _formatDate(informe.fechaInicio),
        detallePrincipal: informe.conjuntoNombre,
        detalleSecundario: 'NIT: ${informe.conjuntoNit}',
        logoImage: logoImage,
      ),
      build: (_) => [
        if (informe.fechaFin != null)
          pw.Text(
            'Fecha de cierre: ${_formatDate(informe.fechaFin)}',
            style: const pw.TextStyle(fontSize: 9),
          ),
        pw.SizedBox(height: 12),
        for (final ubic in informe.ubicaciones) ...[
          _sectionTitle(ubic.ubicacionNombre),
          for (final subz in ubic.subzonas) ...[
            _subTitle(subz.subzonaNombre),
            for (final area in subz.areas)
              _areaInforme(area, evidenceImageByRaw[area.urlFoto ?? '']),
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
  final logoBytes = await _loadPlanEsperanzaLogoBytes();
  final logoImage = pw.MemoryImage(logoBytes);
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
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(22),
      theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
      header: (_) => _header(
        'Historico Plan Esperanza',
        detallePrincipal: conjuntoNombre,
        detalleSecundario: '${historico.planes.length} plan(es)',
        detalleTerciario: fechasPlanes.isEmpty
            ? null
            : 'Planes mostrados: $fechasPlanes',
        logoImage: logoImage,
      ),
      build: (_) => [
        pw.SizedBox(height: 12),
        for (final ubic in historico.ubicaciones) ...[
          _sectionTitle(ubic.ubicacionNombre),
          for (final subz in ubic.subzonas) ...[
            _subTitle(subz.subzonaNombre),
            for (final area in subz.areas)
              _areaHistorico(area, evidenceImageByRaw),
          ],
        ],
      ],
    ),
  );

  return doc.save();
}

pw.Widget _header(
  String title, {
  String? subtitulo,
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
                if (subtitulo != null)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 2),
                    child: pw.Text(
                      subtitulo,
                      style: const pw.TextStyle(fontSize: 9),
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
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 2),
                    child: pw.Text(
                      detalleSecundario,
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ),
                if (detalleTerciario != null)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 2),
                    child: pw.Text(
                      detalleTerciario,
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ),
              ],
            ),
          ),
          pw.SizedBox(width: 12),
          pw.SizedBox(
            height: 58,
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
    padding: const pw.EdgeInsets.all(8),
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
    padding: const pw.EdgeInsets.only(left: 8, top: 5, bottom: 3),
    child: pw.Text(
      text,
      style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
    ),
  );
}

pw.Widget _areaInforme(AreaInforme area, pw.ImageProvider? foto) {
  return _box([
    _bold(area.elementoNombre),
    pw.SizedBox(height: 3),
    pw.Text(
      'Calificacion: ${_rating(area.valoracion)}',
      style: const pw.TextStyle(fontSize: 9),
    ),
    if ((area.observaciones ?? '').isNotEmpty)
      pw.Text(
        'Observaciones: ${area.observaciones}',
        style: const pw.TextStyle(fontSize: 9),
      ),
    if (foto != null) ...[
      pw.SizedBox(height: 6),
      _fotoPdf(foto),
    ],
  ]);
}

pw.Widget _areaHistorico(
  AreaHistorico area,
  Map<String, pw.ImageProvider?> evidenceImageByRaw,
) {
  return _box([
    _bold(area.elementoNombre),
    pw.SizedBox(height: 4),
    for (final entry in area.entradas)
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              '${_formatDate(entry.fecha)} - Calificacion: ${_rating(entry.valoracion)}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            if ((entry.observaciones ?? '').isNotEmpty)
              pw.Text(
                'Observaciones: ${entry.observaciones}',
                style: const pw.TextStyle(fontSize: 9),
              ),
            if (evidenceImageByRaw[entry.urlFoto ?? ''] != null) ...[
              pw.SizedBox(height: 6),
              _fotoPdf(evidenceImageByRaw[entry.urlFoto ?? '']!),
            ],
          ],
        ),
      ),
  ]);
}

pw.Widget _fotoPdf(pw.ImageProvider image) {
  return pw.Container(
    width: 140,
    height: 100,
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey300),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.ClipRRect(
      horizontalRadius: 6,
      verticalRadius: 6,
      child: pw.Image(image, fit: pw.BoxFit.cover),
    ),
  );
}

pw.Widget _box(List<pw.Widget> children) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(left: 16, bottom: 5),
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey300),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: children,
    ),
  );
}

pw.Widget _bold(String text) {
  return pw.Text(
    text,
    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
  );
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
    } catch (_) {
      // sigue con el siguiente candidato
    }
  }
  return null;
}

Future<Uint8List> _loadPlanEsperanzaLogoBytes() async {
  final logo = await rootBundle.load('assets/logo_cronograma.png');
  return logo.buffer.asUint8List();
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
    uniqueRaws.map((raw) async => MapEntry(raw, await _loadEvidenceImage(raw, imageCache))),
  );
  return Map<String, pw.ImageProvider?>.fromEntries(entries);
}

List<String> _pdfEvidenceUrlCandidates(String raw) {
  final driveId = extractDriveId(raw);
  if (driveId != null) {
    return <String>[
      'https://drive.google.com/thumbnail?id=$driveId&sz=w1200',
      'https://lh3.googleusercontent.com/d/$driveId=w1200',
      'https://drive.usercontent.google.com/download?id=$driveId&export=view',
    ];
  }

  final urls = evidenceUrlCandidates(raw);
  if (urls.length <= 3) return urls;
  return urls.take(3).toList();
}
