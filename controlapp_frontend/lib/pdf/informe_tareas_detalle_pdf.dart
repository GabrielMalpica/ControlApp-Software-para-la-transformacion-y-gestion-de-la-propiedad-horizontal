import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<Uint8List> buildInformeTareasDetallePdf({
  required String conjuntoNombre,
  required DateTime desde,
  required DateTime hasta,
  required List<Map<String, dynamic>>
  tareas, // dataset mensual-detalle ya en map
}) async {
  final fontRegular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
  );
  final fontBold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
  );
  final df = DateFormat('dd/MM/yyyy', 'es');
  final dfh = DateFormat('dd/MM HH:mm', 'es');

  final doc = pw.Document();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(18),
      theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
      header: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'INFORME DETALLADO DE TAREAS',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            'Conjunto: $conjuntoNombre • Rango: ${df.format(desde)} - ${df.format(hasta)}',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.SizedBox(height: 8),
          pw.Divider(),
        ],
      ),
      build: (_) {
        return tareas.map((t) {
          final tipo = (t['tipo'] ?? '').toString();
          final id = t['id']?.toString() ?? '';
          final desc = (t['descripcion'] ?? '').toString();
          final estado = (t['estado'] ?? '').toString();

          final fi = DateTime.tryParse(t['fechaInicio'].toString());
          final ff = DateTime.tryParse(t['fechaFin'].toString());

          final operarios = (t['operarios'] as List? ?? [])
              .map((e) => e.toString())
              .toList();
          final evidencias = (t['evidencias'] as List? ?? [])
              .map((e) => e.toString())
              .toList();

          final insumos = (t['insumos'] as List? ?? []);
          final maq = (t['maquinaria'] as List? ?? []);
          final herr = (t['herramientas'] as List? ?? []);

          String lineList(List list, String field) {
            if (list.isEmpty) return '—';
            final items = list.take(6).map((e) {
              final m = (e as Map);
              final n = (m['nombre'] ?? '').toString();
              final c = m[field];
              return c == null ? n : '$n (${c.toString()})';
            }).toList();
            return items.join(', ');
          }

          final evidShort = evidencias.take(3).toList();

          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 10),
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        '$tipo • ID $id • $estado',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Text(desc, style: const pw.TextStyle(fontSize: 10)),
                pw.SizedBox(height: 6),

                pw.Text(
                  'Fecha: ${fi != null ? dfh.format(fi) : "-"} → ${ff != null ? dfh.format(ff) : "-"}',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey700,
                  ),
                ),

                pw.SizedBox(height: 6),
                pw.Text(
                  'Operarios: ${operarios.isEmpty ? "—" : operarios.join(", ")}',
                  style: const pw.TextStyle(fontSize: 9),
                ),

                pw.SizedBox(height: 4),
                pw.Text(
                  'Insumos: ${lineList(insumos, "cantidad")}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Maquinaria: ${lineList(maq, "cantidad")}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Herramientas: ${lineList(herr, "cantidad")}',
                  style: const pw.TextStyle(fontSize: 9),
                ),

                pw.SizedBox(height: 6),
                pw.Text(
                  'Evidencias (links):',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: evidShort.isEmpty
                      ? [pw.Text('—', style: const pw.TextStyle(fontSize: 9))]
                      : evidShort
                            .map(
                              (u) => pw.UrlLink(
                                destination: u,
                                child: pw.Text(
                                  u,
                                  style: const pw.TextStyle(
                                    fontSize: 8,
                                    color: PdfColors.blue,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                ),
              ],
            ),
          );
        }).toList();
      },
    ),
  );

  return doc.save();
}
