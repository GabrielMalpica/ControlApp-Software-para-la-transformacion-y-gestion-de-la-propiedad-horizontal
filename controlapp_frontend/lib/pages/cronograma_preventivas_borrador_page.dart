// lib/pages/cronograma_preventivas_borrador_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/conjunto_api.dart';
import 'package:flutter_application_1/api/festivo_api.dart';
import 'package:flutter_application_1/api/preventiva_api.dart';
import 'package:flutter_application_1/model/cronograma_actividad_informe_model.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/model/novedad_cronograma_model.dart';
import 'package:flutter_application_1/model/preventiva_excluida_borrador_model.dart';
import 'package:intl/intl.dart';

import '../api/cronograma_api.dart';
import '../model/tarea_model.dart';
import '../service/app_error.dart';
import '../service/theme.dart';
import '../utils/schedule_utils.dart';

import 'package:flutter_application_1/service/app_feedback.dart';

enum _VistaCronograma { mensual, semanal, informe }

enum _ModoCambioOperario { soloBorrador, tambienDefinicion }

class CronogramaPreventivasBorradorPage extends StatefulWidget {
  final String nit;
  final int anio;
  final int mes;

  const CronogramaPreventivasBorradorPage({
    super.key,
    required this.nit,
    required this.anio,
    required this.mes,
  });

  @override
  State<CronogramaPreventivasBorradorPage> createState() =>
      _CronogramaPreventivasBorradorPageState();
}

class _CronogramaPreventivasBorradorPageState
    extends State<CronogramaPreventivasBorradorPage> {
  final _cronogramaApi = CronogramaApi();
  final _conjuntoApi = ConjuntoApi();
  final _festivoApi = FestivoApi();
  final _preventivaApi = DefinicionPreventivaApi();
  final ScrollController _mensualHCtrl = ScrollController();

  bool _loading = true;
  bool _publicando = false;
  String? _error;
  Set<String> _festivosYmd = {};
  Map<String, String> _festivoNombrePorYmd = {};

  // ✅ ahora mes/año son mutables (para navegación)
  late int _anioActual;
  late int _mesActual; // 1..12

  late int _daysInMonth;
  late DateTime _inicioMes;

  /// Todas las tareas preventivas en borrador de ese mes
  List<TareaModel> _tareasMes = [];
  List<PreventivaExcluidaBorradorModel> _excluidasMes = [];
  List<CronogramaActividadInformeModel> _informeActividad = [];
  List<HorarioConjunto> _horariosConjunto = const [];

  /// Resumen por día (mensual)
  List<_DiaResumen> _diasResumen = [];

  @override
  void dispose() {
    _mensualHCtrl.dispose();
    super.dispose();
  }

  // Vista y semana seleccionada
  _VistaCronograma _vista = _VistaCronograma.mensual;
  late DateTime _semanaBase;

  bool _mostrarFiltrosMensual = false;

  String _filtroTipo = 'TODAS';
  String _filtroEstado = 'TODOS';
  String _filtroOperario = 'TODOS';
  String _filtroUbicacion = 'TODAS';
  String _filtroEquipo = 'TODOS';

  List<String> _operariosDisponibles = [];
  List<String> _ubicacionesDisponibles = [];
  List<String> _equiposDisponibles = [];

  // ✅ Para no mostrar el cuadro de novedades repetido en el mismo periodo
  final Set<String> _novedadesMostradasPorPeriodo = {};
  final Map<String, Map<String, dynamic>> _confirmacionesReemplazoPorCaso = {};

  int _horaInicioJornada = 8;
  int _horaFinJornada = 16;
  int? _horaDescansoInicio;
  int? _horaDescansoFin;
  String _resumenHorario = 'Horario: 08:00 - 16:00';

  @override
  void initState() {
    super.initState();
    _anioActual = widget.anio;
    _mesActual = widget.mes;

    _initMes();
    _semanaBase = DateTime(_anioActual, _mesActual, 1);

    // ✅ Al entrar: generar borrador -> mostrar novedades -> cargar cronograma
    _generarYcargarAlEntrar();
  }

  void _initMes() {
    _inicioMes = DateTime(_anioActual, _mesActual, 1);
    _daysInMonth = DateUtils.getDaysInMonth(_anioActual, _mesActual);
  }

  TimeOfDay? _parseHora(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parts = raw.trim().split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }
    return TimeOfDay(hour: h, minute: m);
  }

  int _toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  String _fmtMinutes(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  void _aplicarHorarioConjunto({
    required List<HorarioConjunto> horarios,
    required List<TareaModel> tareasMes,
  }) {
    int? minApertura;
    int? maxCierre;
    int? minDescanso;
    int? maxDescanso;

    for (final h in horarios) {
      final apertura = _parseHora(h.horaApertura);
      final cierre = _parseHora(h.horaCierre);
      if (apertura == null || cierre == null) continue;

      final aperMin = _toMinutes(apertura);
      final cierMin = _toMinutes(cierre);
      if (cierMin <= aperMin) continue;

      minApertura = minApertura == null
          ? aperMin
          : (aperMin < minApertura ? aperMin : minApertura);
      maxCierre = maxCierre == null
          ? cierMin
          : (cierMin > maxCierre ? cierMin : maxCierre);

      final descansoInicio = _parseHora(h.descansoInicio);
      final descansoFin = _parseHora(h.descansoFin);
      if (descansoInicio == null || descansoFin == null) continue;

      final dIniMin = _toMinutes(descansoInicio);
      final dFinMin = _toMinutes(descansoFin);
      if (dFinMin <= dIniMin) continue;

      minDescanso = minDescanso == null
          ? dIniMin
          : (dIniMin < minDescanso ? dIniMin : minDescanso);
      maxDescanso = maxDescanso == null
          ? dFinMin
          : (dFinMin > maxDescanso ? dFinMin : maxDescanso);
    }

    if (minApertura == null || maxCierre == null) {
      for (final t in tareasMes) {
        final ini = t.fechaInicio.toLocal();
        final fin = t.fechaFin.toLocal();
        final iniMin = ini.hour * 60 + ini.minute;
        final finMin = fin.hour * 60 + fin.minute;
        if (finMin <= iniMin) continue;

        minApertura = minApertura == null
            ? iniMin
            : (iniMin < minApertura ? iniMin : minApertura);
        maxCierre = maxCierre == null
            ? finMin
            : (finMin > maxCierre ? finMin : maxCierre);
      }
    }

    minApertura ??= 8 * 60;
    maxCierre ??= 16 * 60;

    final inicioHora = (minApertura ~/ 60).clamp(0, 23);
    int finHora = ((maxCierre + 59) ~/ 60).clamp(1, 24);
    if (finHora <= inicioHora) {
      finHora = (inicioHora + 1).clamp(1, 24);
    }

    int? descansoInicioHora;
    int? descansoFinHora;
    if (minDescanso != null &&
        maxDescanso != null &&
        maxDescanso > minDescanso) {
      final inicioDesc = (minDescanso ~/ 60).clamp(inicioHora, finHora - 1);
      final finDesc = ((maxDescanso + 59) ~/ 60).clamp(inicioDesc + 1, finHora);
      if (finDesc > inicioDesc) {
        descansoInicioHora = inicioDesc;
        descansoFinHora = finDesc;
      }
    }

    final tieneDescanso =
        minDescanso != null && maxDescanso != null && maxDescanso > minDescanso;

    _horaInicioJornada = inicioHora;
    _horaFinJornada = finHora;
    _horaDescansoInicio = descansoInicioHora;
    _horaDescansoFin = descansoFinHora;
    _resumenHorario = tieneDescanso
        ? 'Horario: ${_fmtMinutes(minApertura)} - ${_fmtMinutes(maxCierre)} (descanso ${_fmtMinutes(minDescanso)}-${_fmtMinutes(maxDescanso)})'
        : 'Horario: ${_fmtMinutes(minApertura)} - ${_fmtMinutes(maxCierre)}';
  }

  HorarioConjunto? _horarioConjuntoParaDia(DateTime day) {
    for (final horario in _horariosConjunto) {
      if (weekdayFromScheduleDay(horario.dia) == day.weekday) {
        return horario;
      }
    }
    return null;
  }

  List<_MinuteRange> _rangosDesdeHorarioConjunto(HorarioConjunto horario) {
    final apertura = parseHourToTimeOfDay(horario.horaApertura);
    final cierre = parseHourToTimeOfDay(horario.horaCierre);
    if (apertura == null || cierre == null) return const [];

    final inicio = timeOfDayToMinutes(apertura);
    final fin = timeOfDayToMinutes(cierre);
    if (fin <= inicio) return const [];

    final descansoInicio = horario.descansoInicio == null
        ? null
        : parseHourToTimeOfDay(horario.descansoInicio);
    final descansoFin = horario.descansoFin == null
        ? null
        : parseHourToTimeOfDay(horario.descansoFin);

    final tieneDescanso =
        descansoInicio != null &&
        descansoFin != null &&
        timeOfDayToMinutes(descansoFin) > timeOfDayToMinutes(descansoInicio) &&
        timeOfDayToMinutes(descansoInicio) > inicio &&
        timeOfDayToMinutes(descansoFin) < fin;

    if (!tieneDescanso) {
      return [_MinuteRange(start: inicio, end: fin)];
    }

    final descansoIniMin = timeOfDayToMinutes(descansoInicio);
    final descansoFinMin = timeOfDayToMinutes(descansoFin);
    final rangos = <_MinuteRange>[];

    if (descansoIniMin > inicio) {
      rangos.add(_MinuteRange(start: inicio, end: descansoIniMin));
    }
    if (descansoFinMin < fin) {
      rangos.add(_MinuteRange(start: descansoFinMin, end: fin));
    }
    return rangos;
  }

  String _toYmd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool _esFestivo(DateTime d) {
    final dl = d.toLocal();
    final key = _toYmd(DateTime(dl.year, dl.month, dl.day));
    return _festivosYmd.contains(key);
  }

  String? _nombreFestivo(DateTime d) {
    final dl = d.toLocal();
    final key = _toYmd(DateTime(dl.year, dl.month, dl.day));
    return _festivoNombrePorYmd[key];
  }

  bool _isSameLocalDay(DateTime a, DateTime b) {
    final al = a.toLocal();
    final bl = b.toLocal();
    return al.year == bl.year && al.month == bl.month && al.day == bl.day;
  }

  bool _isInThisMonth(DateTime d) {
    final dl = d.toLocal();
    return dl.year == _anioActual && dl.month == _mesActual;
  }

  DateTime _startOfWeekMonday(DateTime d) {
    final dd = DateTime(d.year, d.month, d.day);
    final diff = dd.weekday - DateTime.monday; // monday=1
    return dd.subtract(Duration(days: diff));
  }

  DateTime _endOfWeekSunday(DateTime d) {
    final start = _startOfWeekMonday(d);
    return start.add(const Duration(days: 6));
  }

  List<TareaModel> _tareasSemana(DateTime semanaBase) {
    return _tareasFiltradas.where((t) {
      final start = _startOfWeekMonday(semanaBase);
      final end = start.add(const Duration(days: 7));
      final dt = t.fechaInicio.toLocal();
      return !dt.isBefore(start) && dt.isBefore(end);
    }).toList();
  }

  List<TareaModel> get _tareasFiltradas =>
      _tareasMes.where(_pasaFiltros).toList();

  List<PreventivaExcluidaBorradorModel> _excluidasPorFecha(DateTime fecha) {
    return _excluidasMes.where((item) {
      final d = item.fechaObjetivo;
      return d.year == fecha.year &&
          d.month == fecha.month &&
          d.day == fecha.day;
    }).toList();
  }

  bool _esCanceladaPorReemplazo(TareaModel t) {
    final estado = (t.estado ?? '').trim().toUpperCase();
    return estado == 'NO_COMPLETADA' &&
        t.reprogramada == true &&
        t.reprogramadaPorTareaId != null;
  }

  bool _pasaFiltros(TareaModel t) {
    if (_esCanceladaPorReemplazo(t)) return false;

    // Tipo
    if (_filtroTipo != 'TODAS') {
      final tipo = (t.tipo ?? '').toUpperCase();
      if (tipo != _filtroTipo) return false;
    }

    // Estado
    if (_filtroEstado != 'TODOS') {
      if ((t.estado ?? '') != _filtroEstado) return false;
    }

    // Operario
    if (_filtroOperario != 'TODOS') {
      if (!_tareaTieneOperario(t, _filtroOperario)) return false;
    }

    // Ubicación
    if (_filtroUbicacion != 'TODAS') {
      final u = _nombreUbicacion(t) ?? '';
      if (u != _filtroUbicacion) return false;
    }

    if (_filtroEquipo != 'TODOS') {
      final equipo = _equipoOperariosLabel(t);
      if (equipo != _filtroEquipo) {
        return false;
      }
    }

    return true;
  }

  String? _nombreUbicacion(TareaModel t) => t.ubicacionNombre;
  String? _nombreObjeto(TareaModel t) => t.elementoNombre;

  final Set<String> _detalleCamposVisibles = {
    'id',
    'descripcion',
    'estado',
    'tipo',
    'frecuencia',
    'prioridad',
    'fechaInicio',
    'fechaFin',
    'duracion',
    'conjunto',
    'ubicacion',
    'elemento',
    'supervisor',
    'operarios',
    'maquinaria',
    'observaciones',
    'evidencias',
    'insumos',
  };

  static const Map<String, String> _detalleCamposLabels = {
    'id': 'ID',
    'descripcion': 'Descripcion',
    'estado': 'Estado',
    'tipo': 'Tipo',
    'frecuencia': 'Frecuencia',
    'prioridad': 'Prioridad',
    'fechaInicio': 'Fecha inicio',
    'fechaFin': 'Fecha fin',
    'duracion': 'Duracion',
    'conjunto': 'Conjunto',
    'ubicacion': 'Ubicacion',
    'elemento': 'Elemento',
    'supervisor': 'Supervisor',
    'operarios': 'Operarios',
    'maquinaria': 'Maquinaria',
    'observaciones': 'Observaciones',
    'evidencias': 'Evidencias',
    'insumos': 'Insumos usados',
  };

  List<String> _nombresOperarios(TareaModel t) => t.operariosNombres;

  String _labelPrioridad(int prioridad) {
    switch (prioridad) {
      case 1:
        return 'Prioridad alta';
      case 2:
        return 'Prioridad media';
      case 3:
        return 'Prioridad baja';
      default:
        return 'Prioridad $prioridad';
    }
  }

  String? _equipoOperariosLabel(TareaModel t) {
    final operarios =
        t.operariosNombres
            .map((name) => name.trim())
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (operarios.length < 2) return null;
    return operarios.join(' + ');
  }

  Future<void> _configurarCamposDetalle(VoidCallback refreshSheet) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(12),
                children: [
                  const Text(
                    'Selecciona la informacion a mostrar',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  ..._detalleCamposLabels.entries.map((entry) {
                    final activo = _detalleCamposVisibles.contains(entry.key);
                    return CheckboxListTile(
                      value: activo,
                      title: Text(entry.value),
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _detalleCamposVisibles.add(entry.key);
                          } else {
                            _detalleCamposVisibles.remove(entry.key);
                          }
                        });
                        setModalState(() {});
                        refreshSheet();
                      },
                    );
                  }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  bool _tareaTieneOperario(TareaModel t, String nombreOperario) {
    return _nombresOperarios(t).contains(nombreOperario);
  }

  DateTime _ensureEndAfterStart(DateTime start, DateTime end) {
    if (end.isAfter(start)) return end;
    return start.add(const Duration(minutes: 30));
  }

  List<_MinuteRange> _rangosDisponiblesDia(DateTime day) {
    final fecha = DateTime(day.year, day.month, day.day);
    if (_esFestivo(fecha)) return const [];

    final horarioDia = _horarioConjuntoParaDia(fecha);
    if (horarioDia != null) {
      return _rangosDesdeHorarioConjunto(horarioDia);
    }

    if (fecha.weekday == DateTime.sunday) return const [];

    final inicio = _horaInicioJornada * 60;
    final fin = _horaFinJornada * 60;
    if (fin <= inicio) return const [];

    final tieneDescanso =
        _horaDescansoInicio != null &&
        _horaDescansoFin != null &&
        _horaDescansoFin! > _horaDescansoInicio!;

    if (!tieneDescanso) {
      return [_MinuteRange(start: inicio, end: fin)];
    }

    final descansoInicio = _horaDescansoInicio! * 60;
    final descansoFin = _horaDescansoFin! * 60;
    final rangos = <_MinuteRange>[];

    if (descansoInicio > inicio) {
      rangos.add(_MinuteRange(start: inicio, end: descansoInicio));
    }
    if (descansoFin < fin) {
      rangos.add(_MinuteRange(start: descansoFin, end: fin));
    }
    return rangos;
  }

  List<_MinuteRange> _mergeMinuteRanges(List<_MinuteRange> ranges) {
    if (ranges.isEmpty) return const [];
    final sorted = [...ranges]..sort((a, b) => a.start.compareTo(b.start));
    final merged = <_MinuteRange>[sorted.first];

    for (final range in sorted.skip(1)) {
      final last = merged.last;
      if (range.start <= last.end) {
        merged[merged.length - 1] = _MinuteRange(
          start: last.start,
          end: range.end > last.end ? range.end : last.end,
        );
      } else {
        merged.add(range);
      }
    }
    return merged;
  }

  _SemanaHorasResumen _calcularResumenHorasSemana(
    DateTime weekStart,
    List<TareaModel> tareas,
  ) {
    var disponiblesMin = 0;
    var ocupadasMin = 0;

    for (int i = 0; i < 7; i++) {
      final day = DateTime(
        weekStart.year,
        weekStart.month,
        weekStart.day,
      ).add(Duration(days: i));
      final rangosDisponibles = _rangosDisponiblesDia(day);
      if (rangosDisponibles.isEmpty) continue;

      for (final rango in rangosDisponibles) {
        disponiblesMin += rango.end - rango.start;
      }

      final dayStart = DateTime(day.year, day.month, day.day);
      final dayEnd = dayStart.add(const Duration(days: 1));
      final rangosOcupados = <_MinuteRange>[];

      for (final t in tareas) {
        final inicioOriginal = t.fechaInicio.toLocal();
        final finOriginal = _ensureEndAfterStart(
          inicioOriginal,
          t.fechaFin.toLocal(),
        );
        if (!finOriginal.isAfter(dayStart) ||
            !inicioOriginal.isBefore(dayEnd)) {
          continue;
        }

        final inicioDia = inicioOriginal.isBefore(dayStart)
            ? dayStart
            : inicioOriginal;
        final finDia = finOriginal.isAfter(dayEnd) ? dayEnd : finOriginal;
        final inicioMin = inicioDia.hour * 60 + inicioDia.minute;
        final finMin = finDia.hour * 60 + finDia.minute;

        for (final rango in rangosDisponibles) {
          final inicioClip = inicioMin > rango.start ? inicioMin : rango.start;
          final finClip = finMin < rango.end ? finMin : rango.end;
          if (finClip > inicioClip) {
            rangosOcupados.add(_MinuteRange(start: inicioClip, end: finClip));
          }
        }
      }

      for (final rango in _mergeMinuteRanges(rangosOcupados)) {
        ocupadasMin += rango.end - rango.start;
      }
    }

    return _SemanaHorasResumen(
      disponiblesMin: disponiblesMin,
      ocupadasMin: ocupadasMin,
    );
  }

  List<_OperarioSemanaResumen> _calcularResumenHorasSemanaPorOperario(
    DateTime weekStart,
    List<TareaModel> tareas,
  ) {
    var disponiblesMin = 0;
    final ocupadasPorOperario = <String, int>{};

    for (int i = 0; i < 7; i++) {
      final day = DateTime(
        weekStart.year,
        weekStart.month,
        weekStart.day,
      ).add(Duration(days: i));
      final rangosDisponibles = _rangosDisponiblesDia(day);
      if (rangosDisponibles.isEmpty) continue;

      for (final rango in rangosDisponibles) {
        disponiblesMin += rango.end - rango.start;
      }

      final dayStart = DateTime(day.year, day.month, day.day);
      final dayEnd = dayStart.add(const Duration(days: 1));
      final rangosPorOperario = <String, List<_MinuteRange>>{};

      for (final t in tareas) {
        final operarios = t.operariosNombres
            .map((name) => name.trim())
            .where((name) => name.isNotEmpty)
            .toSet();
        if (operarios.isEmpty) continue;

        final inicioOriginal = t.fechaInicio.toLocal();
        final finOriginal = _ensureEndAfterStart(
          inicioOriginal,
          t.fechaFin.toLocal(),
        );
        if (!finOriginal.isAfter(dayStart) ||
            !inicioOriginal.isBefore(dayEnd)) {
          continue;
        }

        final inicioDia = inicioOriginal.isBefore(dayStart)
            ? dayStart
            : inicioOriginal;
        final finDia = finOriginal.isAfter(dayEnd) ? dayEnd : finOriginal;
        final inicioMin = inicioDia.hour * 60 + inicioDia.minute;
        final finMin = finDia.hour * 60 + finDia.minute;

        for (final rango in rangosDisponibles) {
          final inicioClip = inicioMin > rango.start ? inicioMin : rango.start;
          final finClip = finMin < rango.end ? finMin : rango.end;
          if (finClip <= inicioClip) continue;

          for (final operario in operarios) {
            rangosPorOperario
                .putIfAbsent(operario, () => <_MinuteRange>[])
                .add(_MinuteRange(start: inicioClip, end: finClip));
          }
        }
      }

      for (final entry in rangosPorOperario.entries) {
        final ocupadasDia = _mergeMinuteRanges(
          entry.value,
        ).fold<int>(0, (acc, rango) => acc + (rango.end - rango.start));
        ocupadasPorOperario.update(
          entry.key,
          (actual) => actual + ocupadasDia,
          ifAbsent: () => ocupadasDia,
        );
      }
    }

    final lista = ocupadasPorOperario.entries
        .map(
          (entry) => _OperarioSemanaResumen(
            nombre: entry.key,
            disponiblesMin: disponiblesMin,
            ocupadasMin: entry.value,
          ),
        )
        .toList();

    lista.sort((a, b) {
      final byBusy = b.ocupadasMin.compareTo(a.ocupadasMin);
      if (byBusy != 0) return byBusy;
      return a.nombre.compareTo(b.nombre);
    });
    return lista;
  }

  Widget _buildResumenHorasSemanaCard(
    _SemanaHorasResumen resumen,
    List<_OperarioSemanaResumen> operarios,
  ) {
    final porcentaje = resumen.porcentajeOcupacion.clamp(0, 1).toDouble();

    Color colorPorUso(double value) {
      if (value >= 0.8) return Colors.green.shade500;
      if (value >= 0.4) return Colors.orange.shade500;
      return Colors.red.shade400;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Horas semanales por operario',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${resumen.ocupadasHorasLabel} ocupadas de ${resumen.disponiblesHorasLabel} disponibles',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade800,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 9,
              value: porcentaje,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                colorPorUso(porcentaje),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Libres: ${resumen.libresHorasLabel} • Ocupación: ${resumen.porcentajeTexto}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          if (operarios.isEmpty)
            Text(
              'No hay operarios con horas asignadas en esta semana.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            )
          else
            Column(
              children: [
                for (int index = 0; index < operarios.length; index++) ...[
                  if (index > 0) const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final item = operarios[index];
                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.nombre,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  item.porcentajeTexto,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${item.ocupadasHorasLabel} / ${item.disponiblesHorasLabel}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                minHeight: 7,
                                value: item.porcentajeOcupacion
                                    .clamp(0, 1)
                                    .toDouble(),
                                backgroundColor: Colors.grey.shade200,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  colorPorUso(item.porcentajeOcupacion),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  void _reconstruirFiltrosDisponibles() {
    final ops = <String>{};
    final ubis = <String>{};
    final equipos = <String>{};

    for (final t in _tareasMes) {
      if (_esCanceladaPorReemplazo(t)) continue;

      final u = _nombreUbicacion(t);
      if (u != null && u.trim().isNotEmpty) ubis.add(u.trim());

      for (final op in _nombresOperarios(t)) {
        final n = op.trim();
        if (n.isNotEmpty) ops.add(n);
      }

      final equipo = _equipoOperariosLabel(t);
      if (equipo != null) equipos.add(equipo);
    }

    _operariosDisponibles = ops.toList()..sort();
    _ubicacionesDisponibles = ubis.toList()..sort();
    _equiposDisponibles = equipos.toList()..sort();
    if (_equiposDisponibles.isEmpty ||
        (_filtroEquipo != 'TODOS' &&
            !_equiposDisponibles.contains(_filtroEquipo))) {
      _filtroEquipo = 'TODOS';
    }
  }

  void _aplicarFiltrosYRefrescar() {
    _recalcularResumenDias(); // si lo usas
    setState(() {});
  }

  void _limpiarFiltros() {
    setState(() {
      _filtroTipo = 'TODAS';
      _filtroEstado = 'TODOS';
      _filtroOperario = 'TODOS';
      _filtroUbicacion = 'TODAS';
      _filtroEquipo = 'TODOS';
    });
    _aplicarFiltrosYRefrescar();
  }

  Future<void> _cambiarMes(int delta) async {
    int nuevoMes = _mesActual + delta;
    int nuevoAnio = _anioActual;

    if (nuevoMes == 13) {
      nuevoMes = 1;
      nuevoAnio++;
    } else if (nuevoMes == 0) {
      nuevoMes = 12;
      nuevoAnio--;
    }

    setState(() {
      _anioActual = nuevoAnio;
      _mesActual = nuevoMes;
      _initMes();
      _semanaBase = DateTime(_anioActual, _mesActual, 1);
    });
    _confirmacionesReemplazoPorCaso.clear();

    // ✅ al cambiar mes: generar + novedades + cargar
    await _generarYcargarAlEntrar();
  }

  /// ==============================
  /// NUEVO: Generar borrador y mostrar "novedades"
  /// (para que el cliente no quede a ciegas)
  /// ==============================
  Future<void> _generarYcargarAlEntrar() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final periodoKey =
          '${_anioActual.toString().padLeft(4, '0')}-${_mesActual.toString().padLeft(2, '0')}';

      // 1) Generar borrador (backend debería devolver {creadas, novedades})
      //    OJO: este método debe existir en tu CronogramaApi
      //    Si ya tienes otro nombre, cámbialo aquí.
      final gen = await _preventivaApi.generarCronogramaMensual(
        nit: widget.nit,
        anio: _anioActual,
        mes: _mesActual,
        confirmacionesReemplazo: _confirmacionesPeriodoActual(),
        // tamanoBloqueMinutos: 60,
      );

      final creadas = int.tryParse('${gen['creadas'] ?? 0}') ?? 0;
      final novedades = _parseNovedadesGeneracion(gen);

      // 2) Cargar cronograma (como antes)
      await _cargarDatos(); // deja _loading en false al final

      // 3) Mostrar novedades:
      // - Si hay novedades, SIEMPRE mostrar (aunque ya se haya abierto antes en el periodo).
      // - Si no hay novedades, mostrar solo 1 vez por periodo para no molestar.
      final debeMostrarModal =
          novedades.isNotEmpty ||
          !_novedadesMostradasPorPeriodo.contains(periodoKey);

      if (mounted && debeMostrarModal) {
        _novedadesMostradasPorPeriodo.add(periodoKey);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _mostrarModalNovedades(creadas: creadas, novedades: novedades);
        });
      }
    } catch (e) {
      setState(() {
        _error = AppError.messageOf(e);
        _loading = false;
      });
    }
  }

  String get _periodoKeyActual =>
      '${_anioActual.toString().padLeft(4, '0')}-${_mesActual.toString().padLeft(2, '0')}';

  String _decisionKeyFromNovedad(NovedadCronogramaModel n) {
    final defId = n.defId ?? 0;
    final fecha = (n.fecha ?? '').trim();
    final prioridadSolicitante = n.prioridad ?? 0;
    final prioridadObjetivo = n.prioridadObjetivo ?? 0;
    return '$_periodoKeyActual|$defId|$fecha|$prioridadSolicitante|$prioridadObjetivo';
  }

  List<Map<String, dynamic>> _confirmacionesPeriodoActual() {
    final prefix = '$_periodoKeyActual|';
    return _confirmacionesReemplazoPorCaso.entries
        .where((e) => e.key.startsWith(prefix))
        .map((e) => Map<String, dynamic>.from(e.value))
        .toList();
  }

  List<NovedadCronogramaModel> _parseNovedadesGeneracion(
    Map<String, dynamic> gen,
  ) {
    final rawNovedades = gen['novedades'];
    final rawNovedadesList = (rawNovedades is List)
        ? rawNovedades
        : (rawNovedades is Map && rawNovedades['items'] is List)
        ? (rawNovedades['items'] as List)
        : const [];

    final novedades = <NovedadCronogramaModel>[];
    for (final e in rawNovedadesList) {
      if (e is! Map) continue;
      final map = <String, dynamic>{};
      e.forEach((k, v) => map['$k'] = v);
      novedades.add(NovedadCronogramaModel.fromJson(map));
    }
    return novedades;
  }

  Map<String, dynamic> _buildPayloadDecision(
    NovedadCronogramaModel n, {
    required bool aceptar,
    bool? reprogramarReemplazada,
  }) {
    final candidataSugerida = n.candidatasIds.isNotEmpty
        ? n.candidatasIds.first
        : null;
    return {
      'defId': n.defId,
      'fecha': n.fecha,
      'prioridadSolicitante': n.prioridad,
      'prioridadObjetivo': n.prioridadObjetivo,
      'aceptar': aceptar,
      if (aceptar && reprogramarReemplazada != null)
        'reprogramarReemplazada': reprogramarReemplazada,
      if (aceptar && candidataSugerida != null)
        'candidataId': candidataSugerida,
    };
  }

  Future<List<NovedadCronogramaModel>> _resolverDecisionReemplazoNovedad({
    required NovedadCronogramaModel novedad,
    required bool aceptar,
    bool? reprogramarReemplazada,
  }) async {
    if (novedad.tipo != 'REQUIERE_CONFIRMACION_REEMPLAZO') return const [];
    if (novedad.defId == null ||
        novedad.fecha == null ||
        novedad.prioridad == null ||
        novedad.prioridadObjetivo == null) {
      throw Exception(
        'La novedad no trae datos suficientes para confirmar reemplazo.',
      );
    }

    final key = _decisionKeyFromNovedad(novedad);
    _confirmacionesReemplazoPorCaso[key] = _buildPayloadDecision(
      novedad,
      aceptar: aceptar,
      reprogramarReemplazada: reprogramarReemplazada,
    );

    final gen = await _preventivaApi.generarCronogramaMensual(
      nit: widget.nit,
      anio: _anioActual,
      mes: _mesActual,
      confirmacionesReemplazo: _confirmacionesPeriodoActual(),
    );

    final novedades = _parseNovedadesGeneracion(gen);
    await _cargarDatos();
    return novedades;
  }

  Future<void> _mostrarModalNovedades({
    required int creadas,
    required List<NovedadCronogramaModel> novedades,
  }) async {
    final mesNombre = DateFormat.MMMM(
      'es',
    ).format(DateTime(_anioActual, _mesActual, 1));
    final titulo = 'Novedades del borrador ($mesNombre $_anioActual)';
    final subtitulo = 'Tareas creadas: $creadas';

    IconData iconForType(String tipo) {
      switch (tipo) {
        case 'FESTIVO_MOVIDO':
          return Icons.event_busy;
        case 'FESTIVO_OMITIDO':
          return Icons.event_busy;
        case 'REEMPLAZO_PRIORIDAD':
          return Icons.swap_horiz;
        case 'REQUIERE_CONFIRMACION_REEMPLAZO':
          return Icons.help_outline;
        case 'SIN_CANDIDATAS':
          return Icons.warning_amber_rounded;
        case 'SIN_HUECO':
          return Icons.schedule;
        default:
          return Icons.info_outline;
      }
    }

    Color colorForType(String tipo) {
      switch (tipo) {
        case 'FESTIVO_MOVIDO':
          return Colors.red.shade700;
        case 'FESTIVO_OMITIDO':
          return Colors.red.shade700;
        case 'REEMPLAZO_PRIORIDAD':
          return Colors.indigo.shade700;
        case 'REQUIERE_CONFIRMACION_REEMPLAZO':
          return Colors.blueGrey.shade700;
        case 'SIN_CANDIDATAS':
          return Colors.orange.shade800;
        case 'SIN_HUECO':
          return Colors.deepOrange.shade800;
        default:
          return Colors.grey.shade800;
      }
    }

    String idsLabel(List<int> ids) {
      if (ids.isEmpty) return 'ninguna';
      return ids.map((id) => '#$id').join(', ');
    }

    String reglaPrioridad(int? prioridad) {
      if (prioridad == 1) {
        return 'Regla: prioridad 1 reemplaza automaticamente prioridad 3. '
            'Para prioridad 2 se pide confirmacion.';
      }
      if (prioridad == 2) {
        return 'Regla: prioridad 2 no reemplaza de forma automatica. '
            'Si hay candidatas prioridad 3, se solicita confirmacion.';
      }
      return 'Regla: prioridad 3 no reemplaza tareas.';
    }

    String fechaLabel(NovedadCronogramaModel n) {
      return n.fecha ?? n.fechaOriginal ?? n.fechaNueva ?? '-';
    }

    String detalleReemplazo(NovedadCronogramaModel n) {
      if (n.reprogramadasIds.isNotEmpty && n.nuevaTareaIds.isNotEmpty) {
        final nuevasRef = idsLabel(n.nuevaTareaIds);
        return n.reprogramadasIds
            .map(
              (oldId) =>
                  'La preventiva #$oldId fue reemplazada por la tarea $nuevasRef.',
            )
            .join('\n');
      }
      if (n.reprogramadasIds.isNotEmpty) {
        return 'Preventivas afectadas: ${idsLabel(n.reprogramadasIds)}.';
      }
      if (n.nuevaTareaIds.isNotEmpty) {
        return 'Tareas creadas por reemplazo: ${idsLabel(n.nuevaTareaIds)}.';
      }
      return 'No llegaron IDs de reemplazo en esta novedad.';
    }

    String titleForNovedad(NovedadCronogramaModel n) {
      switch (n.tipo) {
        case 'FESTIVO_MOVIDO':
          return 'Movida por fecha no laborable';
        case 'FESTIVO_OMITIDO':
          return 'Omitida por fecha no laborable';
        case 'REEMPLAZO_PRIORIDAD':
          return 'Reemplazo aplicado';
        case 'REQUIERE_CONFIRMACION_REEMPLAZO':
          return 'Reemplazo pendiente de decision';
        case 'SIN_CANDIDATAS':
          return 'Sin candidatas para reemplazo';
        case 'SIN_HUECO':
          return 'Sin hueco en agenda';
        default:
          final tipoTxt = n.tipo.replaceAll('_', ' ').trim();
          if (tipoTxt.isEmpty || tipoTxt == 'OTRO') {
            return 'Novedad registrada';
          }
          return 'Novedad registrada ($tipoTxt)';
      }
    }

    String bodyForNovedad(NovedadCronogramaModel n) {
      final desc = (n.descripcion ?? 'Sin descripcion').trim();
      final pr = n.prioridad != null ? 'Prioridad: P${n.prioridad}' : '';
      final fecha = fechaLabel(n);

      if (n.tipo == 'FESTIVO_MOVIDO') {
        DateTime? parseYmd(String? ymd) {
          if (ymd == null || ymd.trim().isEmpty) return null;
          try {
            return DateTime.parse(ymd.trim());
          } catch (_) {
            return null;
          }
        }

        final fO = parseYmd(n.fechaOriginal);
        final fN = parseYmd(n.fechaNueva);
        final movidaSiguienteDia =
            fO != null && fN != null && fN.difference(fO).inDays == 1;
        final motivo = movidaSiguienteDia
            ? 'Se movio al siguiente dia porque la fecha original no era laborable.'
            : 'Se reprogramo porque la fecha original no era laborable.';
        return '$desc\n$pr\n$motivo\n${n.fechaOriginal ?? '-'} -> ${n.fechaNueva ?? '-'}';
      }

      if (n.tipo == 'FESTIVO_OMITIDO') {
        return '$desc\n$pr\nNo se programo la tarea por fecha no laborable.\nFecha: $fecha';
      }

      if (n.tipo == 'REEMPLAZO_PRIORIDAD') {
        final detalle = detalleReemplazo(n);
        final extra = (n.mensaje ?? '').trim();
        return '$desc\n$pr\nFecha: $fecha\n$detalle'
            '${extra.isEmpty ? '' : '\n$extra'}\n'
            'Este reemplazo queda reflejado en el informe y en el estado final de la preventiva desplazada.';
      }

      if (n.tipo == 'REQUIERE_CONFIRMACION_REEMPLAZO') {
        final candTxt = n.candidatasIds.isEmpty
            ? 'No se reportaron candidatas en backend.'
            : 'Candidatas: ${idsLabel(n.candidatasIds)}.';
        final prObjTxt = n.prioridadObjetivo != null
            ? 'Prioridad objetivo a confirmar: P${n.prioridadObjetivo}.'
            : '';
        final msg = (n.mensaje ?? '').trim();
        return '$desc\n$pr\nFecha: $fecha\n'
            'Aun no se reemplazo ninguna tarea: se requiere decision manual.\n'
            '$candTxt\n'
            '${reglaPrioridad(n.prioridad)}'
            '${prObjTxt.isEmpty ? '' : '\n$prObjTxt'}'
            '${msg.isEmpty ? '' : '\n$msg'}';
      }

      if (n.tipo == 'SIN_CANDIDATAS') {
        final extra = (n.mensaje ?? '').trim();
        return '$desc\n$pr\nFecha: $fecha\n'
            'No se encontro una tarea candidata para reemplazar, por eso no hubo reemplazo.\n'
            '${reglaPrioridad(n.prioridad)}\n'
            'La novedad queda registrada en el informe.'
            '${extra.isEmpty ? '' : '\n$extra'}';
      }

      if (n.tipo == 'SIN_HUECO') {
        final extra = (n.mensaje ?? '').trim();
        return '$desc\n$pr\nFecha: $fecha\n'
            'No se encontro hueco en agenda y no se ejecuto reemplazo.\n'
            '${reglaPrioridad(n.prioridad)}'
            '${extra.isEmpty ? '' : '\n$extra'}';
      }

      final msg = (n.mensaje ?? '').trim();
      final detalle =
          (n.nuevaTareaIds.isNotEmpty || n.reprogramadasIds.isNotEmpty)
          ? detalleReemplazo(n)
          : 'No hubo reemplazo ejecutado en esta novedad.';
      return '$desc\n$pr\nFecha: $fecha\n'
          '${msg.isEmpty ? 'Novedad no clasificada por el backend.' : msg}\n'
          '$detalle\n'
          'Consulta el informe para trazabilidad completa.';
    }

    String keyNovedad(NovedadCronogramaModel n) {
      return '${n.tipo}|${n.defId ?? 0}|${n.fecha ?? ''}|${n.prioridad ?? 0}|${n.prioridadObjetivo ?? 0}';
    }

    String textoPreguntaReemplazo(NovedadCronogramaModel n) {
      final objetivo = n.prioridadObjetivo != null
          ? 'P${n.prioridadObjetivo}'
          : 'prioridad inferior';
      final candidata = n.candidatasIds.isNotEmpty
          ? '#${n.candidatasIds.first}'
          : 'la candidata sugerida';
      if (n.prioridadObjetivo == 1) {
        return 'Advertencia: la candidata sugerida es $candidata (P1). ¿Desea reemplazar esta tarea?';
      }
      return '¿Desea reemplazar esta tarea por $candidata ($objetivo) en la fecha objetivo?';
    }

    Future<bool?> preguntarReprogramacionReemplazada(BuildContext ctx) {
      return showDialog<bool>(
        context: ctx,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Preventiva reemplazada'),
          content: const Text(
            'La preventiva reemplazada puede quedar pendiente de reprogramacion o marcarse como no completada por reemplazo. ¿Desea dejarla pendiente para reprogramarla despues?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('No, dejar no completada'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Si, reprogramar despues'),
            ),
          ],
        ),
      );
    }

    Future<Map<String, dynamic>?> elegirHuecoReprogramacion(
      BuildContext ctx,
      int tareaId,
    ) async {
      final data = await _preventivaApi.listarOpcionesReprogramacionBorrador(
        nit: widget.nit,
        tareaId: tareaId,
      );
      if (!ctx.mounted) return null;
      final opciones = (data['opciones'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (opciones.isEmpty) return null;

      return showDialog<Map<String, dynamic>>(
        context: ctx,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Elegir hueco para reprogramar'),
          content: SizedBox(
            width: 420,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: opciones.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final item = opciones[index];
                final inicio = DateTime.tryParse(
                  item['fechaInicio'].toString(),
                );
                final fin = DateTime.tryParse(item['fechaFin'].toString());
                final label = inicio != null && fin != null
                    ? '${DateFormat('dd/MM/yyyy HH:mm').format(inicio)} - ${DateFormat('HH:mm').format(fin)}'
                    : item.toString();
                return ListTile(
                  title: Text(label),
                  subtitle: Text('Duracion: ${item['duracionMinutos']} min'),
                  onTap: () => Navigator.pop(dialogContext, item),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      );
    }

    var novedadesActuales = List<NovedadCronogramaModel>.from(novedades);
    final enProceso = <String>{};

    await showDialog<void>(
      context: context,
      barrierDismissible: false, // ✅ solo cierra con Aceptar
      builder: (ctx) {
        final w = MediaQuery.of(ctx).size.width;
        final h = MediaQuery.of(ctx).size.height;
        final dialogW = (w * 0.92).clamp(320.0, 900.0);
        final dialogH = (h * 0.76).clamp(360.0, 820.0);
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 18,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: SizedBox(
                width: dialogW,
                height: dialogH,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitulo,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Text(
                          novedadesActuales.isEmpty
                              ? 'No hubo novedades. El borrador se generó sin mover tareas por fechas no laborables y sin reemplazos por prioridad.'
                              : 'Estas son las novedades detectadas al generar el borrador (movimientos por fechas no laborables, reemplazos por prioridad y/o casos sin hueco).',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: novedadesActuales.isEmpty
                            ? Center(
                                child: Text(
                                  '✅ Sin novedades',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.green.shade700,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: novedadesActuales.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, i) {
                                  final n = novedadesActuales[i];
                                  final c = colorForType(n.tipo);
                                  final key = keyNovedad(n);
                                  final procesando = enProceso.contains(key);
                                  return Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.03,
                                          ),
                                          blurRadius: 10,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 38,
                                          height: 38,
                                          decoration: BoxDecoration(
                                            color: c.withValues(alpha: 0.10),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Icon(
                                            iconForType(n.tipo),
                                            color: c,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                titleForNovedad(n),
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                bodyForNovedad(n),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  height: 1.25,
                                                  color: Colors.grey.shade800,
                                                ),
                                              ),
                                              if (n.tipo ==
                                                  'REQUIERE_CONFIRMACION_REEMPLAZO') ...[
                                                const SizedBox(height: 10),
                                                Container(
                                                  width: double.infinity,
                                                  padding: const EdgeInsets.all(
                                                    10,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: c.withValues(
                                                      alpha: 0.08,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                    border: Border.all(
                                                      color: c.withValues(
                                                        alpha: 0.24,
                                                      ),
                                                    ),
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        textoPreguntaReemplazo(
                                                          n,
                                                        ),
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      Wrap(
                                                        spacing: 8,
                                                        runSpacing: 8,
                                                        children: [
                                                          OutlinedButton(
                                                            onPressed:
                                                                procesando
                                                                ? null
                                                                : () async {
                                                                    setModalState(
                                                                      () => enProceso
                                                                          .add(
                                                                            key,
                                                                          ),
                                                                    );
                                                                    try {
                                                                      final nuevas = await _resolverDecisionReemplazoNovedad(
                                                                        novedad:
                                                                            n,
                                                                        aceptar:
                                                                            false,
                                                                      );
                                                                      if (!ctx
                                                                          .mounted) {
                                                                        return;
                                                                      }
                                                                      setModalState(() {
                                                                        novedadesActuales =
                                                                            nuevas;
                                                                        enProceso
                                                                            .remove(
                                                                              key,
                                                                            );
                                                                      });
                                                                    } catch (
                                                                      e
                                                                    ) {
                                                                      if (!ctx
                                                                          .mounted) {
                                                                        return;
                                                                      }
                                                                      setModalState(
                                                                        () => enProceso
                                                                            .remove(
                                                                              key,
                                                                            ),
                                                                      );
                                                                      AppFeedback.showFromSnackBar(
                                                                        ctx,
                                                                        SnackBar(
                                                                          content: Text(
                                                                            'No se pudo registrar la decision: $e',
                                                                          ),
                                                                          backgroundColor:
                                                                              Colors.red,
                                                                        ),
                                                                      );
                                                                    }
                                                                  },
                                                            child: const Text(
                                                              'No reemplazar',
                                                            ),
                                                          ),
                                                          ElevatedButton(
                                                            onPressed:
                                                                procesando
                                                                ? null
                                                                : () async {
                                                                    final reprogramar =
                                                                        await preguntarReprogramacionReemplazada(
                                                                          ctx,
                                                                        );
                                                                    if (reprogramar ==
                                                                        null) {
                                                                      return;
                                                                    }
                                                                    setModalState(
                                                                      () => enProceso
                                                                          .add(
                                                                            key,
                                                                          ),
                                                                    );
                                                                    try {
                                                                      final nuevas = await _resolverDecisionReemplazoNovedad(
                                                                        novedad:
                                                                            n,
                                                                        aceptar:
                                                                            true,
                                                                        reprogramarReemplazada:
                                                                            reprogramar,
                                                                      );
                                                                      if (reprogramar) {
                                                                        final reemplazo = nuevas.firstWhere(
                                                                          (x) =>
                                                                              x.tipo ==
                                                                                  'REEMPLAZO_PRIORIDAD' &&
                                                                              x.reprogramadasIds.isNotEmpty,
                                                                          orElse: () => NovedadCronogramaModel(
                                                                            tipo:
                                                                                'OTRO',
                                                                          ),
                                                                        );
                                                                        final tareaId =
                                                                            reemplazo.reprogramadasIds.isNotEmpty
                                                                            ? reemplazo.reprogramadasIds.first
                                                                            : null;
                                                                        if (tareaId !=
                                                                                null &&
                                                                            ctx.mounted) {
                                                                          final hueco = await elegirHuecoReprogramacion(
                                                                            ctx,
                                                                            tareaId,
                                                                          );
                                                                          if (hueco !=
                                                                              null) {
                                                                            final fi = DateTime.parse(
                                                                              hueco['fechaInicio'].toString(),
                                                                            );
                                                                            final ff = DateTime.parse(
                                                                              hueco['fechaFin'].toString(),
                                                                            );
                                                                            await _preventivaApi.editarBloqueBorrador(
                                                                              nit: widget.nit,
                                                                              tareaId: tareaId,
                                                                              fechaInicio: fi,
                                                                              fechaFin: ff,
                                                                            );
                                                                            await _cargarDatos();
                                                                          }
                                                                        }
                                                                      }
                                                                      if (!ctx
                                                                          .mounted) {
                                                                        return;
                                                                      }
                                                                      setModalState(() {
                                                                        novedadesActuales =
                                                                            nuevas;
                                                                        enProceso
                                                                            .remove(
                                                                              key,
                                                                            );
                                                                      });
                                                                    } catch (
                                                                      e
                                                                    ) {
                                                                      if (!ctx
                                                                          .mounted) {
                                                                        return;
                                                                      }
                                                                      setModalState(
                                                                        () => enProceso
                                                                            .remove(
                                                                              key,
                                                                            ),
                                                                      );
                                                                      AppFeedback.showFromSnackBar(
                                                                        ctx,
                                                                        SnackBar(
                                                                          content: Text(
                                                                            'No se pudo aplicar el reemplazo: $e',
                                                                          ),
                                                                          backgroundColor:
                                                                              Colors.red,
                                                                        ),
                                                                      );
                                                                    }
                                                                  },
                                                            child: const Text(
                                                              'Si, reemplazar',
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.check),
                          label: const Text('Aceptar'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _cargarDatos() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final desde = DateTime(_anioActual, _mesActual, 1);
      final hasta = DateTime(_anioActual, _mesActual, _daysInMonth);

      final horariosFuture = _conjuntoApi
          .obtenerHorariosConjunto(widget.nit)
          .catchError((_) => <HorarioConjunto>[]);

      final results = await Future.wait([
        _cronogramaApi.cronogramaMensual(
          nit: widget.nit,
          anio: _anioActual,
          mes: _mesActual,
          borrador: true,
          tipo: 'PREVENTIVA',
        ),
        _festivoApi.listarFestivosRango(desde: desde, hasta: hasta, pais: 'CO'),
        horariosFuture,
        _preventivaApi.listarExcluidasBorrador(
          nit: widget.nit,
          anio: _anioActual,
          mes: _mesActual,
        ),
        _cronogramaApi.informeActividadMensual(
          nit: widget.nit,
          anio: _anioActual,
          mes: _mesActual,
          borrador: true,
        ),
      ]);

      final lista = results[0] as List<TareaModel>;
      final festivos = results[1] as List<FestivoItem>;
      final horarios = results[2] as List<HorarioConjunto>;
      final excluidas = results[3] as List<PreventivaExcluidaBorradorModel>;
      final informe = results[4] as List<CronogramaActividadInformeModel>;
      final filtradas = lista
          .where((t) => _isInThisMonth(t.fechaInicio))
          .toList();

      final setYmd = <String>{};
      final nombrePorYmd = <String, String>{};

      for (final f in festivos) {
        final key = _toYmd(f.fecha);
        setYmd.add(key);
        if (f.nombre != null && f.nombre!.trim().isNotEmpty) {
          nombrePorYmd[key] = f.nombre!.trim();
        }
      }

      setState(() {
        _tareasMes = filtradas;
        _excluidasMes = excluidas;
        _informeActividad = informe;
        _horariosConjunto = horarios;
        _reconstruirFiltrosDisponibles();
        _festivosYmd = setYmd;
        _festivoNombrePorYmd = nombrePorYmd;
        _aplicarHorarioConjunto(horarios: horarios, tareasMes: filtradas);
        _recalcularResumenDias();
      });
    } catch (e) {
      setState(() => _error = AppError.messageOf(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _hayTareas => _tareasMes.isNotEmpty;
  DateTime get _inicioPeriodoSeleccionado =>
      DateTime(_anioActual, _mesActual, 1);
  DateTime get _inicioVentanaPublicacion =>
      _inicioPeriodoSeleccionado.subtract(const Duration(days: 7));
  bool get _ventanaPublicacionAbierta =>
      !DateTime.now().isBefore(_inicioVentanaPublicacion);

  String get _mensajeVentanaPublicacion {
    final desde = DateFormat('dd/MM/yyyy').format(_inicioVentanaPublicacion);
    final periodo = DateFormat(
      'MMMM yyyy',
      'es',
    ).format(_inicioPeriodoSeleccionado);
    return 'La publicación de $periodo se habilita desde $desde.';
  }

  Future<void> _eliminarTareaBorrador(TareaModel tarea) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar del borrador'),
        content: Text(
          'La tarea "${tarea.descripcion}" se quitara del borrador y pasara a excluidas. ¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await _preventivaApi.eliminarBloqueBorrador(
      nit: widget.nit,
      tareaId: tarea.id,
    );
    if (!mounted) return;
    AppFeedback.showFromSnackBar(
      context,
      const SnackBar(content: Text('Tarea enviada a excluidas.')),
    );
    await _cargarDatos();
  }

  Future<void> _agendarExcluida(
    PreventivaExcluidaBorradorModel excluida,
  ) async {
    final sugerencias = await _preventivaApi.sugerirHuecosExcluida(
      nit: widget.nit,
      excluidaId: excluida.id,
      fechaPreferida: excluida.fechaObjetivo,
    );
    final opciones = (sugerencias['opciones'] as List? ?? const []);
    if (!mounted) return;
    if (opciones.isEmpty) {
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(content: Text('No se encontraron huecos disponibles.')),
      );
      return;
    }

    final seleccion = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          itemCount: opciones.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Opciones para agendar o dividir',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Si una tarea no cabe completa en un día, aquí verás planes divididos por horas entre varios días.',
                  ),
                ],
              );
            }
            final item = Map<String, dynamic>.from(opciones[index - 1] as Map);
            final bloques = ((item['bloques'] as List?) ?? const [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            final fi = DateTime.parse(item['fechaInicio'].toString()).toLocal();
            final ff = DateTime.parse(item['fechaFin'].toString()).toLocal();
            final requiereDivision = item['requiereDivision'] == true;
            final detalleBloques = bloques.isEmpty
                ? '${DateFormat('HH:mm').format(fi)} - ${DateFormat('HH:mm').format(ff)}'
                : bloques
                      .map((bloque) {
                        final bfi = DateTime.parse(
                          bloque['fechaInicio'].toString(),
                        ).toLocal();
                        final bff = DateTime.parse(
                          bloque['fechaFin'].toString(),
                        ).toLocal();
                        return '${DateFormat('EEE dd MMM · HH:mm', 'es').format(bfi)} - ${DateFormat('HH:mm').format(bff)}';
                      })
                      .join('\n');
            return ListTile(
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              leading: requiereDivision
                  ? const Icon(Icons.splitscreen_outlined, color: Colors.orange)
                  : const Icon(Icons.event_available_outlined),
              title: Text(
                requiereDivision
                    ? 'Plan dividido en ${item['diasUtilizados'] ?? bloques.length} dia(s)'
                    : DateFormat('EEE dd MMM · HH:mm', 'es').format(fi),
              ),
              subtitle: Text(
                requiereDivision
                    ? detalleBloques
                    : '${DateFormat('HH:mm').format(fi)} - ${DateFormat('HH:mm').format(ff)} • ${item['tipoSugerencia'] == 'MISMO_DIA' ? 'Mismo dia' : 'Otro dia del mes'}',
              ),
              isThreeLine: requiereDivision,
              onTap: () => Navigator.pop(context, item),
            );
          },
        ),
      ),
    );

    if (seleccion == null) return;

    final bloques = ((seleccion['bloques'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final res = await _preventivaApi.agendarExcluidaBorrador(
      nit: widget.nit,
      excluidaId: excluida.id,
      fechaInicio: bloques.isEmpty
          ? DateTime.parse(seleccion['fechaInicio'].toString())
          : null,
      fechaFin: bloques.isEmpty
          ? DateTime.parse(seleccion['fechaFin'].toString())
          : null,
      bloques: bloques.isEmpty
          ? null
          : bloques
                .map(
                  (bloque) => {
                    'fechaInicio': bloque['fechaInicio'].toString(),
                    'fechaFin': bloque['fechaFin'].toString(),
                  },
                )
                .toList(),
    );
    if (!mounted) return;
    final tareasCreadas = (res['tareas'] as List?)?.length ?? 1;
    AppFeedback.showFromSnackBar(
      context,
      SnackBar(
        content: Text(
          tareasCreadas > 1
              ? 'Tarea excluida agendada y dividida en $tareasCreadas bloques.'
              : 'Tarea excluida agendada en borrador.',
        ),
      ),
    );
    await _cargarDatos();
  }

  Future<List<int>?> _pedirDivisionManualExcluida(
    PreventivaExcluidaBorradorModel excluida,
  ) {
    final totalHoras = excluida.duracionMinutos / 60;
    return showDialog<List<int>>(
      context: context,
      builder: (ctx) {
        int cantidadBloques = 2;
        List<TextEditingController> controllers = List.generate(
          cantidadBloques,
          (_) => TextEditingController(),
        );

        void syncControllers(StateSetter setState) {
          final actuales = controllers;
          controllers = List.generate(cantidadBloques, (index) {
            if (index < actuales.length) return actuales[index];
            return TextEditingController();
          });
          if (actuales.length > cantidadBloques) {
            for (final item in actuales.skip(cantidadBloques)) {
              item.dispose();
            }
          }
          setState(() {});
        }

        return StatefulBuilder(
          builder: (context, setState) {
            final valores = controllers
                .map(
                  (item) =>
                      double.tryParse(item.text.replaceAll(',', '.')) ?? 0,
                )
                .toList();
            final totalDigitado = valores.fold<double>(0, (a, b) => a + b);
            return AlertDialog(
              title: const Text('Dividir tarea en horas'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Duración total: ${totalHoras.toStringAsFixed(1)} h'),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: cantidadBloques,
                      decoration: const InputDecoration(
                        labelText: 'Cantidad de bloques',
                        border: OutlineInputBorder(),
                      ),
                      items: List.generate(
                        6,
                        (index) => DropdownMenuItem(
                          value: index + 2,
                          child: Text('${index + 2} bloques'),
                        ),
                      ),
                      onChanged: (value) {
                        if (value == null) return;
                        cantidadBloques = value;
                        syncControllers(setState);
                      },
                    ),
                    const SizedBox(height: 12),
                    ...List.generate(cantidadBloques, (index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: TextField(
                          controller: controllers[index],
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Bloque ${index + 1} (horas)',
                            hintText: 'Ej. 2 o 1.5',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      );
                    }),
                    Text(
                      'Total digitado: ${totalDigitado.toStringAsFixed(1)} h',
                      style: TextStyle(
                        color: (totalDigitado - totalHoras).abs() < 0.01
                            ? Colors.green.shade700
                            : Colors.orange.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final minutos = controllers
                        .map(
                          (item) =>
                              ((double.tryParse(
                                            item.text.replaceAll(',', '.'),
                                          ) ??
                                          0) *
                                      60)
                                  .round(),
                        )
                        .toList();
                    final total = minutos.fold<int>(0, (a, b) => a + b);
                    final tieneInvalidos = minutos.any((item) => item <= 0);
                    if (tieneInvalidos || total != excluida.duracionMinutos) {
                      AppFeedback.showFromSnackBar(
                        context,
                        SnackBar(
                          content: Text(
                            'La suma de bloques debe ser exactamente ${totalHoras.toStringAsFixed(1)} h y todos los bloques deben ser mayores a 0.',
                          ),
                        ),
                      );
                      return;
                    }
                    Navigator.pop(ctx, minutos);
                  },
                  child: const Text('Guardar división'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _dividirExcluidaEnHoras(
    PreventivaExcluidaBorradorModel excluida,
  ) async {
    final minutos = await _pedirDivisionManualExcluida(excluida);
    if (minutos == null || minutos.isEmpty) return;
    await _preventivaApi.dividirExcluidaManual(
      nit: widget.nit,
      excluidaId: excluida.id,
      bloquesDuracionMinutos: minutos,
    );
    if (!mounted) return;
    AppFeedback.showFromSnackBar(
      context,
      SnackBar(
        content: Text(
          'Tarea dividida manualmente en ${minutos.length} bloques.',
        ),
      ),
    );
    await _cargarDatos();
  }

  Future<void> _agendarBloqueExcluida(
    PreventivaExcluidaBorradorModel excluida,
    PreventivaExcluidaBloqueModel bloque,
  ) async {
    final sugerencias = await _preventivaApi.sugerirHuecosBloqueExcluida(
      nit: widget.nit,
      excluidaId: excluida.id,
      bloqueId: bloque.id,
      fechaPreferida: excluida.fechaObjetivo,
    );
    final opciones = (sugerencias['opciones'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (!mounted) return;
    if (opciones.isEmpty) {
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(
          content: Text(
            'No se encontraron huecos disponibles para este bloque.',
          ),
        ),
      );
      return;
    }

    final seleccion = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          itemCount: opciones.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (ctx, index) {
            final item = opciones[index];
            final fi = DateTime.parse(item['fechaInicio'].toString()).toLocal();
            final ff = DateTime.parse(item['fechaFin'].toString()).toLocal();
            return ListTile(
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              title: Text('Bloque ${bloque.orden} · ${bloque.duracionLabel}'),
              subtitle: Text(
                '${DateFormat('EEE dd MMM · HH:mm', 'es').format(fi)} - ${DateFormat('HH:mm').format(ff)}',
              ),
              onTap: () => Navigator.pop(ctx, item),
            );
          },
        ),
      ),
    );
    if (seleccion == null) return;

    await _preventivaApi.agendarBloqueExcluida(
      nit: widget.nit,
      excluidaId: excluida.id,
      bloqueId: bloque.id,
      fechaInicio: DateTime.parse(seleccion['fechaInicio'].toString()),
      fechaFin: DateTime.parse(seleccion['fechaFin'].toString()),
    );
    if (!mounted) return;
    AppFeedback.showFromSnackBar(
      context,
      SnackBar(content: Text('Bloque ${bloque.orden} agendado.')),
    );
    await _cargarDatos();
  }

  Future<void> _reordenarTareasDia(
    DateTime fecha,
    List<TareaModel> tareasOrdenadas,
  ) async {
    await _preventivaApi.reordenarTareasDiaBorrador(
      nit: widget.nit,
      fecha: fecha,
      tareaIds: tareasOrdenadas.map((item) => item.id).toList(),
    );
    if (!mounted) return;
    AppFeedback.showFromSnackBar(
      context,
      const SnackBar(content: Text('Orden del día actualizado.')),
    );
    await _cargarDatos();
  }

  Future<void> _reemplazarTareaConExcluida(TareaModel tarea) async {
    if (_excluidasMes.isEmpty) {
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(content: Text('No hay tareas excluidas disponibles.')),
      );
      return;
    }

    final excluida = await showModalBottomSheet<PreventivaExcluidaBorradorModel>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: _excluidasMes.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final item = _excluidasMes[index];
            return ListTile(
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              title: Text(item.descripcion),
              subtitle: Text(
                'P${item.prioridad} • ${item.ubicacionNombre ?? '-'} • ${item.duracionLabel}',
              ),
              onTap: () => Navigator.pop(context, item),
            );
          },
        ),
      ),
    );

    if (excluida == null) return;

    await _preventivaApi.reemplazarTareaConExcluida(
      nit: widget.nit,
      tareaId: tarea.id,
      excluidaId: excluida.id,
    );
    if (!mounted) return;
    AppFeedback.showFromSnackBar(
      context,
      const SnackBar(content: Text('Reemplazo manual aplicado.')),
    );
    await _cargarDatos();
  }

  Future<void> _publicarCronograma() async {
    if (!_hayTareas || _publicando) return;
    if (!_ventanaPublicacionAbierta) {
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text(_mensajeVentanaPublicacion),
          backgroundColor: Colors.orange.shade800,
        ),
      );
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Publicar cronograma'),
        content: const Text(
          '¿Seguro que quieres publicar el cronograma de tareas preventivas '
          'para este mes? Ya no se podrán editar como borrador.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Publicar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _publicando = true);

    try {
      final res = await _cronogramaApi.publicarCronogramaPreventivas(
        nit: widget.nit,
        anio: _anioActual,
        mes: _mesActual,
        consolidar: false,
      );

      if (!mounted) return;

      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text(
            'Cronograma publicado. Publicadas: ${res['publicadas'] ?? res['publicadasSimples'] ?? '-'}',
          ),
        ),
      );

      await _cargarDatos();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text('Error publicando cronograma: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _publicando = false);
    }
  }

  void _recalcularResumenDias() {
    _diasResumen = [];
    for (int dia = 1; dia <= _daysInMonth; dia++) {
      final fechaDia = DateTime(_anioActual, _mesActual, dia);

      final tareasDia = _tareasFiltradas.where((t) {
        return _isSameLocalDay(t.fechaInicio, fechaDia);
      }).toList();

      _diasResumen.add(
        _DiaResumen(
          dia: dia,
          total: tareasDia.length,
          preventivas: tareasDia.length,
        ),
      );
    }
  }

  bool _hayFiltrosActivos() {
    return _filtroTipo != 'TODAS' ||
        _filtroEstado != 'TODOS' ||
        _filtroOperario != 'TODOS' ||
        _filtroUbicacion != 'TODAS' ||
        _filtroEquipo != 'TODOS';
  }

  // ========= NUEVO: Mensual tipo matriz (como la foto) =========

  String _codigoEstado(String? estado) {
    final e = (estado ?? '').trim().toUpperCase();
    const map = <String, String>{
      'ASIGNADA': 'AS',
      'EN_PROCESO': 'EP',
      'COMPLETADA': 'CO',
      'APROBADA': 'AP',
      'PENDIENTE_APROBACION': 'PA',
      'RECHAZADA': 'RE',
      'NO_COMPLETADA': 'NC',
      'PENDIENTE_REPROGRAMACION': 'PR',
    };

    if (e.isEmpty) return '';
    if (map.containsKey(e)) return map[e]!;

    // fallback: 1-2 letras desde el texto
    final parts = e
        .split(RegExp(r'[_\s]+'))
        .where((x) => x.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1);
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  bool _esDomingo(DateTime d) => d.weekday == DateTime.sunday;

  String _weekdayLetter(DateTime d) {
    // L M M J V S D (lunes..domingo)
    const letters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
    return letters[d.weekday - 1];
  }

  Widget _ddTipo() {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Tipo',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      initialValue: _filtroTipo,
      items: const [
        DropdownMenuItem(value: 'TODAS', child: Text('Todas')),
        DropdownMenuItem(value: 'PREVENTIVA', child: Text('Preventivas')),
        DropdownMenuItem(value: 'CORRECTIVA', child: Text('Correctivas')),
      ],
      onChanged: (v) {
        if (v == null) return;
        setState(() => _filtroTipo = v);
        _aplicarFiltrosYRefrescar();
      },
    );
  }

  Widget _ddEstado() {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Estado',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      initialValue: _filtroEstado,
      items: const [
        DropdownMenuItem(value: 'TODOS', child: Text('Todos')),
        DropdownMenuItem(value: 'ASIGNADA', child: Text('Asignada')),
        DropdownMenuItem(value: 'EN_PROCESO', child: Text('En proceso')),
        DropdownMenuItem(value: 'COMPLETADA', child: Text('Completada')),
        DropdownMenuItem(value: 'APROBADA', child: Text('Aprobada')),
        DropdownMenuItem(
          value: 'PENDIENTE_APROBACION',
          child: Text('Pendiente aprobación'),
        ),
        DropdownMenuItem(value: 'RECHAZADA', child: Text('Rechazada')),
        DropdownMenuItem(value: 'NO_COMPLETADA', child: Text('No completada')),
        DropdownMenuItem(
          value: 'PENDIENTE_REPROGRAMACION',
          child: Text('Pendiente reprogramación'),
        ),
      ],
      onChanged: (v) {
        if (v == null) return;
        setState(() => _filtroEstado = v);
        _aplicarFiltrosYRefrescar();
      },
    );
  }

  Widget _ddOperario() {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Operario',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      initialValue: _filtroOperario,
      items: [
        const DropdownMenuItem(value: 'TODOS', child: Text('Todos')),
        ..._operariosDisponibles.map(
          (o) => DropdownMenuItem(value: o, child: Text(o)),
        ),
      ],
      onChanged: (v) {
        if (v == null) return;
        setState(() => _filtroOperario = v);
        _aplicarFiltrosYRefrescar();
      },
    );
  }

  Widget _ddUbicacion() {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Ubicación',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      initialValue: _filtroUbicacion,
      items: [
        const DropdownMenuItem(value: 'TODAS', child: Text('Todas')),
        ..._ubicacionesDisponibles.map(
          (u) => DropdownMenuItem(value: u, child: Text(u)),
        ),
      ],
      onChanged: (v) {
        if (v == null) return;
        setState(() => _filtroUbicacion = v);
        _aplicarFiltrosYRefrescar();
      },
    );
  }

  Widget _ddEquipo() {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Equipo',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      initialValue: _filtroEquipo,
      items: [
        const DropdownMenuItem(value: 'TODOS', child: Text('Todos')),
        ..._equiposDisponibles.map(
          (equipo) => DropdownMenuItem(value: equipo, child: Text(equipo)),
        ),
      ],
      onChanged: (v) {
        if (v == null) return;
        setState(() => _filtroEquipo = v);
        _aplicarFiltrosYRefrescar();
      },
    );
  }

  Widget _buildFiltrosMensualCompacto() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  'Filtros',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade900,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _limpiarFiltros,
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('Limpiar'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 2 columnas para que no quede "bloque ladrillo"
            Row(
              children: [
                Expanded(child: _ddTipo()),
                const SizedBox(width: 10),
                Expanded(child: _ddEstado()),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _ddOperario()),
                const SizedBox(width: 10),
                Expanded(
                  child: _equiposDisponibles.isNotEmpty
                      ? _ddEquipo()
                      : const SizedBox.shrink(),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _ddUbicacion()),
                const SizedBox(width: 10),
                const Expanded(child: SizedBox.shrink()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltrosComoColumna({bool mostrarTitulo = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (mostrarTitulo) ...[
          const Text(
            'Filtros',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 10),
        ],
        _ddTipo(),
        const SizedBox(height: 8),
        _ddEstado(),
        const SizedBox(height: 8),
        _ddOperario(),
        if (_equiposDisponibles.isNotEmpty) ...[
          const SizedBox(height: 8),
          _ddEquipo(),
        ],
        const SizedBox(height: 8),
        _ddUbicacion(),
      ],
    );
  }

  List<_FilaCrono> _buildFilasCronoMensual() {
    // Agrupa por: descripcion + frecuencia + ubicacion + responsable (ajustable)
    final Map<String, _FilaCrono> rows = {};

    for (final t in _tareasFiltradas) {
      final ubic = (t.ubicacionNombre ?? 'ID ${t.ubicacionId}').trim();
      final objeto = (_nombreObjeto(t) ?? 'ID ${t.elementoId}').trim();
      final freq = (t.frecuencia ?? '—').trim();
      final diag = (t.descripcion).trim();

      // responsable: prioriza operarios, si no supervisor
      final operarios = [...t.operariosNombres]..sort();
      final resp = operarios.isNotEmpty
          ? operarios.join(', ')
          : (t.supervisorNombre ??
                (t.supervisorId != null
                    ? 'ID ${t.supervisorId}'
                    : 'Sin asignar'));

      final key = '$freq||$diag||$ubic||$objeto||$resp';

      rows.putIfAbsent(
        key,
        () => _FilaCrono(
          frecuencia: freq,
          diagnostico: diag,
          ubicacion: ubic,
          objeto: objeto,
          responsable: resp,
          porDia: {},
        ),
      );

      final day = t.fechaInicio.toLocal().day;

      // Si hay varias tareas el mismo dia para esa fila, mostramos la mas critica
      // Orden: X > R > O > vacío (ajusta si quieres)
      final s = _codigoEstado(t.estado);
      final actual = rows[key]!.porDia[day] ?? '';
      rows[key]!.porDia[day] = _mergeSimbolos(actual, s);
    }

    final list = rows.values.toList();

    // Ordena: frecuencia, diagnóstico, ubicación
    list.sort((a, b) {
      final c1 = a.frecuencia.compareTo(b.frecuencia);
      if (c1 != 0) return c1;
      final c2 = a.diagnostico.compareTo(b.diagnostico);
      if (c2 != 0) return c2;
      final c3 = a.ubicacion.compareTo(b.ubicacion);
      if (c3 != 0) return c3;
      return a.objeto.compareTo(b.objeto);
    });

    return list;
  }

  String _mergeSimbolos(String a, String b) {
    int rank(String s) {
      switch (s) {
        case 'NC':
          return 90; // no completada
        case 'RE':
          return 80; // rechazada
        case 'PR':
          return 70; // pendiente reprogramación
        case 'PA':
          return 60; // pendiente aprobación
        case 'EP':
          return 50; // en proceso
        case 'AS':
          return 40; // asignada
        case 'CO':
          return 30; // completada
        case 'AP':
          return 20; // aprobada
        default:
          return s.isEmpty ? 0 : 10;
      }
    }

    return rank(b) > rank(a) ? b : a;
  }

  Color _colorPorCodigo(String code) {
    switch (code) {
      case 'NC':
        return Colors.red.shade700;
      case 'RE':
        return Colors.red.shade900;
      case 'PR':
        return Colors.deepOrange.shade800;
      case 'PA':
        return Colors.orange.shade800;
      case 'EP':
        return Colors.blue.shade800;
      case 'AS':
        return Colors.indigo.shade700;
      case 'CO':
        return Colors.green.shade800;
      case 'AP':
        return Colors.teal.shade800;
      default:
        return Colors.grey.shade900;
    }
  }

  Widget _buildCronogramaMensualTipoFoto() {
    final filas = _buildFilasCronoMensual();

    // tamaños (ajusta si quieres)
    const wFrecuencia = 120.0;
    const wDiagnostico = 260.0;
    const wUbicacion = 130.0;
    const wElemento = 130.0;
    const wResponsable = 250.0;
    const wDia = 34.0;
    const hFila = 56.0;

    final headerStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: Colors.grey.shade900,
    );

    final border = BorderSide(color: Colors.grey.shade300);

    Widget cellBox({
      required double w,
      required Widget child,
      Color? color,
      Alignment align = Alignment.center,
      double? h,
    }) {
      return Container(
        width: w,
        height: h,
        padding: EdgeInsets.symmetric(
          horizontal: 8,
          vertical: h == null ? 12 : 8,
        ),
        alignment: align,
        decoration: BoxDecoration(
          color: color ?? Colors.white,
          border: Border(right: border, bottom: border),
        ),
        child: child,
      );
    }

    // encabezados días
    final dias = List.generate(_daysInMonth, (i) => i + 1);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          color: Colors.white,
        ),
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            controller: _mensualHCtrl,
            scrollDirection: Axis.horizontal,
            child: Scrollbar(
              controller: _mensualHCtrl,
              thumbVisibility: true,
              scrollbarOrientation: ScrollbarOrientation.bottom,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ===== Header 1: títulos fijos + letras de semana =====
                  Row(
                    children: [
                      cellBox(
                        w: wFrecuencia,
                        color: Colors.green.shade200,
                        align: Alignment.center,
                        child: Text('Frecuencia', style: headerStyle),
                      ),
                      cellBox(
                        w: wDiagnostico,
                        color: Colors.green.shade200,
                        align: Alignment.center,
                        child: Text('Tarea', style: headerStyle),
                      ),
                      cellBox(
                        w: wUbicacion,
                        color: Colors.green.shade200,
                        align: Alignment.center,
                        child: Text('Ubicación', style: headerStyle),
                      ),
                      cellBox(
                        w: wElemento,
                        color: Colors.green.shade200,
                        align: Alignment.center,
                        child: Text('Elemento', style: headerStyle),
                      ),
                      cellBox(
                        w: wResponsable,
                        color: Colors.green.shade200,
                        align: Alignment.center,
                        child: Text('Responsable', style: headerStyle),
                      ),
                      ...dias.map((dia) {
                        final fecha = DateTime(_anioActual, _mesActual, dia);
                        final dom = _esDomingo(fecha);
                        final fest = _esFestivo(fecha);

                        Color headerColor;
                        if (dom) {
                          headerColor = Colors.yellow.shade300;
                        } else if (fest) {
                          headerColor = const Color(0xFFE53935); // festivo
                        } else {
                          headerColor = Colors.green.shade200;
                        }

                        return cellBox(
                          w: wDia,
                          color: headerColor,
                          child: Tooltip(
                            message: fest
                                ? (_nombreFestivo(fecha) ?? 'Festivo')
                                : '',
                            child: Text(
                              _weekdayLetter(fecha),
                              style: headerStyle,
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                  // ===== Header 2: números de día =====
                  Row(
                    children: [
                      cellBox(
                        w: wFrecuencia,
                        color: Colors.white,
                        child: const SizedBox.shrink(),
                      ),
                      cellBox(
                        w: wDiagnostico,
                        color: Colors.white,
                        child: const SizedBox.shrink(),
                      ),
                      cellBox(
                        w: wUbicacion,
                        color: Colors.white,
                        child: const SizedBox.shrink(),
                      ),
                      cellBox(
                        w: wElemento,
                        color: Colors.white,
                        child: const SizedBox.shrink(),
                      ),
                      cellBox(
                        w: wResponsable,
                        color: Colors.white,
                        child: const SizedBox.shrink(),
                      ),
                      ...dias.map((dia) {
                        final fecha = DateTime(_anioActual, _mesActual, dia);
                        final dom = _esDomingo(fecha);
                        final fest = _esFestivo(fecha);

                        Color header2Color;
                        if (dom) {
                          header2Color = Colors.yellow.shade300;
                        } else if (fest) {
                          header2Color = const Color(
                            0xFFFFCDD2,
                          ); // festivo // 👈 festivo
                        } else {
                          header2Color = Colors.grey.shade100;
                        }

                        return cellBox(
                          w: wDia,
                          color: header2Color,
                          child: Tooltip(
                            message: fest
                                ? (_nombreFestivo(fecha) ?? 'Festivo')
                                : '',
                            child: Text(
                              '$dia',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade900,
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),

                  // ===== Body =====
                  ...filas.map((f) {
                    return Row(
                      children: [
                        cellBox(
                          w: wFrecuencia,
                          h: hFila,
                          align: Alignment.topLeft,
                          child: Text(
                            f.frecuencia,
                            style: const TextStyle(fontSize: 12),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        cellBox(
                          w: wDiagnostico,
                          h: hFila,
                          align: Alignment.topLeft,
                          child: Text(
                            f.diagnostico,
                            style: const TextStyle(fontSize: 12),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        cellBox(
                          w: wUbicacion,
                          h: hFila,
                          align: Alignment.topLeft,
                          child: Text(
                            f.ubicacion,
                            style: const TextStyle(fontSize: 12),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        cellBox(
                          w: wElemento,
                          h: hFila,
                          align: Alignment.topLeft,
                          child: Text(
                            f.objeto,
                            style: const TextStyle(fontSize: 12),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        cellBox(
                          w: wResponsable,
                          h: hFila,
                          align: Alignment.topLeft,
                          child: Text(
                            f.responsable,
                            style: const TextStyle(fontSize: 12, height: 1.3),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        ...dias.map((dia) {
                          final fecha = DateTime(_anioActual, _mesActual, dia);
                          final dom = _esDomingo(fecha);
                          final fest = _esFestivo(fecha);
                          final val = f.porDia[dia] ?? '';

                          return GestureDetector(
                            onTap: () => _abrirDia(dia),
                            child: cellBox(
                              w: wDia,
                              h: hFila,
                              color: dom
                                  ? Colors.yellow.shade200
                                  : fest
                                  ? const Color(0xFFFFEBEE)
                                  : Colors.white,
                              child: Text(
                                val,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: _colorPorCodigo(
                                    val,
                                  ), // Aqui se usa el color por codigo
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===== bloques por hora (modal diario, se mantiene) =====
  List<_BloqueHora> _generarBloquesDia(DateTime fecha) {
    final fechaLocal = fecha.toLocal();
    final List<_BloqueHora> bloques = [];

    for (int h = _horaInicioJornada; h < _horaFinJornada; h++) {
      final tieneDescanso =
          _horaDescansoInicio != null &&
          _horaDescansoFin != null &&
          _horaDescansoFin! > _horaDescansoInicio!;
      if (tieneDescanso && h >= _horaDescansoInicio! && h < _horaDescansoFin!) {
        continue;
      }

      final inicio = DateTime(
        fechaLocal.year,
        fechaLocal.month,
        fechaLocal.day,
        h,
        0,
      );
      final fin = inicio.add(const Duration(hours: 1));

      final tareasDelDia = _tareasFiltradas;

      final tareasBloque = tareasDelDia.where((t) {
        final i = t.fechaInicio.toLocal();
        final f = t.fechaFin.toLocal();
        return i.isBefore(fin) && f.isAfter(inicio);
      }).toList();

      bloques.add(_BloqueHora(inicio: inicio, fin: fin, tareas: tareasBloque));
    }

    return bloques;
  }

  String _etiquetaConteoTareas(int total) {
    if (total == 0) return 'Sin tareas';
    return total == 1 ? '1 tarea' : '$total tareas';
  }

  String _resumenBloque(_BloqueHora bloque) {
    if (bloque.tareas.isEmpty) {
      return 'No hay tareas programadas en este bloque.';
    }

    final descripciones = bloque.tareas
        .map((t) => t.descripcion.trim())
        .where((d) => d.isNotEmpty)
        .toList();

    if (descripciones.isEmpty) {
      return _etiquetaConteoTareas(bloque.tareas.length);
    }

    final visibles = descripciones.take(2).join(' | ');
    if (descripciones.length <= 2) return visibles;
    return '$visibles | +${descripciones.length - 2} mas';
  }

  Future<void> _abrirBloqueDia(_BloqueHora bloque, DateTime fechaBase) async {
    final fechaLabel = DateFormat("d 'de' MMMM", 'es').format(fechaBase);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final horaIni = TimeOfDay.fromDateTime(bloque.inicio).format(ctx);
        final horaFin = TimeOfDay.fromDateTime(bloque.fin).format(ctx);

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: bloque.tareas.isEmpty ? 0.32 : 0.72,
          minChildSize: 0.25,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Material(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Bloque $horaIni - $horaFin',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$fechaLabel | ${_etiquetaConteoTareas(bloque.tareas.length)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: bloque.tareas.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'No hay tareas programadas en este bloque.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: bloque.tareas.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final t = bloque.tareas[index];
                              return _buildTareaTile(t, ctx);
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDiaSheet(
    BuildContext ctx,
    double alto,
    List<_BloqueHora> bloques,
    DateTime fechaBase,
  ) {
    return SizedBox(
      height: alto,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Tareas borrador del dia',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat("d 'de' MMMM", 'es').format(fechaBase),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: bloques.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final b = bloques[index];
                final horaIni = TimeOfDay.fromDateTime(b.inicio).format(ctx);
                final horaFin = TimeOfDay.fromDateTime(b.fin).format(ctx);
                final total = b.tareas.length;
                final tieneTareas = total > 0;

                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: tieneTareas ? 2 : 0,
                  color: tieneTareas ? Colors.white : Colors.grey.shade50,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    leading: CircleAvatar(
                      radius: 20,
                      backgroundColor: tieneTareas
                          ? AppTheme.primary.withValues(alpha: 0.12)
                          : Colors.grey.shade200,
                      child: Text(
                        '$total',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: tieneTareas
                              ? AppTheme.primary
                              : Colors.grey.shade700,
                        ),
                      ),
                    ),
                    title: Text(
                      '$horaIni - $horaFin',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _etiquetaConteoTareas(total),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _resumenBloque(b),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _abrirBloqueDia(b, fechaBase),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirDia(int dia) async {
    final fechaBase = DateTime(_anioActual, _mesActual, dia);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final alto = MediaQuery.of(ctx).size.height * 0.8;
        final bloques = _generarBloquesDia(fechaBase);
        return _buildDiaSheet(ctx, alto, bloques, fechaBase);
      },
    );

    setState(() => _recalcularResumenDias());
  }

  Widget _buildTareaTile(
    TareaModel t,
    BuildContext ctx, {
    VoidCallback? onTap,
  }) {
    final iniLocal = t.fechaInicio.toLocal();
    final finLocal = t.fechaFin.toLocal();

    final horaIni = TimeOfDay.fromDateTime(iniLocal).format(ctx);
    final horaFin = TimeOfDay.fromDateTime(finLocal).format(ctx);

    final durMin = t.duracionMinutos;
    final durH = durMin / 60.0;

    final operarios = t.operariosNombres.isEmpty
        ? 'Sin asignar'
        : t.operariosNombres.join(', ');
    final supervisor =
        t.supervisorNombre ??
        (t.supervisorId != null ? 'ID ${t.supervisorId}' : 'Sin supervisor');

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 2,
      child: ListTile(
        title: Text(
          t.descripcion,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'Duracion: $durMin min (${durH.toStringAsFixed(1)} h) | $horaIni - $horaFin',
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              'Supervisor: $supervisor',
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              '👷 Operarios: $operarios',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        onTap: onTap ?? () => _mostrarDetalleTarea(t, ctx),
      ),
    );
  }

  Future<_ModoCambioOperario?> _preguntarModoCambioOperario() {
    return showDialog<_ModoCambioOperario>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aplicar cambio de operario'),
        content: const Text(
          'Puedes mover esta tarea solo en este borrador o dejar el nuevo operario también en la definición para futuros cronogramas.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, _ModoCambioOperario.soloBorrador),
            child: const Text('Solo este borrador'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(ctx, _ModoCambioOperario.tambienDefinicion),
            child: const Text('Tambien en definicion'),
          ),
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _cargarOperariosDelConjunto({
    required DateTime inicio,
    required DateTime fin,
  }) {
    return _cronogramaApi.sugerirOperarios(
      nit: widget.nit,
      inicio: inicio,
      fin: fin,
      max: 20,
    );
  }

  Future<Map<String, dynamic>?> _seleccionarOperarioDelConjunto({
    required DateTime inicio,
    required DateTime fin,
    required Set<String> actualIds,
  }) async {
    final operarios = await _cargarOperariosDelConjunto(
      inicio: inicio,
      fin: fin,
    );
    if (!mounted) return null;
    if (operarios.isEmpty) {
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(
          content: Text(
            'No hay operarios del conjunto disponibles para reasignar.',
          ),
        ),
      );
      return null;
    }

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: operarios.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (ctx, index) {
            final item = operarios[index];
            final id = (item['id'] ?? '').toString();
            final esActual = actualIds.contains(id);
            final horasSemana =
                num.tryParse((item['horasSemana'] ?? 0).toString()) ?? 0;
            final solapa = item['solapa'] == true;
            final subtitulo = esActual
                ? 'Operario actual'
                : solapa
                ? 'Tiene cruce en ese rango'
                : '${(horasSemana / 60).toStringAsFixed(1)} h programadas esa semana';
            return ListTile(
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              title: Text((item['nombre'] ?? 'Operario').toString()),
              subtitle: Text(subtitulo),
              trailing: esActual
                  ? const Icon(Icons.check_circle_outline, color: Colors.green)
                  : solapa
                  ? const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange,
                    )
                  : const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(ctx, item),
            );
          },
        ),
      ),
    );
  }

  Future<void> _reasignarOperarioTarea(TareaModel tarea) async {
    final actualIds = tarea.operariosIds.toSet();
    final seleccionado = await _seleccionarOperarioDelConjunto(
      inicio: tarea.fechaInicio,
      fin: tarea.fechaFin,
      actualIds: actualIds,
    );

    if (seleccionado == null) return;
    if (!mounted) return;

    final nuevoOperarioId = int.tryParse((seleccionado['id'] ?? '').toString());
    if (nuevoOperarioId == null) {
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(
          content: Text(
            'No se pudo interpretar el ID del operario seleccionado.',
          ),
        ),
      );
      return;
    }

    final modo = await _preguntarModoCambioOperario();
    if (modo == null) return;

    final res = await _preventivaApi.reasignarOperarioBorrador(
      nit: widget.nit,
      tareaId: tarea.id,
      nuevoOperarioId: nuevoOperarioId,
      aplicarADefinicion: modo == _ModoCambioOperario.tambienDefinicion,
    );
    if (!mounted) return;

    final warning = (res['warning'] ?? '').toString().trim();
    final definicionActualizada = res['definicionActualizada'] == true;
    final mensaje = warning.isNotEmpty
        ? warning
        : definicionActualizada
        ? 'Operario cambiado en el borrador y en la definición.'
        : 'Operario cambiado solo en este borrador.';

    AppFeedback.showFromSnackBar(context, SnackBar(content: Text(mensaje)));
    await _cargarDatos();
  }

  Future<void> _reasignarOperarioExcluida(
    PreventivaExcluidaBorradorModel excluida,
  ) async {
    final actualIds = excluida.operariosIds.toSet();
    final finReferencia = excluida.fechaObjetivo.add(
      Duration(minutes: excluida.duracionMinutos),
    );
    final seleccionado = await _seleccionarOperarioDelConjunto(
      inicio: excluida.fechaObjetivo,
      fin: finReferencia,
      actualIds: actualIds,
    );

    if (seleccionado == null) return;
    if (!mounted) return;

    final nuevoOperarioId = int.tryParse((seleccionado['id'] ?? '').toString());
    if (nuevoOperarioId == null) {
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(
          content: Text(
            'No se pudo interpretar el ID del operario seleccionado.',
          ),
        ),
      );
      return;
    }

    final modo = await _preguntarModoCambioOperario();
    if (modo == null) return;

    final res = await _preventivaApi.reasignarOperarioExcluidaBorrador(
      nit: widget.nit,
      excluidaId: excluida.id,
      nuevoOperarioId: nuevoOperarioId,
      aplicarADefinicion: modo == _ModoCambioOperario.tambienDefinicion,
    );
    if (!mounted) return;

    final warning = (res['warning'] ?? '').toString().trim();
    final definicionActualizada = res['definicionActualizada'] == true;
    final mensaje = warning.isNotEmpty
        ? warning
        : definicionActualizada
        ? 'Operario de la excluida cambiado en borrador y definición.'
        : 'Operario de la excluida cambiado solo en este borrador.';

    AppFeedback.showFromSnackBar(context, SnackBar(content: Text(mensaje)));
    await _cargarDatos();
  }

  void _mostrarDetalleExcluida(PreventivaExcluidaBorradorModel item) {
    final fechaObjetivo = DateFormat(
      'dd/MM/yyyy',
      'es',
    ).format(item.fechaObjetivo);
    final operarios = item.operariosNombres.isEmpty
        ? 'Sin operario sugerido'
        : item.operariosNombres.join(', ');
    final bloques = item.divisionManual?.bloques ?? const [];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Detalle de excluida',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _infoRow('Descripción', item.descripcion),
              _infoRow('Fecha objetivo', fechaObjetivo),
              _infoRow('Prioridad', _labelPrioridad(item.prioridad)),
              _infoRow('Duración', item.duracionLabel),
              _infoRow('Ubicación', item.ubicacionNombre ?? '—'),
              _infoRow('Elemento', item.elementoNombre ?? '—'),
              _infoRow('Supervisor', item.supervisorNombre ?? '—'),
              _infoRow('Operarios', operarios),
              _infoRow('Motivo', item.motivoMensaje ?? item.motivoTipo),
              if (bloques.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Bloques manuales',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                ...bloques.map(
                  (bloque) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade200),
                      color: Colors.orange.withValues(alpha: 0.06),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bloque ${bloque.orden} · ${bloque.duracionLabel}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          bloque.agendado &&
                                  bloque.fechaInicio != null &&
                                  bloque.fechaFin != null
                              ? 'Agendado: ${DateFormat('dd/MM HH:mm', 'es').format(bloque.fechaInicio!)} - ${DateFormat('HH:mm').format(bloque.fechaFin!)}'
                              : 'Pendiente por agendar',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                        if (!bloque.agendado) ...[
                          const SizedBox(height: 8),
                          FilledButton.tonalIcon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _agendarBloqueExcluida(item, bloque);
                            },
                            icon: const Icon(Icons.search_outlined),
                            label: const Text('Buscar hueco para este bloque'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!item.tieneDivisionManual)
                    FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _agendarExcluida(item);
                      },
                      icon: const Icon(Icons.search_outlined),
                      label: const Text('Encontrar hueco'),
                    ),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _dividirExcluidaEnHoras(item);
                    },
                    icon: const Icon(Icons.splitscreen_outlined),
                    label: Text(
                      item.tieneDivisionManual
                          ? 'Redefinir división'
                          : 'Dividir en horas',
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _reasignarOperarioExcluida(item);
                    },
                    icon: const Icon(Icons.person_search_outlined),
                    label: const Text('Cambiar operario'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _mostrarDetalleTarea(TareaModel t, BuildContext ctx) {
    final iniLocal = t.fechaInicio.toLocal();
    final finLocal = t.fechaFin.toLocal();

    final fechaIniStr = DateFormat('dd/MM/yyyy HH:mm', 'es').format(iniLocal);
    final fechaFinStr = DateFormat('dd/MM/yyyy HH:mm', 'es').format(finLocal);

    final evidenciasTxt = (t.evidencias ?? []).isEmpty
        ? 'Sin evidencias'
        : t.evidencias!.join('\n');
    final insumosCount = (t.insumosUsados ?? []).length;

    final operarios = t.operariosNombres.isEmpty
        ? 'Sin asignar'
        : t.operariosNombres.join(', ');

    final conjuntoLabel = t.conjuntoNombre ?? t.conjuntoId ?? '—';
    final ubicacionLabel =
        t.ubicacionNombre ?? 'ID ${t.ubicacionId.toString()}';
    final elementoLabel = t.elementoNombre ?? 'ID ${t.elementoId.toString()}';
    final prioridadLabel = _labelPrioridad(t.prioridad);

    final supervisorLabel =
        t.supervisorNombre ??
        (t.supervisorId != null ? 'ID ${t.supervisorId}' : '—');

    final durMin = t.duracionMinutos;
    final durH = durMin / 60.0;

    final maquinariaLista = t.maquinariaPlan ?? const [];
    final maquinariaTxt = maquinariaLista.isEmpty
        ? 'Sin maquinaria planificada'
        : maquinariaLista
              .map((m) {
                String base = 'ID ${m.maquinariaId ?? '-'}';
                if (m.tipo != null && m.tipo!.trim().isNotEmpty) {
                  base += ' – ${m.tipo}';
                }
                if (m.cantidad != null) base += ' (${m.cantidad} h / unidades)';
                return base;
              })
              .join('\n');

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return StatefulBuilder(
              builder: (context, setSheetState) {
                final rows = <Widget>[];
                void addRow(String key, String label, String value) {
                  if (!_detalleCamposVisibles.contains(key)) return;
                  rows.add(_infoRow(label, value));
                }

                addRow('id', 'ID', t.id.toString());
                addRow('descripcion', 'Descripción', t.descripcion);
                addRow('estado', 'Estado', t.estado ?? '—');
                addRow('tipo', 'Tipo', t.tipo ?? '—');
                addRow('frecuencia', 'Frecuencia', t.frecuencia ?? '—');
                addRow('prioridad', 'Prioridad', prioridadLabel);
                rows.add(const SizedBox(height: 8));
                addRow('fechaInicio', 'Fecha inicio', fechaIniStr);
                addRow('fechaFin', 'Fecha fin', fechaFinStr);
                addRow(
                  'duracion',
                  'Duración',
                  '$durMin min (${durH.toStringAsFixed(1)} h)',
                );
                rows.add(const SizedBox(height: 8));
                addRow('conjunto', 'Conjunto', conjuntoLabel);
                addRow('ubicacion', 'Ubicación', ubicacionLabel);
                addRow('elemento', 'Elemento', elementoLabel);
                addRow('supervisor', 'Supervisor', supervisorLabel);
                rows.add(const SizedBox(height: 8));
                addRow('operarios', 'Operarios', operarios);
                addRow('maquinaria', 'Maquinaria planificada', maquinariaTxt);
                rows.add(const SizedBox(height: 8));
                addRow(
                  'observaciones',
                  'Observaciones',
                  t.observaciones ?? '—',
                );
                addRow('evidencias', 'Evidencias', evidenciasTxt);
                addRow(
                  'insumos',
                  'Insumos usados',
                  insumosCount == 0
                      ? 'Sin insumos registrados'
                      : '$insumosCount ítem(s)',
                );

                return Material(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Detalle de la tarea',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.tune),
                              tooltip: 'Elegir informacion visible',
                              onPressed: () => _configurarCamposDetalle(
                                () => setSheetState(() {}),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ...rows,
                              const SizedBox(height: 16),
                              FilledButton.tonalIcon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _reasignarOperarioTarea(t);
                                },
                                icon: const Icon(Icons.person_search_outlined),
                                label: const Text('Cambiar operario'),
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  static const Map<String, String> _leyendaEstados = {
    'AS': 'Asignada',
    'EP': 'En proceso',
    'CO': 'Completada',
    'AP': 'Aprobada',
    'PA': 'Pendiente aprobación',
    'RE': 'Rechazada',
    'NC': 'No completada',
    'PR': 'Pendiente reprogramación',
  };

  Widget _buildLeyendaMensual() {
    // mostrar solo lo que aparece en el mes
    final usados = <String>{};
    for (final f in _buildFilasCronoMensual()) {
      usados.addAll(f.porDia.values.where((x) => x.trim().isNotEmpty));
    }

    final items = usados.toList()..sort();

    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        children: items.map((code) {
          final label = _leyendaEstados[code] ?? 'Estado: $code';
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: AppTheme.primary.withValues(alpha: 0.18),
              ),
            ),
            child: Text(
              '$code = $label',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade900,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.primary;
    final mesNombre = DateFormat.MMMM('es').format(_inicioMes).toUpperCase();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: primary,
        title: const Text(
          'Cronograma preventivas (borrador)',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // ✅ refresca generando de nuevo y mostrando novedades
          IconButton(
            onPressed: _generarYcargarAlEntrar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildError()
          : _buildContenido(mesNombre),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 40),
            const SizedBox(height: 12),
            Text(
              'Error cargando cronograma:\n$_error',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _generarYcargarAlEntrar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContenido(String mesNombre) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _buildTopBar(mesNombre),
          if (_vista == _VistaCronograma.mensual)
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 180),
              crossFadeState: _mostrarFiltrosMensual
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _buildFiltrosMensualCompacto(),
              ),
              secondChild: const SizedBox.shrink(),
            ),
          const SizedBox(height: 10),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: _vista == _VistaCronograma.mensual
                      ? _buildCronogramaMensualTipoFoto()
                      : _vista == _VistaCronograma.semanal
                      ? _buildAgendaSemanal()
                      : _buildInformeActividad(),
                ),
                if (_vista == _VistaCronograma.mensual) _buildLeyendaMensual(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(String mesNombre) {
    final start = _startOfWeekMonday(_semanaBase);
    final end = _endOfWeekSunday(_semanaBase);
    final rangoSemana =
        "${DateFormat('dd MMM', 'es').format(start)} - ${DateFormat('dd MMM', 'es').format(end)}";
    final isNarrow = MediaQuery.of(context).size.width < 880;

    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<_VistaCronograma>(
              segments: const [
                ButtonSegment(
                  value: _VistaCronograma.mensual,
                  label: Text('Mensual'),
                  icon: Icon(Icons.calendar_month),
                ),
                ButtonSegment(
                  value: _VistaCronograma.semanal,
                  label: Text('Semanal'),
                  icon: Icon(Icons.view_week),
                ),
                ButtonSegment(
                  value: _VistaCronograma.informe,
                  label: Text('Informe'),
                  icon: Icon(Icons.table_chart_outlined),
                ),
              ],
              selected: {_vista},
              onSelectionChanged: (s) => setState(() => _vista = s.first),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (_vista == _VistaCronograma.mensual) ...[
                  IconButton(
                    tooltip: 'Mes anterior',
                    onPressed: () => _cambiarMes(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(
                    '$mesNombre $_anioActual',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Mes siguiente',
                    onPressed: () => _cambiarMes(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.filter_alt_outlined, size: 18),
                    label: Text(
                      _hayFiltrosActivos() ? 'Filtros â€¢' : 'Filtros',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () => setState(
                      () => _mostrarFiltrosMensual = !_mostrarFiltrosMensual,
                    ),
                  ),
                ] else ...[
                  IconButton(
                    tooltip: 'Semana anterior',
                    onPressed: () => setState(
                      () => _semanaBase = _semanaBase.subtract(
                        const Duration(days: 7),
                      ),
                    ),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(
                    rangoSemana,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Semana siguiente',
                    onPressed: () => setState(
                      () => _semanaBase = _semanaBase.add(
                        const Duration(days: 7),
                      ),
                    ),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        SegmentedButton<_VistaCronograma>(
          segments: const [
            ButtonSegment(
              value: _VistaCronograma.mensual,
              label: Text('Mensual'),
              icon: Icon(Icons.calendar_month),
            ),
            ButtonSegment(
              value: _VistaCronograma.semanal,
              label: Text('Semanal'),
              icon: Icon(Icons.view_week),
            ),
            ButtonSegment(
              value: _VistaCronograma.informe,
              label: Text('Informe'),
              icon: Icon(Icons.table_chart_outlined),
            ),
          ],
          selected: {_vista},
          onSelectionChanged: (s) => setState(() => _vista = s.first),
        ),
        const Spacer(),
        if (_vista == _VistaCronograma.mensual) ...[
          IconButton(
            tooltip: 'Mes anterior',
            onPressed: () => _cambiarMes(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          Text(
            '$mesNombre $_anioActual',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          IconButton(
            tooltip: 'Mes siguiente',
            onPressed: () => _cambiarMes(1),
            icon: const Icon(Icons.chevron_right),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.filter_alt_outlined, size: 18),
            label: Text(
              _hayFiltrosActivos() ? 'Filtros •' : 'Filtros',
              style: const TextStyle(fontSize: 12),
            ),
            onPressed: () => setState(
              () => _mostrarFiltrosMensual = !_mostrarFiltrosMensual,
            ),
          ),
        ] else ...[
          IconButton(
            tooltip: 'Semana anterior',
            onPressed: () => setState(
              () => _semanaBase = _semanaBase.subtract(const Duration(days: 7)),
            ),
            icon: const Icon(Icons.chevron_left),
          ),
          Text(
            rangoSemana,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          IconButton(
            tooltip: 'Semana siguiente',
            onPressed: () => setState(
              () => _semanaBase = _semanaBase.add(const Duration(days: 7)),
            ),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ],
    );
  }

  Widget _buildAgendaSemanal() {
    final weekStart = _startOfWeekMonday(_semanaBase);
    final tareas = _tareasSemana(_semanaBase);
    final resumenSemana = _calcularResumenHorasSemana(weekStart, tareas);
    final resumenOperarios = _calcularResumenHorasSemanaPorOperario(
      weekStart,
      tareas,
    );

    final w = MediaQuery.of(context).size.width;
    final showSidebar = w >= 1100;

    if (!showSidebar) {
      return _WeekScheduleView(
        weekStart: weekStart,
        tareas: tareas,
        horaInicio: _horaInicioJornada,
        horaFin: _horaFinJornada,
        horaDescansoInicio: _horaDescansoInicio,
        horaDescansoFin: _horaDescansoFin,
        esFestivo: _esFestivo,
        nombreFestivo: _nombreFestivo,
        onTapTarea: (t) => _mostrarDetalleTarea(t, context),
      );
    }

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: _SidebarSimple(
            title: 'Resumen',
            items: [
              'Tareas semana: ${tareas.length}',
              'Tareas mes: ${_tareasFiltradas.length}',
              _resumenHorario,
            ],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _buildFiltrosComoColumna(mostrarTitulo: false),
                ),
                const SizedBox(height: 12),
                _buildResumenHorasSemanaCard(resumenSemana, resumenOperarios),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 8,
          child: _WeekScheduleView(
            weekStart: weekStart,
            tareas: tareas,
            horaInicio: _horaInicioJornada,
            horaFin: _horaFinJornada,
            horaDescansoInicio: _horaDescansoInicio,
            horaDescansoFin: _horaDescansoFin,
            esFestivo: _esFestivo,
            nombreFestivo: _nombreFestivo,
            onTapTarea: (t) => _mostrarDetalleTarea(t, context),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 4,
          child: _SidebarAgendaDia(
            weekStart: weekStart,
            tareasSemana: tareas,
            onTapTarea: (t) => _mostrarDetalleTarea(t, context),
            excluidasMes: _excluidasMes,
            excluirPorFecha: _excluidasPorFecha,
            onReordenarTareasDia: _reordenarTareasDia,
            onEliminarTarea: _eliminarTareaBorrador,
            onTapExcluida: _mostrarDetalleExcluida,
            onAgendarExcluida: _agendarExcluida,
            onDividirExcluida: _dividirExcluidaEnHoras,
            onAgendarBloqueExcluida: _agendarBloqueExcluida,
            onReemplazarConExcluida: _reemplazarTareaConExcluida,
            onReasignarOperario: _reasignarOperarioTarea,
            onReasignarOperarioExcluida: _reasignarOperarioExcluida,
          ),
        ),
      ],
    );
  }

  int _indiceSemanaMes(DateTime date) =>
      (((date.toLocal().day - 1) ~/ 7) + 1).clamp(1, 5);

  List<_HorasGrupoResumen> _resumenHorasAgrupadas(
    List<TareaModel> tareas,
    Iterable<String> Function(TareaModel tarea) keysForTask,
  ) {
    final acumulado = <String, List<double>>{};

    for (final tarea in tareas) {
      final keys = keysForTask(
        tarea,
      ).map((item) => item.trim()).where((item) => item.isNotEmpty).toSet();
      if (keys.isEmpty) continue;

      final semana = _indiceSemanaMes(tarea.fechaInicio);
      final horas = tarea.duracionHorasDecimal;

      for (final key in keys) {
        final bucket = acumulado.putIfAbsent(key, () => List.filled(6, 0));
        bucket[0] += horas;
        bucket[semana] += horas;
      }
    }

    final rows = acumulado.entries
        .map(
          (entry) => _HorasGrupoResumen(
            nombre: entry.key,
            horasMes: entry.value[0],
            semana1: entry.value[1],
            semana2: entry.value[2],
            semana3: entry.value[3],
            semana4: entry.value[4],
            semana5: entry.value[5],
          ),
        )
        .toList();

    rows.sort((a, b) {
      final byHours = b.horasMes.compareTo(a.horasMes);
      if (byHours != 0) return byHours;
      return a.nombre.compareTo(b.nombre);
    });
    return rows;
  }

  Widget _buildInformeHorasTable({
    required String titulo,
    required String columnaPrincipal,
    required List<_HorasGrupoResumen> rows,
    required String emptyLabel,
  }) {
    DataColumn col(String label) => DataColumn(label: Text(label));
    DataCell cellNum(num value) => DataCell(Text(value.toStringAsFixed(1)));

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              titulo,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 4),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                emptyLabel,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  col(columnaPrincipal),
                  col('Horas mes'),
                  col('Semana 1'),
                  col('Semana 2'),
                  col('Semana 3'),
                  col('Semana 4'),
                  col('Semana 5'),
                ],
                rows: rows
                    .map(
                      (item) => DataRow(
                        cells: [
                          DataCell(
                            SizedBox(
                              width: 320,
                              child: Text(
                                item.nombre,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          cellNum(item.horasMes),
                          cellNum(item.semana1),
                          cellNum(item.semana2),
                          cellNum(item.semana3),
                          cellNum(item.semana4),
                          cellNum(item.semana5),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInformeActividad() {
    if (_informeActividad.isEmpty) {
      return const Center(
        child: Text('No hay actividades planificadas para este periodo.'),
      );
    }

    final horasPorZona = _resumenHorasAgrupadas(
      _tareasFiltradas,
      (tarea) => [(tarea.ubicacionNombre ?? '').trim()],
    );
    final horasPorTrabajador = _resumenHorasAgrupadas(
      _tareasFiltradas,
      (tarea) => tarea.operariosNombres,
    );

    DataColumn col(String label) => DataColumn(label: Text(label));
    DataCell cellNum(num value) => DataCell(Text(value.toStringAsFixed(1)));

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  col('Actividad'),
                  col('Horas mes'),
                  col('Semana 1'),
                  col('Semana 2'),
                  col('Semana 3'),
                  col('Semana 4'),
                  col('Semana 5'),
                ],
                rows: _informeActividad
                    .map(
                      (item) => DataRow(
                        cells: [
                          DataCell(
                            SizedBox(
                              width: 320,
                              child: Text(
                                item.actividad,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          cellNum(item.horasMes),
                          cellNum(item.semana1),
                          cellNum(item.semana2),
                          cellNum(item.semana3),
                          cellNum(item.semana4),
                          cellNum(item.semana5),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
            _buildInformeHorasTable(
              titulo: 'Horas por ubicación',
              columnaPrincipal: 'Ubicación',
              rows: horasPorZona,
              emptyLabel: 'Sin ubicaciones con horas registradas.',
            ),
            _buildInformeHorasTable(
              titulo: 'Horas por trabajador',
              columnaPrincipal: 'Trabajador',
              rows: horasPorTrabajador,
              emptyLabel: 'Sin trabajadores con horas registradas.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final puedePublicar =
        _hayTareas && !_loading && !_publicando && _ventanaPublicacionAbierta;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: puedePublicar ? _publicarCronograma : null,
            icon: _publicando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.publish),
            label: Text(
              _publicando
                  ? 'Publicando...'
                  : _hayTareas
                  ? (_ventanaPublicacionAbierta
                        ? 'Publicar cronograma'
                        : 'Publicación disponible 7 días antes')
                  : 'No hay tareas para publicar',
            ),
          ),
        ),
      ),
    );
  }
}

class _HorasGrupoResumen {
  final String nombre;
  final double horasMes;
  final double semana1;
  final double semana2;
  final double semana3;
  final double semana4;
  final double semana5;

  const _HorasGrupoResumen({
    required this.nombre,
    required this.horasMes,
    required this.semana1,
    required this.semana2,
    required this.semana3,
    required this.semana4,
    required this.semana5,
  });
}

// ============================
//   WIDGETS: Semana tipo agenda
//   ✅ FIX: Banda de almuerzo + pxPorMin + tema claro
// ============================

Color _cronogramaBorradorColorBaseTareaSemana(TareaModel t) {
  final tipo = (t.tipo ?? '').toUpperCase().trim();
  if (tipo == 'CORRECTIVA') return Colors.red.shade500;

  final texto = '${t.ubicacionNombre ?? ''} ${t.elementoNombre ?? ''}'
      .toLowerCase();
  if (texto.contains('humed') || texto.contains('agua')) {
    return Colors.blue.shade500;
  }
  if (texto.contains('verde') ||
      texto.contains('jardin') ||
      texto.contains('cesped')) {
    return Colors.green.shade600;
  }
  if (texto.contains('transit') || texto.contains('circul')) {
    return Colors.orange.shade600;
  }
  if (texto.contains('parque') || texto.contains('parqueadero')) {
    return Colors.brown.shade500;
  }
  return AppTheme.primary;
}

class _WeekScheduleView extends StatefulWidget {
  final DateTime weekStart; // lunes 00:00
  final List<TareaModel> tareas;
  final int horaInicio;
  final int horaFin;
  final int? horaDescansoInicio;
  final int? horaDescansoFin;
  final bool Function(DateTime d) esFestivo;
  final String? Function(DateTime d) nombreFestivo;
  final void Function(TareaModel t) onTapTarea;

  const _WeekScheduleView({
    required this.weekStart,
    required this.tareas,
    required this.horaInicio,
    required this.horaFin,
    this.horaDescansoInicio,
    this.horaDescansoFin,
    required this.esFestivo,
    required this.nombreFestivo,
    required this.onTapTarea,
  });

  @override
  State<_WeekScheduleView> createState() => _WeekScheduleViewState();
}

class _WeekTaskSpan {
  final TareaModel tarea;
  final DateTime inicio;
  final DateTime fin;

  const _WeekTaskSpan({
    required this.tarea,
    required this.inicio,
    required this.fin,
  });
}

class _WeekTaskPlacement {
  final TareaModel tarea;
  final int dayIndex;
  final DateTime inicio;
  final DateTime fin;
  final DateTime groupEnd;
  final int groupSize;
  final int orderInGroup;
  final List<String> groupTitles;

  const _WeekTaskPlacement({
    required this.tarea,
    required this.dayIndex,
    required this.inicio,
    required this.fin,
    required this.groupEnd,
    required this.groupSize,
    required this.orderInGroup,
    required this.groupTitles,
  });
}

class _WeekScheduleViewState extends State<_WeekScheduleView> {
  final ScrollController _headerHCtrl = ScrollController();
  final ScrollController _hCtrl = ScrollController();
  final ScrollController _vCtrl = ScrollController();
  bool _syncingHeader = false;
  bool _syncingBody = false;

  // Mas respirable
  static const double pxPorMin = 1.6; // estaba 1.2
  static const double anchoHora = 56;
  static const double altoHeader = 44;

  int get _horaInicio => widget.horaInicio;
  int get _horaFin => widget.horaFin;
  int get _horasVisible => (_horaFin - _horaInicio).clamp(1, 24);

  int _minutesFromStart(DateTime d) {
    final start = DateTime(d.year, d.month, d.day, _horaInicio);
    return d.difference(start).inMinutes;
  }

  int _dayIndex(DateTime d) {
    final diff = DateTime(d.year, d.month, d.day)
        .difference(
          DateTime(
            widget.weekStart.year,
            widget.weekStart.month,
            widget.weekStart.day,
          ),
        )
        .inDays;
    return diff;
  }

  bool _isWithinWeek(DateTime d) {
    final start = DateTime(
      widget.weekStart.year,
      widget.weekStart.month,
      widget.weekStart.day,
    );
    final end = start.add(const Duration(days: 7));
    final dd = DateTime(d.year, d.month, d.day);
    return !dd.isBefore(start) && dd.isBefore(end);
  }

  DateTime _ensureEndAfterStart(DateTime start, DateTime end) {
    if (end.isAfter(start)) return end;
    return start.add(const Duration(minutes: 1));
  }

  bool _tareaTieneVariosOperarios(TareaModel tarea) {
    return tarea.operariosNombres
            .map((name) => name.trim())
            .where((name) => name.isNotEmpty)
            .toSet()
            .length >=
        2;
  }

  DateTime _effectiveGroupEnd(_WeekTaskSpan span) {
    if (!_tareaTieneVariosOperarios(span.tarea)) {
      return span.fin;
    }

    final normalized = _ensureEndAfterStart(span.inicio, span.fin);
    final minMinutes = (18 / pxPorMin).ceil();
    final visualMinEnd = span.inicio.add(Duration(minutes: minMinutes));
    return normalized.isAfter(visualMinEnd) ? normalized : visualMinEnd;
  }

  List<_WeekTaskPlacement> _buildTaskPlacements() {
    final spansByDay = List.generate(7, (_) => <_WeekTaskSpan>[]);

    for (final t in widget.tareas) {
      final inicioOriginal = t.fechaInicio.toLocal();
      if (!_isWithinWeek(inicioOriginal)) continue;

      final day = _dayIndex(inicioOriginal);
      if (day < 0 || day > 6) continue;

      final finOriginal = _ensureEndAfterStart(
        inicioOriginal,
        t.fechaFin.toLocal(),
      );
      final inicioJornada = DateTime(
        inicioOriginal.year,
        inicioOriginal.month,
        inicioOriginal.day,
        _horaInicio,
      );
      final finJornada = DateTime(
        inicioOriginal.year,
        inicioOriginal.month,
        inicioOriginal.day,
        _horaFin,
      );

      if (!finOriginal.isAfter(inicioJornada) ||
          !inicioOriginal.isBefore(finJornada)) {
        continue;
      }

      final inicio = inicioOriginal.isBefore(inicioJornada)
          ? inicioJornada
          : inicioOriginal;
      final fin = finOriginal.isAfter(finJornada) ? finJornada : finOriginal;
      spansByDay[day].add(_WeekTaskSpan(tarea: t, inicio: inicio, fin: fin));
    }

    final out = <_WeekTaskPlacement>[];

    for (int day = 0; day < 7; day++) {
      final daySpans = spansByDay[day]
        ..sort((a, b) {
          final byStart = a.inicio.compareTo(b.inicio);
          if (byStart != 0) return byStart;
          final byEnd = a.fin.compareTo(b.fin);
          if (byEnd != 0) return byEnd;
          return a.tarea.id.compareTo(b.tarea.id);
        });

      if (daySpans.isEmpty) continue;

      final group = <_WeekTaskSpan>[];
      DateTime? groupEnd;

      void flushGroup() {
        if (group.isEmpty) return;
        out.addAll(_buildGroupPlacements(group, day));
        group.clear();
        groupEnd = null;
      }

      for (final span in daySpans) {
        final effectiveEnd = _effectiveGroupEnd(span);
        if (group.isEmpty) {
          group.add(span);
          groupEnd = effectiveEnd;
          continue;
        }

        final overlapsGroup = span.inicio.isBefore(groupEnd!);
        if (overlapsGroup) {
          group.add(span);
          if (effectiveEnd.isAfter(groupEnd!)) groupEnd = effectiveEnd;
          continue;
        }

        flushGroup();
        group.add(span);
        groupEnd = effectiveEnd;
      }

      flushGroup();
    }

    return out;
  }

  List<_WeekTaskPlacement> _buildGroupPlacements(
    List<_WeekTaskSpan> group,
    int dayIndex,
  ) {
    final groupEnd = group
        .map((e) => e.fin)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final groupTitles = group
        .map((e) => e.tarea.descripcion.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

    return group
        .asMap()
        .entries
        .map(
          (entry) => _WeekTaskPlacement(
            tarea: entry.value.tarea,
            dayIndex: dayIndex,
            inicio: entry.value.inicio,
            fin: entry.value.fin,
            groupEnd: groupEnd,
            groupSize: group.length,
            orderInGroup: entry.key,
            groupTitles: groupTitles,
          ),
        )
        .toList();
  }

  @override
  void dispose() {
    _headerHCtrl.dispose();
    _hCtrl.dispose();
    _vCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _headerHCtrl.addListener(() {
      if (_syncingBody || !_hCtrl.hasClients) return;
      _syncingHeader = true;
      _hCtrl.jumpTo(_headerHCtrl.offset);
      _syncingHeader = false;
    });
    _hCtrl.addListener(() {
      if (_syncingHeader || !_headerHCtrl.hasClients) return;
      _syncingBody = true;
      _headerHCtrl.jumpTo(_hCtrl.offset);
      _syncingBody = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hours = _horasVisible;
    final heightGrid = (hours * 60) * pxPorMin;
    final taskPlacements = _buildTaskPlacements();

    // ✅ tema claro
    final bg = Colors.white;
    final line = Colors.grey.shade300;
    final text = Colors.grey.shade900;
    final subtext = Colors.grey.shade700;

    final lunchStartMin = widget.horaDescansoInicio != null
        ? (widget.horaDescansoInicio! - _horaInicio) * 60
        : null;
    final lunchDurMin =
        widget.horaDescansoInicio != null && widget.horaDescansoFin != null
        ? (widget.horaDescansoFin! - widget.horaDescansoInicio!) * 60
        : null;

    return LayoutBuilder(
      builder: (context, c) {
        const minDayCol = 120.0;
        final available = c.maxWidth - anchoHora;
        final colWidth = (available / 7).clamp(minDayCol, 9999.0);
        final totalWidth = anchoHora + colWidth * 7;

        return Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade300), // ✅
          ),
          child: Column(
            children: [
              SizedBox(
                height: altoHeader,
                child: SingleChildScrollView(
                  controller: _headerHCtrl,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: totalWidth,
                    child: Row(
                      children: [
                        SizedBox(
                          width: anchoHora,
                          child: Center(
                            child: Text(
                              'Hora',
                              style: TextStyle(color: subtext, fontSize: 12),
                            ),
                          ),
                        ),
                        ...List.generate(7, (i) {
                          final d = widget.weekStart.add(Duration(days: i));
                          final label = [
                            "Lun",
                            "Mar",
                            "Mié",
                            "Jue",
                            "Vie",
                            "Sáb",
                            "Dom",
                          ][i];
                          final fest = widget.esFestivo(d);
                          final festivoNombre = widget.nombreFestivo(d);
                          return SizedBox(
                            width: colWidth,
                            child: Tooltip(
                              message: fest
                                  ? 'Festivo${festivoNombre != null ? ': $festivoNombre' : ''}'
                                  : '',
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                  vertical: 4,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: fest
                                      ? const Color(0xFFFFCDD2)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  border: fest
                                      ? Border.all(
                                          color: const Color(0xFFD32F2F),
                                          width: 1,
                                        )
                                      : null,
                                ),
                                child: Center(
                                  child: Text(
                                    fest
                                        ? "$label ${d.day} • F"
                                        : "$label ${d.day}",
                                    style: TextStyle(
                                      color: fest
                                          ? const Color(0xFFB71C1C)
                                          : text,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ),
              Container(height: 1, color: line),
              Expanded(
                child: Scrollbar(
                  controller: _hCtrl,
                  thumbVisibility: true,
                  scrollbarOrientation: ScrollbarOrientation.bottom,
                  child: SingleChildScrollView(
                    controller: _hCtrl,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: totalWidth,
                      child: SingleChildScrollView(
                        controller: _vCtrl,
                        child: SizedBox(
                          height: heightGrid,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: anchoHora,
                                      child: _HoursColumnDark(
                                        pxPorMin: pxPorMin,
                                        textColor: subtext,
                                        horaInicio: _horaInicio,
                                        horaFin: _horaFin,
                                      ),
                                    ),
                                    ...List.generate(7, (_) {
                                      return Container(
                                        width: colWidth,
                                        decoration: BoxDecoration(
                                          border: Border(
                                            left: BorderSide(color: line),
                                          ),
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),

                              // líneas horizontales por hora
                              ...List.generate(hours + 1, (h) {
                                final top = (h * 60) * pxPorMin;
                                return Positioned(
                                  left: 0,
                                  right: 0,
                                  top: top,
                                  child: Container(height: 1, color: line),
                                );
                              }),

                              if (lunchStartMin != null &&
                                  lunchDurMin != null &&
                                  lunchDurMin > 0 &&
                                  lunchStartMin >= 0)
                                Positioned(
                                  left: anchoHora,
                                  right: 0,
                                  top: lunchStartMin * pxPorMin,
                                  height: lunchDurMin * pxPorMin,
                                  child: Container(
                                    color: Colors.orange.withValues(
                                      alpha: 0.12,
                                    ),
                                  ),
                                ),

                              // tareas
                              ...taskPlacements.map((placement) {
                                final t = placement.tarea;
                                final ini = placement.inicio;
                                final fin = placement.fin;

                                final startMin = _minutesFromStart(ini);
                                final durMin = fin.difference(ini).inMinutes;

                                const dayPadding = 6.0;
                                final left =
                                    anchoHora +
                                    placement.dayIndex * colWidth +
                                    dayPadding;
                                final top = startMin * pxPorMin;
                                final fullWidth = colWidth - (dayPadding * 2);
                                final colorBase =
                                    _cronogramaBorradorColorBaseTareaSemana(t);
                                final fill = colorBase.withValues(alpha: 0.12);
                                final border = colorBase.withValues(
                                  alpha: 0.55,
                                );

                                final horaIni = DateFormat('HH:mm').format(ini);
                                final horaFinStr = DateFormat(
                                  'HH:mm',
                                ).format(fin);
                                final horaFinGrupo = DateFormat(
                                  'HH:mm',
                                ).format(placement.groupEnd);

                                if (placement.groupSize > 1) {
                                  if (placement.orderInGroup != 0) {
                                    return const SizedBox.shrink();
                                  }

                                  final colors = [
                                    Colors.red.shade400,
                                    Colors.blue.shade500,
                                    Colors.green.shade500,
                                    Colors.orange.shade500,
                                  ];
                                  final dotCount = placement.groupSize > 4
                                      ? 4
                                      : placement.groupSize;
                                  final resumen = placement.groupTitles
                                      .take(2)
                                      .join(' / ');
                                  final extra = placement.groupSize - 2;
                                  final overlapMinutes = placement.groupEnd
                                      .difference(placement.inicio)
                                      .inMinutes;
                                  final markerHeight =
                                      ((overlapMinutes <= 0
                                                  ? 1
                                                  : overlapMinutes) *
                                              pxPorMin)
                                          .clamp(26.0, 120.0);

                                  return Positioned(
                                    left: left,
                                    top: top,
                                    width: fullWidth,
                                    height: markerHeight,
                                    child: GestureDetector(
                                      onTap: () => widget.onTapTarea(t),
                                      child: Container(
                                        clipBehavior: Clip.hardEdge,
                                        padding: const EdgeInsets.fromLTRB(
                                          8,
                                          7,
                                          8,
                                          7,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.withValues(
                                            alpha: 0.14,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: Colors.amber.shade700,
                                            width: 1,
                                          ),
                                        ),
                                        child: LayoutBuilder(
                                          builder: (context, box) {
                                            if (box.maxHeight < 18) {
                                              return const SizedBox.shrink();
                                            }
                                            final compactMarker =
                                                box.maxHeight < 58;
                                            final ultraCompactMarker =
                                                box.maxHeight < 34;
                                            return Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    ...List.generate(dotCount, (
                                                      i,
                                                    ) {
                                                      return Container(
                                                        width: 10,
                                                        height: 10,
                                                        margin: EdgeInsets.only(
                                                          right:
                                                              i == dotCount - 1
                                                              ? 0
                                                              : 4,
                                                        ),
                                                        decoration: BoxDecoration(
                                                          color:
                                                              colors[i %
                                                                  colors
                                                                      .length],
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                2,
                                                              ),
                                                        ),
                                                      );
                                                    }),
                                                    if (!ultraCompactMarker &&
                                                        placement.groupSize >
                                                            dotCount) ...[
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        '+${placement.groupSize - dotCount}',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          color: text,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ],
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        compactMarker
                                                            ? 'Tareas solapadas'
                                                            : 'Superposicion detectada',
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          color: text,
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                if (!compactMarker) ...[
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    'Aqui hay ${placement.groupSize} tareas superpuestas. Filtra por operario para verlo mejor.',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: subtext,
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                ] else if (!ultraCompactMarker)
                                                  const SizedBox(height: 2),
                                                if (!ultraCompactMarker)
                                                  Text(
                                                    '$horaIni - $horaFinGrupo${resumen.isEmpty ? '' : ' • $resumen${extra > 0 ? ' y $extra mas' : ''}'}',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: subtext,
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                              ],
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  );
                                }

                                final height =
                                    ((durMin <= 0 ? 1 : durMin) * pxPorMin)
                                        .clamp(18.0, 9999.0);

                                return Positioned(
                                  left: left,
                                  top: top,
                                  width: fullWidth,
                                  height: height,
                                  child: GestureDetector(
                                    onTap: () => widget.onTapTarea(t),
                                    child: Container(
                                      clipBehavior: Clip.hardEdge,
                                      padding: EdgeInsets.fromLTRB(
                                        6,
                                        height < 30 ? 1 : (height < 42 ? 3 : 8),
                                        6,
                                        height < 30 ? 1 : (height < 42 ? 3 : 8),
                                      ),
                                      decoration: BoxDecoration(
                                        color: fill,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: border,
                                          width: 1,
                                        ),
                                      ),
                                      child: LayoutBuilder(
                                        builder: (context, box) {
                                          final h = box.maxHeight;
                                          final tiny = h < 26;
                                          final compact = h < 54;

                                          return Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Tooltip(
                                                message: t.descripcion,
                                                waitDuration: const Duration(
                                                  milliseconds: 250,
                                                ),
                                                child: Text(
                                                  t.descripcion,
                                                  maxLines: compact ? 1 : 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: text,
                                                    fontSize: tiny
                                                        ? 8
                                                        : (compact ? 10 : 12),
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                              if (!compact) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  '$horaIni - $horaFinStr',
                                                  style: TextStyle(
                                                    color: subtext,
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HoursColumnDark extends StatelessWidget {
  final double pxPorMin;
  final Color textColor;
  final int horaInicio;
  final int horaFin;

  const _HoursColumnDark({
    required this.pxPorMin,
    required this.textColor,
    required this.horaInicio,
    required this.horaFin,
  });

  @override
  Widget build(BuildContext context) {
    final hours = (horaFin - horaInicio).clamp(1, 24);

    return LayoutBuilder(
      builder: (context, c) {
        final height = c.maxHeight;

        return Stack(
          children: List.generate(hours + 1, (i) {
            final h = horaInicio + i;

            double top = (i * 60) * pxPorMin;
            top += 6;

            const labelHeight = 16.0;
            if (top > height - labelHeight) top = height - labelHeight;

            return Positioned(
              top: top,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  "${h.toString().padLeft(2, '0')}:00",
                  style: TextStyle(fontSize: 11, color: textColor),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// Sidebar simple (izquierda)
class _SidebarSimple extends StatelessWidget {
  final String title;
  final List<String> items;
  final Widget? child;

  const _SidebarSimple({required this.title, required this.items, this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...items.map(
                          (s) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              '• $s',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        if (child != null) ...[const Divider(), child!],
                        const SizedBox(height: 12),
                        Text(
                          'Tip: aquí metes filtros (supervisor, operario, ubicación) sin tocar la agenda.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// Sidebar agenda del día (derecha)
class _SidebarAgendaDia extends StatefulWidget {
  final DateTime weekStart;
  final List<TareaModel> tareasSemana;
  final void Function(TareaModel t) onTapTarea;
  final List<PreventivaExcluidaBorradorModel> excluidasMes;
  final List<PreventivaExcluidaBorradorModel> Function(DateTime fecha)
  excluirPorFecha;
  final Future<void> Function(DateTime fecha, List<TareaModel> tareasOrdenadas)
  onReordenarTareasDia;
  final Future<void> Function(TareaModel tarea) onEliminarTarea;
  final void Function(PreventivaExcluidaBorradorModel excluida) onTapExcluida;
  final Future<void> Function(PreventivaExcluidaBorradorModel excluida)
  onAgendarExcluida;
  final Future<void> Function(PreventivaExcluidaBorradorModel excluida)
  onDividirExcluida;
  final Future<void> Function(
    PreventivaExcluidaBorradorModel excluida,
    PreventivaExcluidaBloqueModel bloque,
  )
  onAgendarBloqueExcluida;
  final Future<void> Function(TareaModel tarea) onReemplazarConExcluida;
  final Future<void> Function(TareaModel tarea) onReasignarOperario;
  final Future<void> Function(PreventivaExcluidaBorradorModel excluida)
  onReasignarOperarioExcluida;

  const _SidebarAgendaDia({
    required this.weekStart,
    required this.tareasSemana,
    required this.onTapTarea,
    required this.excluidasMes,
    required this.excluirPorFecha,
    required this.onReordenarTareasDia,
    required this.onEliminarTarea,
    required this.onTapExcluida,
    required this.onAgendarExcluida,
    required this.onDividirExcluida,
    required this.onAgendarBloqueExcluida,
    required this.onReemplazarConExcluida,
    required this.onReasignarOperario,
    required this.onReasignarOperarioExcluida,
  });

  @override
  State<_SidebarAgendaDia> createState() => _SidebarAgendaDiaState();
}

class _SidebarAgendaDiaState extends State<_SidebarAgendaDia> {
  int _diaIndex = 0; // 0..6
  bool _verExcluidasMes = false;
  final Set<int> _excluidasExpandidaIds = <int>{};
  bool _reordenandoDia = false;

  @override
  Widget build(BuildContext context) {
    final fecha = widget.weekStart.add(Duration(days: _diaIndex));
    final tareasDia = widget.tareasSemana.where((t) {
      final d = t.fechaInicio.toLocal();
      return d.year == fecha.year &&
          d.month == fecha.month &&
          d.day == fecha.day;
    }).toList()..sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));
    final excluidas = _verExcluidasMes
        ? widget.excluidasMes
        : widget.excluirPorFecha(fecha);

    return Card(
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Agenda',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
                DropdownButton<int>(
                  value: _diaIndex,
                  items: List.generate(7, (i) {
                    final d = widget.weekStart.add(Duration(days: i));
                    final label = [
                      "Lun",
                      "Mar",
                      "Mié",
                      "Jue",
                      "Vie",
                      "Sáb",
                      "Dom",
                    ][i];
                    return DropdownMenuItem(
                      value: i,
                      child: Text("$label ${d.day}"),
                    );
                  }),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _diaIndex = v);
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(value: false, label: Text('Excluidas dia')),
                ButtonSegment<bool>(value: true, label: Text('Excluidas mes')),
              ],
              selected: {_verExcluidasMes},
              onSelectionChanged: (value) {
                setState(() => _verExcluidasMes = value.first);
              },
            ),
            const SizedBox(height: 6),
            Text(
              DateFormat("EEEE dd MMMM", "es").format(fecha),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const Divider(height: 18),
            Expanded(
              child: ListView(
                children: [
                  Text(
                    'Programadas (${tareasDia.length})',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  if (tareasDia.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Sin tareas este día',
                        style: TextStyle(fontSize: 12),
                      ),
                    )
                  else ...[
                    Text(
                      'Arrastra para cambiar el orden del día.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: tareasDia.length,
                      buildDefaultDragHandles: false,
                      onReorder: (oldIndex, newIndex) async {
                        if (_reordenandoDia) return;
                        if (newIndex > oldIndex) newIndex -= 1;
                        final nuevas = [...tareasDia];
                        final item = nuevas.removeAt(oldIndex);
                        nuevas.insert(newIndex, item);
                        setState(() => _reordenandoDia = true);
                        try {
                          await widget.onReordenarTareasDia(fecha, nuevas);
                        } catch (e) {
                          if (context.mounted) {
                            AppFeedback.showFromSnackBar(
                              context,
                              SnackBar(
                                content: Text(
                                  'No se pudo reordenar el día: $e',
                                ),
                              ),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _reordenandoDia = false);
                        }
                      },
                      itemBuilder: (context, index) {
                        final t = tareasDia[index];
                        final ini = t.fechaInicio.toLocal();
                        final fin = t.fechaFin.toLocal();
                        return Padding(
                          key: ValueKey('task-${t.id}'),
                          padding: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            onTap: () => widget.onTapTarea(t),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppTheme.primary.withValues(
                                    alpha: 0.25,
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          t.descripcion,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      ReorderableDragStartListener(
                                        index: index,
                                        child: const Padding(
                                          padding: EdgeInsets.only(left: 8),
                                          child: Icon(Icons.drag_indicator),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    "${DateFormat('HH:mm').format(ini)} - ${DateFormat('HH:mm').format(fin)}",
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      TextButton.icon(
                                        onPressed: () =>
                                            widget.onEliminarTarea(t),
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          size: 16,
                                        ),
                                        label: const Text('Eliminar'),
                                      ),
                                      const SizedBox(width: 6),
                                      TextButton.icon(
                                        onPressed: () =>
                                            widget.onReemplazarConExcluida(t),
                                        icon: const Icon(
                                          Icons.swap_horiz,
                                          size: 16,
                                        ),
                                        label: const Text('Reemplazar'),
                                      ),
                                      const SizedBox(width: 6),
                                      TextButton.icon(
                                        onPressed: () =>
                                            widget.onReasignarOperario(t),
                                        icon: const Icon(
                                          Icons.person_search_outlined,
                                          size: 16,
                                        ),
                                        label: const Text('Operario'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    if (_reordenandoDia) ...[
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(minHeight: 3),
                    ],
                  ],
                  const Divider(height: 24),
                  Text(
                    _verExcluidasMes
                        ? 'Excluidas del mes (${excluidas.length})'
                        : 'Excluidas del día (${excluidas.length})',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  if (excluidas.isEmpty)
                    const Text(
                      'No hay excluidas en este filtro.',
                      style: TextStyle(fontSize: 12),
                    )
                  else
                    ...excluidas.map((item) {
                      final expandida = _excluidasExpandidaIds.contains(
                        item.id,
                      );
                      final bloques = item.divisionManual?.bloques ?? const [];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.22),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              InkWell(
                                onTap: () => widget.onTapExcluida(item),
                                borderRadius: BorderRadius.circular(8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.descripcion,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        if (bloques.isNotEmpty)
                                          IconButton(
                                            onPressed: () {
                                              setState(() {
                                                if (expandida) {
                                                  _excluidasExpandidaIds.remove(
                                                    item.id,
                                                  );
                                                } else {
                                                  _excluidasExpandidaIds.add(
                                                    item.id,
                                                  );
                                                }
                                              });
                                            },
                                            icon: Icon(
                                              expandida
                                                  ? Icons.expand_less
                                                  : Icons.expand_more,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'P${item.prioridad} • ${item.ubicacionNombre ?? '-'} • ${item.duracionLabel}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                    if (item.tieneDivisionManual) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Dividida manualmente en ${bloques.length} bloque(s)',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.orange.shade900,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                    if ((item.motivoMensaje ?? '')
                                        .trim()
                                        .isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        item.motivoMensaje!,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  if (!item.tieneDivisionManual)
                                    FilledButton.tonalIcon(
                                      onPressed: () =>
                                          widget.onAgendarExcluida(item),
                                      icon: const Icon(
                                        Icons.search_outlined,
                                        size: 16,
                                      ),
                                      label: const Text('Encontrar hueco'),
                                    ),
                                  FilledButton.tonalIcon(
                                    onPressed: () =>
                                        widget.onDividirExcluida(item),
                                    icon: const Icon(
                                      Icons.splitscreen_outlined,
                                      size: 16,
                                    ),
                                    label: Text(
                                      item.tieneDivisionManual
                                          ? 'Redefinir división'
                                          : 'Dividir en horas',
                                    ),
                                  ),
                                  FilledButton.tonalIcon(
                                    onPressed: () => widget
                                        .onReasignarOperarioExcluida(item),
                                    icon: const Icon(
                                      Icons.person_search_outlined,
                                      size: 16,
                                    ),
                                    label: const Text('Operario'),
                                  ),
                                ],
                              ),
                              if (bloques.isNotEmpty && expandida) ...[
                                const SizedBox(height: 10),
                                ...bloques.map(
                                  (bloque) => Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.orange.shade100,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Bloque ${bloque.orden} · ${bloque.duracionLabel}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                bloque.agendado &&
                                                        bloque.fechaInicio !=
                                                            null &&
                                                        bloque.fechaFin != null
                                                    ? 'Agendado ${DateFormat('dd/MM HH:mm', 'es').format(bloque.fechaInicio!)} - ${DateFormat('HH:mm').format(bloque.fechaFin!)}'
                                                    : 'Pendiente por agendar',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (!bloque.agendado)
                                          TextButton.icon(
                                            onPressed: () =>
                                                widget.onAgendarBloqueExcluida(
                                                  item,
                                                  bloque,
                                                ),
                                            icon: const Icon(
                                              Icons.search_outlined,
                                              size: 16,
                                            ),
                                            label: const Text('Buscar hueco'),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiaResumen {
  final int dia;
  final int total;
  final int preventivas;

  _DiaResumen({
    required this.dia,
    required this.total,
    required this.preventivas,
  });
}

class _BloqueHora {
  final DateTime inicio;
  final DateTime fin;
  final List<TareaModel> tareas;

  _BloqueHora({required this.inicio, required this.fin, required this.tareas});
}

// ✅ Modelo interno de fila (debe ser top-level en Dart)
class _FilaCrono {
  final String frecuencia;
  final String diagnostico;
  final String ubicacion;
  final String objeto;
  final String responsable;
  final Map<int, String> porDia;

  _FilaCrono({
    required this.frecuencia,
    required this.diagnostico,
    required this.ubicacion,
    required this.objeto,
    required this.responsable,
    required this.porDia,
  });
}

class _MinuteRange {
  final int start;
  final int end;

  const _MinuteRange({required this.start, required this.end});
}

class _SemanaHorasResumen {
  final int disponiblesMin;
  final int ocupadasMin;

  const _SemanaHorasResumen({
    required this.disponiblesMin,
    required this.ocupadasMin,
  });

  int get libresMin => (disponiblesMin - ocupadasMin).clamp(0, disponiblesMin);
  double get porcentajeOcupacion =>
      disponiblesMin == 0 ? 0 : ocupadasMin / disponiblesMin;
  String get porcentajeTexto =>
      '${(porcentajeOcupacion * 100).toStringAsFixed(0)}%';
  String get ocupadasHorasLabel => '${(ocupadasMin / 60).toStringAsFixed(1)} h';
  String get disponiblesHorasLabel =>
      '${(disponiblesMin / 60).toStringAsFixed(1)} h';
  String get libresHorasLabel => '${(libresMin / 60).toStringAsFixed(1)} h';
}

class _OperarioSemanaResumen {
  final String nombre;
  final int disponiblesMin;
  final int ocupadasMin;

  const _OperarioSemanaResumen({
    required this.nombre,
    required this.disponiblesMin,
    required this.ocupadasMin,
  });

  double get porcentajeOcupacion =>
      disponiblesMin == 0 ? 0 : ocupadasMin / disponiblesMin;
  String get porcentajeTexto =>
      '${(porcentajeOcupacion * 100).toStringAsFixed(0)}%';
  String get ocupadasHorasLabel => '${(ocupadasMin / 60).toStringAsFixed(1)} h';
  String get disponiblesHorasLabel =>
      '${(disponiblesMin / 60).toStringAsFixed(1)} h';
}
