// lib/pages/cronograma_definitivo_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/festivo_api.dart';
import 'package:intl/intl.dart';

import 'package:flutter_application_1/api/conjunto_api.dart';
import 'package:flutter_application_1/api/inventario_api.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/model/inventario_item_model.dart';
import 'package:flutter_application_1/widgets/cerrar_tarea_sheet.dart';

import '../api/cronograma_api.dart';
import '../model/tarea_model.dart';
import '../service/app_error.dart';
import '../service/session_service.dart';
import '../service/tarea_cierre_service.dart';
import '../service/theme.dart';
import '../utils/schedule_utils.dart';
import '../widgets/section_card.dart';

import 'package:flutter_application_1/service/app_feedback.dart';

enum _VistaCronograma { mensual, semanal }

class CronogramaPage extends StatefulWidget {
  final String nit;
  final bool soloLectura;

  const CronogramaPage({
    super.key,
    required this.nit,
    this.soloLectura = false,
  });

  @override
  State<CronogramaPage> createState() => _CronogramaPageState();
}

class _CronogramaPageState extends State<CronogramaPage> {
  final _cronogramaApi = CronogramaApi();
  final _festivoApi = FestivoApi();
  final _conjuntoApi = ConjuntoApi();
  final ScrollController _mensualHCtrl = ScrollController();

  // ✅ para cerrar desde cronograma
  final _inventarioApi = InventarioApi();
  final _session = SessionService();
  final _tareaCierreService = TareaCierreService();

  bool _loading = true;
  String? _error;

  Set<String> _festivosYmd = {};
  Map<String, String> _festivoNombrePorYmd = {};

  // ✅ ahora mes/año son mutables (para navegación)
  late int _anioActual;
  late int _mesActual; // 1..12

  late int _daysInMonth;
  late DateTime _inicioMes;

  /// Todas las tareas PUBLICADAS (preventivas + correctivas) del mes
  List<TareaModel> _tareasMes = [];
  List<TareaModel> _tareasFiltradasCache = [];
  List<_FilaCrono> _filasCronoMensualCache = [];

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

  List<String> _operariosDisponibles = [];
  List<String> _ubicacionesDisponibles = [];
  List<HorarioConjunto> _horariosConjunto = [];

  int _horaInicioJornada = 8;
  int _horaFinJornada = 16;
  int? _horaDescansoInicio;
  int? _horaDescansoFin;
  String _resumenHorario = 'Horario: 08:00 - 16:00';
  String? _rolActual;
  String? _usuarioIdActual;

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();
    _anioActual = now.year;
    _mesActual = now.month;

    _initMes();
    _semanaBase = DateTime(_anioActual, _mesActual, 1);
    _cargarSesion();
    _cargarDatos();
  }

  Future<void> _cargarSesion() async {
    final results = await Future.wait<String?>([
      _session.getRol(),
      _session.getUserId(),
    ]);
    if (!mounted) return;
    setState(() {
      _rolActual = results[0]?.trim().toLowerCase();
      _usuarioIdActual = results[1]?.trim();
    });
  }

  void _initMes() {
    _inicioMes = DateTime(_anioActual, _mesActual, 1);
    _daysInMonth = DateUtils.getDaysInMonth(_anioActual, _mesActual);
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

  void _aplicarHorarioConjunto({
    required List<HorarioConjunto> horarios,
    required List<TareaModel> tareasMes,
  }) {
    int? minApertura;
    int? maxCierre;
    int? minDescanso;
    int? maxDescanso;

    for (final h in horarios) {
      final apertura = parseHourToTimeOfDay(h.horaApertura);
      final cierre = parseHourToTimeOfDay(h.horaCierre);
      if (apertura == null || cierre == null) continue;

      final aperMin = timeOfDayToMinutes(apertura);
      final cierMin = timeOfDayToMinutes(cierre);
      if (cierMin <= aperMin) continue;

      minApertura = minApertura == null
          ? aperMin
          : (aperMin < minApertura ? aperMin : minApertura);
      maxCierre = maxCierre == null
          ? cierMin
          : (cierMin > maxCierre ? cierMin : maxCierre);

      final descansoInicio = parseHourToTimeOfDay(h.descansoInicio);
      final descansoFin = parseHourToTimeOfDay(h.descansoFin);
      if (descansoInicio == null || descansoFin == null) continue;

      final dIniMin = timeOfDayToMinutes(descansoInicio);
      final dFinMin = timeOfDayToMinutes(descansoFin);
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

    _horariosConjunto = [...horarios];
    _horaInicioJornada = inicioHora;
    _horaFinJornada = finHora;
    _horaDescansoInicio = descansoInicioHora;
    _horaDescansoFin = descansoFinHora;
    _resumenHorario = tieneDescanso
        ? 'Horario: ${formatMinutesAsHour(minApertura)} - ${formatMinutesAsHour(maxCierre)} (descanso ${formatMinutesAsHour(minDescanso)}-${formatMinutesAsHour(maxDescanso)})'
        : 'Horario: ${formatMinutesAsHour(minApertura)} - ${formatMinutesAsHour(maxCierre)}';
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

  DateTime _ensureEndAfterStart(DateTime start, DateTime end) {
    if (end.isAfter(start)) return end;
    return start.add(const Duration(minutes: 1));
  }

  List<TareaModel> _tareasSemana(DateTime semanaBase) {
    return _tareasFiltradas.where((t) {
      final start = _startOfWeekMonday(semanaBase);
      final end = start.add(const Duration(days: 7));
      final dt = t.fechaInicio.toLocal();
      return !dt.isBefore(start) && dt.isBefore(end);
    }).toList();
  }

  List<TareaModel> get _tareasFiltradas => _tareasFiltradasCache;

  void _recalcularColeccionesDerivadas() {
    _tareasFiltradasCache = _tareasMes.where(_pasaFiltros).toList();
    _filasCronoMensualCache = _construirFilasCronoMensual(
      _tareasFiltradasCache,
    );
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

    return true;
  }

  bool _pasaFiltrosResumenOperarios(TareaModel t) {
    if (_esCanceladaPorReemplazo(t)) return false;

    if (_filtroTipo != 'TODAS') {
      final tipo = (t.tipo ?? '').toUpperCase();
      if (tipo != _filtroTipo) return false;
    }

    if (_filtroEstado != 'TODOS') {
      if ((t.estado ?? '') != _filtroEstado) return false;
    }

    if (_filtroUbicacion != 'TODAS') {
      final u = _nombreUbicacion(t) ?? '';
      if (u != _filtroUbicacion) return false;
    }

    return true;
  }

  String? _nombreUbicacion(TareaModel t) => t.ubicacionNombre;
  String? _nombreObjeto(TareaModel t) => t.elementoNombre;

  List<String> _nombresOperarios(TareaModel t) => t.operariosNombres;

  bool _tareaTieneOperario(TareaModel t, String nombreOperario) {
    return _nombresOperarios(t).contains(nombreOperario);
  }

  List<TareaModel> _tareasSemanaResumenOperarios(DateTime semanaBase) {
    final start = _startOfWeekMonday(semanaBase);
    final end = start.add(const Duration(days: 7));
    return _tareasMes.where((t) {
      if (!_pasaFiltrosResumenOperarios(t)) return false;
      final dt = t.fechaInicio.toLocal();
      return !dt.isBefore(start) && dt.isBefore(end);
    }).toList();
  }

  void _reconstruirFiltrosDisponibles() {
    final ops = <String>{};
    final ubis = <String>{};

    for (final t in _tareasMes) {
      if (_esCanceladaPorReemplazo(t)) continue;

      final u = _nombreUbicacion(t);
      if (u != null && u.trim().isNotEmpty) ubis.add(u.trim());

      for (final op in _nombresOperarios(t)) {
        final n = op.trim();
        if (n.isNotEmpty) ops.add(n);
      }
    }

    _operariosDisponibles = ops.toList()..sort();
    _ubicacionesDisponibles = ubis.toList()..sort();
  }

  void _aplicarFiltrosYRefrescar() {
    _recalcularColeccionesDerivadas();
    _recalcularResumenDias();
    setState(() {});
  }

  void _limpiarFiltros() {
    setState(() {
      _filtroTipo = 'TODAS';
      _filtroEstado = 'TODOS';
      _filtroOperario = 'TODOS';
      _filtroUbicacion = 'TODAS';
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

    await _cargarDatos();
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
          borrador: false,
          tipo: 'PREVENTIVA',
        ),
        _cronogramaApi.cronogramaMensual(
          nit: widget.nit,
          anio: _anioActual,
          mes: _mesActual,
          borrador: false,
          tipo: 'CORRECTIVA',
        ),
        _festivoApi.listarFestivosRango(desde: desde, hasta: hasta, pais: 'CO'),
        horariosFuture,
      ]);

      final prev = results[0] as List<TareaModel>;
      final corr = results[1] as List<TareaModel>;
      final festivos = results[2] as List<FestivoItem>;
      final horarios = results[3] as List<HorarioConjunto>;

      // unir y quitar duplicados por id (por si backend repite algo)
      final Map<int, TareaModel> porId = {};
      for (final t in [...prev, ...corr]) {
        porId[t.id] = t;
      }

      final listaUnida = porId.values.toList();

      final filtradas = listaUnida
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

      if (!mounted) return;

      setState(() {
        _tareasMes = filtradas;
        _reconstruirFiltrosDisponibles();
        _recalcularColeccionesDerivadas();
        _festivosYmd = setYmd;
        _festivoNombrePorYmd = nombrePorYmd;
        _aplicarHorarioConjunto(horarios: horarios, tareasMes: filtradas);
        _recalcularResumenDias();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AppError.messageOf(e));
    } finally {
      if (mounted) setState(() => _loading = false);
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
        _filtroUbicacion != 'TODAS';
  }

  // =======================
  // ✅ CERRAR DESDE CRONOGRAMA
  // =======================

  bool _puedeCerrar(TareaModel t) {
    return _tareaCierreService.puedeCerrar(
      rol: _rolActual,
      usuarioId: _usuarioIdActual,
      tarea: t,
      soloLectura: widget.soloLectura,
    );
  }

  Future<void> _accionCerrarDesdeCronograma(TareaModel t) async {
    final motivo = _tareaCierreService.motivoNoPuedeCerrar(
      rol: _rolActual,
      usuarioId: _usuarioIdActual,
      tarea: t,
      soloLectura: widget.soloLectura,
    );
    if (motivo != null) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(context, SnackBar(content: Text(motivo)));
      return;
    }

    List<InventarioItemResponse> inventario = [];

    try {
      inventario = await _inventarioApi.listarInventarioConjunto(widget.nit);
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text('⚠️ No pude cargar inventario: $e')),
      );
      // seguimos con inventario vacío
    }

    if (!mounted) return;
    final res = await showModalBottomSheet<CerrarTareaResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CerrarTareaSheet(tarea: t, inventario: inventario),
    );

    if (res == null) return;

    try {
      await _tareaCierreService.cerrarTarea(
        rol: _rolActual,
        usuarioId: _usuarioIdActual,
        tarea: t,
        observaciones: res.observaciones,
        insumosUsados: res.insumosUsados,
        evidencias: res.evidencias, // ✅ aquí
      );

      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(
          content: Text('✅ Tarea cerrada. Quedó PENDIENTE_APROBACION.'),
        ),
      );

      await _cargarDatos();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text('❌ Error cerrando: $e')),
      );
    }
  }

  // ========= MATRIZ MENSUAL =========

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
    const letters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
    return letters[d.weekday - 1];
  }

  Widget _buildFiltroDropdown({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: value,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: items,
      onChanged: (v) {
        if (v == null) return;
        onChanged(v);
        _aplicarFiltrosYRefrescar();
      },
    );
  }

  Widget _ddTipo() {
    return _buildFiltroDropdown(
      label: 'Tipo',
      value: _filtroTipo,
      items: const <DropdownMenuItem<String>>[
        DropdownMenuItem(value: 'TODAS', child: Text('Todas')),
        DropdownMenuItem(value: 'PREVENTIVA', child: Text('Preventivas')),
        DropdownMenuItem(value: 'CORRECTIVA', child: Text('Correctivas')),
      ],
      onChanged: (v) => setState(() => _filtroTipo = v),
    );
  }

  Widget _ddEstado() {
    return _buildFiltroDropdown(
      label: 'Estado',
      value: _filtroEstado,
      items: const <DropdownMenuItem<String>>[
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
      onChanged: (v) => setState(() => _filtroEstado = v),
    );
  }

  Widget _ddOperario() {
    return _buildFiltroDropdown(
      label: 'Operario',
      value: _filtroOperario,
      items: <DropdownMenuItem<String>>[
        const DropdownMenuItem(value: 'TODOS', child: Text('Todos')),
        ..._operariosDisponibles.map(
          (o) => DropdownMenuItem(value: o, child: Text(o)),
        ),
      ],
      onChanged: (v) => setState(() => _filtroOperario = v),
    );
  }

  Widget _ddUbicacion() {
    return _buildFiltroDropdown(
      label: 'Ubicación',
      value: _filtroUbicacion,
      items: <DropdownMenuItem<String>>[
        const DropdownMenuItem(value: 'TODAS', child: Text('Todas')),
        ..._ubicacionesDisponibles.map(
          (u) => DropdownMenuItem(value: u, child: Text(u)),
        ),
      ],
      onChanged: (v) => setState(() => _filtroUbicacion = v),
    );
  }

  Widget _buildFiltrosMensualCompacto() {
    final w = MediaQuery.of(context).size.width;
    final isNarrow = w < 760;

    return SectionCard(
      title: 'Filtros',
      subtitle:
          'Ajusta la vista mensual por tipo, estado, responsable y ubicación.',
      padding: const EdgeInsets.all(12),
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            Row(
              children: [
                const Spacer(),
                TextButton.icon(
                  onPressed: _limpiarFiltros,
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('Limpiar'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (isNarrow) ...[
              _ddTipo(),
              const SizedBox(height: 10),
              _ddEstado(),
              const SizedBox(height: 10),
              _ddOperario(),
              const SizedBox(height: 10),
              _ddUbicacion(),
            ] else ...[
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
                  Expanded(child: _ddUbicacion()),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFiltrosComoColumna({bool mostrarTitulo = true}) {
    return SectionCard(
      title: mostrarTitulo ? 'Filtros' : null,
      subtitle: mostrarTitulo
          ? 'Filtra la planeacion para revisar solo lo que necesitas.'
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ddTipo(),
          const SizedBox(height: 8),
          _ddEstado(),
          const SizedBox(height: 8),
          _ddOperario(),
          const SizedBox(height: 8),
          _ddUbicacion(),
        ],
      ),
    );
  }

  List<_FilaCrono> _construirFilasCronoMensual(List<TareaModel> tareas) {
    final Map<String, _FilaCrono> rows = {};

    for (final t in tareas) {
      final esCorrectiva = (t.tipo ?? '').trim().toUpperCase() == 'CORRECTIVA';
      final ubic = (t.ubicacionNombre ?? 'ID ${t.ubicacionId}').trim();
      final objeto = (_nombreObjeto(t) ?? 'ID ${t.elementoId}').trim();
      final freq = (t.frecuencia ?? '—').trim();
      final diag = (t.descripcion).trim();

      final operarios = [...t.operariosNombres]..sort();
      final resp = operarios.isNotEmpty
          ? operarios.join(', ')
          : (t.supervisorNombre ??
                (t.supervisorId != null
                    ? 'ID ${t.supervisorId}'
                    : 'Sin asignar'));

      final key =
          '${esCorrectiva ? 'CORRECTIVA' : 'PREVENTIVA'}||$freq||$diag||$ubic||$objeto||$resp';

      rows.putIfAbsent(
        key,
        () => _FilaCrono(
          frecuencia: freq,
          diagnostico: diag,
          ubicacion: ubic,
          objeto: objeto,
          responsable: resp,
          esCorrectiva: esCorrectiva,
          porDia: {},
        ),
      );

      final day = t.fechaInicio.toLocal().day;
      final s = _codigoEstado(t.estado);
      final actual = rows[key]!.porDia[day] ?? '';
      rows[key]!.porDia[day] = _mergeSimbolos(actual, s);
    }

    final list = rows.values.toList();
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
          return 90;
        case 'RE':
          return 80;
        case 'PR':
          return 70;
        case 'PA':
          return 60;
        case 'EP':
          return 50;
        case 'AS':
          return 40;
        case 'CO':
          return 30;
        case 'AP':
          return 20;
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
    final filas = _filasCronoMensualCache;

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
                // Header 1
                Row(
                  children: [
                    cellBox(
                      w: wFrecuencia,
                      color: Colors.green.shade200,
                      child: Text('Frecuencia', style: headerStyle),
                    ),
                    cellBox(
                      w: wDiagnostico,
                      color: Colors.green.shade200,
                      child: Text('Tarea', style: headerStyle),
                    ),
                    cellBox(
                      w: wUbicacion,
                      color: Colors.green.shade200,
                      child: Text('Ubicación', style: headerStyle),
                    ),
                    cellBox(
                      w: wElemento,
                      color: Colors.green.shade200,
                      child: Text('Elemento', style: headerStyle),
                    ),
                    cellBox(
                      w: wResponsable,
                      color: Colors.green.shade200,
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
                // Header 2
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
                        header2Color = const Color(0xFFFFCDD2); // festivo
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

                // Body
                ...filas.map((f) {
                  final colorFila = f.esCorrectiva
                      ? const Color(0xFFFFF7F7)
                      : Colors.white;
                  final colorCeldaCorrectiva = const Color(0xFFFDE2E1);
                  final colorTextoCorrectiva = const Color(0xFFB23A33);

                  return Row(
                    children: [
                      cellBox(
                        w: wFrecuencia,
                        h: hFila,
                        color: colorFila,
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
                        color: colorFila,
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
                        color: colorFila,
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
                        color: colorFila,
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
                        color: colorFila,
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
                            color: val.isNotEmpty && f.esCorrectiva
                                ? colorCeldaCorrectiva
                                : dom
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
                                color: val.isNotEmpty && f.esCorrectiva
                                    ? colorTextoCorrectiva
                                    : _colorPorCodigo(val),
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

  // ===== bloques por hora (modal diario) =====
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
                        'Tareas del dia',
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

    if (!mounted) return;
    setState(_recalcularResumenDias);
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
    final esCorrectiva = (t.tipo ?? '').trim().toUpperCase() == 'CORRECTIVA';
    final colorFondo = esCorrectiva ? const Color(0xFFFFF1F1) : Colors.white;
    final colorBorde = esCorrectiva
        ? const Color(0xFFF2B8B5)
        : Colors.grey.shade200;

    return Card(
      color: colorFondo,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colorBorde),
      ),
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
            if (esCorrectiva)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDE2E1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Correctiva',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFB23A33),
                    ),
                  ),
                ),
              ),
            Text(
              '⏱ $durMin min (${durH.toStringAsFixed(1)} h)  •  $horaIni - $horaFin',
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              '🧑‍💼 Supervisor: $supervisor',
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
    final prioridadLabel = 'P${t.prioridad}';

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
                          _infoRow('ID', t.id.toString()),
                          _infoRow('Descripción', t.descripcion),
                          _infoRow('Estado', t.estado ?? '—'),
                          _infoRow('Tipo', t.tipo ?? '—'),
                          _infoRow('Frecuencia', t.frecuencia ?? '—'),
                          _infoRow('Prioridad', prioridadLabel),
                          const SizedBox(height: 8),
                          _infoRow('Fecha inicio', fechaIniStr),
                          _infoRow('Fecha fin', fechaFinStr),
                          _infoRow(
                            'Duración',
                            '$durMin min (${durH.toStringAsFixed(1)} h)',
                          ),
                          const SizedBox(height: 8),
                          _infoRow('Conjunto', conjuntoLabel),
                          _infoRow('Ubicación', ubicacionLabel),
                          _infoRow('Elemento', elementoLabel),
                          _infoRow('Supervisor', supervisorLabel),
                          const SizedBox(height: 8),
                          _infoRow('Operarios', operarios),
                          const SizedBox(height: 8),
                          _infoRow('Maquinaria planificada', maquinariaTxt),
                          const SizedBox(height: 8),
                          _infoRow('Observaciones', t.observaciones ?? '—'),
                          _infoRow(
                            'Obs. rechazo',
                            t.observacionesRechazo ?? '—',
                          ),
                          const SizedBox(height: 8),
                          _infoRow('Evidencias', evidenciasTxt),
                          _infoRow(
                            'Insumos usados',
                            insumosCount == 0
                                ? 'Sin insumos registrados'
                                : '$insumosCount ítem(s)',
                          ),

                          const SizedBox(height: 14),

                          // ✅ Cerrar desde aquí
                          if (_puedeCerrar(t)) ...[
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  Navigator.pop(context); // cerrar detalle
                                  await _accionCerrarDesdeCronograma(t);
                                },
                                icon: const Icon(Icons.task_alt),
                                label: const Text('Cerrar tarea'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Nota: El veredicto (aprobar/rechazar) lo hace el Jefe de Operaciones.',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],

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
    final usados = <String>{};
    for (final f in _filasCronoMensualCache) {
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
          'Cronograma mensual',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(onPressed: _cargarDatos, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildError()
          : _buildContenido(mesNombre),
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
              onPressed: _cargarDatos,
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
                      : _buildAgendaSemanal(),
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

  List<_MinuteRange> _rangosDisponiblesDia(DateTime day) {
    final fecha = DateTime(day.year, day.month, day.day);
    if (_esFestivo(fecha)) {
      return const [];
    }

    final horarioDia = _horarioConjuntoParaDia(fecha);
    if (horarioDia != null) {
      return _rangosDesdeHorarioConjunto(horarioDia);
    }

    final jornadaMin = (_horaFinJornada - _horaInicioJornada) * 60;
    if (jornadaMin <= 0) return const [];
    if (fecha.weekday == DateTime.sunday) return const [];

    final inicio = _horaInicioJornada * 60;
    final fin = _horaFinJornada * 60;

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
        continue;
      }
      merged.add(range);
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
    List<_OperarioSemanaResumen> operarios, {
    bool compact = false,
  }) {
    final porcentaje = resumen.porcentajeOcupacion.clamp(0, 1).toDouble();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 12 : 14),
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
              fontSize: compact ? 13 : 14,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${resumen.ocupadasHorasLabel} ocupadas de ${resumen.disponiblesHorasLabel} disponibles',
            style: TextStyle(
              fontSize: compact ? 12 : 13,
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
                porcentaje >= 0.9 ? Colors.red.shade400 : AppTheme.primary,
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
          Text(
            'Operarios de la semana',
            style: TextStyle(
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 8),
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
                      final highlight =
                          _filtroOperario != 'TODOS' &&
                          item.nombre == _filtroOperario;

                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: highlight
                              ? AppTheme.primary.withValues(alpha: 0.08)
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: highlight
                                ? AppTheme.primary.withValues(alpha: 0.25)
                                : Colors.grey.shade300,
                          ),
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
                                  highlight
                                      ? AppTheme.primary
                                      : Colors.red.shade300,
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

  Widget _buildAgendaSemanal() {
    final weekStart = _startOfWeekMonday(_semanaBase);
    final tareas = _tareasSemana(_semanaBase);
    final tareasResumenOperarios = _tareasSemanaResumenOperarios(_semanaBase);
    final resumenSemana = _calcularResumenHorasSemana(
      weekStart,
      tareasResumenOperarios,
    );
    final resumenOperarios = _calcularResumenHorasSemanaPorOperario(
      weekStart,
      tareasResumenOperarios,
    );

    final w = MediaQuery.of(context).size.width;
    final showSidebar = w >= 1100;

    if (!showSidebar) {
      return Column(
        children: [
          _buildResumenHorasSemanaCard(
            resumenSemana,
            resumenOperarios,
            compact: true,
          ),
          const SizedBox(height: 10),
          Expanded(
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
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          flex: 4,
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
                _buildResumenHorasSemanaCard(
                  resumenSemana,
                  resumenOperarios,
                  compact: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 7,
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
          ),
        ),
      ],
    );
  }
}

// ============================
//   WIDGETS: Semana tipo agenda
//   Banda de almuerzo + pxPorMin + tema claro
// ============================

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
  final ScrollController _hCtrl = ScrollController();
  final ScrollController _vCtrl = ScrollController();

  static const double pxPorMin = 1.6;
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
        if (group.isEmpty) {
          group.add(span);
          groupEnd = span.fin;
          continue;
        }

        final overlapsGroup = span.inicio.isBefore(groupEnd!);
        if (overlapsGroup) {
          group.add(span);
          if (span.fin.isAfter(groupEnd!)) groupEnd = span.fin;
          continue;
        }

        flushGroup();
        group.add(span);
        groupEnd = span.fin;
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
    _hCtrl.dispose();
    _vCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hours = _horasVisible;
    final heightGrid = (hours * 60) * pxPorMin;
    final taskPlacements = _buildTaskPlacements();

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
        final minDayCol = c.maxWidth < 700 ? 96.0 : 120.0;
        final available = c.maxWidth - anchoHora;
        final colWidth = (available / 7).clamp(minDayCol, 9999.0);
        final totalWidth = anchoHora + colWidth * 7;

        return Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            children: [
              SizedBox(
                height: altoHeader,
                child: SingleChildScrollView(
                  controller: _hCtrl,
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
                                  color: Colors.orange.withValues(alpha: 0.12),
                                ),
                              ),
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

                              final colorBase = AppTheme.primary;
                              final fill = colorBase.withValues(alpha: 0.12);
                              final border = colorBase.withValues(alpha: 0.55);

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
                                const markerHeight = 72.0;

                                return Positioned(
                                  left: left,
                                  top: top,
                                  width: fullWidth,
                                  height: markerHeight,
                                  child: GestureDetector(
                                    onTap: () => widget.onTapTarea(t),
                                    child: Container(
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
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: Colors.amber.shade700,
                                          width: 1,
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              ...List.generate(dotCount, (i) {
                                                return Container(
                                                  width: 10,
                                                  height: 10,
                                                  margin: EdgeInsets.only(
                                                    right: i == dotCount - 1
                                                        ? 0
                                                        : 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        colors[i %
                                                            colors.length],
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          2,
                                                        ),
                                                  ),
                                                );
                                              }),
                                              if (placement.groupSize >
                                                  dotCount) ...[
                                                const SizedBox(width: 6),
                                                Text(
                                                  '+${placement.groupSize - dotCount}',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: text,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  'Superposicion detectada',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: text,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Aqui hay ${placement.groupSize} tareas superpuestas. Filtra por operario para verlo mejor.',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: subtext,
                                              fontSize: 11,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '$horaIni - $horaFinGrupo${resumen.isEmpty ? '' : ' • $resumen${extra > 0 ? ' y $extra mas' : ''}'}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: subtext,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }

                              final height =
                                  ((durMin <= 0 ? 1 : durMin) * pxPorMin).clamp(
                                    18.0,
                                    9999.0,
                                  );

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
                                        final compact = h < 42;

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
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: text,
                                                  fontSize: tiny
                                                      ? 9
                                                      : (compact ? 10 : 12),
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                            if (!compact) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                '$horaIni - $horaFinStr',
                                                style: TextStyle(
                                                  color: subtext,
                                                  fontSize: 11,
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
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 10),
            ...items.map(
              (s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text("- $s", style: const TextStyle(fontSize: 12)),
              ),
            ),
            if (child != null) ...[const Divider(), child!],
          ],
        ),
      ),
    );
  }
}

class _SidebarAgendaDia extends StatefulWidget {
  final DateTime weekStart;
  final List<TareaModel> tareasSemana;
  final void Function(TareaModel t) onTapTarea;

  const _SidebarAgendaDia({
    required this.weekStart,
    required this.tareasSemana,
    required this.onTapTarea,
  });

  @override
  State<_SidebarAgendaDia> createState() => _SidebarAgendaDiaState();
}

class _SidebarAgendaDiaState extends State<_SidebarAgendaDia> {
  int _diaIndex = 0;

  @override
  Widget build(BuildContext context) {
    final fecha = widget.weekStart.add(Duration(days: _diaIndex));
    final tareasDia = widget.tareasSemana.where((t) {
      final d = t.fechaInicio.toLocal();
      return d.year == fecha.year &&
          d.month == fecha.month &&
          d.day == fecha.day;
    }).toList()..sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));

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
            Text(
              DateFormat("EEEE dd MMMM", "es").format(fecha),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const Divider(height: 18),
            if (tareasDia.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'Sin tareas este día',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: tareasDia.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final t = tareasDia[i];
                    final ini = t.fechaInicio.toLocal();
                    final fin = t.fechaFin.toLocal();
                    return InkWell(
                      onTap: () => widget.onTapTarea(t),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.descripcion,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "${DateFormat('HH:mm').format(ini)} - ${DateFormat('HH:mm').format(fin)}",
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
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

  double get disponiblesHoras => disponiblesMin / 60.0;
  double get ocupadasHoras => ocupadasMin / 60.0;
  double get libresHoras =>
      (disponiblesMin - ocupadasMin).clamp(0, 1 << 30) / 60.0;

  double get porcentajeOcupacion =>
      disponiblesMin <= 0 ? 0 : ocupadasMin / disponiblesMin;

  String get disponiblesHorasLabel =>
      '${disponiblesHoras.toStringAsFixed(1)} h';
  String get ocupadasHorasLabel => '${ocupadasHoras.toStringAsFixed(1)} h';
  String get libresHorasLabel => '${libresHoras.toStringAsFixed(1)} h';
  String get porcentajeTexto =>
      '${(porcentajeOcupacion * 100).clamp(0, 999).toStringAsFixed(0)}%';
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
      disponiblesMin <= 0 ? 0 : ocupadasMin / disponiblesMin;

  String get disponiblesHorasLabel =>
      '${(disponiblesMin / 60.0).toStringAsFixed(1)} h';
  String get ocupadasHorasLabel =>
      '${(ocupadasMin / 60.0).toStringAsFixed(1)} h';
  String get porcentajeTexto =>
      '${(porcentajeOcupacion * 100).clamp(0, 999).toStringAsFixed(0)}%';
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

class _FilaCrono {
  final String frecuencia;
  final String diagnostico;
  final String ubicacion;
  final String objeto;
  final String responsable;
  final bool esCorrectiva;
  final Map<int, String> porDia;

  _FilaCrono({
    required this.frecuencia,
    required this.diagnostico,
    required this.ubicacion,
    required this.objeto,
    required this.responsable,
    required this.esCorrectiva,
    required this.porDia,
  });
}
