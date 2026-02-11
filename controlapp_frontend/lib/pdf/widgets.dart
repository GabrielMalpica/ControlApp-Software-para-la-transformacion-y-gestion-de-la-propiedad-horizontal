import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<Uint8List> buildInformeGestionPdf({
  required String conjuntoNombre,
  required String conjuntoNit,
  required DateTime desde,
  required DateTime hasta,
  required Uint8List chartSeriePng,
  required Uint8List chartEstadosPng,
  required Uint8List chartTiposPng,
  required Map<String, String>
  textos,
}) async {
  final doc = pw.Document();

  pw.Widget chartBox(String title, Uint8List png) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey600, width: .8),
      ),
      padding: const pw.EdgeInsets.all(8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain, height: 150),
        ],
      ),
    );
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(14),
      build: (ctx) => [
        // CABECERA estilo tabla
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey700),
          ),
          child: pw.Column(
            children: [
              pw.Text(
                'INFORME DE GESTIÓN DE SERVICIO',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Row(
                children: [
                  pw.Expanded(child: pw.Text('Cliente: $conjuntoNombre')),
                  pw.Expanded(child: pw.Text('NIT: $conjuntoNit')),
                ],
              ),
              pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      'Rango: ${desde.toString().substring(0, 10)} → ${hasta.toString().substring(0, 10)}',
                    ),
                  ),
                  pw.Expanded(child: pw.Text('Zona: Villavicencio')),
                ],
              ),
            ],
          ),
        ),

        pw.SizedBox(height: 10),

        // 1.1 Visitas / Serie
        pw.Text(
          '1.1 Seguimiento del servicio',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: chartBox('Tareas por día (tendencia)', chartSeriePng),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: pw.Column(
                children: [
                  _boxTexto('ANÁLISIS MES', textos['analisisMes'] ?? ''),
                  pw.SizedBox(height: 8),
                  _boxTexto('PLAN DE ACCIÓN', textos['planAccion'] ?? ''),
                ],
              ),
            ),
          ],
        ),

        pw.SizedBox(height: 10),

        // 1.2 Estados
        pw.Text(
          '1.2 Distribución por estado',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: chartBox('Estados', chartEstadosPng)),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: _boxTexto(
                'ANÁLISIS GENERAL',
                textos['analisisGeneral'] ?? '',
              ),
            ),
          ],
        ),

        pw.SizedBox(height: 10),

        // 1.3 Tipos
        pw.Text(
          '1.3 Preventivas vs Correctivas',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: chartBox('Tipos', chartTiposPng)),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: _boxTexto('CONCLUSIONES', textos['conclusiones'] ?? ''),
            ),
          ],
        ),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _boxTexto(String title, String body) {
  return pw.Container(
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey600, width: .8),
    ),
    padding: const pw.EdgeInsets.all(8),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          color: PdfColors.green700,
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: pw.Text(
            title,
            style: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
              fontSize: 9,
            ),
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          body.isEmpty ? '-' : body,
          style: const pw.TextStyle(fontSize: 9),
        ),
      ],
    ),
  );
}
