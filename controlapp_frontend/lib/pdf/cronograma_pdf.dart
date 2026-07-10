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
    final cierreRaw = _parseHoraMin(
      json['horaCierre'] ?? json['horaFin'] ?? json['cierre'],
    );

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
    final descansoFin = descansoFinRaw == null || descansoInicio == null
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

class _AgendaBlockLite {
  final int startMin;
  final int endMin;
  final _TareaLite? tarea;

  const _AgendaBlockLite.task(this.tarea, this.startMin, this.endMin)
    : assert(tarea != null);

  const _AgendaBlockLite.gap({required this.startMin, required this.endMin})
    : tarea = null;

  bool get isGap => tarea == null;
}

class _DayAgendaLite {
  final DateTime dia;
  final bool esFestivo;
  final bool esFueraDePeriodo;
  final bool esMesAnterior;
  final String? festivoNombre;
  final List<_AgendaBlockLite> bloques;

  const _DayAgendaLite({
    required this.dia,
    required this.esFestivo,
    required this.esFueraDePeriodo,
    required this.esMesAnterior,
    required this.festivoNombre,
    required this.bloques,
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

  final alcance = (data['alcance'] ?? 'SEMANA').toString().toUpperCase();

  final semanaDelMes = (data['semanaDelMes'] is int)
      ? data['semanaDelMes'] as int
      : int.tryParse('${data['semanaDelMes']}') ?? 1;

  final weekStart =
      _parseYmd((data['weekStart'] ?? '').toString()) ?? DateTime(anio, mes, 1);

  final mesAnioTxt = DateFormat(
    'MMMM yyyy',
    'es',
  ).format(DateTime(anio, mes, 1));
  final filename = _safeFileName(
    alcance == 'MES'
        ? 'Cronograma $mesAnioTxt - $operario.pdf'
        : 'Cronograma $mesAnioTxt - Semana $semanaDelMes - $operario.pdf',
  );

  final tareasRaw = (data['tareas'] as List? ?? const []);

  final tareas =
      tareasRaw
          .map((e) => (e as Map).cast<String, dynamic>())
          .map(_TareaLite.fromJson)
          .toList()
        ..sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));
  final horarios = ((data['horariosConjunto'] as List?) ?? const [])
      .map((e) => e is Map ? _HorarioLite.tryParse(e.cast<String, dynamic>()) : null)
      .whereType<_HorarioLite>()
      .toList();
  final festivos = ((data['festivos'] as List?) ?? const [])
      .map((e) => e.toString())
      .toSet();
  final festivoNombrePorYmd =
      ((data['festivoNombrePorYmd'] as Map?) ?? const <dynamic, dynamic>{}).map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );

  final theme = pw.ThemeData.withFont(base: fontRegular, bold: fontBold);
  final weekStarts = alcance == 'MES'
      ? _weekStartsForMonth(anio, mes)
      : <DateTime>[weekStart];

  for (var i = 0; i < weekStarts.length; i++) {
    final currentWeekStart = weekStarts[i];
    final currentWeekEnd = currentWeekStart.add(const Duration(days: 6));
    final weekNumber = alcance == 'MES' ? i + 1 : semanaDelMes;
    final tareasSemana = tareas.where((t) {
      final fecha = DateTime(
        t.fechaInicio.year,
        t.fechaInicio.month,
        t.fechaInicio.day,
      );
      return !fecha.isBefore(currentWeekStart) &&
          !fecha.isAfter(currentWeekEnd);
    }).toList();
    final agendaSemanal = _buildWeekAgenda(
      tareas: tareasSemana,
      horarios: horarios,
      weekStart: currentWeekStart,
      periodoAnio: anio,
      periodoMes: mes,
      festivos: festivos,
      festivoNombrePorYmd: festivoNombrePorYmd,
    );
    final pageCount = _weeklyPageCount(agendaSemanal);

    for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
      final isLastPage = pageIndex == pageCount - 1;
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.fromLTRB(8, 6, 8, 8),
          theme: theme,
          build: (context) => _buildWeeklyCronogramaPage(
            logoImage: logoImage,
            conjunto: conjunto,
            operario: operario,
            mesAnioTxt: mesAnioTxt,
            periodoAnio: anio,
            periodoMes: mes,
            alcance: alcance,
            semanaDelMes: weekNumber,
            weekStart: currentWeekStart,
            weekEnd: currentWeekEnd,
            agendaSemanal: agendaSemanal,
            pageIndex: pageIndex,
            totalPages: pageCount,
            showSignature: isLastPage,
          ),
        ),
      );
    }
  }

  final Uint8List bytes = await doc.save();

  if (kIsWeb) {
    await downloadPdfWeb(bytes, filename);
  } else {
    await Printing.layoutPdf(name: filename, onLayout: (_) async => bytes);
  }
}

List<DateTime> _weekStartsForMonth(int year, int month) {
  final firstDay = DateTime(year, month, 1);
  final lastDay = DateTime(year, month + 1, 0);
  final firstWeekStart = firstDay.subtract(
    Duration(days: firstDay.weekday - 1),
  );
  final out = <DateTime>[];

  for (
    var current = firstWeekStart;
    !current.isAfter(lastDay);
    current = current.add(const Duration(days: 7))
  ) {
    out.add(DateTime(current.year, current.month, current.day));
  }

  return out;
}

pw.Widget _buildWeeklyCronogramaPage({
  required pw.MemoryImage logoImage,
  required String conjunto,
  required String operario,
  required String mesAnioTxt,
  required int periodoAnio,
  required int periodoMes,
  required String alcance,
  required int semanaDelMes,
  required DateTime weekStart,
  required DateTime weekEnd,
  required List<_DayAgendaLite> agendaSemanal,
  required int pageIndex,
  required int totalPages,
  required bool showSignature,
}) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _buildCronogramaHeader(
        logoImage: logoImage,
        conjunto: conjunto,
        operario: operario,
        mesAnioTxt: mesAnioTxt,
        alcance: alcance,
        semanaDelMes: semanaDelMes,
        weekStart: weekStart,
        weekEnd: weekEnd,
        pageIndex: pageIndex,
        totalPages: totalPages,
      ),
      pw.SizedBox(height: 4),
      pw.Expanded(
        child: _buildPreviewLikePdf(
          agendaSemanal: agendaSemanal,
          pageIndex: pageIndex,
        ),
      ),
      if (showSignature) ...[
        pw.SizedBox(height: 6),
        _buildSignatureRow(),
      ],
    ],
  );
}

pw.Widget _buildCronogramaHeader({
  required pw.MemoryImage logoImage,
  required String conjunto,
  required String operario,
  required String mesAnioTxt,
  required String alcance,
  required int semanaDelMes,
  required DateTime weekStart,
  required DateTime weekEnd,
  required int pageIndex,
  required int totalPages,
}) {
  final rangoSemana =
      '${DateFormat('dd/MM').format(weekStart)} - ${DateFormat('dd/MM').format(weekEnd)}';
  final subtitulo = alcance == 'MES'
      ? 'Cronograma mensual - Semana $semanaDelMes ($rangoSemana)'
      : 'Cronograma de $mesAnioTxt - Semana $semanaDelMes';

  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 4),
    padding: const pw.EdgeInsets.only(bottom: 4),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.8),
      ),
    ),
    child: pw.Row(
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
              pw.Text(subtitulo, style: const pw.TextStyle(fontSize: 10)),
              pw.SizedBox(height: 3),
              pw.Text(
                'Operario: $operario',
                style: const pw.TextStyle(fontSize: 10),
              ),
              if (totalPages > 1) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  'Parte ${pageIndex + 1} de $totalPages',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ],
          ),
        ),
        pw.SizedBox(width: 12),
        pw.SizedBox(
          height: 42,
          child: pw.Image(logoImage, fit: pw.BoxFit.contain),
        ),
      ],
    ),
  );
}

pw.Widget _buildSignatureRow() {
  return pw.Row(
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
  );
}

Future<Uint8List> _loadCronogramaLogoBytes() async {
  final logo = await rootBundle.load('assets/logo_cronograma.png');
  return logo.buffer.asUint8List();
}

pw.Widget _buildPreviewLikePdf({
  required List<_DayAgendaLite> agendaSemanal,
  required int pageIndex,
}) {
  final bloquesMaximosPorDiaSemana = agendaSemanal
      .map((dia) => dia.bloques.length)
      .fold<int>(0, math.max);
  final bloquesTotalesSemana = agendaSemanal.fold<int>(
    0,
    (acc, dia) => acc + dia.bloques.length,
  );

  final sparse =
      bloquesMaximosPorDiaSemana <= 2 && bloquesTotalesSemana <= 10;
  final medium =
      !sparse && bloquesMaximosPorDiaSemana <= 3 && bloquesTotalesSemana <= 16;
  final veryDense = bloquesMaximosPorDiaSemana >= 6;
  final compact = !sparse && !medium && bloquesMaximosPorDiaSemana >= 4;
  final dayPadding = (sparse
          ? 8.0
          : (medium ? 6.0 : (veryDense ? 3.0 : (compact ? 4.0 : 6.0)))) *
      1.38;
  final taskPadding = (sparse
          ? 6.0
          : (medium ? 5.0 : (veryDense ? 2.0 : (compact ? 3.0 : 4.0)))) *
      1.38;
  final titleFont = (sparse
          ? 9.2
          : (medium ? 8.4 : (veryDense ? 6.4 : (compact ? 7.2 : 8.0)))) *
      1.38;
  final bodyFont = (sparse
          ? 8.2
          : (medium ? 7.4 : (veryDense ? 5.8 : (compact ? 6.4 : 7.0)))) *
      1.38;
  final blockSpacing = (sparse
          ? 8.0
          : (medium ? 6.0 : (veryDense ? 2.0 : 4.0))) *
      1.38;
  final lineSpacing = (sparse ? 2.0 : 1.0) * 1.38;

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: agendaSemanal.asMap().entries.map((entry) {
      final diaAgenda = entry.value;
      final dia = diaAgenda.dia;
      final esFestivo = diaAgenda.esFestivo;
      final esFueraDePeriodo = diaAgenda.esFueraDePeriodo;
      final festivoNombre = diaAgenda.festivoNombre;
      final bloquesDia = _sliceAgendaBlocks(diaAgenda.bloques, pageIndex);

      return pw.Expanded(
        child: pw.Container(
          margin: pw.EdgeInsets.only(
            right: entry.key == agendaSemanal.length - 1 ? 0 : 8,
          ),
          padding: pw.EdgeInsets.all(dayPadding),
          decoration: pw.BoxDecoration(
            color: esFueraDePeriodo
                ? PdfColor.fromHex('#FFEBEE')
                : esFestivo
                ? PdfColor.fromHex('#FFEBEE')
                : PdfColors.grey100,
            borderRadius: pw.BorderRadius.circular(10),
            border: pw.Border.all(
              color: esFueraDePeriodo
                  ? PdfColor.fromHex('#E53935')
                  : esFestivo
                  ? PdfColor.fromHex('#E53935')
                  : PdfColors.grey400,
              width: 0.8,
            ),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                DateFormat('EEEE dd/MM', 'es').format(dia),
                style: pw.TextStyle(
                  fontSize: compact ? 8 : 9,
                  fontWeight: pw.FontWeight.bold,
                  color: esFueraDePeriodo || esFestivo
                      ? PdfColor.fromHex('#B71C1C')
                      : PdfColors.black,
                ),
              ),
              if (esFueraDePeriodo) ...[
                pw.SizedBox(height: lineSpacing),
                pw.Text(
                  diaAgenda.esMesAnterior
                      ? 'Dia del mes anterior'
                      : 'Dia del mes siguiente',
                  style: pw.TextStyle(
                    fontSize: bodyFont,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#B71C1C'),
                  ),
                ),
              ] else if (esFestivo) ...[
                pw.SizedBox(height: lineSpacing),
                pw.Text(
                  festivoNombre?.isNotEmpty == true
                      ? 'Festivo: $festivoNombre'
                      : 'Festivo - no se programan tareas',
                  style: pw.TextStyle(
                    fontSize: bodyFont,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#B71C1C'),
                  ),
                ),
              ],
              pw.SizedBox(height: blockSpacing),
              if (bloquesDia.isEmpty)
                pw.Text(
                  esFestivo ? 'No se programan tareas.' : 'Sin tareas',
                  style: pw.TextStyle(
                    fontSize: bodyFont,
                    color: esFestivo
                        ? PdfColor.fromHex('#B71C1C')
                        : PdfColors.grey700,
                  ),
                )
              else
                ...bloquesDia.map((bloque) {
                  if (bloque.isGap) {
                    final duracion = _fmtDuracionRango(bloque.startMin, bloque.endMin);
                    return pw.Container(
                      width: double.infinity,
                      margin: pw.EdgeInsets.only(bottom: blockSpacing),
                      padding: pw.EdgeInsets.all(taskPadding),
                      decoration: pw.BoxDecoration(
                        color: PdfColor.fromHex('#FFF3E0'),
                        borderRadius: pw.BorderRadius.circular(8),
                        border: pw.Border.all(
                          color: PdfColor.fromHex('#FB8C00'),
                          width: 0.9,
                        ),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Hueco para correctiva',
                            style: pw.TextStyle(
                              fontSize: sparse ? titleFont : bodyFont - 0.2,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColor.fromHex('#E65100'),
                            ),
                          ),
                          pw.SizedBox(height: lineSpacing),
                          pw.Text(
                            '${_fmtHHmmFromMinutes(bloque.startMin)} - ${_fmtHHmmFromMinutes(bloque.endMin)}  |  $duracion',
                            style: pw.TextStyle(
                              fontSize: sparse ? bodyFont : bodyFont - 0.3,
                              color: PdfColor.fromHex('#BF6000'),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final t = bloque.tarea!;
                  final ubic = (t.ubicacionNombre ?? '').trim();
                  final elem = (t.elementoNombre ?? '').trim();

                  return pw.Container(
                    width: double.infinity,
                    margin: pw.EdgeInsets.only(bottom: blockSpacing),
                    padding: pw.EdgeInsets.all(taskPadding),
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
                          t.descripcion.trim().isEmpty
                              ? 'Sin descripción'
                              : t.descripcion.trim(),
                          style: pw.TextStyle(
                            fontSize: titleFont,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: lineSpacing),
                        pw.Text(
                          '${DateFormat('HH:mm').format(t.fechaInicio)} - ${DateFormat('HH:mm').format(t.fechaFin)}',
                          style: pw.TextStyle(fontSize: bodyFont),
                        ),
                        if (ubic.isNotEmpty) ...[
                          pw.SizedBox(height: lineSpacing),
                          pw.Text(
                            'Ubicación: $ubic',
                            style: pw.TextStyle(fontSize: bodyFont),
                          ),
                        ],
                        if (elem.isNotEmpty) ...[
                          pw.SizedBox(height: lineSpacing),
                          pw.Text(
                            'Elemento: $elem',
                            style: pw.TextStyle(fontSize: bodyFont),
                          ),
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

const int _maxAgendaBlocksPerPage = 5;

List<_DayAgendaLite> _buildWeekAgenda({
  required List<_TareaLite> tareas,
  required List<_HorarioLite> horarios,
  required DateTime weekStart,
  required int periodoAnio,
  required int periodoMes,
  required Set<String> festivos,
  required Map<String, String> festivoNombrePorYmd,
}) {
  final dias = List.generate(6, (i) => weekStart.add(Duration(days: i)));
  return dias.map((dia) {
    final ymd = _toYmd(dia);
    final esFestivo = festivos.contains(ymd);
    final esFueraDePeriodo = dia.year != periodoAnio || dia.month != periodoMes;
    final tareasDia = tareas.where((t) {
      final d = t.fechaInicio.toLocal();
      return d.year == dia.year && d.month == dia.month && d.day == dia.day;
    }).toList()..sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));

    return _DayAgendaLite(
      dia: dia,
      esFestivo: esFestivo,
      esFueraDePeriodo: esFueraDePeriodo,
      esMesAnterior: dia.isBefore(DateTime(periodoAnio, periodoMes, 1)),
      festivoNombre: festivoNombrePorYmd[ymd]?.trim(),
      bloques: _buildAgendaBlocksLite(
        dia: dia,
        tareasDia: tareasDia,
        horarios: horarios,
        esFestivo: esFestivo,
        esFueraDePeriodo: esFueraDePeriodo,
      ),
    );
  }).toList();
}

int _weeklyPageCount(List<_DayAgendaLite> agendaSemanal) {
  final maxBlocks = agendaSemanal
      .map((dia) => dia.bloques.length)
      .fold<int>(0, math.max);
  return math.max(1, (maxBlocks / _maxAgendaBlocksPerPage).ceil());
}

List<_AgendaBlockLite> _sliceAgendaBlocks(
  List<_AgendaBlockLite> bloques,
  int pageIndex,
) {
  final start = pageIndex * _maxAgendaBlocksPerPage;
  if (start >= bloques.length) return const [];
  final end = math.min(bloques.length, start + _maxAgendaBlocksPerPage);
  return bloques.sublist(start, end);
}

List<_AgendaBlockLite> _buildAgendaBlocksLite({
  required DateTime dia,
  required List<_TareaLite> tareasDia,
  required List<_HorarioLite> horarios,
  required bool esFestivo,
  required bool esFueraDePeriodo,
}) {
  final bloques = tareasDia
      .map(
        (t) => _AgendaBlockLite.task(
          t,
          _minutesOfDay(t.fechaInicio),
          math.max(_minutesOfDay(t.fechaInicio) + 1, _minutesOfDay(t.fechaFin)),
        ),
      )
      .toList();

  if (esFestivo || esFueraDePeriodo) {
    bloques.sort((a, b) => a.startMin.compareTo(b.startMin));
    return bloques;
  }

  _HorarioLite? horario;
  for (final item in horarios) {
    if (item.weekday == dia.weekday) {
      horario = item;
      break;
    }
  }
  if (horario == null) {
    bloques.sort((a, b) => a.startMin.compareTo(b.startMin));
    return bloques;
  }

  final segmentos = <(int, int)>[
    (horario.aperturaMin, horario.descansoInicioMin ?? horario.cierreMin),
    if (horario.descansoInicioMin != null && horario.descansoFinMin != null)
      (horario.descansoFinMin!, horario.cierreMin),
  ];

  for (final segmento in segmentos) {
    final inicio = segmento.$1;
    final fin = segmento.$2;
    if (fin <= inicio) continue;

    final tareasSegmento = tareasDia
        .map(
          (t) => (
            t: t,
            inicio: math.max(_minutesOfDay(t.fechaInicio), inicio),
            fin: math.min(
              math.max(_minutesOfDay(t.fechaInicio) + 1, _minutesOfDay(t.fechaFin)),
              fin,
            ),
          ),
        )
        .where((item) => item.fin > item.inicio)
        .toList()
      ..sort((a, b) => a.inicio.compareTo(b.inicio));

    var cursor = inicio;
    for (final item in tareasSegmento) {
      if (item.inicio > cursor) {
        bloques.add(_AgendaBlockLite.gap(startMin: cursor, endMin: item.inicio));
      }
      cursor = math.max(cursor, item.fin);
    }
    if (cursor < fin) {
      bloques.add(_AgendaBlockLite.gap(startMin: cursor, endMin: fin));
    }
  }

  bloques.sort((a, b) => a.startMin.compareTo(b.startMin));
  return bloques;
}

String _fmtDuracionRango(int inicioMin, int finMin) {
  final total = math.max(0, finMin - inicioMin);
  final horas = total ~/ 60;
  final minutos = total % 60;
  if (horas <= 0) return '$minutos min disponibles';
  if (minutos == 0) return '$horas h disponibles';
  return '$horas h $minutos min disponibles';
}

PdfColor _pdfTaskColor(_TareaLite tarea) {
  final texto = '${tarea.ubicacionNombre ?? ''} ${tarea.elementoNombre ?? ''}'
      .toLowerCase();
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
  final texto = '${tarea.ubicacionNombre ?? ''} ${tarea.elementoNombre ?? ''}'
      .toLowerCase();
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
                horario.descansoFinMin != null)
              ...() {
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
    maxCierre = maxCierre == null
        ? h.cierreMin
        : math.max(maxCierre, h.cierreMin);

    final descansoInicio = h.descansoInicioMin;
    final descansoFin = h.descansoFinMin;
    if (descansoInicio == null ||
        descansoFin == null ||
        descansoFin <= descansoInicio) {
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

      minApertura = minApertura == null
          ? iniMin
          : math.min(minApertura, iniMin);
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
  if (minDescanso != null && maxDescanso != null && maxDescanso > minDescanso) {
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
    final spans =
        tareas
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

    temp.add({'span': span, 'column': column});
  }

  final columnCount = math.max(1, columnEnds.length);
  return temp.map((item) {
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
  }).toList();
}

String _safeFileName(String s) {
  final cleaned = s
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return cleaned;
}

int _minutesOfDay(DateTime dt) => dt.hour * 60 + dt.minute;

String _toYmd(DateTime d) {
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

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
  if (hour == null ||
      minute == null ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
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
  const replacements = {'_': '', '-': '', ' ': ''};
  replacements.forEach((from, to) => out = out.replaceAll(from, to));
  return out;
}
