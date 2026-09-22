import 'package:flutter/services.dart';
import 'package:flutter_application_1/model/inventario_activo_model.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Acta de entrega y recepción del inventario de maquinaria y herramientas
/// que un conjunto tiene bajo su propiedad. Sirve como respaldo de auditoría:
/// deja constancia de lo que el conjunto entrega al iniciar el contrato (y de
/// lo que se devuelve al finalizarlo), firmada por el administrador del
/// conjunto y el gerente.
Future<Uint8List> buildActaInventarioPdf({
  required String empresaNit,
  required String conjuntoNombre,
  required String conjuntoNit,
  String? administradorNombre,
  required List<ActivoInventario> maquinaria,
  required List<ActivoInventario> herramientas,
  DateTime? fecha,
}) async {
  final fontRegular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
  );
  final fontBold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
  );
  final logoImage = pw.MemoryImage(
    (await rootBundle.load('assets/logo_cronograma.png')).buffer.asUint8List(),
  );

  final fechaActa = fecha ?? DateTime.now();
  final df = DateFormat('dd/MM/yyyy', 'es');
  final administrador = administradorNombre?.trim();

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
      build: (_) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'ACTA DE ENTREGA Y RECEPCIÓN DE INVENTARIO',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    'Maquinaria y herramientas administradas en el conjunto',
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 12),
            pw.SizedBox(
              height: 50,
              child: pw.Image(logoImage, fit: pw.BoxFit.contain),
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Divider(color: PdfColors.grey400),
        pw.SizedBox(height: 6),
        _infoRow('Conjunto', conjuntoNombre),
        _infoRow('NIT del conjunto', conjuntoNit),
        _infoRow(
          'Administrador del conjunto',
          (administrador?.isNotEmpty ?? false)
              ? administrador!
              : 'Por registrar',
        ),
        _infoRow('Fecha del acta', df.format(fechaActa)),
        pw.SizedBox(height: 12),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromHex('#F2F6F4'),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Text(
            'Por medio de la presente acta se deja constancia del inventario de maquinaria y '
            'herramientas que el conjunto $conjuntoNombre (NIT $conjuntoNit) tiene bajo su propiedad '
            'y entrega para su administración en las operaciones diarias del contrato de servicios '
            'vigente con la empresa identificada con NIT $empresaNit. El listado a continuación '
            'corresponde a la totalidad de los equipos aprobados y existentes a la fecha de firma de '
            'este documento; servirá como soporte de la entrega inicial y como referencia para el '
            'proceso de devolución al finalizar el contrato. Cualquier maquinaria o herramienta que no '
            'se encuentre relacionada en esta acta no hará parte de las obligaciones de custodia, '
            'mantenimiento o reposición a cargo de la empresa.',
            style: const pw.TextStyle(fontSize: 9.5, lineSpacing: 1.4),
          ),
        ),
        pw.SizedBox(height: 16),
        _sectionTitle('1. Maquinaria (${maquinaria.length} unidad(es))'),
        pw.SizedBox(height: 6),
        maquinaria.isEmpty
            ? _emptyNote(
                'El conjunto no registra maquinaria propia al momento de generar esta acta.',
              )
            : _assetTable(maquinaria, isTool: false),
        pw.SizedBox(height: 16),
        _sectionTitle('2. Herramientas (${herramientas.length} unidad(es))'),
        pw.SizedBox(height: 6),
        herramientas.isEmpty
            ? _emptyNote(
                'El conjunto no registra herramientas propias al momento de generar esta acta.',
              )
            : _assetTable(herramientas, isTool: true),
        pw.SizedBox(height: 28),
        pw.Text(
          'Las partes que firman a continuación certifican haber verificado físicamente el inventario '
          'relacionado y estar de acuerdo con su contenido.',
          style: const pw.TextStyle(fontSize: 9.5),
        ),
        pw.SizedBox(height: 26),
        _signatureBlock(administrador),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _infoRow(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 2),
    child: pw.Row(
      children: [
        pw.SizedBox(
          width: 150,
          child: pw.Text(
            label,
            style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Expanded(
          child: pw.Text(value, style: const pw.TextStyle(fontSize: 9.5)),
        ),
      ],
    ),
  );
}

pw.Widget _sectionTitle(String text) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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

pw.Widget _emptyNote(String text) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey300),
    ),
    child: pw.Text(
      text,
      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
    ),
  );
}

pw.Widget _assetTable(List<ActivoInventario> items, {required bool isTool}) {
  final headers = isTool
      ? const [
          'Código',
          'Tipo',
          'Alias',
          'Marca / Modelo',
          'Serial',
          'Estado',
          'Condición',
        ]
      : const [
          'Código',
          'Tipo',
          'Marca / Modelo',
          'Serial',
          'Estado',
          'Condición',
        ];
  final columnWidths = isTool
      ? const <int, pw.TableColumnWidth>{
          0: pw.FlexColumnWidth(1.3),
          1: pw.FlexColumnWidth(1.6),
          2: pw.FlexColumnWidth(1.2),
          3: pw.FlexColumnWidth(1.6),
          4: pw.FlexColumnWidth(1.2),
          5: pw.FlexColumnWidth(1.1),
          6: pw.FlexColumnWidth(1.1),
        }
      : const <int, pw.TableColumnWidth>{
          0: pw.FlexColumnWidth(1.3),
          1: pw.FlexColumnWidth(1.9),
          2: pw.FlexColumnWidth(1.9),
          3: pw.FlexColumnWidth(1.3),
          4: pw.FlexColumnWidth(1.1),
          5: pw.FlexColumnWidth(1.1),
        };

  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.6),
    columnWidths: columnWidths,
    children: [
      _tableHeader(headers),
      for (final item in items)
        pw.TableRow(
          verticalAlignment: pw.TableCellVerticalAlignment.middle,
          children: [
            _cell(item.codigoInterno),
            _cell(item.nombreCatalogo),
            if (isTool) _cell(_safe(item.alias)),
            _cell(_marcaModelo(item)),
            _cell(_safe(item.serial)),
            _cell(_label(item.estado)),
            _cell(_label(item.condicion ?? '')),
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
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
        )
        .toList(),
  );
}

pw.Widget _cell(String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(6),
    child: pw.Text(
      value.isEmpty ? '-' : value,
      style: const pw.TextStyle(fontSize: 8),
    ),
  );
}

pw.Widget _signatureBlock(String? administradorNombre) {
  pw.Widget columna(String rol, String? nombrePrellenado) {
    final tieneNombre = (nombrePrellenado?.trim().isNotEmpty ?? false);
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 30),
          pw.Text(
            'Firma: ________________________________',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Nombre: ${tieneNombre ? nombrePrellenado!.trim() : '________________________________'}',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'C.C.: ________________________________',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            rol,
            style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      columna('Administrador del conjunto', administradorNombre),
      pw.SizedBox(width: 24),
      columna('Gerente', null),
    ],
  );
}

String _marcaModelo(ActivoInventario item) {
  final parts = [
    item.marca,
    item.modelo,
  ].map((value) => value?.trim() ?? '').where((value) => value.isNotEmpty);
  return parts.join(' / ');
}

String _safe(String? value) {
  final text = value?.trim() ?? '';
  return text;
}

String _label(String value) {
  if (value.trim().isEmpty) return '';
  return value
      .toLowerCase()
      .split('_')
      .map(
        (word) =>
            word.isEmpty ? word : word[0].toUpperCase() + word.substring(1),
      )
      .join(' ');
}
