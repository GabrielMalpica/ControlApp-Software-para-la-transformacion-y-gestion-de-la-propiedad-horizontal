import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
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

class _HorarioLite {
  final String dia;
  final int aperturaMin;
  final int cierreMin;
  final int? descansoInicioMin;
  final int? descansoFinMin;

  const _HorarioLite({
    required this.dia,
    required this.aperturaMin,
    required this.cierreMin,
    this.descansoInicioMin,
    this.descansoFinMin,
  });

  int? get weekday => _weekdayDesdeDiaHorario(dia);

  static _HorarioLite? tryParse(Map<String, dynamic> json) {
    final dia = (json['dia'] ?? json['day'] ?? '').toString().trim();
    final aperturaRaw = _parseHoraMin(
      json['horaApertura'] ?? json['horaInicio'] ?? json['apertura'],
    );
    final cierreRaw =
        _parseHoraMin(json['horaCierre'] ?? json['horaFin'] ?? json['cierre']);

    if (aperturaRaw == null || cierreRaw == null) {
      return null;
    }

    final apertura = aperturaRaw;
    final cierre = _ajustarHoraPosterior(aperturaRaw, cierreRaw);

    if (dia.isEmpty || cierre <= apertura) {
      return null;
    }

    final descansoInicioRaw = _parseHoraMin(json['descansoInicio']);
    final descansoFinRaw = _parseHoraMin(json['descansoFin']);
    final descansoInicio = descansoInicioRaw == null
        ? null
        : _ajustarHoraPosterior(apertura, descansoInicioRaw);
    final descansoFin =
        descansoFinRaw == null || descansoInicio == null
        ? null
        : _ajustarHoraPosterior(descansoInicio, descansoFinRaw);
    final tieneDescanso =
        descansoInicio != null &&
        descansoFin != null &&
        descansoFin > descansoInicio;

    return _HorarioLite(
      dia: dia,
      aperturaMin: apertura,
      cierreMin: cierre,
      descansoInicioMin: tieneDescanso ? descansoInicio : null,
      descansoFinMin: tieneDescanso ? descansoFin : null,
    );
  }
}

int _ajustarHoraPosterior(int referenciaMin, int candidatoMin) {
  var ajustado = candidatoMin;
  while (ajustado <= referenciaMin && ajustado + (12 * 60) <= (24 * 60)) {
    ajustado += 12 * 60;
  }
  return ajustado;
}

class _GridHorarioConfig {
  final int inicioMin;
  final int finMin;
  final int? descansoInicioMin;
  final int? descansoFinMin;

  const _GridHorarioConfig({
    required this.inicioMin,
    required this.finMin,
    this.descansoInicioMin,
    this.descansoFinMin,
  });
}

class _TaskSpan {
  final _TareaLite tarea;
  final int dayIndex;
  final int startMin;
  final int endMin;

  const _TaskSpan({
    required this.tarea,
    required this.dayIndex,
    required this.startMin,
    required this.endMin,
  });
}

class _TaskPlacement {
  final _TareaLite tarea;
  final int dayIndex;
  final int startMin;
  final int endMin;
  final int column;
  final int columnCount;

  const _TaskPlacement({
    required this.tarea,
    required this.dayIndex,
    required this.startMin,
    required this.endMin,
    required this.column,
    required this.columnCount,
  });
}

Future<void> imprimirCronogramaOperario(Map<String, dynamic> data) async {
  final fontRegular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
  );
  final fontBold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
  );
  final logoBytes = await _loadCronogramaLogoBytes();
  final logoImage = pw.MemoryImage(logoBytes);

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

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(10),
      theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        conjunto.isEmpty ? 'Sin conjunto' : conjunto,
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'Cronograma de $mesAnioTxt - Semana $semanaDelMes',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'Operario: $operario',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Container(
                  alignment: pw.Alignment.topRight,
                  height: 42,
                  child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Expanded(
              child: _buildPreviewLikePdf(
                tareas: tareas,
                weekStart: weekStart,
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'Firma quien recibe: __________________________',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ),
                pw.SizedBox(width: 20),
                pw.Expanded(
                  child: pw.Text(
                    'Firma quien entrega: _________________________',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );

  final Uint8List bytes = await doc.save();

  if (kIsWeb) {
    await downloadPdfWeb(bytes, filename);
  } else {
    await Printing.layoutPdf(name: filename, onLayout: (_) async => bytes);
  }
}

Future<Uint8List> _loadCronogramaLogoBytes() async {
  const remoteLogo =
      'https://controlsas.com.co/wp-content/uploads/2025/07/Mesa-de-trabajo-3@3x.png';
  try {
    final resp = await http.get(Uri.parse(remoteLogo));
    if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
      return resp.bodyBytes;
    }
  } catch (_) {}

  final fallback = await rootBundle.load('assets/logo.png');
  return fallback.buffer.asUint8List();
}

pw.Widget _buildPreviewLikePdf({
  required List<_TareaLite> tareas,
  required DateTime weekStart,
}) {
  final dias = List.generate(6, (i) => weekStart.add(Duration(days: i)));

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: dias.asMap().entries.map((entry) {
      final dia = entry.value;
      final tareasDia = tareas.where((t) {
        final d = t.fechaInicio.toLocal();
        return d.year == dia.year && d.month == dia.month && d.day == dia.day;
      }).toList()..sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));

      return pw.Expanded(
        child: pw.Container(
          margin: pw.EdgeInsets.only(right: entry.key == dias.length - 1 ? 0 : 8),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: pw.BorderRadius.circular(10),
            border: pw.Border.all(color: PdfColors.grey400, width: 0.8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                DateFormat('EEEE dd/MM', 'es').format(dia),
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              if (tareasDia.isEmpty)
                pw.Text(
                  'Sin tareas',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                )
              else
                ...tareasDia.map((t) {
                  final ubic = (t.ubicacionNombre ?? '').trim();
                  final elem = (t.elementoNombre ?? '').trim();
                  final area = [
                    if (ubic.isNotEmpty) ubic,
                    if (elem.isNotEmpty) elem,
                  ].join(' - ');

                  return pw.Container(
                    width: double.infinity,
                    margin: const pw.EdgeInsets.only(bottom: 6),
                    padding: const pw.EdgeInsets.all(6),
                    decoration: pw.BoxDecoration(
                      color: _pdfTaskColor(t),
                      borderRadius: pw.BorderRadius.circular(8),
                      border: pw.Border.all(
                        color: _pdfTaskBorderColor(t),
                        width: 0.8,
                      ),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          t.descripcion.trim().isEmpty ? 'Sin descripción' : t.descripcion.trim(),
                          maxLines: 2,
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          '${DateFormat('HH:mm').format(t.fechaInicio)} - ${DateFormat('HH:mm').format(t.fechaFin)}',
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                        if (area.isNotEmpty) ...[
                          pw.SizedBox(height: 2),
                          pw.Text(area, maxLines: 2, style: const pw.TextStyle(fontSize: 8)),
                        ],
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      );
    }).toList(),
  );
}

PdfColor _pdfTaskColor(_TareaLite tarea) {
  final texto =
      '${tarea.ubicacionNombre ?? ''} ${tarea.elementoNombre ?? ''}'.toLowerCase();
  if (texto.contains('humed') || texto.contains('agua')) {
    return PdfColor.fromHex('#E3F2FD');
  }
  if (texto.contains('verde') ||
      texto.contains('jardin') ||
      texto.contains('cesped')) {
    return PdfColor.fromHex('#E8F5E9');
  }
  if (texto.contains('transit') || texto.contains('circul')) {
    return PdfColor.fromHex('#FFF3E0');
  }
  if (texto.contains('parque') || texto.contains('parqueadero')) {
    return PdfColor.fromHex('#EFEBE9');
  }
  return PdfColor.fromHex('#E8F1FF');
}

PdfColor _pdfTaskBorderColor(_TareaLite tarea) {
  final texto =
      '${tarea.ubicacionNombre ?? ''} ${tarea.elementoNombre ?? ''}'.toLowerCase();
  if (texto.contains('humed') || texto.contains('agua')) {
    return PdfColor.fromHex('#90CAF9');
  }
  if (texto.contains('verde') ||
      texto.contains('jardin') ||
      texto.contains('cesped')) {
    return PdfColor.fromHex('#81C784');
  }
  if (texto.contains('transit') || texto.contains('circul')) {
    return PdfColor.fromHex('#FFB74D');
  }
  if (texto.contains('parque') || texto.contains('parqueadero')) {
    return PdfColor.fromHex('#A1887F');
  }
  return PdfColor.fromHex('#B9D0FF');
}

pw.Widget _buildCalendarGrid({
  required List<_TareaLite> tareas,
  required List<String> dayLabels,
  required int dayCols,
  required _GridHorarioConfig horario,
  double? forcedHeight,
}) {
  const int stepMin = 30;
  final int fixedStartMin = horario.inicioMin;
  final int fixedEndMin = horario.finMin;

  final int steps = math.max(
    1,
    ((fixedEndMin - fixedStartMin) / stepMin).ceil(),
  );
  final placements = _buildTaskPlacements(
    tareas: tareas,
    fixedStartMin: fixedStartMin,
    fixedEndMin: fixedEndMin,
    dayCols: dayCols,
  );

  // Medidas
  const double timeColW = 40;
  const double dayHeaderH = 18;
  const double bottomPad = 16;

  return pw.LayoutBuilder(
    builder: (context, constraints) {
      final totalW = constraints!.maxWidth;
      final gridH = forcedHeight ?? constraints.maxHeight;
      final usableGridH = gridH <= 0 ? 520.0 : gridH;
      final coreH = math.max(120.0, usableGridH - bottomPad);
      final stepH = math.max(18.0, (coreH - dayHeaderH) / steps);

      double yForMin(int minutes) {
        final clamped = _clampInt(minutes, fixedStartMin, fixedEndMin);
        final idx = (clamped - fixedStartMin) / stepMin;
        return dayHeaderH + (idx * stepH);
      }

      final dayW = (totalW - timeColW) / dayCols;

      return pw.Container(
        height: usableGridH,
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

                       // Líneas horizontales
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

                       // Etiquetas de hora
                       for (int m = fixedStartMin; m < fixedEndMin; m += 60)
                         pw.Positioned(
                           left: 0,
                           top: math.max(0, yForMin(m) - 7),
                           child: pw.SizedBox(
                              width: timeColW,
                                height: 12,
                             child: pw.Padding(
                               padding: const pw.EdgeInsets.only(left: 6),
                               child: pw.Text(
                                 _fmtHHmmFromMinutes(m),
                                 style: const pw.TextStyle(fontSize: 8.5),
                                ),
                              ),
                            ),
                          ),
                       pw.Positioned(
                         left: 0,
                         top: coreH,
                         child: pw.SizedBox(
                           width: timeColW,
                           height: bottomPad,
                           child: pw.Padding(
                             padding: const pw.EdgeInsets.only(left: 6, top: 1),
                             child: pw.Text(
                               _fmtHHmmFromMinutes(fixedEndMin),
                               style: const pw.TextStyle(fontSize: 8.5),
                             ),
                           ),
                         ),
                       ),
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

            if (horario.descansoInicioMin != null &&
                horario.descansoFinMin != null) ...() {
              final top = yForMin(horario.descansoInicioMin!);
              final bottom = yForMin(horario.descansoFinMin!);
              final h = math.max(18.0, bottom - top);

              return [
                pw.Positioned(
                  left: 0,
                  top: top,
                  child: pw.SizedBox(
                    width: totalW,
                    height: h,
                      child: pw.Container(
                      decoration: pw.BoxDecoration(
                        color: PdfColors.red100,
                        border: pw.Border.all(
                          color: PdfColors.red600,
                          width: 0.8,
                        ),
                      ),
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      child: pw.Align(
                        alignment: pw.Alignment.centerLeft,
                        child: pw.Text(
                          'DESCANSO',
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.red900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ];
            }(),

            // Bloques de tareas
            ...placements.expand((placement) {
              final top = yForMin(placement.startMin);
              final bottom = yForMin(placement.endMin);

              final height = math.max(14.0, bottom - top);
              const outerPad = 3.0;
              const columnGap = 4.0;

              final availableW = dayW - (outerPad * 2);
              final columnCount = math.max(1, placement.columnCount);
              final width = columnCount == 1

                  ? availableW
                  : (availableW - (columnGap * (columnCount - 1))) /
                        columnCount;

              // mínimo para 3 líneas siempre
              final left =

                  timeColW +
                  (placement.dayIndex * dayW) +
                  outerPad +
                  (placement.column * (width + columnGap));
              final t = placement.tarea;

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
              final ultraLabel = t.descripcion.trim().isNotEmpty
                  ? t.descripcion.trim()
                  : (ubicElem.isNotEmpty ? ubicElem : timeLabel);
              final areaLabel = ubicElem.isNotEmpty ? ubicElem : timeLabel;

              final ultraCompact = height < 20;
              final compact = height < 40;
              final padding = ultraCompact ? 2.0 : (compact ? 4.0 : 6.0);
              final titleFont = ultraCompact ? 6.5 : (compact ? 7.5 : 9.0);
              final bodyFont = ultraCompact ? 6.0 : (compact ? 6.6 : 8.0);
              final content = <pw.Widget>[
                if (ultraCompact)
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    mainAxisSize: pw.MainAxisSize.min,
                    children: [
                      pw.Text(
                        ultraLabel,
                        style: pw.TextStyle(
                          fontSize: bodyFont,
                          fontWeight: pw.FontWeight.bold,
                        ),
                        maxLines: 1,
                      ),
                      if (height >= 18)
                        pw.Text(
                          areaLabel,
                          style: pw.TextStyle(fontSize: bodyFont - 0.2),
                          maxLines: 1,
                        ),
                    ],
                  )
                else ...[
                  pw.Text(
                    t.descripcion,
                    style: pw.TextStyle(
                      fontSize: titleFont,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    maxLines: 1,
                  ),
                  if (ubicElem.isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(
                      ubicElem,
                      style: pw.TextStyle(fontSize: bodyFont),
                      maxLines: compact ? 2 : 1,
                    ),
                  ],
                  pw.SizedBox(height: 2),
                  pw.Text(
                    timeLabel,
                    style: pw.TextStyle(fontSize: bodyFont),
                    maxLines: 1,
                  ),
                ],
              ];

              return [
                pw.Positioned(
                  left: left,
                  top: top,
                  child: pw.SizedBox(
                    width: width,
                    height: height,
                    child: pw.Container(
                      padding: pw.EdgeInsets.all(padding),
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
                        mainAxisSize: pw.MainAxisSize.min,
                        children: content,

                          // 2) Ubicación - Elemento

                          // 3) Hora
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

_GridHorarioConfig _resolverHorarioGrid({
  required List<_HorarioLite> horarios,
  required List<_TareaLite> tareas,
}) {
  int? minApertura;
  int? maxCierre;
  int? minDescanso;
  int? maxDescanso;

  for (final h in horarios) {
    final weekday = h.weekday;
    if (weekday == null || weekday == DateTime.sunday) continue;

    minApertura = minApertura == null
        ? h.aperturaMin
        : math.min(minApertura, h.aperturaMin);
    maxCierre = maxCierre == null ? h.cierreMin : math.max(maxCierre, h.cierreMin);

    final descansoInicio = h.descansoInicioMin;
    final descansoFin = h.descansoFinMin;
    if (descansoInicio == null || descansoFin == null || descansoFin <= descansoInicio) {
      continue;
    }

    minDescanso = minDescanso == null
        ? descansoInicio
        : math.min(minDescanso, descansoInicio);
    maxDescanso = maxDescanso == null
        ? descansoFin
        : math.max(maxDescanso, descansoFin);
  }

  if (minApertura == null || maxCierre == null) {
    for (final t in tareas) {
      final iniMin = _minutesOfDay(t.fechaInicio);
      final finMin = _minutesOfDay(t.fechaFin);
      if (finMin <= iniMin) continue;

      minApertura = minApertura == null ? iniMin : math.min(minApertura, iniMin);
      maxCierre = maxCierre == null ? finMin : math.max(maxCierre, finMin);
    }

    if (maxCierre != null) {
      maxCierre = math.max(maxCierre, 16 * 60);
    }
  }

  minApertura ??= 8 * 60;
  maxCierre ??= 16 * 60;

  final inicioHora = _clampInt(minApertura ~/ 60, 0, 23);
  var finHora = _clampInt((maxCierre + 59) ~/ 60, 1, 24);
  if (finHora <= inicioHora) {
    finHora = _clampInt(inicioHora + 1, 1, 24);
  }

  int? descansoInicioVisible;
  int? descansoFinVisible;
  if (minDescanso != null &&
      maxDescanso != null &&
      maxDescanso > minDescanso) {
    final inicioRango = inicioHora * 60;
    final finRango = finHora * 60;
    descansoInicioVisible = _clampInt(minDescanso, inicioRango, finRango - 1);
    descansoFinVisible = _clampInt(
      maxDescanso,
      descansoInicioVisible + 1,
      finRango,
    );
  }

  return _GridHorarioConfig(
    inicioMin: inicioHora * 60,
    finMin: finHora * 60,
    descansoInicioMin: descansoInicioVisible,
    descansoFinMin: descansoFinVisible,
  );
}

List<_TaskPlacement> _buildTaskPlacements({
  required List<_TareaLite> tareas,
  required int fixedStartMin,
  required int fixedEndMin,
  required int dayCols,
}) {
  final out = <_TaskPlacement>[];

  for (var dayIndex = 0; dayIndex < dayCols; dayIndex++) {
    final spans = tareas
        .where((t) => (t.fechaInicio.weekday - 1) == dayIndex)
        .map((t) {
          final startMin = _clampInt(
            _minutesOfDay(t.fechaInicio),
            fixedStartMin,
            fixedEndMin,
          );
          final rawEnd = math.max(
            _minutesOfDay(t.fechaFin),
            _minutesOfDay(t.fechaInicio) + 1,
          );
          final endMin = _clampInt(rawEnd, fixedStartMin, fixedEndMin);
          return _TaskSpan(
            tarea: t,
            dayIndex: dayIndex,
            startMin: startMin,
            endMin: endMin,
          );
        })
        .where((span) => span.endMin > span.startMin)
        .toList()
      ..sort((a, b) {
        final startCmp = a.startMin.compareTo(b.startMin);
        if (startCmp != 0) return startCmp;
        return a.endMin.compareTo(b.endMin);
      });

    if (spans.isEmpty) continue;

    var cluster = <_TaskSpan>[];
    var clusterEnd = -1;

    void flushCluster() {
      if (cluster.isEmpty) return;
      out.addAll(_assignTaskColumns(cluster));
      cluster = <_TaskSpan>[];
      clusterEnd = -1;
    }

    for (final span in spans) {
      if (cluster.isEmpty) {
        cluster.add(span);
        clusterEnd = span.endMin;
        continue;
      }

      if (span.startMin < clusterEnd) {
        cluster.add(span);
        clusterEnd = math.max(clusterEnd, span.endMin);
        continue;
      }

      flushCluster();
      cluster.add(span);
      clusterEnd = span.endMin;
    }

    flushCluster();
  }

  return out;
}

List<_TaskPlacement> _assignTaskColumns(List<_TaskSpan> cluster) {
  final columnEnds = <int>[];
  final temp = <Map<String, dynamic>>[];

  for (final span in cluster) {
    var column = -1;
    for (var i = 0; i < columnEnds.length; i++) {
      if (span.startMin >= columnEnds[i]) {
        column = i;
        break;
      }
    }

    if (column == -1) {
      column = columnEnds.length;
      columnEnds.add(span.endMin);
    } else {
      columnEnds[column] = span.endMin;
    }

    temp.add({
      'span': span,
      'column': column,
    });
  }

  final columnCount = math.max(1, columnEnds.length);
  return temp
      .map((item) {
        final span = item['span'] as _TaskSpan;
        final column = item['column'] as int;
        return _TaskPlacement(
          tarea: span.tarea,
          dayIndex: span.dayIndex,
          startMin: span.startMin,
          endMin: span.endMin,
          column: column,
          columnCount: columnCount,
        );
      })
      .toList();
}

String _safeFileName(String s) {
  final cleaned = s
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return cleaned;
}

int _minutesOfDay(DateTime dt) => dt.hour * 60 + dt.minute;

int _clampInt(int value, int min, int max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

String _fmtHHmmFromMinutes(int m) {
  final hh = (m ~/ 60).toString().padLeft(2, '0');
  final mm = (m % 60).toString().padLeft(2, '0');
  return '$hh:$mm';
}

int? _parseHoraMin(dynamic raw) {
  final value = raw?.toString().trim() ?? '';
  if (value.isEmpty) return null;

  final parts = value.split(':');
  if (parts.length < 2) return null;

  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    return null;
  }
  return hour * 60 + minute;
}

int? _weekdayDesdeDiaHorario(String? rawDia) {
  if (rawDia == null) return null;
  switch (_normalizarDia(rawDia)) {
    case 'LUNES':
    case 'MONDAY':
      return DateTime.monday;
    case 'MARTES':
    case 'TUESDAY':
      return DateTime.tuesday;
    case 'MIERCOLES':
    case 'WEDNESDAY':
      return DateTime.wednesday;
    case 'JUEVES':
    case 'THURSDAY':
      return DateTime.thursday;
    case 'VIERNES':
    case 'FRIDAY':
      return DateTime.friday;
    case 'SABADO':
    case 'SATURDAY':
      return DateTime.saturday;
    case 'DOMINGO':
    case 'SUNDAY':
      return DateTime.sunday;
    default:
      return null;
  }
}

String _normalizarDia(String raw) {
  var out = raw.trim().toUpperCase();
  const replacements = {
    '_': '',
    '-': '',
    ' ': '',
  };
  replacements.forEach((from, to) => out = out.replaceAll(from, to));
  return out;
}
