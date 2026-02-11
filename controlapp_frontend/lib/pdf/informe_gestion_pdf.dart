import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<Uint8List> buildInformeGestionPdf({
  required String conjuntoNombre,
  required DateTime desde,
  required DateTime hasta,
  required Map<String, dynamic> kpisJson,
  required Map<String, dynamic> tiposJson,
  required Uint8List chartEstadosPng,
  required Uint8List chartSeriePng,
  required Uint8List chartTiposPng,
}) async {
  final fontRegular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
  );
  final fontBold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
  );

  final df = DateFormat('dd/MM/yyyy', 'es');

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(22),
      theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
      build: (_) => [
        pw.Text(
          'INFORME DE GESTIÓN',
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'Conjunto: $conjuntoNombre',
          style: const pw.TextStyle(fontSize: 11),
        ),
        pw.Text(
          'Rango: ${df.format(desde)} - ${df.format(hasta)}',
          style: const pw.TextStyle(fontSize: 11),
        ),
        pw.SizedBox(height: 14),

        _kpiRow(kpisJson, tiposJson),

        pw.SizedBox(height: 12),
        pw.Text(
          'Distribución por estado',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Image(pw.MemoryImage(chartEstadosPng), fit: pw.BoxFit.contain),

        pw.SizedBox(height: 12),
        pw.Text(
          'Tendencia diaria (total tareas)',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Image(pw.MemoryImage(chartSeriePng), fit: pw.BoxFit.contain),

        pw.SizedBox(height: 12),
        pw.Text(
          'Preventivas vs Correctivas',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Image(pw.MemoryImage(chartTiposPng), fit: pw.BoxFit.contain),

        pw.SizedBox(height: 14),

        // Secciones tipo informe (dejas texto automático o editable)
        pw.Text(
          'Análisis',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        _boxText(
          'Resumen automático del periodo (puedes hacerlo editable o traerlo del backend).',
        ),

        pw.SizedBox(height: 10),
        pw.Text(
          'Plan de acción',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        _boxText('Acciones sugeridas según indicadores (editable).'),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _boxText(String txt) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey300),
    ),
    child: pw.Text(txt, style: const pw.TextStyle(fontSize: 10)),
  );
}

pw.Widget _kpiRow(
  Map<String, dynamic> kpisJson,
  Map<String, dynamic> tiposJson,
) {
  final kpi = (kpisJson['kpi'] as Map?) ?? {};
  final tipos = (tiposJson['data'] as Map?) ?? {};

  pw.Widget box(String t, String v) => pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            t,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            v,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    ),
  );

  return pw.Row(
    children: [
      box('Total', '${kpisJson['total'] ?? 0}'),
      pw.SizedBox(width: 8),
      box('Aprobadas', '${kpi['aprobadas'] ?? 0}'),
      pw.SizedBox(width: 8),
      box('% Cierre', '${kpi['tasaCierrePct'] ?? 0}%'),
      pw.SizedBox(width: 8),
      box(
        'Preventivas/Correctivas',
        '${tipos['preventivas'] ?? 0} / ${tipos['correctivas'] ?? 0}',
      ),
    ],
  );
}
