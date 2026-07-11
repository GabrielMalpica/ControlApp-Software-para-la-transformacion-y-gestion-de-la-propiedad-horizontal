import 'package:flutter/services.dart';
import 'package:flutter_application_1/model/plan_esperanza_model.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<Uint8List> buildPlanEsperanzaInformePdf(InformeResponse informe) async {
  final fontRegular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
  );
  final fontBold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
  );
  final doc = pw.Document();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(22),
      theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
      header: (_) => _header(
        'Informe Plan Esperanza',
        '${informe.conjuntoNombre} - ${_formatDate(informe.fechaInicio)}',
      ),
      build: (_) => [
        _summaryRow([
          'NIT: ${informe.conjuntoNit}',
          'Estado: ${informe.completado ? "Finalizado" : "Activo"}',
          'Fin: ${_formatDate(informe.fechaFin)}',
        ]),
        pw.SizedBox(height: 12),
        for (final ubic in informe.ubicaciones) ...[
          _sectionTitle(ubic.ubicacionNombre),
          for (final subz in ubic.subzonas) ...[
            _subTitle(subz.subzonaNombre),
            for (final area in subz.areas) _areaInforme(area),
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
  final doc = pw.Document();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(22),
      theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
      header: (_) => _header(
        'Historico Plan Esperanza',
        '$conjuntoNombre - ${historico.planes.length} plan(es)',
      ),
      build: (_) => [
        _summaryRow(
          historico.planes
              .map((p) => '${_formatDate(p.fechaInicio)} (${p.totalAreas})')
              .toList(),
        ),
        pw.SizedBox(height: 12),
        for (final ubic in historico.ubicaciones) ...[
          _sectionTitle(ubic.ubicacionNombre),
          for (final subz in ubic.subzonas) ...[
            _subTitle(subz.subzonaNombre),
            for (final area in subz.areas) _areaHistorico(area),
          ],
        ],
      ],
    ),
  );

  return doc.save();
}

pw.Widget _header(String title, String subtitle) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        title,
        style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
      ),
      pw.Text(subtitle, style: const pw.TextStyle(fontSize: 10)),
      pw.SizedBox(height: 8),
      pw.Divider(),
    ],
  );
}

pw.Widget _summaryRow(List<String> items) {
  if (items.isEmpty) return pw.SizedBox.shrink();
  return pw.Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final item in items)
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Text(item, style: const pw.TextStyle(fontSize: 8)),
        ),
    ],
  );
}

pw.Widget _sectionTitle(String text) {
  return pw.Container(
    width: double.infinity,
    margin: const pw.EdgeInsets.only(top: 8, bottom: 4),
    padding: const pw.EdgeInsets.all(8),
    decoration: const pw.BoxDecoration(color: PdfColors.blue50),
    child: pw.Text(
      text,
      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
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

pw.Widget _areaInforme(AreaInforme area) {
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
    if ((area.urlFoto ?? '').isNotEmpty)
      pw.UrlLink(
        destination: area.urlFoto!,
        child: pw.Text(
          'Foto: ${area.urlFoto}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.blue),
        ),
      ),
  ]);
}

pw.Widget _areaHistorico(AreaHistorico area) {
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
            if ((entry.urlFoto ?? '').isNotEmpty)
              pw.UrlLink(
                destination: entry.urlFoto!,
                child: pw.Text(
                  'Foto: ${entry.urlFoto}',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.blue),
                ),
              ),
          ],
        ),
      ),
  ]);
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
