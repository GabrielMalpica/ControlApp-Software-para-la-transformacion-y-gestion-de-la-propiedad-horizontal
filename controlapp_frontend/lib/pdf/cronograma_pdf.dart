import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'pdf_download.dart';

class _TareaLite {
  final String descripcion;
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final String? ubicacionNombre;
  final String? elementoNombre;

  _TareaLite({
    required this.descripcion,
    required this.fechaInicio,
    required this.fechaFin,
    this.ubicacionNombre,
    this.elementoNombre,
  });

  factory _TareaLite.fromJson(Map<String, dynamic> json) {
    final fi = DateTime.parse(json['fechaInicio'].toString()).toLocal();
    final ff = DateTime.parse(json['fechaFin'].toString()).toLocal();

    String? ubic;
    String? elem;

    if (json['ubicacionNombre'] != null) {
      ubic = json['ubicacionNombre']?.toString();
    } else if (json['ubicacion'] is Map) {
      ubic = (json['ubicacion'] as Map)['nombre']?.toString();
    }

    if (json['elementoNombre'] != null) {
      elem = json['elementoNombre']?.toString();
    } else if (json['elemento'] is Map) {
      elem = (json['elemento'] as Map)['nombre']?.toString();
    }

    return _TareaLite(
      descripcion: (json['descripcion'] ?? '').toString(),
      fechaInicio: fi,
      fechaFin: ff,
      ubicacionNombre: ubic,
      elementoNombre: elem,
    );
  }
}

Future<void> imprimirCronogramaOperario(Map<String, dynamic> data) async {
  final fontRegular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
  );
  final fontBold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
  );

  final doc = pw.Document();

  final operario = (data['operarioNombre'] ?? data['operarioId'] ?? '')
      .toString();
  final conjunto = (data['conjuntoNombre'] ?? data['conjuntoId'] ?? '')
      .toString();

  final anio = (data['anio'] is int)
      ? data['anio'] as int
      : int.tryParse('${data['anio']}') ?? DateTime.now().year;

  final mes = (data['mes'] is int)
      ? data['mes'] as int
      : int.tryParse('${data['mes']}') ?? DateTime.now().month;

  final semanaDelMes = (data['semanaDelMes'] is int)
      ? data['semanaDelMes'] as int
      : int.tryParse('${data['semanaDelMes']}') ?? 1;

  final weekStart =
      _parseYmd((data['weekStart'] ?? '').toString()) ?? DateTime(anio, mes, 1);
  final weekEnd =
      _parseYmd((data['weekEnd'] ?? '').toString()) ??
      weekStart.add(const Duration(days: 6));

  final mesAnioTxt = DateFormat(
    "MMMM yyyy",
    "es",
  ).format(DateTime(anio, mes, 1));
  final filename = _safeFileName(
    'Cronograma $mesAnioTxt - Semana $semanaDelMes - $operario.pdf',
  );

  final tareasRaw = (data['tareas'] as List? ?? const []);

  final tareas = tareasRaw
      .map((e) => (e as Map).cast<String, dynamic>())
      .map(_TareaLite.fromJson)
      .toList();

  const dayCols = 6;
  const dayLabels = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
  ];

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(18),
      theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
      build: (_) => [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Línea 1: título
            pw.Text(
              'CRONOGRAMA SEMANAL',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),

            pw.SizedBox(height: 6),

            // Línea 2: datos compactos
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'Operario: $operario\nConjunto: $conjunto',
                    style: const pw.TextStyle(fontSize: 11),
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    'Semana $semanaDelMes - $mesAnioTxt\n'
                    'Rango: ${DateFormat('dd/MM/yyyy', 'es').format(weekStart)}'
                    ' - ${DateFormat('dd/MM/yyyy', 'es').format(weekEnd)}',
                    style: const pw.TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ),

        pw.SizedBox(height: 12),
        _buildCalendarGrid(
          tareas: tareas,
          dayLabels: dayLabels,
          dayCols: dayCols,
        ),
        pw.SizedBox(height: 14),
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text('Firma Operario: __________________________'),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Text('Firma Supervisor: ________________________'),
            ),
          ],
        ),
      ],
    ),
  );

  final Uint8List bytes = await doc.save();

  if (kIsWeb) {
    await downloadPdfWeb(bytes, filename);
  } else {
    await Printing.layoutPdf(name: filename, onLayout: (_) async => bytes);
  }
}

pw.Widget _buildCalendarGrid({
  required List<_TareaLite> tareas,
  required List<String> dayLabels,
  required int dayCols,
}) {
  // Rango fijo 08:00 - 16:00 (por hora)
  const int fixedStartMin = 8 * 60; // 08:00
  const int fixedEndMin = 16 * 60; // 16:00 (borde final)
  const int stepMin = 60; // 1 hora por fila

  // 8 filas: 8-9, 9-10, ..., 15-16
  final int steps = ((fixedEndMin - fixedStartMin) / stepMin).ceil();

  // Medidas
  const double timeColW = 70;
  const double dayHeaderH = 26;
  const double stepH = 52;
  const double bottomPad = 18;

  final double coreH = dayHeaderH + (steps * stepH);
  final double gridH = coreH + bottomPad;

  double yForMin(int minutes) {
    final clamped = minutes.clamp(fixedStartMin, fixedEndMin);
    final idx = (clamped - fixedStartMin) / stepMin;
    return dayHeaderH + (idx * stepH);
  }

  return pw.LayoutBuilder(
    builder: (context, constraints) {
      final totalW = constraints!.maxWidth;
      final dayW = (totalW - timeColW) / dayCols;

      return pw.Container(
        height: gridH,
        child: pw.Stack(
          children: [
            // Fondo (rejilla)
            pw.Positioned(
              left: 0,
              top: 0,
              child: pw.SizedBox(
                width: totalW,
                height: coreH,
                child: pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey700, width: 0.8),
                  ),
                  child: pw.Stack(
                    children: [
                      // Header
                      pw.Positioned(
                        left: 0,
                        top: 0,
                        child: pw.SizedBox(
                          width: totalW,
                          height: dayHeaderH,
                          child: pw.Row(
                            children: [
                              pw.Container(
                                width: timeColW,
                                height: dayHeaderH,
                                padding: const pw.EdgeInsets.all(6),
                                decoration: pw.BoxDecoration(
                                  color: PdfColors.amber,
                                  border: pw.Border(
                                    right: const pw.BorderSide(
                                      color: PdfColors.grey700,
                                      width: 0.8,
                                    ),
                                    bottom: const pw.BorderSide(
                                      color: PdfColors.grey700,
                                      width: 0.8,
                                    ),
                                  ),
                                ),
                                child: pw.Text(
                                  'Hora',
                                  style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                              for (int d = 0; d < dayCols; d++)
                                pw.Container(
                                  width: dayW,
                                  height: dayHeaderH,
                                  padding: const pw.EdgeInsets.all(6),
                                  decoration: pw.BoxDecoration(
                                    color: PdfColors.amber,
                                    border: pw.Border(
                                      right: const pw.BorderSide(
                                        color: PdfColors.grey700,
                                        width: 0.8,
                                      ),
                                      bottom: const pw.BorderSide(
                                        color: PdfColors.grey700,
                                        width: 0.8,
                                      ),
                                    ),
                                  ),
                                  child: pw.Text(
                                    dayLabels[d],
                                    style: pw.TextStyle(
                                      fontWeight: pw.FontWeight.bold,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),

                      // Líneas horizontales (incluye borde final 16:00)
                      for (int i = 0; i <= steps; i++)
                        pw.Positioned(
                          left: 0,
                          top: dayHeaderH + i * stepH,
                          child: pw.SizedBox(
                            width: totalW,
                            height: 0.8,
                            child: pw.Container(color: PdfColors.grey300),
                          ),
                        ),

                      // Etiquetas de hora 08:00 ... 15:00
                      for (int m = fixedStartMin; m < fixedEndMin; m += 60)
                        pw.Positioned(
                          left: 0,
                          top: yForMin(m) + 8,
                          child: pw.SizedBox(
                            width: timeColW,
                            height: 14,
                            child: pw.Padding(
                              padding: const pw.EdgeInsets.only(left: 6),
                              child: pw.Text(
                                _fmtHHmmFromMinutes(m),
                                style: const pw.TextStyle(fontSize: 10),
                              ),
                            ),
                          ),
                        ),

                      // Líneas verticales
                      for (int d = 0; d <= dayCols; d++)
                        pw.Positioned(
                          left: timeColW + d * dayW,
                          top: 0,
                          child: pw.SizedBox(
                            width: 0.8,
                            height: coreH,
                            child: pw.Container(color: PdfColors.grey700),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            // Banda almuerzo 13:00-14:00
            ...() {
              final top = yForMin(13 * 60);
              final bottom = yForMin(14 * 60);
              final h = (bottom - top).clamp(18.0, 9999.0);

              return [
                pw.Positioned(
                  left: 0,
                  top: top,
                  child: pw.SizedBox(
                    width: totalW,
                    height: h,
                    child: pw.Container(
                      decoration: pw.BoxDecoration(color: PdfColors.orange100),
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: pw.Align(
                        alignment: pw.Alignment.centerLeft,
                        child: pw.Text(
                          'ALMUERZO',
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.brown800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ];
            }(),

            // Bloques de tareas
            ...tareas.expand((t) {
              final dow0 = t.fechaInicio.weekday - 1; // Lunes=0
              if (dow0 < 0 || dow0 >= dayCols) return <pw.Widget>[];

              final startMinRaw = _minutesOfDay(t.fechaInicio);
              final endMinRaw = _minutesOfDay(t.fechaFin);
              final endMinSafe = math.max(startMinRaw + 1, endMinRaw);

              // clamp al rango fijo
              final sMin = startMinRaw.clamp(fixedStartMin, fixedEndMin);
              final eMin = endMinSafe.clamp(fixedStartMin, fixedEndMin);

              final top = yForMin(sMin);
              final bottom = yForMin(eMin);

              // mínimo para 3 líneas siempre
              final height = math.max(60.0, bottom - top);

              final left = timeColW + (dow0 * dayW) + 3;
              final width = dayW - 6;

              final ubic = (t.ubicacionNombre ?? '').trim();
              final elem = (t.elementoNombre ?? '').trim();

              final ubicElem = (ubic.isEmpty && elem.isEmpty)
                  ? ''
                  : [
                      if (ubic.isNotEmpty) ubic,
                      if (elem.isNotEmpty) elem,
                    ].join(' - ');

              final timeLabel =
                  '${DateFormat('HH:mm').format(t.fechaInicio)} - ${DateFormat('HH:mm').format(t.fechaFin)}';

              return [
                pw.Positioned(
                  left: left,
                  top: top,
                  child: pw.SizedBox(
                    width: width,
                    height: height,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.green100,
                        border: pw.Border.all(
                          color: PdfColors.green700,
                          width: 0.9,
                        ),
                        borderRadius: pw.BorderRadius.circular(7),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          // 1) Nombre tarea
                          pw.Text(
                            t.descripcion,
                            style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                            ),
                            maxLines: 1,
                          ),
                          pw.SizedBox(height: 3),

                          // 2) Ubicación - Elemento
                          pw.Text(
                            ubicElem,
                            style: const pw.TextStyle(fontSize: 10),
                            maxLines: 1,
                          ),
                          pw.SizedBox(height: 3),

                          // 3) Hora
                          pw.Text(
                            timeLabel,
                            style: const pw.TextStyle(fontSize: 10),
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ];
            }),
          ],
        ),
      );
    },
  );
}

DateTime? _parseYmd(String ymd) {
  if (ymd.trim().isEmpty) return null;
  try {
    final parts = ymd.split('-');
    if (parts.length != 3) return null;
    final y = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final d = int.parse(parts[2]);
    return DateTime(y, m, d);
  } catch (_) {
    return null;
  }
}

String _safeFileName(String s) {
  final cleaned = s
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return cleaned;
}

int _minutesOfDay(DateTime dt) => dt.hour * 60 + dt.minute;

String _fmtHHmmFromMinutes(int m) {
  final hh = (m ~/ 60).toString().padLeft(2, '0');
  final mm = (m % 60).toString().padLeft(2, '0');
  return '$hh:$mm';
}
