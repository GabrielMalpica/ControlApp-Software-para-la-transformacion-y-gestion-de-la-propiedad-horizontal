import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/cronograma_api.dart';
import 'package:flutter_application_1/api/festivo_api.dart';
import 'package:flutter_application_1/api/gerente_api.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/pdf/cronograma_pdf.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:intl/intl.dart';

class _PreviewAgendaBlock {
  final DateTime inicio;
  final DateTime fin;
  final TareaModel? tarea;

  const _PreviewAgendaBlock.task({
    required this.inicio,
    required this.fin,
    required this.tarea,
  });

  const _PreviewAgendaBlock.gap({required this.inicio, required this.fin})
    : tarea = null;

  bool get isGap => tarea == null;
}

class CronogramaImpresionPage extends StatefulWidget {
  final String nit;

  const CronogramaImpresionPage({super.key, required this.nit});

  @override
  State<CronogramaImpresionPage> createState() =>
      _CronogramaImpresionPageState();
}

class _CronogramaImpresionPageState extends State<CronogramaImpresionPage> {
  final _cronogramaApi = CronogramaApi();
  final _festivoApi = FestivoApi();
  final _gerenteApi = GerenteApi();

  bool _loading = true;
  String? _error;

  int _mes = DateTime.now().month;
  int _anio = DateTime.now().year;
  int _semana = 1;
  String _operario = 'TODOS';
  String _alcance = 'SEMANA';

  List<TareaModel> _tareasMes = [];
  List<HorarioConjunto> _horariosConjunto = const [];
  List<String> _operariosDisponibles = [];
  String _conjuntoNombre = '';
  Set<String> _festivosYmd = {};
  Map<String, String> _festivoNombrePorYmd = {};

  @override
  void initState() {
    super.initState();
    _cargarMes();
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _startOfWeekMonday(DateTime d) {
    final dd = _dayOnly(d);
    final diff = dd.weekday - DateTime.monday;
    return dd.subtract(Duration(days: diff));
  }

  DateTime _weekStartOfMonthByIndex(int year, int month, int weekIndex) {
    final firstDay = DateTime(year, month, 1);
    final firstWeekStart = _startOfWeekMonday(firstDay);
    return firstWeekStart.add(Duration(days: 7 * (weekIndex - 1)));
  }

  String _nombreMes(int month) {
    return DateFormat('MMMM', 'es').format(DateTime(2000, month, 1));
  }

  String _toYmd(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  int? _parseHoraMin(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    final parts = value.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return hour * 60 + minute;
  }

  int _ajustarHoraPosterior(int referenciaMin, int candidatoMin) {
    var ajustado = candidatoMin;
    while (ajustado <= referenciaMin && ajustado + (12 * 60) <= (24 * 60)) {
      ajustado += 12 * 60;
    }
    return ajustado;
  }

  String _normalizarDia(String raw) {
    var out = raw.trim().toUpperCase();
    const replacements = {'_': '', '-': '', ' ': ''};
    replacements.forEach((from, to) => out = out.replaceAll(from, to));
    return out;
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

  HorarioConjunto? _horarioDelDia(DateTime dia) {
    for (final horario in _horariosConjunto) {
      if (_weekdayDesdeDiaHorario(horario.dia) == dia.weekday) {
        return horario;
      }
    }
    return null;
  }

  String _formatearDuracionDisponible(Duration duration) {
    final horas = duration.inHours;
    final minutos = duration.inMinutes % 60;
    if (horas <= 0) return '$minutos min disponibles';
    if (minutos == 0) return '$horas h disponibles';
    return '$horas h $minutos min disponibles';
  }

  List<_PreviewAgendaBlock> _bloquesPreviewDia(
    DateTime dia,
    List<TareaModel> tareasDia,
    bool esFestivo,
    bool esFueraDePeriodo,
  ) {
    final bloques = tareasDia
        .map(
          (t) => _PreviewAgendaBlock.task(
            inicio: t.fechaInicio.toLocal(),
            fin: t.fechaFin.toLocal(),
            tarea: t,
          ),
        )
        .toList()
      ..sort((a, b) => a.inicio.compareTo(b.inicio));

    if (esFestivo || esFueraDePeriodo) return bloques;

    final horario = _horarioDelDia(dia);
    if (horario == null) return bloques;

    final aperturaRaw = _parseHoraMin(horario.horaApertura);
    final cierreRaw = _parseHoraMin(horario.horaCierre);
    if (aperturaRaw == null || cierreRaw == null) return bloques;

    final apertura = aperturaRaw;
    final cierre = _ajustarHoraPosterior(aperturaRaw, cierreRaw);
    final descansoInicioRaw = _parseHoraMin(horario.descansoInicio);
    final descansoFinRaw = _parseHoraMin(horario.descansoFin);
    final descansoInicio = descansoInicioRaw == null
        ? null
        : _ajustarHoraPosterior(apertura, descansoInicioRaw);
    final descansoFin = descansoInicio == null || descansoFinRaw == null
        ? null
        : _ajustarHoraPosterior(descansoInicio, descansoFinRaw);

    final segmentos = <(DateTime, DateTime)>[
      (
        DateTime(dia.year, dia.month, dia.day).add(Duration(minutes: apertura)),
        DateTime(dia.year, dia.month, dia.day).add(
          Duration(minutes: descansoInicio ?? cierre),
        ),
      ),
      if (descansoInicio != null && descansoFin != null && descansoFin > descansoInicio)
        (
          DateTime(dia.year, dia.month, dia.day).add(Duration(minutes: descansoFin)),
          DateTime(dia.year, dia.month, dia.day).add(Duration(minutes: cierre)),
        ),
    ];

    for (final segmento in segmentos) {
      final inicio = segmento.$1;
      final fin = segmento.$2;
      if (!fin.isAfter(inicio)) continue;

      final tareasSegmento = tareasDia
          .map(
            (t) => (
              tarea: t,
              inicio: t.fechaInicio.toLocal().isAfter(inicio)
                  ? t.fechaInicio.toLocal()
                  : inicio,
              fin: t.fechaFin.toLocal().isBefore(fin) ? t.fechaFin.toLocal() : fin,
            ),
          )
          .where((item) => item.fin.isAfter(item.inicio))
          .toList()
        ..sort((a, b) => a.inicio.compareTo(b.inicio));

      var cursor = inicio;
      for (final item in tareasSegmento) {
        if (item.inicio.isAfter(cursor)) {
          bloques.add(_PreviewAgendaBlock.gap(inicio: cursor, fin: item.inicio));
        }
        if (item.fin.isAfter(cursor)) {
          cursor = item.fin;
        }
      }
      if (fin.isAfter(cursor)) {
        bloques.add(_PreviewAgendaBlock.gap(inicio: cursor, fin: fin));
      }
    }

    bloques.sort((a, b) => a.inicio.compareTo(b.inicio));
    return bloques;
  }

  List<int> get _aniosDisponibles {
    final years = <int>{DateTime.now().year};
    for (final t in _tareasMes) {
      years.add(t.fechaInicio.toLocal().year);
    }
    final current = DateTime.now().year;
    years.add(current - 1);
    years.add(current + 1);
    final out = years.toList()..sort();
    return out;
  }

  Future<void> _cargarMes() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final desde = DateTime(_anio, _mes, 1);
      final hasta = DateTime(_anio, _mes + 1, 0);
      final results = await Future.wait([
        _cronogramaApi.listarPorConjuntoYMes(
          nit: widget.nit,
          anio: _anio,
          mes: _mes,
        ),
        _festivoApi.listarFestivosRango(desde: desde, hasta: hasta, pais: 'CO'),
      ]);
      final tareas = results[0] as List<TareaModel>;
      final festivos = results[1] as List<FestivoItem>;
      List<HorarioConjunto> horarios = const [];
      try {
        final detalle = await _gerenteApi.obtenerConjunto(widget.nit);
        horarios = detalle.horarios;
        _conjuntoNombre = detalle.nombre.trim();
      } catch (_) {
        try {
          final conjuntos = await _gerenteApi.listarConjuntos();
          for (final conjunto in conjuntos) {
            if (conjunto.nit == widget.nit) {
              horarios = conjunto.horarios;
              _conjuntoNombre = conjunto.nombre.trim();
              break;
            }
          }
        } catch (_) {}
      }

      final operarios = <String>{};
      final festivosYmd = <String>{};
      final festivoNombrePorYmd = <String, String>{};

      for (final t in tareas) {
        for (final name in t.operariosNombres) {
          final clean = name.trim();
          if (clean.isNotEmpty) operarios.add(clean);
        }
      }

      for (final festivo in festivos) {
        final key = _toYmd(festivo.fecha);
        festivosYmd.add(key);
        final nombre = festivo.nombre?.trim() ?? '';
        if (nombre.isNotEmpty) {
          festivoNombrePorYmd[key] = nombre;
        }
      }

      if (!mounted) return;
      final totalSemanasMes = _calcularSemanasDelMes(_anio, _mes).length;
      setState(() {
        _tareasMes = tareas;
        _horariosConjunto = horarios;
        _operariosDisponibles = operarios.toList()..sort();
        _festivosYmd = festivosYmd;
        _festivoNombrePorYmd = festivoNombrePorYmd;
        if (!_operariosDisponibles.contains(_operario)) {
          _operario = 'TODOS';
        }
        if (_semana > totalSemanasMes) {
          _semana = totalSemanasMes;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppError.messageOf(e);
        _loading = false;
      });
    }
  }

  List<TareaModel> get _tareasOperarioMes {
    return _tareasMes.where((t) {
      if (_operario == 'TODOS') return false;
      return t.operariosNombres.map((e) => e.trim()).contains(_operario);
    }).toList();
  }

  List<TareaModel> get _tareasPreviewSemana {
    if (_operario == 'TODOS') return const [];
    final weekStart = _weekStartOfMonthByIndex(_anio, _mes, _semana);
    final weekEnd = weekStart.add(const Duration(days: 6));
    return _tareasOperarioMes.where((t) {
      final d = _dayOnly(t.fechaInicio.toLocal());
      return !d.isBefore(_dayOnly(weekStart)) && !d.isAfter(_dayOnly(weekEnd));
    }).toList()..sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));
  }

  List<DateTime> get _semanasDelMes {
    return _calcularSemanasDelMes(_anio, _mes);
  }

  List<DateTime> _calcularSemanasDelMes(int anio, int mes) {
    final firstDay = DateTime(anio, mes, 1);
    final lastDay = DateTime(anio, mes + 1, 0);
    final firstWeekStart = _startOfWeekMonday(firstDay);
    final semanas = <DateTime>[];

    for (
      var current = firstWeekStart;
      !current.isAfter(lastDay);
      current = current.add(const Duration(days: 7))
    ) {
      semanas.add(current);
    }

    return semanas;
  }

  Future<void> _descargarPdf() async {
    if (_operario == 'TODOS') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un operario para imprimir.')),
      );
      return;
    }

    final tareasImpresion = _alcance == 'MES'
        ? _tareasOperarioMes
        : _tareasPreviewSemana;
    final puedeImprimirHuecosSemana =
        _alcance == 'SEMANA' && _horariosConjunto.isNotEmpty;
    if (tareasImpresion.isEmpty && !puedeImprimirHuecosSemana) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _alcance == 'MES'
                ? 'Ese operario no tiene tareas en el mes seleccionado.'
                : 'Ese operario no tiene tareas en la semana seleccionada.',
          ),
        ),
      );
      return;
    }

    final weekStart = _weekStartOfMonthByIndex(_anio, _mes, _semana);
    final weekEnd = weekStart.add(const Duration(days: 6));
    final conjuntoNombre = tareasImpresion.isNotEmpty
        ? ((tareasImpresion.first.conjuntoNombre ?? '').trim().isNotEmpty
              ? tareasImpresion.first.conjuntoNombre!.trim()
              : _conjuntoNombre)
        : _conjuntoNombre;

    final payload = <String, dynamic>{
      'operarioNombre': _operario,
      'operarioId': '',
      'conjuntoNombre': conjuntoNombre.isEmpty ? widget.nit : conjuntoNombre,
      'anio': _anio,
      'mes': _mes,
      'alcance': _alcance,
      'semanaDelMes': _semana,
      'weekStart': DateFormat('yyyy-MM-dd').format(weekStart),
      'weekEnd': DateFormat('yyyy-MM-dd').format(weekEnd),
      'horariosConjunto': _horariosConjunto
          .map(
            (h) => {
              'dia': h.dia,
              'horaApertura': h.horaApertura,
              'horaCierre': h.horaCierre,
              'descansoInicio': h.descansoInicio,
              'descansoFin': h.descansoFin,
            },
          )
          .toList(),
      'tareas': tareasImpresion
          .map(
            (t) => {
              'fechaInicio': t.fechaInicio.toIso8601String(),
              'fechaFin': t.fechaFin.toIso8601String(),
              'descripcion': t.descripcion,
              'ubicacionNombre': t.ubicacionNombre ?? '',
              'elementoNombre': t.elementoNombre ?? '',
            },
          )
          .toList(),
      'festivos': _festivosYmd.toList(),
      'festivoNombrePorYmd': _festivoNombrePorYmd,
    };

    await imprimirCronogramaOperario(payload);
  }

  Widget _buildFiltros() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selecciona el cronograma a imprimir',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _mes,
                    decoration: const InputDecoration(
                      labelText: 'Mes',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: List.generate(12, (i) => i + 1)
                        .map(
                          (m) => DropdownMenuItem(
                            value: m,
                            child: Text(_nombreMes(m)),
                          ),
                        )
                        .toList(),
                    onChanged: (v) async {
                      setState(() => _mes = v ?? _mes);
                      await _cargarMes();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _anio,
                    decoration: const InputDecoration(
                      labelText: 'Año',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _aniosDisponibles
                        .map(
                          (year) => DropdownMenuItem(
                            value: year,
                            child: Text('$year'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) async {
                      setState(() => _anio = v ?? _anio);
                      await _cargarMes();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _operario,
                    decoration: const InputDecoration(
                      labelText: 'Operario',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'TODOS',
                        child: Text('Selecciona uno'),
                      ),
                      ..._operariosDisponibles.map(
                        (o) => DropdownMenuItem(value: o, child: Text(o)),
                      ),
                    ],
                    onChanged: (v) => setState(() => _operario = v ?? 'TODOS'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _semana,
                    decoration: const InputDecoration(
                      labelText: 'Semana',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _semanasDelMes
                        .asMap()
                        .map(
                          (index, _) => MapEntry(
                            index,
                            DropdownMenuItem(
                              value: index + 1,
                              child: Text('Semana ${index + 1}'),
                            ),
                          ),
                        )
                        .values
                        .toList(),
                    onChanged: _alcance == 'MES'
                        ? null
                        : (v) => setState(() => _semana = v ?? 1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _alcance,
              decoration: const InputDecoration(
                labelText: 'Imprimir',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(
                  value: 'SEMANA',
                  child: Text('Solo la semana seleccionada'),
                ),
                DropdownMenuItem(
                  value: 'MES',
                  child: Text('Todo el mes en un solo PDF'),
                ),
              ],
              onChanged: (v) => setState(() => _alcance = v ?? 'SEMANA'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final tareas = _tareasPreviewSemana;
    final weekStart = _weekStartOfMonthByIndex(_anio, _mes, _semana);
    final dias = List.generate(6, (i) => weekStart.add(Duration(days: i)));

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Previsualización del PDF',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _operario == 'TODOS'
                  ? 'Selecciona un operario para ver el cronograma.'
                  : _alcance == 'MES'
                  ? 'Se imprimirá todo ${_nombreMes(_mes)} de $_anio en un solo PDF.'
                  : 'Semana $_semana de ${_nombreMes(_mes)} de $_anio',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            if (_operario == 'TODOS')
              const Text('Sin operario seleccionado.')
            else if (_alcance == 'MES')
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _semanasDelMes.asMap().entries.map((entry) {
                  final weekIndex = entry.key + 1;
                  final weekStart = entry.value;
                  final weekEnd = weekStart.add(const Duration(days: 6));
                  final totalSemana = _tareasOperarioMes.where((t) {
                    final d = _dayOnly(t.fechaInicio.toLocal());
                    return !d.isBefore(_dayOnly(weekStart)) &&
                        !d.isAfter(_dayOnly(weekEnd));
                  }).length;

                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      'Semana $weekIndex (${DateFormat('dd/MM').format(weekStart)} - ${DateFormat('dd/MM').format(weekEnd)}): $totalSemana tarea(s)',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }).toList(),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final totalWidth = constraints.maxWidth;
                  final spacing = 10.0;
                  final cardWidth = (totalWidth - (spacing * 5)) / 6;

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: dias.asMap().entries.map((entry) {
                      final dia = entry.value;
                      final tareasDia =
                          tareas.where((t) {
                            final d = t.fechaInicio.toLocal();
                            return d.year == dia.year &&
                                d.month == dia.month &&
                                d.day == dia.day;
                          }).toList()..sort(
                            (a, b) => a.fechaInicio.compareTo(b.fechaInicio),
                          );
                      final esFestivo = _festivosYmd.contains(_toYmd(dia));
                      final esFueraDePeriodo =
                          dia.year != _anio || dia.month != _mes;
                      final bloquesDia = _bloquesPreviewDia(
                        dia,
                        tareasDia,
                        esFestivo,
                        esFueraDePeriodo,
                      );

                      return Container(
                        width: cardWidth,
                        margin: EdgeInsets.only(
                          right: entry.key == dias.length - 1 ? 0 : spacing,
                        ),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: esFueraDePeriodo
                              ? const Color(0xFFFFEBEE)
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: esFueraDePeriodo
                                ? const Color(0xFFE53935)
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateFormat('EEEE dd/MM', 'es').format(dia),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (esFueraDePeriodo)
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFCDD2),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFFE53935),
                                  ),
                                ),
                                child: Text(
                                  dia.isBefore(DateTime(_anio, _mes, 1))
                                      ? 'Día del mes anterior'
                                      : 'Día del mes siguiente',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFB71C1C),
                                  ),
                                ),
                              )
                            else if (esFestivo)
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFEBEE),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFFE53935),
                                  ),
                                ),
                                child: Text(
                                  _festivoNombrePorYmd[_toYmd(dia)]?.trim().isNotEmpty == true
                                      ? 'Festivo: ${_festivoNombrePorYmd[_toYmd(dia)]!.trim()}'
                                      : 'Festivo - no se programan tareas',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFB71C1C),
                                  ),
                                ),
                              ),
                            if (bloquesDia.isEmpty)
                              Text(
                                esFestivo ? 'No se programan tareas.' : 'Sin tareas',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              )
                            else
                              ...bloquesDia.map(
                                (bloque) => Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: bloque.isGap
                                        ? const Color(0xFFFFF3E0)
                                        : AppTheme.primary.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: bloque.isGap
                                          ? const Color(0xFFFB8C00)
                                          : AppTheme.primary.withValues(alpha: 0.20),
                                    ),
                                  ),
                                  child: bloque.isGap
                                      ? Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Hueco para correctiva',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFFE65100),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${DateFormat('HH:mm').format(bloque.inicio)} - ${DateFormat('HH:mm').format(bloque.fin)}',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey.shade800,
                                              ),
                                            ),
                                            Text(
                                              _formatearDuracionDisponible(
                                                bloque.fin.difference(bloque.inicio),
                                              ),
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: Color(0xFFBF6000),
                                              ),
                                            ),
                                          ],
                                        )
                                      : Builder(
                                          builder: (context) {
                                            final t = bloque.tarea!;
                                            final ubicacion =
                                                (t.ubicacionNombre ?? '').trim();
                                            final elemento =
                                                (t.elementoNombre ?? '').trim();

                                            return Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  t.descripcion,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  '${DateFormat('HH:mm').format(t.fechaInicio.toLocal())} - ${DateFormat('HH:mm').format(t.fechaFin.toLocal())}',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.grey.shade700,
                                                  ),
                                                ),
                                                if (ubicacion.isNotEmpty)
                                                  Text(
                                                    'Ubicación: $ubicacion',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.grey.shade700,
                                                    ),
                                                  ),
                                                if (elemento.isNotEmpty)
                                                  Text(
                                                    'Elemento: $elemento',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.grey.shade700,
                                                    ),
                                                  ),
                                              ],
                                            );
                                          },
                                        ),
                                ),
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _descargarPdf,
                icon: const Icon(Icons.download),
                label: Text(
                  _alcance == 'MES'
                      ? 'Descargar PDF mensual'
                      : 'Descargar PDF semanal',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: const Text(
          'Imprimir cronograma',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Error: $_error'),
              ),
            )
          : RefreshIndicator(
              onRefresh: _cargarMes,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _buildFiltros(),
                  const SizedBox(height: 12),
                  _buildPreview(),
                ],
              ),
            ),
    );
  }
}
