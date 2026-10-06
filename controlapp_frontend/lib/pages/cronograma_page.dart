// lib/pages/cronograma_definitivo_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/auth_api.dart';
import 'package:flutter_application_1/api/festivo_api.dart';
import 'package:intl/intl.dart';

import 'package:flutter_application_1/api/conjunto_api.dart';
import 'package:flutter_application_1/api/inventario_api.dart';
import 'package:flutter_application_1/model/cronograma_informe_jerarquico_model.dart';
import 'package:flutter_application_1/model/cronograma_actividad_informe_model.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/model/inventario_item_model.dart';
import 'package:flutter_application_1/widgets/cerrar_tarea_sheet.dart';
import 'package:flutter_application_1/widgets/corregir_cierre_sheet.dart';
import 'package:flutter_application_1/widgets/cronograma_informe_jerarquico.dart';
import 'package:flutter_application_1/widgets/skeleton.dart';

import '../api/cronograma_api.dart';
import '../model/actividad_especial_pendiente.dart';
import '../model/preventiva_excluida_borrador_model.dart';
import '../api/tarea_api.dart';
import '../model/tarea_model.dart';
import '../service/app_error.dart';
import '../service/api_exception.dart';
import '../service/permission_service.dart';
import '../service/session_service.dart';
import '../service/tarea_cierre_service.dart';
import '../service/tarea_labels.dart';
import '../service/theme.dart';
import '../utils/duration_format.dart';
import '../utils/schedule_utils.dart';
import '../utils/week_layout.dart';
import 'dart:async';
import 'dart:math' as math;

import '../api/auditoria_api.dart';
import '../model/auditoria_model.dart';
import '../widgets/auditoria_trazabilidad.dart';
import '../model/maquinaria_model.dart';
import '../utils/frecuencia_utils.dart';
import '../widgets/section_card.dart';
import '../widgets/maquinaria_conflict_dialog.dart';
import '../widgets/evidencia_gallery.dart';
import 'crear_tarea_page.dart';

import 'package:flutter_application_1/service/app_feedback.dart';

enum _VistaCronograma { mensual, semanal, informe }

enum _SidebarAgendaModo { agenda, excluidas }

final ValueNotifier<bool> _weekCorrectivaDragActiveNotifier =
    ValueNotifier<bool>(false);
final ValueNotifier<bool> _weekExcluidaDragActiveNotifier = ValueNotifier<bool>(
  false,
);
final ValueNotifier<bool> _weekEspecialDragActiveNotifier = ValueNotifier<bool>(
  false,
);

/// Previsualización de dónde quedaría lo que se está arrastrando en la
/// semana (actividad especial, excluida o correctiva que se mueve).
class _EspecialDropPreview {
  final int dayIndex;
  final int startMinute;
  final int duracionMinutos;
  final bool valido;
  final bool reemplaza;
  final String titulo;
  final String? reemplazaTitulo;
  final Color color;

  /// Minuto donde el usuario soltaría (ajustado a la grilla) y, si es
  /// distinto de [startMinute], dónde se ubicaría realmente al haber tareas
  /// en medio. [choquesIds] son las tareas que ocupan el punto deseado.
  final int? deseadoMinute;
  final List<int> choquesIds;

  /// Carril de la tarea que se reemplaza (para dibujar el preview solo sobre
  /// ese carril y no sobre todo el día).
  final int lane;
  final int laneCount;
  final int laneSpan;

  const _EspecialDropPreview({
    required this.dayIndex,
    required this.startMinute,
    required this.duracionMinutos,
    required this.valido,
    this.reemplaza = false,
    this.titulo = '',
    this.reemplazaTitulo,
    this.color = const Color(0xFF7C3AED),
    this.deseadoMinute,
    this.choquesIds = const [],
    this.lane = 0,
    this.laneCount = 1,
    this.laneSpan = 1,
  });

  bool sameAs(_EspecialDropPreview? o) =>
      o != null &&
      o.dayIndex == dayIndex &&
      o.startMinute == startMinute &&
      o.duracionMinutos == duracionMinutos &&
      o.valido == valido &&
      o.reemplaza == reemplaza &&
      o.titulo == titulo &&
      o.reemplazaTitulo == reemplazaTitulo &&
      o.deseadoMinute == deseadoMinute &&
      o.lane == lane &&
      o.laneCount == laneCount &&
      o.laneSpan == laneSpan &&
      o.choquesIds.length == choquesIds.length &&
      o.color == color;
}

const Color _kColorPreviewEspecial = Color(0xFF7C3AED);
const Color _kColorPreviewExcluida = Color(0xFFEA580C);
const Color _kColorPreviewMover = Color(0xFF2563EB);

final ValueNotifier<_EspecialDropPreview?> _weekEspecialPreviewNotifier =
    ValueNotifier<_EspecialDropPreview?>(null);

void _setEspecialPreview(_EspecialDropPreview? nueva) {
  final actual = _weekEspecialPreviewNotifier.value;
  if (nueva == null ? actual == null : nueva.sameAs(actual)) return;
  _weekEspecialPreviewNotifier.value = nueva;
}

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
  final _authApi = AuthApi();
  final _cronogramaApi = CronogramaApi();
  final _auditoriaApi = AuditoriaApi();

  /// Trazabilidad del mes indexada por id de tarea. Se carga de una sola vez
  /// junto al cronograma para no hacer una peticion por tarea.
  Map<String, TrazabilidadEntidad> _trazabilidadTareas = const {};

  /// Informe de excluidas del periodo: cuáles se programaron después y qué
  /// tareas se desplazaron para lograrlo.
  Map<String, dynamic> _informeExcluidas = const {};
  final _festivoApi = FestivoApi();
  final _conjuntoApi = ConjuntoApi();
  final _tareaApi = TareaApi();
  final ScrollController _mensualHCtrl = ScrollController();

  // ✅ para cerrar desde cronograma
  final _inventarioApi = InventarioApi();
  final _session = SessionService();
  final _tareaCierreService = TareaCierreService();

  bool _loading = true;

  /// Recarga en segundo plano tras una acción (mover, reordenar, excluir...):
  /// el contenido se mantiene en pantalla (y su scroll) en vez de volver al
  /// esqueleto de carga.
  bool _recargando = false;
  bool _yaCargo = false;
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
  List<PreventivaExcluidaBorradorModel> _excluidasMes = [];

  /// Actividades especiales (correctivas) creadas sin fecha, pendientes de
  /// arrastrarse a una franja del cronograma semanal. Solo viven en esta
  /// pantalla: no se guardan en el backend hasta que se ubican.
  final List<ActividadEspecialPendiente> _pendientes = [];

  /// Pendiente que el usuario quiere ubicar tocando la grilla (alternativa
  /// al arrastre, pensada para móvil/tablet).
  ActividadEspecialPendiente? _pendienteEnUbicacion;

  bool _guardandoPendiente = false;
  CronogramaInformeJerarquicoModel? _informeJerarquico;
  final List<CronogramaActividadInformeModel> _informeActividad = const [];
  bool _cargandoInformeJerarquico = false;
  String? _informeOperarioId;
  bool _informeFiltrarSemana = false;
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
  int _escalaSemanalMinutos = 60;
  bool _sidebarResumenColapsado = false;
  bool _sidebarAgendaColapsada = false;
  // Los dos sidebars de la vista semanal (filtros/resumen a la izquierda,
  // agenda del día a la derecha) arrancan expandidos en pantallas grandes,
  // pero en tablet (>=1100px ya usa el layout de fila con sidebars, pero
  // sigue siendo una pantalla chica) deben arrancar colapsados para dejarle
  // espacio a la cuadrícula. Solo se aplica una vez al entrar a la pantalla
  // para no pisar lo que el usuario decida después con los botones de
  // colapsar/expandir.
  bool _sidebarsSemanaDefaultsAplicados = false;
  int _sidebarDiaIndex = 0;
  _SidebarAgendaModo _sidebarAgendaModo = _SidebarAgendaModo.agenda;
  bool _sidebarVerExcluidasMes = false;
  // En móvil (< 1100px), la cuadrícula semanal exige scroll horizontal Y
  // vertical simultáneos y el drag&drop para reprogramar no puede alcanzar
  // columnas fuera de pantalla; por eso ahí la vista por defecto es la
  // agenda por día (lista), con la cuadrícula disponible como alternativa.
  bool _vistaAgendaEnMovil = true;

  bool _mostrarFiltrosMensual = false;

  String _filtroTipo = 'TODAS';
  String _filtroEstado = 'TODOS';
  String _filtroOperario = 'TODOS';
  String _filtroUbicacion = 'TODAS';
  String _filtroEquipo = 'TODOS';

  List<String> _operariosDisponibles = [];
  List<String> _ubicacionesDisponibles = [];
  List<String> _equiposDisponibles = [];
  List<HorarioConjunto> _horariosConjunto = [];

  int _horaInicioJornada = 8;
  int _horaFinJornada = 16;
  int? _horaDescansoInicio;
  int? _horaDescansoFin;
  String _resumenHorario = 'Horario: 08:00 - 16:00';
  String? _rolActual;
  String? _usuarioIdActual;

  bool get _puedeEliminarCronogramaPublicado =>
      !widget.soloLectura &&
      PermissionService.instance.can('cronograma.eliminar_publicado') &&
      _tareasMes.isNotEmpty &&
      !_loading;

  bool get _canViewCronograma =>
      PermissionService.instance.can('cronograma.ver');

  bool get _canScheduleCorrectivasInCronograma =>
      !widget.soloLectura &&
      PermissionService.instance.canAny(const [
        'tareas.crear',
        'cronograma.correctivas_programar',
      ]);

  /// Evita disparar dos acciones simultaneas sobre la misma excluida.
  bool _accionExcluidaEnCurso = false;

  /// Mostrar las excluidas del mes como filas de seguimiento en la matriz.
  bool _verExcluidasEnMatriz = true;

  bool get _canViewExcluidasStandby =>
      PermissionService.instance.can('cronograma.excluidas_ver');

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();
    _anioActual = now.year;
    _mesActual = now.month;

    _initMes();
    _semanaBase = DateTime(_anioActual, _mesActual, 1);

    // La sesion/rol ya se cargo en el splash (GET /auth/me). Aqui solo se lee
    // de almacenamiento local (rapido) y se arranca la carga de datos de una
    // vez, en vez de esperar un round-trip de red redundante antes de pintar
    // nada. El refresco de permisos sigue en segundo plano sin bloquear.
    unawaited(_refreshSessionProfile());
    _cargarSesion().then((_) {
      if (!mounted) return;
      _cargarDatos();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sidebarsSemanaDefaultsAplicados) return;
    _sidebarsSemanaDefaultsAplicados = true;
    if (MediaQuery.of(context).size.width < 1366) {
      _sidebarResumenColapsado = true;
      _sidebarAgendaColapsada = true;
    }
  }

  Future<void> _refreshSessionProfile() async {
    try {
      await _authApi.me();
      if (mounted) setState(() {});
    } catch (_) {}
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

    // Amplía (nunca reduce) el horario del conjunto con las horas reales de
    // las tareas del mes: una plaza con horario especial (necesidad
    // operativa) puede empezar antes o terminar después que el horario
    // general -o el conjunto puede no tener horario configurado ese día- y
    // la rejilla debe mostrar esas tareas completas en vez de recortarlas.
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

  List<PreventivaExcluidaBorradorModel> get _excluidasFiltradas =>
      _excluidasMes.where(_pasaFiltrosExcluida).toList();

  List<PreventivaExcluidaBorradorModel> _excluidasPorFecha(DateTime fecha) {
    return _excluidasFiltradas.where((item) {
      final d = item.fechaObjetivo;
      return d.year == fecha.year &&
          d.month == fecha.month &&
          d.day == fecha.day;
    }).toList();
  }

  void _recalcularColeccionesDerivadas() {
    _tareasFiltradasCache = _tareasMes.where(_pasaFiltros).toList();
    _filasCronoMensualCache = [
      ..._construirFilasCronoMensual(_tareasFiltradasCache),
      if (_verExcluidasEnMatriz && _canViewExcluidasStandby)
        ..._construirFilasExcluidas(),
    ];
  }

  /// Filas de seguimiento de las tareas excluidas del mes. Se marcan con `EX`
  /// en su fecha objetivo y desaparecen solas al cambiar de periodo.
  List<_FilaCrono> _construirFilasExcluidas() {
    return _excluidasFiltradas
        .where((item) => item.estado.toUpperCase() == 'PENDIENTE')
        .map(
          (item) => _FilaCrono(
            frecuencia: etiquetaFrecuencia(
              item.frecuencia,
              diaSemana: item.diaSemanaProgramado,
              fechaReferencia: item.fechaObjetivo,
            ),
            diagnostico: item.descripcion.trim(),
            ubicacion: (item.ubicacionNombre ?? 'ID ${item.ubicacionId}')
                .trim(),
            objeto: (item.elementoNombre ?? 'ID ${item.elementoId}').trim(),
            responsable: item.operariosNombres.isEmpty
                ? 'Sin asignar'
                : item.operariosNombres.join(', '),
            esCorrectiva: false,
            esExcluida: true,
            excluidaId: item.id,
            porDia: {item.fechaObjetivo.day: 'EX'},
          ),
        )
        .toList();
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

  bool _pasaFiltrosExcluida(PreventivaExcluidaBorradorModel item) {
    if (_filtroOperario != 'TODOS' &&
        !item.operariosNombres.any((name) => name.trim() == _filtroOperario)) {
      return false;
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

  List<String> _operariosConCargo(TareaModel tarea) {
    final items = <String>[];
    for (var i = 0; i < tarea.operariosNombres.length; i++) {
      final nombre = tarea.operariosNombres[i].trim();
      if (nombre.isEmpty) continue;
      final cargo = i < tarea.operariosCargos.length
          ? tarea.operariosCargos[i].trim()
          : '';
      items.add(cargo.isEmpty ? nombre : '$nombre ($cargo)');
    }
    return items;
  }

  List<MapEntry<String, String>> _operariosConCargoEntries(TareaModel tarea) {
    final items = <MapEntry<String, String>>[];
    for (var i = 0; i < tarea.operariosNombres.length; i++) {
      final nombre = tarea.operariosNombres[i].trim();
      if (nombre.isEmpty) continue;
      final cargo = i < tarea.operariosCargos.length
          ? tarea.operariosCargos[i].trim()
          : '';
      items.add(MapEntry(nombre, cargo));
    }
    return items;
  }

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
    'reprogramacion',
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
    'duracion': 'Duración',
    'conjunto': 'Conjunto',
    'ubicacion': 'Ubicación',
    'elemento': 'Elemento',
    'supervisor': 'Supervisor',
    'operarios': 'Operarios',
    'maquinaria': 'Maquinaria',
    'observaciones': 'Observaciones',
    'reprogramacion': 'Obs. rechazo',
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
    final buscado = nombreOperario.trim().toLowerCase();
    return _nombresOperarios(
      t,
    ).any((nombre) => nombre.trim().toLowerCase() == buscado);
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
      _diaFoco = null;
      _yaCargo = false;
      _informeOperarioId = null;
    });

    await _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    final silenciosa = _yaCargo;
    setState(() {
      if (silenciosa) {
        _recargando = true;
      } else {
        _loading = true;
      }
      _error = null;
    });

    try {
      final desde = DateTime(_anioActual, _mesActual, 1);
      final hasta = DateTime(_anioActual, _mesActual, _daysInMonth);

      final horariosFuture = _conjuntoApi
          .obtenerHorariosConjunto(widget.nit)
          .catchError((_) => <HorarioConjunto>[]);
      final excluidasFuture = _canViewExcluidasStandby
          ? _cronogramaApi.listarExcluidasStandby(
              nit: widget.nit,
              anio: _anioActual,
              mes: _mesActual,
            )
          : Future.value(const <PreventivaExcluidaBorradorModel>[]);

      final results = await Future.wait([
        // El backend ignora el filtro `tipo` y siempre devuelve preventivas +
        // correctivas juntas (ver CronogramaController.cronogramaMensual), asi
        // que una sola llamada trae exactamente lo mismo que dos.
        _cronogramaApi.cronogramaMensual(
          nit: widget.nit,
          anio: _anioActual,
          mes: _mesActual,
          borrador: false,
        ),
        _festivoApi.listarFestivosRango(desde: desde, hasta: hasta, pais: 'CO'),
        horariosFuture,
        _cronogramaApi.informeActividadJerarquico(
          nit: widget.nit,
          anio: _anioActual,
          mes: _mesActual,
          borrador: false,
          semanaInicio: _informeFiltrarSemana
              ? _startOfWeekMonday(_semanaBase)
              : null,
        ),
        excluidasFuture,
      ]);

      final todas = results[0] as List<TareaModel>;
      final festivos = results[1] as List<FestivoItem>;
      final horarios = results[2] as List<HorarioConjunto>;
      final informe = results[3] as CronogramaInformeJerarquicoModel;
      final excluidas = results[4] as List<PreventivaExcluidaBorradorModel>;

      // unir y quitar duplicados por id (por si backend repite algo)
      final Map<int, TareaModel> porId = {};
      for (final t in todas) {
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

      unawaited(_cargarTrazabilidadTareas(filtradas));
      unawaited(_cargarInformeExcluidas());

      setState(() {
        _tareasMes = filtradas;
        _excluidasMes = excluidas;
        _informeJerarquico = informe;
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
      if (mounted) {
        setState(() {
          _loading = false;
          _recargando = false;
          _yaCargo = true;
        });
      }
    }
  }

  Future<void> _cargarInformeJerarquico() async {
    if (_cargandoInformeJerarquico) return;
    setState(() => _cargandoInformeJerarquico = true);
    try {
      final informe = await _cronogramaApi.informeActividadJerarquico(
        nit: widget.nit,
        anio: _anioActual,
        mes: _mesActual,
        borrador: false,
        operarioId: _informeOperarioId,
        semanaInicio: _informeFiltrarSemana
            ? _startOfWeekMonday(_semanaBase)
            : null,
      );
      if (mounted) setState(() => _informeJerarquico = informe);
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, message: AppError.messageOf(e));
      }
    } finally {
      if (mounted) setState(() => _cargandoInformeJerarquico = false);
    }
  }

  // ── Enfoque en un solo día (vista semanal) ──────────────────────────────
  /// Día enfocado de la vista semanal; null = semana completa.
  DateTime? _diaFoco;

  bool get _enFocoDia => _vista == _VistaCronograma.semanal && _diaFoco != null;

  bool _diaEnMesActual(DateTime d) =>
      d.year == _anioActual && d.month == _mesActual;

  void _enfocarDia(DateTime d) {
    final dia = DateTime(d.year, d.month, d.day);
    if (!_diaEnMesActual(dia)) return;
    setState(() {
      _diaFoco = dia;
      _semanaBase = dia;
      _sidebarDiaIndex = dia.weekday - 1;
    });
  }

  void _salirFocoDia() => setState(() => _diaFoco = null);

  /// Mueve el enfoque [delta] días sin salirse del mes cargado.
  void _moverFocoDia(int delta) {
    final actual = _diaFoco;
    if (actual == null) return;
    final nuevo = actual.add(Duration(days: delta));
    if (!_diaEnMesActual(nuevo)) return;
    _enfocarDia(nuevo);
  }

  /// Botón "Enfocar día" / selector de día + "Ver semana".
  Widget _buildBotonFocoDia() {
    if (_vista != _VistaCronograma.semanal) return const SizedBox.shrink();
    // En pantallas chicas con la agenda en lista no hay cuadrícula que enfocar.
    if (MediaQuery.of(context).size.width < 1100 && _vistaAgendaEnMovil) {
      return const SizedBox.shrink();
    }
    final foco = _diaFoco;
    if (foco == null) {
      return Tooltip(
        message:
            'Muestra un solo día con más espacio (también puedes tocar '
            'el nombre de un día en el encabezado).',
        child: OutlinedButton.icon(
          icon: const Icon(Icons.center_focus_strong_outlined, size: 18),
          label: const Text('Enfocar día', style: TextStyle(fontSize: 12)),
          onPressed: () {
            final inicio = _startOfWeekMonday(_semanaBase);
            final hoy = DateTime.now();
            DateTime? elegido;
            for (var i = 0; i < 7; i++) {
              final d = inicio.add(Duration(days: i));
              if (!_diaEnMesActual(d)) continue;
              elegido ??= d;
              if (d.year == hoy.year &&
                  d.month == hoy.month &&
                  d.day == hoy.day) {
                elegido = d;
                break;
              }
            }
            if (elegido != null) _enfocarDia(elegido);
          },
        ),
      );
    }
    const iniciales = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
    final inicio = _startOfWeekMonday(foco);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 7; i++)
          Builder(
            builder: (context) {
              final d = inicio.add(Duration(days: i));
              final habilitado = _diaEnMesActual(d);
              final seleccionado =
                  d.year == foco.year &&
                  d.month == foco.month &&
                  d.day == foco.day;
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Tooltip(
                  message: DateFormat("EEEE d 'de' MMMM", 'es').format(d),
                  child: ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      '${iniciales[i]} ${d.day}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: seleccionado,
                    onSelected: habilitado ? (_) => _enfocarDia(d) : null,
                  ),
                ),
              );
            },
          ),
        const SizedBox(width: 4),
        FilledButton.tonalIcon(
          icon: const Icon(Icons.view_week_outlined, size: 18),
          label: const Text('Ver semana', style: TextStyle(fontSize: 12)),
          onPressed: _salirFocoDia,
        ),
      ],
    );
  }

  void _cambiarSemanaInforme(int dias) {
    // En enfoque de un día las flechas mueven de a un día.
    if (_enFocoDia) {
      _moverFocoDia(dias > 0 ? 1 : -1);
      return;
    }
    setState(() => _semanaBase = _semanaBase.add(Duration(days: dias)));
    if (_vista == _VistaCronograma.informe && _informeFiltrarSemana) {
      unawaited(_cargarInformeJerarquico());
    }
  }

  void _seleccionarVista(_VistaCronograma vista) {
    setState(() => _vista = vista);
    if (vista == _VistaCronograma.informe) {
      unawaited(_cargarInformeJerarquico());
    }
  }

  /// Abre el formulario de "Más opciones → Creación actividad especial":
  /// sin fecha/hora, entrega la pendiente para arrastrarla en el cronograma.
  Future<void> _abrirCrearActividadEspecialModal() async {
    if (!_canScheduleCorrectivasInCronograma || !mounted) return;

    final etiqueta = etiquetaCorrectiva();

    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        final keyboardBottom = MediaQuery.of(modalContext).viewInsets.bottom;
        final size = MediaQuery.of(modalContext).size;
        final pantallaChica = size.width < 640;
        return Padding(
          padding: EdgeInsets.only(bottom: keyboardBottom),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 980,
                maxHeight: pantallaChica ? size.height : size.height * 0.94,
              ),
              child: Material(
                color: Colors.white,
                borderRadius: pantallaChica
                    ? BorderRadius.zero
                    : BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                      decoration: const BoxDecoration(
                        color: Color(0xFFEDE9FE),
                        border: Border(
                          bottom: BorderSide(color: Color(0xFFD9CCFB)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Nueva $etiqueta',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF5B21B6),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Guárdala y luego arrástrala al horario que quieras en el cronograma.',
                                  style: TextStyle(
                                    color: Color(0xFF6D28D9),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Cerrar',
                            onPressed: () => Navigator.of(modalContext).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: CorrectivaSchedulerForm(
                        nit: widget.nit,
                        embedded: true,
                        onPendienteCreada: (pendiente) {
                          setState(() => _pendientes.add(pendiente));
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _abrirEditarCorrectivaModal(TareaModel tarea) async {
    if (!_canScheduleCorrectivasInCronograma || !mounted) return;

    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        final keyboardBottom = MediaQuery.of(modalContext).viewInsets.bottom;
        final height = MediaQuery.of(modalContext).size.height;
        return Padding(
          padding: EdgeInsets.only(bottom: keyboardBottom),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 980,
                maxHeight: height * 0.94,
              ),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFDECEC),
                        border: Border(
                          bottom: BorderSide(color: Color(0xFFF6C8C8)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Editar ${etiquetaCorrectiva(minuscula: true)}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFA61E1E),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Cerrar',
                            onPressed: () => Navigator.of(modalContext).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: CorrectivaSchedulerForm(
                        nit: widget.nit,
                        embedded: true,
                        existingTask: tarea,
                        onCreated: _cargarDatos,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _moverCorrectivaDesdeCronograma({
    required TareaModel tarea,
    required DateTime nuevoInicio,
    required DateTime nuevoFin,
  }) async {
    final cantidadOperarios = tarea.operariosIds.toSet().length;
    if (cantidadOperarios > 1) {
      final nombres = tarea.operariosNombres
          .map((nombre) => nombre.trim())
          .where((nombre) => nombre.isNotEmpty)
          .toSet()
          .join(', ');
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Mover tarea de equipo'),
          content: Text(
            'El nuevo horario se aplicará a los $cantidadOperarios operarios y '
            'solo se guardará si todos están disponibles.'
            '${nombres.isEmpty ? '' : '\n\n$nombres'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Mover equipo'),
            ),
          ],
        ),
      );
      if (confirmado != true || !mounted) return;
    }
    final req = TareaRequest(
      descripcion: tarea.descripcion,
      fechaInicio: nuevoInicio,
      fechaFin: nuevoFin,
      duracionMinutos: nuevoFin.difference(nuevoInicio).inMinutes,
      prioridad: tarea.prioridad,
      tipo: 'CORRECTIVA',
      ubicacionId: tarea.ubicacionId,
      elementoId: tarea.elementoId,
      conjuntoId: tarea.conjuntoId ?? widget.nit,
      supervisorId: tarea.supervisorId,
      operariosIds: tarea.operariosIds,
      observaciones: tarea.observaciones,
    );

    final resp = await _tareaApi.editarTareaConRespuesta(tarea.id, req);
    if (resp['ok'] == false) {
      if ((resp['reason'] ?? '').toString().toUpperCase() ==
          'MAQUINARIA_NO_DISPONIBLE') {
        throw ApiException.fromMap(
          resp.cast<String, dynamic>(),
          statusCode: 409,
          fallback: 'La maquinaria no está disponible para ese movimiento.',
        );
      }
      throw Exception(
        (resp['message'] ??
                'No se pudo mover la ${etiquetaCorrectiva(minuscula: true)}.')
            .toString(),
      );
    }

    if (!mounted) return;
    await _cargarDatos();
    if (!mounted) return;
    AppFeedback.showFromSnackBar(
      context,
      SnackBar(
        content: Text('${etiquetaCorrectiva()} reprogramada correctamente.'),
      ),
    );
  }

  Future<void> _eliminarCronogramaPublicado() async {
    if (!_puedeEliminarCronogramaPublicado) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Borrar cronograma publicado'),
        content: Text(
          '¿Seguro que deseas borrar las tareas publicadas de ${DateFormat.MMMM('es').format(_inicioMes)} de $_anioActual para el conjunto ${widget.nit}? Esta accion no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Borrar todo',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    setState(() => _loading = true);
    try {
      final res = await _cronogramaApi.eliminarCronogramaPublicado(
        nit: widget.nit,
        anio: _anioActual,
        mes: _mesActual,
      );
      if (!mounted) return;
      final eliminadas = res['eliminadas'];
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text(
            eliminadas is num
                ? 'Cronograma eliminado. Tareas borradas: ${eliminadas.toInt()}.'
                : 'Cronograma del mes eliminado correctamente.',
          ),
        ),
      );
      await _cargarDatos();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text(AppError.messageOf(e))),
      );
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
        accion: res.accion,
        observaciones: res.observaciones,
        insumosUsados: res.insumosUsados,
        evidencias: res.evidencias, // ✅ aquí
      );

      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text(
            res.accion == 'NO_COMPLETADA'
                ? '✅ Tarea marcada como no completada.'
                : '✅ Tarea cerrada y aprobada.',
          ),
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
      items: <DropdownMenuItem<String>>[
        const DropdownMenuItem(value: 'TODAS', child: Text('Todas')),
        const DropdownMenuItem(value: 'PREVENTIVA', child: Text('Preventivas')),
        DropdownMenuItem(
          value: 'CORRECTIVA',
          child: Text(etiquetaCorrectiva(plural: true)),
        ),
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

  Widget _ddEquipo() {
    return _buildFiltroDropdown(
      label: 'Equipo',
      value: _filtroEquipo,
      items: <DropdownMenuItem<String>>[
        const DropdownMenuItem(value: 'TODOS', child: Text('Todos')),
        ..._equiposDisponibles.map(
          (equipo) => DropdownMenuItem(value: equipo, child: Text(equipo)),
        ),
      ],
      onChanged: (v) => setState(() => _filtroEquipo = v),
    );
  }

  Widget _buildFiltrosMensualCompacto() {
    final w = MediaQuery.of(context).size.width;
    final isNarrow = w < 760;

    return SectionCard(
      title: 'Filtros',
      subtitle:
          'Ajusta la vista mensual por tipo, estado, responsable, equipo y ubicación.',
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
              if (_equiposDisponibles.isNotEmpty) ...[
                _ddEquipo(),
                const SizedBox(height: 10),
              ],
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
          if (_equiposDisponibles.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ddEquipo(),
          ],
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
      final freq = etiquetaFrecuencia(
        t.frecuencia,
        diaSemana: t.diaSemanaProgramado,
        fechaReferencia: t.fechaInicio.toLocal(),
      );
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
          esExcluida: false,
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
      final c1 = compararPorFrecuencia(a.frecuencia, b.frecuencia);
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
        case 'EX':
          return 15;
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
      case 'EX':
        return Colors.orange.shade900;
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
                    final colorFila = f.esExcluida
                        ? const Color(0xFFFFF8EE)
                        : f.esCorrectiva
                        ? const Color(0xFFFFF7F7)
                        : Colors.white;
                    final colorCeldaCorrectiva = const Color(0xFFFDE2E1);
                    final colorTextoCorrectiva = const Color(0xFFB23A33);
                    final colorCeldaExcluida = const Color(0xFFFFE7C2);

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
                            onTap: () => f.esExcluida && f.excluidaId != null
                                ? _abrirDetalleExcluidaPorId(f.excluidaId!)
                                : _abrirDia(dia),
                            child: cellBox(
                              w: wDia,
                              h: hFila,
                              color: val.isNotEmpty && f.esExcluida
                                  ? colorCeldaExcluida
                                  : val.isNotEmpty && f.esCorrectiva
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
    return '$visibles | +${descripciones.length - 2} más';
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
                        'Tareas del día',
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
                  child: Text(
                    etiquetaCorrectiva(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFB23A33),
                    ),
                  ),
                ),
              ),
            Text(
              '⏱ ${formatHoursMinutes(durMin)}  •  $horaIni - $horaFin',
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

    final maquinariaLista = t.maquinariaPlan ?? const [];
    final maquinariaTxt = maquinariaLista.isEmpty
        ? 'Sin maquinaria planificada'
        : maquinariaLista
              .map((m) {
                // La preventiva declara el tipo necesario; la máquina concreta
                // se asigna desde el cronograma de maquinaria.
                final tipo = m.tipoEnum?.label ?? m.tipo ?? 'Sin tipo';
                final cantidad = (m.cantidad ?? 1).round();
                return cantidad > 1 ? '$tipo × $cantidad' : tipo;
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
                addRow(
                  'frecuencia',
                  'Frecuencia',
                  etiquetaFrecuencia(
                    t.frecuencia,
                    diaSemana: t.diaSemanaProgramado,
                    fechaReferencia: t.fechaInicio.toLocal(),
                  ),
                );
                addRow('prioridad', 'Prioridad', prioridadLabel);
                rows.add(const SizedBox(height: 8));
                rows.add(
                  AuditoriaTrazabilidad(
                    trazabilidad: _trazabilidadTareas[t.id.toString()],
                  ),
                );
                rows.add(const SizedBox(height: 8));
                addRow('fechaInicio', 'Fecha inicio', fechaIniStr);
                addRow('fechaFin', 'Fecha fin', fechaFinStr);
                addRow('duracion', 'Duración', formatHoursMinutes(durMin));
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
                addRow(
                  'reprogramacion',
                  'Obs. rechazo',
                  t.observacionesRechazo ?? '—',
                );
                if (_detalleCamposVisibles.contains('evidencias')) {
                  rows.add(
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Evidencias:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          EvidenciaGallery(
                            evidencias: t.evidencias ?? const [],
                          ),
                        ],
                      ),
                    ),
                  );
                }
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
                              const SizedBox(height: 14),
                              if (_puedeCerrar(t)) ...[
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () async {
                                      Navigator.pop(context);
                                      await _accionCerrarDesdeCronograma(t);
                                    },
                                    icon: const Icon(Icons.task_alt),
                                    label: const Text('Cerrar tarea'),
                                  ),
                                ),
                              ],
                              if ((t.tipo ?? '').trim().toUpperCase() ==
                                      'CORRECTIVA' &&
                                  _canScheduleCorrectivasInCronograma) ...[
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      Navigator.pop(context);
                                      await _abrirEditarCorrectivaModal(t);
                                    },
                                    icon: const Icon(
                                      Icons.edit_calendar_rounded,
                                    ),
                                    label: Text(
                                      'Editar ${etiquetaCorrectiva(minuscula: true)}',
                                    ),
                                  ),
                                ),
                              ],
                              if (puedeCorregirCierre(t)) ...[
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      Navigator.pop(context);
                                      final corregido =
                                          await abrirCorregirCierre(
                                            ctx,
                                            tareaId: t.id,
                                          );
                                      if (corregido) _cargarDatos();
                                    },
                                    icon: const Icon(Icons.edit_note),
                                    label: const Text('Corregir cierre'),
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
    if (!_canViewCronograma) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cronograma')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Tu rol no tiene acceso a esta pantalla. Pidele al gerente que habilite el permiso de cronogramas.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final primary = AppTheme.primary;
    final mesNombre = DateFormat.MMMM('es').format(_inicioMes).toUpperCase();

    return PopScope(
      canPop: _pendientes.isEmpty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final puedeSalir = await _confirmarSalidaConPendientes();
        if (puedeSalir) navigator.pop(result);
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: primary,
          title: const Text(
            'Cronograma mensual',
            style: TextStyle(color: Colors.white),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            if (_puedeEliminarCronogramaPublicado)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconButton(
                  tooltip: 'Borrar cronograma publicado',
                  onPressed: _eliminarCronogramaPublicado,
                  icon: const Icon(
                    Icons.delete_forever_rounded,
                    color: Colors.white,
                  ),
                ),
              ),
            IconButton(
              onPressed: _cargarDatos,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _loading
            ? const SkeletonTable(rows: 10, cols: 5)
            : _error != null
            ? _buildError()
            : _buildContenido(mesNombre),
      ),
    );
  }

  /// Si hay actividades especiales pendientes sin programar, pide
  /// confirmación antes de salir porque se perderían (viven solo en memoria).
  Future<bool> _confirmarSalidaConPendientes() async {
    if (_pendientes.isEmpty) return true;
    final unaSola = _pendientes.length == 1;
    final etiqueta = etiquetaCorrectiva(plural: !unaSola, minuscula: true);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Salir sin programar?'),
        content: Text(
          unaSola
              ? 'Tienes 1 $etiqueta sin programar. Si sales se perderá. ¿Salir de todas formas?'
              : 'Tienes ${_pendientes.length} $etiqueta sin programar. Si sales se perderán. ¿Salir de todas formas?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Seguir aquí'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Salir de todas formas'),
          ),
        ],
      ),
    );
    return ok == true;
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
          if (_recargando) const LinearProgressIndicator(minHeight: 2),
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
                if (_vista == _VistaCronograma.mensual &&
                    _canViewExcluidasStandby)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: FilterChip(
                        selected: _verExcluidasEnMatriz,
                        avatar: const Icon(Icons.event_busy, size: 16),
                        label: Text(
                          'Ver excluidas del mes (${_excluidasFiltradas.length})',
                        ),
                        onSelected: (value) => setState(() {
                          _verExcluidasEnMatriz = value;
                          _recalcularColeccionesDerivadas();
                        }),
                      ),
                    ),
                  ),
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
    final rangoSemana = _enFocoDia
        ? toBeginningOfSentenceCase(
            DateFormat("EEEE d MMM", 'es').format(_diaFoco!),
          )
        : "${DateFormat('dd MMM', 'es').format(start)} - ${DateFormat('dd MMM', 'es').format(end)}";
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
              onSelectionChanged: (s) => _seleccionarVista(s.first),
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
                    tooltip: _enFocoDia ? 'Día anterior' : 'Semana anterior',
                    onPressed: () => _cambiarSemanaInforme(-7),
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
                    tooltip: _enFocoDia ? 'Día siguiente' : 'Semana siguiente',
                    onPressed: () => _cambiarSemanaInforme(7),
                    icon: const Icon(Icons.chevron_right),
                  ),
                  const SizedBox(width: 8),
                  _buildBotonFocoDia(),
                  const SizedBox(width: 8),
                  PopupMenuButton<int>(
                    tooltip: 'Cambiar escala semanal',
                    initialValue: _escalaSemanalMinutos,
                    onSelected: (value) =>
                        setState(() => _escalaSemanalMinutos = value),
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 1, child: Text('Escala 1 minuto')),
                      PopupMenuItem(
                        value: 15,
                        child: Text('Escala 15 minutos'),
                      ),
                      PopupMenuItem(
                        value: 30,
                        child: Text('Escala 30 minutos'),
                      ),
                      PopupMenuItem(value: 60, child: Text('Escala 1 hora')),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade400),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.zoom_in, size: 18),
                          const SizedBox(width: 6),
                          Text('Escala ${_escalaSemanalMinutos}m'),
                        ],
                      ),
                    ),
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
          onSelectionChanged: (s) => _seleccionarVista(s.first),
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
            tooltip: _enFocoDia ? 'Día anterior' : 'Semana anterior',
            onPressed: () => _cambiarSemanaInforme(-7),
            icon: const Icon(Icons.chevron_left),
          ),
          Text(
            rangoSemana,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          IconButton(
            tooltip: _enFocoDia ? 'Día siguiente' : 'Semana siguiente',
            onPressed: () => _cambiarSemanaInforme(7),
            icon: const Icon(Icons.chevron_right),
          ),
          const SizedBox(width: 8),
          _buildBotonFocoDia(),
          const SizedBox(width: 8),
          PopupMenuButton<int>(
            tooltip: 'Cambiar escala semanal',
            initialValue: _escalaSemanalMinutos,
            onSelected: (value) =>
                setState(() => _escalaSemanalMinutos = value),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 1, child: Text('Escala 1 minuto')),
              PopupMenuItem(value: 15, child: Text('Escala 15 minutos')),
              PopupMenuItem(value: 30, child: Text('Escala 30 minutos')),
              PopupMenuItem(value: 60, child: Text('Escala 1 hora')),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade400),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.zoom_in, size: 18),
                  const SizedBox(width: 6),
                  Text('Escala ${_escalaSemanalMinutos}m'),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Menú de creación de actividades especiales junto a la agenda.
  Widget _buildMasOpcionesButton({bool compact = false}) {
    final etiqueta = etiquetaCorrectiva();
    return PopupMenuButton<String>(
      tooltip: 'Más opciones',
      onSelected: (value) {
        if (value == 'crear_actividad_especial') {
          _abrirCrearActividadEspecialModal();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'crear_actividad_especial',
          child: Text('1. Creación $etiqueta'),
        ),
      ],
      child: IgnorePointer(
        child: FilledButton.tonalIcon(
          onPressed: () {},
          icon: const Icon(Icons.more_horiz_rounded, size: 18),
          label: Text(compact ? 'Más' : 'Más opciones'),
        ),
      ),
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

    // El conjunto no tiene horario general configurado para este día. Por
    // defecto un domingo se asume cerrado -salvo que una plaza con horario
    // especial (necesidad operativa) sí tenga tareas programadas ese día:
    // en ese caso su disponibilidad real sale de esas tareas, en vez de
    // reportar el domingo entero como no disponible (lo dejaba "distinto"
    // de los demás días del cronograma pese a tener trabajo real).
    if (fecha.weekday == DateTime.sunday) {
      return _rangosDesdeTareasDelDia(fecha);
    }

    final jornadaMin = (_horaFinJornada - _horaInicioJornada) * 60;
    if (jornadaMin <= 0) return const [];

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

  /// Disponibilidad de un día sin horario general configurado, derivada de
  /// las tareas realmente programadas ese día (envolvente: inicio más
  /// temprano a fin más tardío). Usado para domingo, donde por defecto se
  /// asume cerrado salvo que una plaza con horario especial sí trabaje ahí.
  List<_MinuteRange> _rangosDesdeTareasDelDia(DateTime fecha) {
    int? minInicio;
    int? maxFin;
    for (final t in _tareasFiltradas) {
      final ini = t.fechaInicio.toLocal();
      if (!DateUtils.isSameDay(ini, fecha)) continue;
      final fin = t.fechaFin.toLocal();
      final iniMin = ini.hour * 60 + ini.minute;
      final finMin = fin.hour * 60 + fin.minute;
      if (finMin <= iniMin) continue;
      minInicio = minInicio == null
          ? iniMin
          : (iniMin < minInicio ? iniMin : minInicio);
      maxFin = maxFin == null ? finMin : (finMin > maxFin ? finMin : maxFin);
    }
    if (minInicio == null || maxFin == null) return const [];
    return [_MinuteRange(start: minInicio, end: maxFin)];
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
        final operarios = _operariosConCargoEntries(t).toSet();
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
            final key = '${operario.key}|${operario.value}';
            rangosPorOperario
                .putIfAbsent(key, () => <_MinuteRange>[])
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
            nombre: entry.key.split('|').first,
            cargo: entry.key.contains('|')
                ? entry.key.substring(entry.key.indexOf('|') + 1)
                : '',
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

    Color colorPorUso(double value) {
      if (value >= 0.8) return Colors.green.shade500;
      if (value >= 0.4) return Colors.orange.shade500;
      return Colors.red.shade400;
    }

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
                                    item.cargo.isEmpty
                                        ? item.nombre
                                        : '${item.nombre} (${item.cargo})',
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
                                      : colorPorUso(item.porcentajeOcupacion),
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

  /// Carga la trazabilidad del mes. Es informativa: si falla, el cronograma
  /// se sigue mostrando sin el bloque de auditoría.
  Future<void> _cargarTrazabilidadTareas(List<TareaModel> tareas) async {
    if (tareas.isEmpty) {
      if (mounted) setState(() => _trazabilidadTareas = const {});
      return;
    }

    try {
      final mapa = await _auditoriaApi.trazabilidad(
        nit: widget.nit,
        entidad: 'Tarea',
        entidadIds: tareas.map((t) => t.id.toString()).toList(),
      );
      if (!mounted) return;
      setState(() => _trazabilidadTareas = mapa);
    } catch (_) {
      if (!mounted) return;
      setState(() => _trazabilidadTareas = const {});
    }
  }

  /// Informativo: si falla no debe impedir ver el cronograma.
  Future<void> _cargarInformeExcluidas() async {
    if (!_canViewExcluidasStandby) return;
    try {
      final data = await _cronogramaApi.informeExcluidas(
        nit: widget.nit,
        anio: _anioActual,
        mes: _mesActual,
      );
      if (!mounted) return;
      setState(() => _informeExcluidas = data);
    } catch (_) {
      if (!mounted) return;
      setState(() => _informeExcluidas = const {});
    }
  }

  /// Sección del informe (al pie) con las excluidas programadas
  /// posteriormente, los cambios de operario y las que siguen pendientes,
  /// presentadas como una sola tabla resumen.
  Widget _buildSeccionInformeExcluidas() {
    final programadas =
        ((_informeExcluidas['programadasPosteriormente'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
    final excepciones =
        ((_informeExcluidas['excepcionesOperario'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
    final pendientes = ((_informeExcluidas['pendientes'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    if (programadas.isEmpty && excepciones.isEmpty && pendientes.isEmpty) {
      return const SizedBox.shrink();
    }

    String actorDe(Map<String, dynamic> item) {
      final actor = item['actor'] as Map?;
      final nombre = actor?['nombre']?.toString();
      final rol = actor?['rol']?.toString();
      if (nombre == null || nombre.trim().isEmpty) return 'el sistema';
      return rol == null || rol.isEmpty ? nombre : '$nombre ($rol)';
    }

    final filas = <_FilaExcluidaInforme>[
      for (final item in programadas)
        _FilaExcluidaInforme(
          descripcion: (item['descripcion'] ?? '—').toString(),
          estado: 'Reprogramada',
          color: Colors.blue.shade700,
          detalle: (() {
            final desplazadas =
                ((item['tareasDesplazadas'] as List?) ?? const [])
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList();
            if (desplazadas.isEmpty) {
              return 'Se ubicó en un hueco libre, sin desplazar tareas.';
            }
            return desplazadas
                .map(
                  (d) =>
                      '${d['descripcion'] ?? '—'} '
                      '(${(d['accion'] ?? '').toString().toLowerCase()})',
                )
                .join(' · ');
          })(),
          responsable: actorDe(item),
        ),
      for (final item in excepciones)
        _FilaExcluidaInforme(
          descripcion: (item['descripcion'] ?? '—').toString(),
          estado: 'Cambio de operario',
          color: Colors.purple.shade700,
          detalle:
              '${((item['operariosOriginales'] as List?) ?? const []).join(', ')} '
              '→ ${((item['operariosNuevos'] as List?) ?? const []).join(', ')}',
          responsable: actorDe(item),
        ),
      for (final item in pendientes)
        _FilaExcluidaInforme(
          descripcion: (item['descripcion'] ?? '—').toString(),
          estado: 'Pendiente',
          color: Colors.red.shade700,
          detalle: (item['motivoMensaje'] ?? item['motivoTipo'] ?? '—')
              .toString(),
          responsable: '—',
        ),
    ];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .025),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    Icons.event_busy_outlined,
                    color: Colors.indigo.shade700,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tareas excluidas del periodo (${filas.length})',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tareas que no quedaron programadas en su fecha original: cómo se resolvieron o por qué siguen pendientes.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStatePropertyAll(Colors.blueGrey.shade50),
              headingTextStyle: TextStyle(
                color: Colors.blueGrey.shade900,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
              dataTextStyle: const TextStyle(fontSize: 12),
              horizontalMargin: 16,
              columnSpacing: 24,
              border: TableBorder(
                horizontalInside: BorderSide(color: Colors.grey.shade200),
              ),
              columns: const [
                DataColumn(label: Text('Tarea')),
                DataColumn(label: Text('Estado')),
                DataColumn(label: Text('Detalle')),
                DataColumn(label: Text('Responsable')),
              ],
              rows: filas.indexed.map((entry) {
                final index = entry.$1;
                final fila = entry.$2;
                return DataRow(
                  color: WidgetStatePropertyAll(
                    index.isEven
                        ? Colors.white
                        : Colors.blueGrey.withValues(alpha: .025),
                  ),
                  cells: [
                    DataCell(
                      SizedBox(
                        width: 220,
                        child: Text(
                          fila.descripcion,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: fila.color.withValues(alpha: .09),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: fila.color.withValues(alpha: .28),
                          ),
                        ),
                        child: Text(
                          fila.estado,
                          style: TextStyle(
                            color: fila.color,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 320,
                        child: Text(
                          fila.detalle,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(Text(fila.responsable)),
                  ],
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _abrirDetalleExcluidaPorId(int excluidaId) {
    final excluida = _excluidasMes.where((e) => e.id == excluidaId).firstOrNull;
    if (excluida == null) return;
    _mostrarDetalleExcluidaStandby(excluida, context);
  }

  void _mostrarDetalleExcluidaStandby(
    PreventivaExcluidaBorradorModel item,
    BuildContext context,
  ) {
    final operarios = item.operariosNombres.isEmpty
        ? 'Sin operario sugerido'
        : item.operariosNombres.join(', ');
    final motivo = item.motivoMensaje ?? item.motivoTipo;

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.descripcion,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Fecha objetivo: ${DateFormat('dd/MM/yyyy', 'es').format(item.fechaObjetivo)}',
              ),
              Text('Duración: ${item.duracionLabel}'),
              Text('Ubicación: ${item.ubicacionNombre ?? '—'}'),
              Text('Elemento: ${item.elementoNombre ?? '—'}'),
              Text('Operarios: $operarios'),
              Text('Motivo: $motivo'),
              Text(
                etiquetaFrecuenciaCompleta(
                  item.frecuencia,
                  diaSemana: item.diaSemanaProgramado,
                  fechaReferencia: item.fechaObjetivo,
                ),
              ),
              const SizedBox(height: 12),
              if (_canScheduleCorrectivasInCronograma) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _cambiarOperarioExcluida(item);
                      },
                      icon: const Icon(Icons.person_search, size: 18),
                      label: const Text('Cambiar operario (excepción)'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _programarExcluidaDesplazandoTareas(item);
                      },
                      icon: const Icon(Icons.event_available, size: 18),
                      label: const Text('Programar desplazando tareas'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cerrar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _pedirMotivoReemplazoOpcional() async {
    // El controller vive dentro del diálogo (StatefulWidget): si se liberara
    // aquí, el TextField aún se reconstruiría durante la animación de cierre
    // y lanzaría "used after being disposed".
    return showDialog<String?>(
      context: context,
      builder: (_) => const _MotivoReemplazoDialog(),
    );
  }

  /// Cambia el operario de una excluida del cronograma publicado. Es una
  /// excepción puntual: no toca la definición preventiva ni los meses siguientes.
  Future<void> _cambiarOperarioExcluida(
    PreventivaExcluidaBorradorModel excluida,
  ) async {
    if (_accionExcluidaEnCurso) return;

    // Se piden los operarios con disponibilidad en la ventana de la excluida.
    final inicio = DateTime(
      excluida.fechaObjetivo.year,
      excluida.fechaObjetivo.month,
      excluida.fechaObjetivo.day,
      8,
    );

    setState(() => _accionExcluidaEnCurso = true);
    List<Map<String, dynamic>> candidatos;
    try {
      candidatos = await _cronogramaApi.sugerirOperarios(
        nit: widget.nit,
        inicio: inicio,
        fin: inicio.add(Duration(minutes: excluida.duracionMinutos)),
        max: 20,
      );
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text(AppError.messageOf(e))),
      );
      return;
    } finally {
      if (mounted) setState(() => _accionExcluidaEnCurso = false);
    }

    if (!mounted) return;
    if (candidatos.isEmpty) {
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(
          content: Text('Ningún operario tiene disponibilidad ese día.'),
        ),
      );
      return;
    }

    final seleccionado = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Asignar otro operario solo para esta tarea',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'El plan preventivo no cambia: el próximo mes vuelve a programarse '
              'con ${excluida.operariosNombres.isEmpty ? 'el operario original' : excluida.operariosNombres.join(', ')}.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            ...candidatos.map(
              (op) => ListTile(
                leading: const Icon(Icons.person),
                title: Text((op['nombre'] ?? op['id'] ?? '—').toString()),
                onTap: () => Navigator.of(ctx).pop(op),
              ),
            ),
          ],
        ),
      ),
    );

    if (seleccionado == null || !mounted) return;

    final motivo = await _pedirMotivoReemplazoOpcional();
    if (motivo == null || !mounted) return;

    final nombreOperario =
        (seleccionado['nombre'] ?? seleccionado['id'] ?? 'El operario')
            .toString();

    setState(() => _accionExcluidaEnCurso = true);
    try {
      await _cronogramaApi.reasignarOperarioExcluidaStandby(
        nit: widget.nit,
        excluidaId: excluida.id,
        nuevoOperarioId: seleccionado['id'].toString(),
        motivo: motivo.trim().isEmpty ? null : motivo,
      );
      await _cargarDatos();
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text(
            'Excepción aplicada: $nombreOperario asumirá esta tarea.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text(AppError.messageOf(e))),
      );
    } finally {
      if (mounted) setState(() => _accionExcluidaEnCurso = false);
    }
  }

  /// Programa una excluida desplazando una o varias tareas ya publicadas.
  Future<void> _programarExcluidaDesplazandoTareas(
    PreventivaExcluidaBorradorModel excluida, {
    TareaModel? preseleccionada,
    DateTime? fecha,
  }) async {
    if (_accionExcluidaEnCurso) return;

    final dia = fecha ?? preseleccionada?.fechaInicio ?? excluida.fechaObjetivo;

    setState(() => _accionExcluidaEnCurso = true);
    Map<String, dynamic> opciones;
    try {
      opciones = await _cronogramaApi.opcionesReemplazoExcluida(
        nit: widget.nit,
        excluidaId: excluida.id,
        fecha: dia,
      );
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text(AppError.messageOf(e))),
      );
      return;
    } finally {
      if (mounted) setState(() => _accionExcluidaEnCurso = false);
    }

    if (!mounted) return;

    final seleccion = await _elegirTareasADesplazar(
      excluida: excluida,
      opciones: opciones,
      preseleccionadaId: preseleccionada?.id,
    );
    if (seleccion == null || !mounted) return;

    final motivo = await _pedirMotivoReemplazoOpcional();
    if (motivo == null || !mounted) return;

    final inicio = DateTime(
      dia.year,
      dia.month,
      dia.day,
      preseleccionada?.fechaInicio.hour ?? 8,
      preseleccionada?.fechaInicio.minute ?? 0,
    );

    setState(() => _accionExcluidaEnCurso = true);
    try {
      final resp = await _cronogramaApi.programarExcluidaComoCorrectiva(
        nit: widget.nit,
        excluidaId: excluida.id,
        fechaInicio: inicio,
        fechaFin: inicio.add(Duration(minutes: excluida.duracionMinutos)),
        reemplazarTareaIds: seleccion.isEmpty ? null : seleccion,
        motivoReemplazo: motivo.trim().isEmpty ? null : motivo,
      );

      if (resp['ok'] == false) {
        throw Exception(
          (resp['message'] ??
                  'No se pudo programar la excluida como correctiva.')
              .toString(),
        );
      }

      await _cargarDatos();
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text(
            seleccion.isEmpty
                ? 'Excluida programada como correctiva.'
                : 'Excluida programada desplazando ${seleccion.length} tarea(s).',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text(AppError.messageOf(e))),
      );
    } finally {
      if (mounted) setState(() => _accionExcluidaEnCurso = false);
    }
  }

  /// Hoja de selección múltiple: muestra cuántos minutos libera cada tarea y
  /// cuántos faltan para que quepa la excluida.
  Future<List<int>?> _elegirTareasADesplazar({
    required PreventivaExcluidaBorradorModel excluida,
    required Map<String, dynamic> opciones,
    int? preseleccionadaId,
  }) {
    final lista = ((opciones['opciones'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final combinacionMinima =
        ((opciones['combinacionMinima'] as List?) ?? const [])
            .map((e) => (e as num).toInt())
            .toList();
    final minutosFaltantes =
        (opciones['minutosFaltantes'] as num?)?.toInt() ?? 0;

    final seleccionados = <int>{
      if (preseleccionadaId != null) preseleccionadaId,
      ...combinacionMinima,
    };

    return showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final liberados = lista
              .where(
                (t) => seleccionados.contains((t['tareaId'] as num).toInt()),
              )
              .fold<int>(
                0,
                (acc, t) =>
                    acc + ((t['minutosQueLibera'] as num?)?.toInt() ?? 0),
              );
          final suficiente = liberados >= minutosFaltantes;

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tareas a desplazar para "${excluida.descripcion}"',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    minutosFaltantes == 0
                        ? 'Ya hay espacio libre: puedes programarla sin desplazar nada.'
                        : 'Faltan $minutosFaltantes min. Seleccionadas: $liberados min.',
                    style: TextStyle(
                      fontSize: 12,
                      color: suficiente
                          ? Colors.green.shade800
                          : Colors.orange.shade900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (lista.isEmpty)
                    const Text(
                      'No hay tareas publicadas ese día para desplazar.',
                    )
                  else
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: lista.map((t) {
                          final id = (t['tareaId'] as num).toInt();
                          final inicio = DateTime.parse(
                            t['fechaInicio'].toString(),
                          ).toLocal();
                          final fin = DateTime.parse(
                            t['fechaFin'].toString(),
                          ).toLocal();
                          return CheckboxListTile(
                            value: seleccionados.contains(id),
                            onChanged: (v) => setSheetState(() {
                              if (v == true) {
                                seleccionados.add(id);
                              } else {
                                seleccionados.remove(id);
                              }
                            }),
                            title: Text(t['descripcion']?.toString() ?? '—'),
                            subtitle: Text(
                              'P${t['prioridad']} · '
                              '${DateFormat('HH:mm').format(inicio)}-${DateFormat('HH:mm').format(fin)} · '
                              'libera ${t['minutosQueLibera']} min',
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Cancelar'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: suficiente
                            ? () =>
                                  Navigator.of(ctx).pop(seleccionados.toList())
                            : null,
                        child: const Text('Programar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _programarExcluidaComoCorrectiva({
    required PreventivaExcluidaBorradorModel excluida,
    required DateTime nuevoInicio,
    required DateTime nuevoFin,
    TareaModel? tareaReemplazo,
  }) async {
    int? reemplazarTareaId;
    String? motivoReemplazo;

    if (tareaReemplazo != null) {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Reemplazar preventiva publicada'),
          content: Text(
            'La excluida "${excluida.descripcion}" se programará como correctiva sobre la preventiva "${tareaReemplazo.descripcion}". La preventiva quedará en no completada. ¿Deseas continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Reemplazar'),
            ),
          ],
        ),
      );
      if (confirmar != true || !mounted) return;

      motivoReemplazo = await _pedirMotivoReemplazoOpcional();
      if (!mounted) return;
      if (motivoReemplazo == null) return;
      reemplazarTareaId = tareaReemplazo.id;
    }

    final resp = await _cronogramaApi.programarExcluidaComoCorrectiva(
      nit: widget.nit,
      excluidaId: excluida.id,
      fechaInicio: nuevoInicio,
      fechaFin: nuevoFin,
      reemplazarTareaId: reemplazarTareaId,
      motivoReemplazo: motivoReemplazo,
    );

    if (resp['ok'] == false) {
      throw Exception(
        (resp['message'] ?? 'No se pudo programar la excluida como correctiva.')
            .toString(),
      );
    }

    await _cargarDatos();
    if (!mounted) return;
    AppFeedback.showFromSnackBar(
      context,
      SnackBar(
        content: Text(
          reemplazarTareaId != null
              ? 'Excluida programada como correctiva y preventiva reemplazada.'
              : 'Excluida programada como correctiva correctamente.',
        ),
      ),
    );
  }

  /// Ubica una actividad especial pendiente (arrastrada o "tocar para
  /// ubicar") en el horario elegido. Sin [tareaReemplazo] se crea sobre un
  /// hueco libre; con ella, se pide confirmación y reemplaza la preventiva
  /// (queda NO_COMPLETADA, como el resto del flujo de reemplazo).
  Future<void> _programarActividadEspecial({
    required ActividadEspecialPendiente pendiente,
    required DateTime nuevoInicio,
    required DateTime nuevoFin,
    TareaModel? tareaReemplazo,
  }) async {
    if (_guardandoPendiente) return;

    final etiqueta = etiquetaCorrectiva();
    String? motivoReemplazo;

    if (tareaReemplazo != null) {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Reemplazar preventiva publicada'),
          content: Text(
            '"${pendiente.descripcion}" se programará sobre la preventiva '
            '"${tareaReemplazo.descripcion}" '
            '(${DateFormat("HH:mm").format(tareaReemplazo.fechaInicio.toLocal())} - '
            '${DateFormat("HH:mm").format(tareaReemplazo.fechaFin.toLocal())}, '
            'P${tareaReemplazo.prioridad}). '
            'La preventiva quedará en no completada. ¿Deseas continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Reemplazar'),
            ),
          ],
        ),
      );
      if (confirmar != true || !mounted) return;

      motivoReemplazo = await _pedirMotivoReemplazoOpcional();
      if (!mounted) return;
      if (motivoReemplazo == null) return;
    }

    setState(() => _guardandoPendiente = true);
    try {
      final req = pendiente.toRequest(
        conjuntoId: widget.nit,
        inicio: nuevoInicio,
        fin: nuevoFin,
      );

      final resp = tareaReemplazo != null
          ? await _tareaApi.crearTareaConReemplazo(
              tarea: req,
              reemplazarIds: [tareaReemplazo.id],
              accionReemplazadas: 'CANCELAR',
              motivoReemplazo: motivoReemplazo!.isEmpty
                  ? null
                  : motivoReemplazo,
            )
          : await _tareaApi.crearTarea(req);

      if (!mounted) return;

      if (resp['needsReplacement'] == true) {
        AppFeedback.showFromSnackBar(
          context,
          SnackBar(
            content: Text(
              'Ese horario ya no está libre para "${pendiente.descripcion}". '
              'Suéltala en otra franja libre o sobre la preventiva que quieras reemplazar.',
            ),
          ),
        );
        return;
      }

      if (resp['ok'] == false) {
        AppFeedback.showFromSnackBar(
          context,
          SnackBar(
            content: Text(
              (resp['message'] ?? 'No se pudo programar la $etiqueta.')
                  .toString(),
            ),
          ),
        );
        return;
      }

      setState(() {
        _pendientes.removeWhere((p) => p.localId == pendiente.localId);
        if (_pendienteEnUbicacion?.localId == pendiente.localId) {
          _pendienteEnUbicacion = null;
        }
      });

      await _cargarDatos();
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text(
            tareaReemplazo != null
                ? '$etiqueta programada y preventiva reemplazada.'
                : '$etiqueta programada correctamente.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text(AppError.messageOf(e))),
      );
    } finally {
      if (mounted) setState(() => _guardandoPendiente = false);
    }
  }

  Future<void> _confirmarQuitarPendiente(
    ActividadEspecialPendiente pendiente,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Quitar ${etiquetaCorrectiva(minuscula: true)}'),
        content: Text(
          'Se perderá la información de "${pendiente.descripcion}" porque aún no se ha programado. ¿Deseas quitarla?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _pendientes.removeWhere((p) => p.localId == pendiente.localId);
      if (_pendienteEnUbicacion?.localId == pendiente.localId) {
        _pendienteEnUbicacion = null;
      }
    });
  }

  Widget _buildPendienteCard(ActividadEspecialPendiente pendiente) {
    final activa = _pendienteEnUbicacion?.localId == pendiente.localId;
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: activa ? const Color(0xFFDDD6FE) : const Color(0xFFF5F3FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: activa ? const Color(0xFF6D28D9) : const Color(0xFFC4B5FD),
          width: activa ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.build_circle_outlined,
                size: 16,
                color: Color(0xFF6D28D9),
              ),
              const SizedBox(width: 4),
              Text(
                'P${pendiente.prioridad} · ${pendiente.duracionLabel}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF5B21B6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            pendiente.descripcion,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            '${pendiente.ubicacionNombre} · ${pendiente.elementoNombre}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _pendienteEnUbicacion = activa ? null : pendiente;
                      if (!activa) _vistaAgendaEnMovil = false;
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 32),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: Icon(
                    activa ? Icons.close_rounded : Icons.touch_app_outlined,
                    size: 14,
                  ),
                  label: Text(
                    activa ? 'Cancelar' : 'Ubicar',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Quitar',
                onPressed: () => _confirmarQuitarPendiente(pendiente),
                icon: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: Colors.redAccent,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );

    return LongPressDraggable<_DraggedWeekEspecial>(
      data: _DraggedWeekEspecial(pendiente: pendiente),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () => _weekEspecialDragActiveNotifier.value = true,
      onDragEnd: (_) {
        _weekEspecialDragActiveNotifier.value = false;
        _setEspecialPreview(null);
      },
      onDraggableCanceled: (_, __) {
        _weekEspecialDragActiveNotifier.value = false;
        _setEspecialPreview(null);
      },
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: 210, child: card),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: card),
      child: card,
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
      // El supervisor no necesita el resumen de horas por operario (es
      // información de gestión, no algo que use para cerrar tareas), pero
      // sí necesita los filtros (operario, ubicación, estado...) para poder
      // ubicar rápido a quién le va a cerrar una tarea; en desktop esos
      // filtros solo viven dentro del sidebar "Resumen", que en móvil no se
      // muestra en absoluto, así que aquí se exponen aparte.
      final esSupervisor = _rolActual == 'supervisor';
      // Todo el contenido hace scroll vertical: con los filtros desplegados o
      // en pantallas bajas (celular horizontal) la agenda/cuadrícula ya no se
      // desborda, solo queda más abajo.
      final altoContenido = (MediaQuery.of(context).size.height * 0.72)
          .clamp(420.0, 900.0)
          .toDouble();
      return SingleChildScrollView(
        child: Column(
          children: [
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                // Colapsado por defecto en móvil/tablet: en pantallas chicas
                // los filtros desplegados empujan la agenda/cuadrícula fuera
                // de la vista inicial. El usuario los expande si los necesita.
                initiallyExpanded: false,
                title: const Text(
                  'Filtros',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                childrenPadding: const EdgeInsets.only(bottom: 8),
                children: [_buildFiltrosComoColumna(mostrarTitulo: false)],
              ),
            ),
            // El resumen de horas solo se muestra con la agenda en lista: en la
            // cuadrícula le quita espacio vertical al horario.
            if (!esSupervisor && _vistaAgendaEnMovil) ...[
              _buildResumenHorasSemanaCard(
                resumenSemana,
                resumenOperarios,
                compact: true,
              ),
              const SizedBox(height: 10),
            ],
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('Agenda'),
                  icon: Icon(Icons.view_agenda_outlined),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('Cuadrícula'),
                  icon: Icon(Icons.grid_on_outlined),
                ),
              ],
              selected: {_vistaAgendaEnMovil},
              onSelectionChanged: (value) {
                setState(() => _vistaAgendaEnMovil = value.first);
                // En celular, 7 columnas no caben: al abrir la cuadrícula se
                // enfoca un día (hoy si está en la semana). "Ver semana" vuelve.
                if (!value.first &&
                    _diaFoco == null &&
                    MediaQuery.of(context).size.width < 600) {
                  final inicio = _startOfWeekMonday(_semanaBase);
                  final hoy = DateTime.now();
                  DateTime? elegido;
                  for (var i = 0; i < 7; i++) {
                    final d = inicio.add(Duration(days: i));
                    if (!_diaEnMesActual(d)) continue;
                    elegido ??= d;
                    if (d.year == hoy.year &&
                        d.month == hoy.month &&
                        d.day == hoy.day) {
                      elegido = d;
                      break;
                    }
                  }
                  if (elegido != null) _enfocarDia(elegido);
                }
              },
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: altoContenido,
              child: _vistaAgendaEnMovil
                  ? _SidebarAgendaDia(
                      weekStart: weekStart,
                      dayIndex: _sidebarDiaIndex,
                      onDayIndexChanged: (value) =>
                          setState(() => _sidebarDiaIndex = value),
                      modo: _sidebarAgendaModo,
                      onModoChanged: _canViewExcluidasStandby
                          ? (value) =>
                                setState(() => _sidebarAgendaModo = value)
                          : null,
                      verExcluidasMes: _sidebarVerExcluidasMes,
                      onVerExcluidasMesChanged: (value) =>
                          setState(() => _sidebarVerExcluidasMes = value),
                      tareasSemana: tareas,
                      excluidasMes: _excluidasFiltradas,
                      excluirPorFecha: _excluidasPorFecha,
                      actividadesEspeciales: _pendientes,
                      masOpcionesButton: _canScheduleCorrectivasInCronograma
                          ? _buildMasOpcionesButton(compact: true)
                          : null,
                      buildActividadEspecial: _buildPendienteCard,
                      onTapTarea: (t) => _mostrarDetalleTarea(t, context),
                      onTapExcluida: _canViewExcluidasStandby
                          ? (item) =>
                                _mostrarDetalleExcluidaStandby(item, context)
                          : null,
                    )
                  : _WeekScheduleView(
                      weekStart: _diaFoco ?? weekStart,
                      dias: _diaFoco == null ? 7 : 1,
                      onFocoDia: _enfocarDia,
                      tareas: tareas,
                      horariosConjunto: _horariosConjunto,
                      scaleMinutes: _escalaSemanalMinutos,
                      horaInicio: _horaInicioJornada,
                      horaFin: _horaFinJornada,
                      horaDescansoInicio: _horaDescansoInicio,
                      horaDescansoFin: _horaDescansoFin,
                      esFestivo: _esFestivo,
                      nombreFestivo: _nombreFestivo,
                      onTapTarea: (t) => _mostrarDetalleTarea(t, context),
                      onMoveCorrectiva: _canScheduleCorrectivasInCronograma
                          ? _moverCorrectivaDesdeCronograma
                          : null,
                      onProgramExcluidaComoCorrectiva: _canViewExcluidasStandby
                          ? _programarExcluidaComoCorrectiva
                          : null,
                      onProgramarActividadEspecial:
                          _canScheduleCorrectivasInCronograma
                          ? _programarActividadEspecial
                          : null,
                      pendienteEnUbicacion: _pendienteEnUbicacion,
                    ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: _sidebarResumenColapsado ? 76 : 340,
          child: _SidebarSimple(
            title: 'Resumen',
            collapsed: _sidebarResumenColapsado,
            onToggle: () {
              setState(() {
                _sidebarResumenColapsado = !_sidebarResumenColapsado;
              });
            },
            items: [
              'Tareas semana: ${tareas.length}',
              'Tareas mes: ${_tareasFiltradas.length}',
              _resumenHorario,
              if (_canScheduleCorrectivasInCronograma &&
                  _vista == _VistaCronograma.semanal)
                'Usa "Más opciones" para crear una ${etiquetaCorrectiva(minuscula: true)} y arrástrala al horario',
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _WeekScheduleView(
                  weekStart: _diaFoco ?? weekStart,
                  dias: _diaFoco == null ? 7 : 1,
                  onFocoDia: _enfocarDia,
                  tareas: tareas,
                  horariosConjunto: _horariosConjunto,
                  scaleMinutes: _escalaSemanalMinutos,
                  horaInicio: _horaInicioJornada,
                  horaFin: _horaFinJornada,
                  horaDescansoInicio: _horaDescansoInicio,
                  horaDescansoFin: _horaDescansoFin,
                  esFestivo: _esFestivo,
                  nombreFestivo: _nombreFestivo,
                  onTapTarea: (t) => _mostrarDetalleTarea(t, context),
                  onMoveCorrectiva: _canScheduleCorrectivasInCronograma
                      ? _moverCorrectivaDesdeCronograma
                      : null,
                  onProgramExcluidaComoCorrectiva: _canViewExcluidasStandby
                      ? _programarExcluidaComoCorrectiva
                      : null,
                  onProgramarActividadEspecial:
                      _canScheduleCorrectivasInCronograma
                      ? _programarActividadEspecial
                      : null,
                  pendienteEnUbicacion: _pendienteEnUbicacion,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: _sidebarAgendaColapsada ? 76 : 360,
          child: _sidebarAgendaColapsada
              ? Card(
                  color: Colors.white,
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Tooltip(
                          message: 'Agenda y excluidas',
                          child: Icon(Icons.event_note_outlined, size: 22),
                        ),
                        const SizedBox(height: 10),
                        IconButton(
                          tooltip: 'Expandir agenda del día',
                          onPressed: () =>
                              setState(() => _sidebarAgendaColapsada = false),
                          icon: const Icon(
                            Icons.keyboard_double_arrow_left_rounded,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        tooltip: 'Colapsar agenda del día',
                        onPressed: () =>
                            setState(() => _sidebarAgendaColapsada = true),
                        icon: const Icon(
                          Icons.keyboard_double_arrow_right_rounded,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _SidebarAgendaDia(
                        weekStart: weekStart,
                        dayIndex: _sidebarDiaIndex,
                        onDayIndexChanged: (value) =>
                            setState(() => _sidebarDiaIndex = value),
                        modo: _sidebarAgendaModo,
                        onModoChanged: _canViewExcluidasStandby
                            ? (value) =>
                                  setState(() => _sidebarAgendaModo = value)
                            : null,
                        verExcluidasMes: _sidebarVerExcluidasMes,
                        onVerExcluidasMesChanged: (value) =>
                            setState(() => _sidebarVerExcluidasMes = value),
                        tareasSemana: tareas,
                        excluidasMes: _excluidasFiltradas,
                        excluirPorFecha: _excluidasPorFecha,
                        actividadesEspeciales: _pendientes,
                        masOpcionesButton: _canScheduleCorrectivasInCronograma
                            ? _buildMasOpcionesButton(compact: true)
                            : null,
                        buildActividadEspecial: _buildPendienteCard,
                        onTapTarea: (t) => _mostrarDetalleTarea(t, context),
                        onTapExcluida: _canViewExcluidasStandby
                            ? (item) =>
                                  _mostrarDetalleExcluidaStandby(item, context)
                            : null,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  int _indiceSemanaMes(DateTime date) {
    final localDate = date.toLocal();
    final firstDay = DateTime(_anioActual, _mesActual, 1);
    final offset = firstDay.weekday - DateTime.monday;
    return (((localDate.day + offset - 1) ~/ 7) + 1).clamp(1, 5);
  }

  List<String> _labelsSemanasInforme() {
    final firstDay = DateTime(_anioActual, _mesActual, 1);
    final lastDay = DateTime(_anioActual, _mesActual + 1, 0);
    final offset = firstDay.weekday - DateTime.monday;

    return List.generate(5, (index) {
      final weekStartDay = index == 0 ? 1 : (index * 7) - offset + 1;
      final weekEndDay = ((index + 1) * 7) - offset;
      final startDay = weekStartDay.clamp(1, lastDay.day);
      final endDay = weekEndDay.clamp(1, lastDay.day);
      final start = DateTime(_anioActual, _mesActual, startDay);
      final end = DateTime(_anioActual, _mesActual, endDay);
      final rango =
          DateFormat('d MMM', 'es').format(start) ==
              DateFormat('d MMM', 'es').format(end)
          ? DateFormat('d MMM', 'es').format(start)
          : '${DateFormat('d MMM', 'es').format(start)} - ${DateFormat('d MMM', 'es').format(end)}';
      return 'Semana ${index + 1}\n($rango)';
    });
  }

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
    final weekLabels = _labelsSemanasInforme();
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
                  col(weekLabels[0]),
                  col(weekLabels[1]),
                  col(weekLabels[2]),
                  col(weekLabels[3]),
                  col(weekLabels[4]),
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
    return SingleChildScrollView(
      child: CronogramaInformeJerarquico(
        informe: _informeJerarquico,
        loading: _cargandoInformeJerarquico,
        operarioId: _informeOperarioId,
        filtrarSemana: _informeFiltrarSemana,
        onFiltrarSemanaChanged: (value) {
          setState(() => _informeFiltrarSemana = value);
          unawaited(_cargarInformeJerarquico());
        },
        piePagina: _buildSeccionInformeExcluidas(),
        onOperarioChanged: (operarioId) {
          setState(() => _informeOperarioId = operarioId);
          unawaited(_cargarInformeJerarquico());
        },
      ),
    );
  }

  // Se conserva durante la transición de datos históricos sin ocurrencias.
  // ignore: unused_element
  Widget _buildInformeActividadLegacy() {
    if (_informeActividad.isEmpty) {
      return const Center(
        child: Text('No hay actividades planificadas para este periodo.'),
      );
    }

    final weekLabels = _labelsSemanasInforme();
    final horasPorZona = _resumenHorasAgrupadas(
      _tareasFiltradas,
      (tarea) => [(tarea.ubicacionNombre ?? '').trim()],
    );
    final horasPorTrabajador = _resumenHorasAgrupadas(
      _tareasFiltradas,
      _operariosConCargo,
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
            _buildSeccionInformeExcluidas(),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  col('Actividad'),
                  col('Horas mes'),
                  col(weekLabels[0]),
                  col(weekLabels[1]),
                  col(weekLabels[2]),
                  col(weekLabels[3]),
                  col(weekLabels[4]),
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
}

class _FilaExcluidaInforme {
  final String descripcion;
  final String estado;
  final Color color;
  final String detalle;
  final String responsable;

  const _FilaExcluidaInforme({
    required this.descripcion,
    required this.estado,
    required this.color,
    required this.detalle,
    required this.responsable,
  });
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
//   Banda de almuerzo + pxPorMin + tema claro
// ============================

Color _cronogramaColorBaseTareaSemana(TareaModel t) {
  final tipo = (t.tipo ?? '').toUpperCase().trim();
  if (tipo == 'CORRECTIVA') return Colors.red.shade500;

  // El color de la categoría manda: así una categoría se reconoce de un vistazo
  // en el borrador y en el cronograma publicado.
  final colorCategoria = t.categoriaColorHex?.replaceFirst('#', '');
  if (colorCategoria != null &&
      RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(colorCategoria)) {
    return Color(int.parse('FF$colorCategoria', radix: 16));
  }

  final colorZona = t.zonaCronograma?.colorHex.replaceFirst('#', '');
  if (colorZona != null && RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(colorZona)) {
    return Color(int.parse('FF$colorZona', radix: 16));
  }

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
  final DateTime weekStart; // lunes 00:00 (o el día enfocado si dias == 1)

  /// Cuántos días se dibujan desde [weekStart]: 7 = semana; 1 = enfoque en
  /// un solo día (más espacio para cuadrar las tareas).
  final int dias;

  /// Si se entrega, tocar el encabezado de un día pide enfocarlo.
  final void Function(DateTime dia)? onFocoDia;
  final List<TareaModel> tareas;
  final List<HorarioConjunto> horariosConjunto;
  final int scaleMinutes;
  final int horaInicio;
  final int horaFin;
  final int? horaDescansoInicio;
  final int? horaDescansoFin;
  final bool Function(DateTime d) esFestivo;
  final String? Function(DateTime d) nombreFestivo;
  final void Function(TareaModel t) onTapTarea;
  final Future<void> Function({
    required TareaModel tarea,
    required DateTime nuevoInicio,
    required DateTime nuevoFin,
  })?
  onMoveCorrectiva;
  final Future<void> Function({
    required PreventivaExcluidaBorradorModel excluida,
    required DateTime nuevoInicio,
    required DateTime nuevoFin,
    TareaModel? tareaReemplazo,
  })?
  onProgramExcluidaComoCorrectiva;
  final Future<void> Function({
    required ActividadEspecialPendiente pendiente,
    required DateTime nuevoInicio,
    required DateTime nuevoFin,
    TareaModel? tareaReemplazo,
  })?
  onProgramarActividadEspecial;

  /// Pendiente que el usuario activó con "Ubicar" en la bandeja: mientras no
  /// sea null, tocar un hueco o una preventiva ubica esa actividad especial
  /// (alternativa al arrastre, para pantallas táctiles).
  final ActividadEspecialPendiente? pendienteEnUbicacion;

  const _WeekScheduleView({
    required this.weekStart,
    this.dias = 7,
    this.onFocoDia,
    required this.tareas,
    required this.horariosConjunto,
    required this.scaleMinutes,
    required this.horaInicio,
    required this.horaFin,
    this.horaDescansoInicio,
    this.horaDescansoFin,
    required this.esFestivo,
    required this.nombreFestivo,
    required this.onTapTarea,
    this.onMoveCorrectiva,
    this.onProgramExcluidaComoCorrectiva,
    this.onProgramarActividadEspecial,
    this.pendienteEnUbicacion,
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

  /// Carril (columna) que ocupa dentro de su grupo de tareas solapadas y
  /// cuántos carriles tiene el grupo: las tareas simultáneas se reparten el
  /// ancho del día lado a lado, como las reuniones en Teams/Outlook.
  final int lane;
  final int laneCount;

  /// Cuántos carriles ocupa: una tarea se ensancha hacia la derecha mientras
  /// los carriles contiguos estén libres en su franja horaria.
  final int laneSpan;

  /// Fin con el que se dibuja (>= fin real): la altura mínima legible se
  /// recorta para no pisar a la tarea siguiente.
  final DateTime? visualFin;

  const _WeekTaskPlacement({
    required this.tarea,
    required this.dayIndex,
    required this.inicio,
    required this.fin,
    this.lane = 0,
    this.laneCount = 1,
    this.laneSpan = 1,
    this.visualFin,
  });
}

class _MotivoReemplazoDialog extends StatefulWidget {
  const _MotivoReemplazoDialog();

  @override
  State<_MotivoReemplazoDialog> createState() => _MotivoReemplazoDialogState();
}

class _MotivoReemplazoDialogState extends State<_MotivoReemplazoDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reemplazar preventiva'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Puedes registrar un motivo de reemplazo si quieres dejar trazabilidad en el reporte.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Motivo opcional',
              hintText: 'Ej. urgencia operacional o daño correctivo',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Continuar'),
        ),
      ],
    );
  }
}

class _DraggedWeekTask {
  final TareaModel tarea;
  final int duracionMinutos;

  const _DraggedWeekTask({required this.tarea, required this.duracionMinutos});
}

class _DraggedWeekExcluida {
  final PreventivaExcluidaBorradorModel excluida;

  const _DraggedWeekExcluida({required this.excluida});
}

class _DraggedWeekEspecial {
  final ActividadEspecialPendiente pendiente;

  const _DraggedWeekEspecial({required this.pendiente});
}

enum _ExcluidaDropState { none, allowed, blocked }

enum _EspecialDropState { none, allowed, blocked }

class _WeekScheduleViewState extends State<_WeekScheduleView> {
  int get _dias => widget.dias.clamp(1, 7);

  final ScrollController _headerHCtrl = ScrollController();
  final ScrollController _hCtrl = ScrollController();
  final ScrollController _vCtrl = ScrollController();
  bool _syncingHeader = false;
  bool _syncingBody = false;
  bool _moviendoCorrectiva = false;
  final Map<int, List<_MinuteRange>> _occupiedRangesByDay = {};
  List<_WeekTaskPlacement> _taskPlacementsCache = const [];
  String _taskPlacementsSignature = '';

  static const double anchoHora = 56;
  static const double altoHeader = 44;

  double get pxPorMin {
    switch (widget.scaleMinutes) {
      case 1:
        return 15.6;
      case 15:
        return 2.4;
      case 30:
        return 1.7;
      default:
        return 1.1;
    }
  }

  int get _horaInicio => widget.horaInicio;
  int get _horaFin => widget.horaFin;
  int get _horasVisible => (_horaFin - _horaInicio).clamp(1, 24);

  String _buildTasksSignature() {
    final buffer = StringBuffer(
      '${widget.weekStart.toIso8601String()}|${widget.scaleMinutes}|'
      '${widget.horaInicio}|${widget.horaFin}|${widget.dias}|',
    );
    for (final tarea in widget.tareas) {
      buffer
        ..write(tarea.id)
        ..write(':')
        ..write(tarea.fechaInicio.millisecondsSinceEpoch)
        ..write(':')
        ..write(tarea.fechaFin.millisecondsSinceEpoch)
        ..write(':')
        ..write(tarea.estado)
        ..write(':')
        ..write(tarea.prioridad)
        ..write(':')
        ..write(tarea.operariosIds.join(','))
        ..write(':')
        ..write(tarea.descripcion.hashCode)
        ..write(';');
    }
    return buffer.toString();
  }

  void _rebuildDerivedWeekDataIfNeeded() {
    final signature = _buildTasksSignature();
    if (signature == _taskPlacementsSignature) return;
    _taskPlacementsSignature = signature;
    _taskPlacementsCache = _buildTaskPlacements();
    _occupiedRangesByDay
      ..clear()
      ..addAll(_buildOccupiedRangesByDay());
  }

  Map<int, List<_MinuteRange>> _buildOccupiedRangesByDay() {
    final out = <int, List<_MinuteRange>>{};
    for (final item in widget.tareas) {
      final ini = item.fechaInicio.toLocal();
      final fin = item.fechaFin.toLocal();
      final day = _dayIndex(ini);
      if (day < 0 || day >= _dias) continue;
      out
          .putIfAbsent(day, () => <_MinuteRange>[])
          .add(
            _MinuteRange(
              tareaId: item.id,
              start: ini.hour * 60 + ini.minute,
              end: fin.hour * 60 + fin.minute,
            ),
          );
    }
    for (final ranges in out.values) {
      ranges.sort((a, b) => a.start.compareTo(b.start));
    }
    return out;
  }

  int _snapToGridNearest(int minutes) {
    final snap = widget.scaleMinutes <= 15 ? widget.scaleMinutes : 30;
    return ((minutes / snap).round()) * snap;
  }

  int _snapToGridForward(int minutes) {
    final snap = widget.scaleMinutes <= 15 ? widget.scaleMinutes : 30;
    return ((minutes + snap - 1) ~/ snap) * snap;
  }

  _MinuteRange? _descansoDia(int dayIndex) {
    final fecha = DateTime(
      widget.weekStart.year,
      widget.weekStart.month,
      widget.weekStart.day,
    ).add(Duration(days: dayIndex));

    for (final horario in widget.horariosConjunto) {
      if (weekdayFromScheduleDay(horario.dia) != fecha.weekday) continue;
      final descansoInicioTime = horario.descansoInicio == null
          ? null
          : parseHourToTimeOfDay(horario.descansoInicio);
      final descansoFinTime = horario.descansoFin == null
          ? null
          : parseHourToTimeOfDay(horario.descansoFin);
      final descansoInicio = descansoInicioTime == null
          ? null
          : timeOfDayToMinutes(descansoInicioTime);
      final descansoFin = descansoFinTime == null
          ? null
          : timeOfDayToMinutes(descansoFinTime);
      final tieneDescanso =
          descansoInicio != null &&
          descansoFin != null &&
          descansoFin > descansoInicio;

      if (!tieneDescanso) return null;
      return _MinuteRange(start: descansoInicio, end: descansoFin);
    }
    return null;
  }

  /// Solo es "después del almuerzo" si el bloque realmente arranca justo al
  /// terminar el almuerzo de ese día — nunca por su sola posición en la
  /// serie de bloques (bloqueIndex), que puede no tener nada que ver con la
  /// hora real (ej. divisiones antiguas entre días).
  bool _esBloqueDespuesDeAlmuerzo(TareaModel t) {
    if (t.bloqueIndex == null || t.bloqueIndex! <= 1) return false;
    final descanso = _descansoDia(_dayIndex(t.fechaInicio));
    if (descanso == null) return false;
    final inicioMin = t.fechaInicio.hour * 60 + t.fechaInicio.minute;
    return inicioMin == descanso.end;
  }

  int _minutesFromStart(DateTime d) {
    final start = DateTime(d.year, d.month, d.day, _horaInicio);
    return d.difference(start).inMinutes;
  }

  List<_MinuteRange> _rangosProgramablesDia(int dayIndex) {
    final fecha = DateTime(
      widget.weekStart.year,
      widget.weekStart.month,
      widget.weekStart.day,
    ).add(Duration(days: dayIndex));

    for (final horario in widget.horariosConjunto) {
      if (weekdayFromScheduleDay(horario.dia) != fecha.weekday) continue;

      final apertura = parseHourToTimeOfDay(horario.horaApertura);
      final cierre = parseHourToTimeOfDay(horario.horaCierre);
      if (apertura == null || cierre == null) return const [];

      final inicio = timeOfDayToMinutes(apertura);
      final fin = timeOfDayToMinutes(cierre);
      if (fin <= inicio) return const [];

      final descanso = _descansoDia(dayIndex);
      if (descanso == null || descanso.end <= descanso.start) {
        return [_MinuteRange(start: inicio, end: fin)];
      }

      final rangos = <_MinuteRange>[];
      if (descanso.start > inicio) {
        rangos.add(_MinuteRange(start: inicio, end: descanso.start));
      }
      if (descanso.end < fin) {
        rangos.add(_MinuteRange(start: descanso.end, end: fin));
      }
      return rangos;
    }

    // El conjunto no tiene horario general para este día (p.ej. domingo):
    // se cae a la jornada ya ampliada por las tareas reales del mes -así
    // una plaza con horario especial que trabaja ese día también permite
    // crear/arrastrar tareas ahí, no solo mostrar las que ya existen-.
    final inicio = _horaInicio * 60;
    final fin = _horaFin * 60;
    if (fin <= inicio) return const [];
    final descanso = _descansoDia(dayIndex);
    if (descanso == null || descanso.end <= descanso.start) {
      return [_MinuteRange(start: inicio, end: fin)];
    }
    final rangos = <_MinuteRange>[];
    if (descanso.start > inicio) {
      rangos.add(_MinuteRange(start: inicio, end: descanso.start));
    }
    if (descanso.end < fin) {
      rangos.add(_MinuteRange(start: descanso.end, end: fin));
    }
    return rangos;
  }

  bool _cabeCompletaEnRangoDisponible({
    required int startMinute,
    required int duracionMinutos,
    required List<_MinuteRange> rangosDisponibles,
  }) {
    final endMinute = startMinute + duracionMinutos;
    return rangosDisponibles.any(
      (rango) => startMinute >= rango.start && endMinute <= rango.end,
    );
  }

  int? _resolverInicioLibreEnDia({
    required int duracionMinutos,
    int? excluirTareaId,
    required int dayIndex,
    required int desiredMinuteOfDay,
  }) {
    final rangosDisponibles = _rangosProgramablesDia(dayIndex);
    if (rangosDisponibles.isEmpty) return null;

    final inicioJornada = rangosDisponibles.first.start;
    final finJornada = rangosDisponibles.last.end;
    if (desiredMinuteOfDay < inicioJornada ||
        desiredMinuteOfDay >= finJornada) {
      return null;
    }

    final spans = (_occupiedRangesByDay[dayIndex] ?? const <_MinuteRange>[])
        .where((range) => range.tareaId != excluirTareaId)
        .toList();

    var start = _snapToGridNearest(desiredMinuteOfDay);
    if (start < inicioJornada) start = _snapToGridForward(inicioJornada);

    var guard = 0;
    while (start + duracionMinutos <= finJornada) {
      if (guard++ > 500) return null;

      if (!_cabeCompletaEnRangoDisponible(
        startMinute: start,
        duracionMinutos: duracionMinutos,
        rangosDisponibles: rangosDisponibles,
      )) {
        final siguienteRango = rangosDisponibles.firstWhere(
          (rango) => start < rango.start || start < rango.end,
          orElse: () => const _MinuteRange(start: -1, end: -1),
        );
        if (siguienteRango.start < 0) return null;
        final nextStart = _snapToGridForward(
          start < siguienteRango.start
              ? siguienteRango.start
              : siguienteRango.end,
        );
        if (nextStart <= start) return null;
        start = nextStart;
        continue;
      }

      var ajustado = false;
      for (final range in spans) {
        final overlaps =
            start < range.end && (start + duracionMinutos) > range.start;
        if (overlaps) {
          final nextStart = _snapToGridForward(range.end);
          if (nextStart <= start) return null;
          start = nextStart;
          ajustado = true;
          break;
        }
      }
      if (!ajustado) return start;
    }
    return null;
  }

  /// Modo "tocar para ubicar": con una pendiente activa (botón "Ubicar" en
  /// la bandeja), tocar un hueco libre la programa ahí mismo, sin arrastre.
  Future<void> _handleTapEnHueco({
    required BuildContext context,
    required TapUpDetails details,
    required int dayIndex,
    required double localTop,
  }) async {
    final pendiente = widget.pendienteEnUbicacion;
    if (pendiente == null) return;
    await _intentarProgramarEspecialEnHueco(
      dragged: _DraggedWeekEspecial(pendiente: pendiente),
      dayIndex: dayIndex,
      localDy: localTop,
    );
  }

  Future<void> _intentarMoverCorrectivaSemana({
    required _DraggedWeekTask dragged,
    required int dayIndex,
    required double localDy,
  }) async {
    if (_moviendoCorrectiva || widget.onMoveCorrectiva == null) return;

    final targetDay = widget.weekStart.add(Duration(days: dayIndex));
    // La plaza de la tarea puede trabajar festivos (con su propio horario);
    // el backend valida el horario exacto al guardar.
    if (widget.esFestivo(targetDay) && !dragged.tarea.tieneTrabajaFestivos) {
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(
          content: Text('No puedes mover correctivas a un día festivo.'),
        ),
      );
      return;
    }

    final minuteFromGrid = (localDy / pxPorMin).round();
    final minuteOfDay = (_horaInicio * 60) + minuteFromGrid;
    final startMinute = _resolverInicioLibreEnDia(
      duracionMinutos: dragged.duracionMinutos,
      excluirTareaId: dragged.tarea.id,
      dayIndex: dayIndex,
      desiredMinuteOfDay: minuteOfDay,
    );

    if (startMinute == null) {
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(
          content: Text(
            'Ese movimiento no es válido por horario, descanso o falta de hueco disponible.',
          ),
        ),
      );
      return;
    }

    final nuevoInicio = DateTime(
      targetDay.year,
      targetDay.month,
      targetDay.day,
      startMinute ~/ 60,
      startMinute % 60,
    );
    final nuevoFin = nuevoInicio.add(
      Duration(minutes: dragged.duracionMinutos),
    );

    setState(() => _moviendoCorrectiva = true);
    try {
      await widget.onMoveCorrectiva!(
        tarea: dragged.tarea,
        nuevoInicio: nuevoInicio,
        nuevoFin: nuevoFin,
      );
    } catch (e) {
      if (!mounted) return;
      if (hasMaquinariaConflictDetails(e)) {
        await showMaquinariaConflictDialog(
          context,
          e,
          fallbackTitle: 'Conflicto de maquinaria al mover la tarea',
        );
        return;
      }
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text(
            'No se pudo mover la correctiva: ${AppError.messageOf(e)}',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _moviendoCorrectiva = false);
      }
    }
  }

  Future<void> _intentarProgramarExcluidaEnHueco({
    required _DraggedWeekExcluida dragged,
    required int dayIndex,
    required double localDy,
  }) async {
    if (widget.onProgramExcluidaComoCorrectiva == null) return;

    final targetDay = widget.weekStart.add(Duration(days: dayIndex));
    if (widget.esFestivo(targetDay)) {
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(
          content: Text(
            'No puedes programar correctivas desde excluidas en un día festivo.',
          ),
        ),
      );
      return;
    }

    final minuteFromGrid = (localDy / pxPorMin).round();
    final minuteOfDay = (_horaInicio * 60) + minuteFromGrid;
    final startMinute = _resolverInicioLibreEnDia(
      duracionMinutos: dragged.excluida.duracionMinutos,
      dayIndex: dayIndex,
      desiredMinuteOfDay: minuteOfDay,
    );

    if (startMinute == null) {
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(
          content: Text(
            'No hay un hueco libre válido para programar esta excluida como correctiva.',
          ),
        ),
      );
      return;
    }

    final nuevoInicio = DateTime(
      targetDay.year,
      targetDay.month,
      targetDay.day,
      startMinute ~/ 60,
      startMinute % 60,
    );
    final nuevoFin = nuevoInicio.add(
      Duration(minutes: dragged.excluida.duracionMinutos),
    );

    await widget.onProgramExcluidaComoCorrectiva!(
      excluida: dragged.excluida,
      nuevoInicio: nuevoInicio,
      nuevoFin: nuevoFin,
    );
  }

  Future<void> _intentarProgramarExcluidaSobreTarea({
    required _DraggedWeekExcluida dragged,
    required TareaModel tareaObjetivo,
  }) async {
    if (widget.onProgramExcluidaComoCorrectiva == null) return;
    final tipo = (tareaObjetivo.tipo ?? '').trim().toUpperCase();
    if (tipo != 'PREVENTIVA') {
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(
          content: Text(
            'Solo puedes soltar una excluida sobre una preventiva publicada.',
          ),
        ),
      );
      return;
    }
    if (!_puedeReemplazarPreventiva(
      prioridadCorrectiva: dragged.excluida.prioridad,
      prioridadPreventiva: tareaObjetivo.prioridad,
    )) {
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text(
            'Una excluida P${dragged.excluida.prioridad} no puede reemplazar una preventiva P${tareaObjetivo.prioridad}.',
          ),
        ),
      );
      return;
    }

    final nuevoInicio = tareaObjetivo.fechaInicio.toLocal();
    final nuevoFin = nuevoInicio.add(
      Duration(minutes: dragged.excluida.duracionMinutos),
    );
    await widget.onProgramExcluidaComoCorrectiva!(
      excluida: dragged.excluida,
      nuevoInicio: nuevoInicio,
      nuevoFin: nuevoFin,
      tareaReemplazo: tareaObjetivo,
    );
  }

  List<Widget> _buildTapTargets(BuildContext context, double colWidth) {
    if (widget.pendienteEnUbicacion == null) return const [];

    final widgets = <Widget>[];
    for (int dayIndex = 0; dayIndex < _dias; dayIndex++) {
      final rangos = _rangosProgramablesDia(dayIndex);
      for (final rango in rangos) {
        final top = (rango.start - (_horaInicio * 60)) * pxPorMin;
        final height = (rango.end - rango.start) * pxPorMin;
        widgets.add(
          Positioned(
            left: anchoHora + dayIndex * colWidth,
            width: colWidth,
            top: top,
            height: height,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: (details) => _handleTapEnHueco(
                context: context,
                details: details,
                dayIndex: dayIndex,
                localTop: top + details.localPosition.dy,
              ),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  List<Widget> _buildExcluidaDropTargets(double colWidth) {
    if (widget.onProgramExcluidaComoCorrectiva == null) return const [];

    final widgets = <Widget>[];
    for (int dayIndex = 0; dayIndex < _dias; dayIndex++) {
      final rangos = _rangosProgramablesDia(dayIndex);
      for (final rango in rangos) {
        final top = (rango.start - (_horaInicio * 60)) * pxPorMin;
        final height = (rango.end - rango.start) * pxPorMin;
        widgets.add(
          Positioned(
            left: anchoHora + dayIndex * colWidth,
            width: colWidth,
            top: top,
            height: height,
            child: Builder(
              builder: (targetContext) {
                double localDyDe(Offset globalOffset) {
                  final box = targetContext.findRenderObject() as RenderBox?;
                  final local = box?.globalToLocal(globalOffset);
                  return (local?.dy ?? 0) + top;
                }

                return DragTarget<_DraggedWeekExcluida>(
                  onWillAcceptWithDetails: (_) => true,
                  onMove: (details) => _actualizarPreviewEnHueco(
                    duracionMinutos: details.data.excluida.duracionMinutos,
                    titulo: details.data.excluida.descripcion,
                    color: _kColorPreviewExcluida,
                    dayIndex: dayIndex,
                    localDy: localDyDe(details.offset),
                  ),
                  onLeave: (_) => _setEspecialPreview(null),
                  onAcceptWithDetails: (details) async {
                    _setEspecialPreview(null);
                    await _intentarProgramarExcluidaEnHueco(
                      dragged: details.data,
                      dayIndex: dayIndex,
                      localDy: localDyDe(details.offset),
                    );
                  },
                  builder: (context, candidateData, rejectedData) =>
                      const SizedBox.expand(),
                );
              },
            ),
          ),
        );
      }
    }
    return widgets;
  }

  Future<void> _intentarProgramarEspecialEnHueco({
    required _DraggedWeekEspecial dragged,
    required int dayIndex,
    required double localDy,
  }) async {
    if (widget.onProgramarActividadEspecial == null) return;

    final targetDay = widget.weekStart.add(Duration(days: dayIndex));
    if (widget.esFestivo(targetDay)) {
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text(
            'No puedes programar ${etiquetaCorrectiva(minuscula: true)}s en un día festivo.',
          ),
        ),
      );
      return;
    }

    final minuteFromGrid = (localDy / pxPorMin).round();
    final minuteOfDay = (_horaInicio * 60) + minuteFromGrid;
    final startMinute = _resolverInicioLibreEnDia(
      duracionMinutos: dragged.pendiente.duracionMinutos,
      dayIndex: dayIndex,
      desiredMinuteOfDay: minuteOfDay,
    );

    if (startMinute == null) {
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text(
            'No hay un hueco libre válido para programar esta ${etiquetaCorrectiva(minuscula: true)}.',
          ),
        ),
      );
      return;
    }

    final nuevoInicio = DateTime(
      targetDay.year,
      targetDay.month,
      targetDay.day,
      startMinute ~/ 60,
      startMinute % 60,
    );
    final nuevoFin = nuevoInicio.add(
      Duration(minutes: dragged.pendiente.duracionMinutos),
    );

    await widget.onProgramarActividadEspecial!(
      pendiente: dragged.pendiente,
      nuevoInicio: nuevoInicio,
      nuevoFin: nuevoFin,
    );
  }

  Future<void> _intentarProgramarEspecialSobreTarea({
    required _DraggedWeekEspecial dragged,
    required TareaModel tareaObjetivo,
  }) async {
    if (widget.onProgramarActividadEspecial == null) return;
    final tipo = (tareaObjetivo.tipo ?? '').trim().toUpperCase();
    if (tipo != 'PREVENTIVA') {
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text(
            'Solo puedes ubicar una ${etiquetaCorrectiva(minuscula: true)} sobre una preventiva publicada.',
          ),
        ),
      );
      return;
    }
    if (!_puedeReemplazarPreventiva(
      prioridadCorrectiva: dragged.pendiente.prioridad,
      prioridadPreventiva: tareaObjetivo.prioridad,
    )) {
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text(
            'Una ${etiquetaCorrectiva(minuscula: true)} P${dragged.pendiente.prioridad} no puede reemplazar una preventiva P${tareaObjetivo.prioridad}.',
          ),
        ),
      );
      return;
    }

    final nuevoInicio = tareaObjetivo.fechaInicio.toLocal();
    final nuevoFin = nuevoInicio.add(
      Duration(minutes: dragged.pendiente.duracionMinutos),
    );
    await widget.onProgramarActividadEspecial!(
      pendiente: dragged.pendiente,
      nuevoInicio: nuevoInicio,
      nuevoFin: nuevoFin,
      tareaReemplazo: tareaObjetivo,
    );
  }

  /// Ids de las tareas que ocupan el rango [inicio, inicio + duracion) del día.
  List<int> _tareasQueChocan({
    required int dayIndex,
    required int inicio,
    required int duracionMinutos,
    int? excluirTareaId,
  }) {
    final fin = inicio + duracionMinutos;
    return [
      for (final r in _occupiedRangesByDay[dayIndex] ?? const <_MinuteRange>[])
        if (r.tareaId != null &&
            r.tareaId != excluirTareaId &&
            inicio < r.end &&
            fin > r.start)
          r.tareaId!,
    ];
  }

  /// Calcula dónde caería lo que se arrastra en un hueco libre del día
  /// (misma resolución que usa al soltar) para pintar el cuadrito previo, y
  /// qué tareas hay justo donde el usuario lo está soltando.
  void _actualizarPreviewEnHueco({
    required int duracionMinutos,
    required String titulo,
    required Color color,
    required int dayIndex,
    required double localDy,
    int? excluirTareaId,
    bool permiteFestivo = false,
  }) {
    final targetDay = widget.weekStart.add(Duration(days: dayIndex));
    final desired = (_horaInicio * 60) + (localDy / pxPorMin).round();
    final resolved = widget.esFestivo(targetDay) && !permiteFestivo
        ? null
        : _resolverInicioLibreEnDia(
            duracionMinutos: duracionMinutos,
            excluirTareaId: excluirTareaId,
            dayIndex: dayIndex,
            desiredMinuteOfDay: desired,
          );
    final deseado = _snapToGridNearest(
      desired,
    ).clamp(_horaInicio * 60, (_horaFin * 60) - 1).toInt();
    final choques = _tareasQueChocan(
      dayIndex: dayIndex,
      inicio: deseado,
      duracionMinutos: duracionMinutos,
      excluirTareaId: excluirTareaId,
    );
    _setEspecialPreview(
      _EspecialDropPreview(
        dayIndex: dayIndex,
        startMinute: resolved ?? deseado,
        duracionMinutos: duracionMinutos,
        valido: resolved != null,
        titulo: titulo,
        color: color,
        deseadoMinute: deseado,
        choquesIds: choques,
      ),
    );
  }

  /// Preview al pasar sobre una preventiva que se puede reemplazar: se dibuja
  /// solo sobre el carril de esa preventiva.
  void _actualizarPreviewReemplazo({
    required TareaModel objetivo,
    required int dayIndex,
    required int duracionMinutos,
    required String titulo,
    required Color color,
  }) {
    final inicioLocal = objetivo.fechaInicio.toLocal();
    var lane = 0;
    var laneCount = 1;
    var laneSpan = 1;
    for (final pl in _taskPlacementsCache) {
      if (pl.tarea.id == objetivo.id) {
        lane = pl.lane;
        laneCount = pl.laneCount;
        laneSpan = pl.laneSpan;
        break;
      }
    }
    _setEspecialPreview(
      _EspecialDropPreview(
        dayIndex: dayIndex,
        startMinute: inicioLocal.hour * 60 + inicioLocal.minute,
        duracionMinutos: duracionMinutos,
        valido: true,
        reemplaza: true,
        titulo: titulo,
        reemplazaTitulo: objetivo.descripcion,
        color: color,
        choquesIds: [objetivo.id],
        lane: lane,
        laneCount: laneCount,
        laneSpan: laneSpan,
      ),
    );
  }

  List<Widget> _buildEspecialDropTargets(double colWidth) {
    if (widget.onProgramarActividadEspecial == null) return const [];

    final widgets = <Widget>[];
    for (int dayIndex = 0; dayIndex < _dias; dayIndex++) {
      final rangos = _rangosProgramablesDia(dayIndex);
      for (final rango in rangos) {
        final top = (rango.start - (_horaInicio * 60)) * pxPorMin;
        final height = (rango.end - rango.start) * pxPorMin;
        widgets.add(
          Positioned(
            left: anchoHora + dayIndex * colWidth,
            width: colWidth,
            top: top,
            height: height,
            child: Builder(
              builder: (targetContext) {
                double localDyDe(Offset globalOffset) {
                  final box = targetContext.findRenderObject() as RenderBox?;
                  final local = box?.globalToLocal(globalOffset);
                  return (local?.dy ?? 0) + top;
                }

                return DragTarget<_DraggedWeekEspecial>(
                  onWillAcceptWithDetails: (_) => true,
                  onMove: (details) => _actualizarPreviewEnHueco(
                    duracionMinutos: details.data.pendiente.duracionMinutos,
                    titulo: details.data.pendiente.descripcion,
                    color: _kColorPreviewEspecial,
                    dayIndex: dayIndex,
                    localDy: localDyDe(details.offset),
                  ),
                  onLeave: (_) => _setEspecialPreview(null),
                  onAcceptWithDetails: (details) async {
                    _setEspecialPreview(null);
                    await _intentarProgramarEspecialEnHueco(
                      dragged: details.data,
                      dayIndex: dayIndex,
                      localDy: localDyDe(details.offset),
                    );
                  },
                  builder: (context, candidateData, rejectedData) =>
                      const SizedBox.expand(),
                );
              },
            ),
          ),
        );
      }
    }
    return widgets;
  }

  /// Rectángulo (left, top, ancho, alto) de una tarea ya ubicada en su carril.
  Rect _rectDeColocacion(_WeekTaskPlacement pl, double colWidth) {
    const dayPadding = 6.0;
    const laneGap = 3.0;
    final w =
        ((colWidth - dayPadding * 2) - laneGap * (pl.laneCount - 1)) /
        pl.laneCount;
    final left =
        anchoHora +
        pl.dayIndex * colWidth +
        dayPadding +
        pl.lane * (w + laneGap);
    final top = _minutesFromStart(pl.inicio) * pxPorMin;
    final dur = pl.fin.difference(pl.inicio).inMinutes;
    final h = ((dur <= 0 ? 1 : dur) * pxPorMin).clamp(18.0, 9999.0);
    final span = pl.laneSpan;
    return Rect.fromLTWH(left, top, w * span + laneGap * (span - 1), h);
  }

  /// Capa de previsualización del arrastre. Muestra:
  ///  - el cuadro "fantasma" donde quedaría (morado/naranja/azul según qué se
  ///    arrastra; rojo si no cabe),
  ///  - las tareas que quedan afectadas (se resaltan en rojo/ámbar encima de
  ///    su tarjeta, con una etiqueta de qué pasaría),
  ///  - si el punto donde se suelta está ocupado, un recuadro rojo punteado
  ///    en ese punto y el fantasma en el hueco libre al que se ajustará.
  Widget _buildEspecialPreviewLayer({
    required double colWidth,
    required double heightGrid,
  }) {
    return ValueListenableBuilder<_EspecialDropPreview?>(
      valueListenable: _weekEspecialPreviewNotifier,
      builder: (context, preview, _) {
        if (preview == null) return const SizedBox.shrink();

        final previewColor = preview.valido
            ? preview.color
            : Colors.red.shade700;
        final altoPreview = (preview.duracionMinutos * pxPorMin)
            .clamp(24.0, heightGrid)
            .toDouble();
        double topDe(int minuto) => ((minuto - (_horaInicio * 60)) * pxPorMin)
            .clamp(0.0, (heightGrid - altoPreview).clamp(0.0, heightGrid))
            .toDouble();

        final endMinute = preview.startMinute + preview.duracionMinutos;
        final horas =
            '${_formatMinuteOfDay(preview.startMinute)} - ${_formatMinuteOfDay(endMinute)}';
        final titulo = preview.titulo.trim();
        final ajustado =
            !preview.reemplaza &&
            preview.valido &&
            preview.deseadoMinute != null &&
            preview.deseadoMinute != preview.startMinute;

        // Geometría del fantasma: solo el carril de la preventiva cuando
        // reemplaza; en un hueco libre, todo el ancho del día.
        double ghostLeft;
        double ghostWidth;
        if (preview.reemplaza && preview.laneCount > 1) {
          const dayPadding = 6.0;
          const laneGap = 3.0;
          final w =
              ((colWidth - dayPadding * 2) -
                  laneGap * (preview.laneCount - 1)) /
              preview.laneCount;
          ghostLeft =
              anchoHora +
              preview.dayIndex * colWidth +
              dayPadding +
              preview.lane * (w + laneGap);
          ghostWidth = w * preview.laneSpan + laneGap * (preview.laneSpan - 1);
        } else {
          ghostLeft = anchoHora + preview.dayIndex * colWidth + 4;
          ghostWidth = colWidth - 8;
        }

        final lineaTitulo = !preview.valido
            ? 'No cabe aquí'
            : (titulo.isEmpty ? horas : titulo);
        final lineaDetalle = !preview.valido
            ? (titulo.isEmpty
                  ? 'Suéltala en otra franja libre'
                  : '$titulo · $horas')
            : (preview.reemplaza
                  ? '$horas · reemplaza "${preview.reemplazaTitulo ?? ''}"'
                  : (ajustado
                        ? '$horas · se ajusta al hueco libre'
                        : (titulo.isEmpty ? null : horas)));

        final children = <Widget>[];

        // Tareas afectadas: resaltadas encima de su tarjeta.
        final afectadas = preview.choquesIds.toSet();
        if (afectadas.isNotEmpty) {
          final colorAfectada = preview.reemplaza
              ? const Color(0xFFD97706)
              : Colors.red.shade700;
          for (final pl in _taskPlacementsCache) {
            if (!afectadas.contains(pl.tarea.id)) continue;
            if (pl.dayIndex != preview.dayIndex) continue;
            final r = _rectDeColocacion(pl, colWidth);
            children.add(
              Positioned(
                left: r.left - 1,
                top: r.top - 1,
                width: r.width + 2,
                height: r.height + 2,
                child: Container(
                  alignment: Alignment.topRight,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: colorAfectada.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colorAfectada, width: 2),
                  ),
                  child: r.height >= 26 && r.width >= 40
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: colorAfectada,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            preview.reemplaza ? 'Se reemplaza' : 'Ocupado',
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        )
                      : null,
                ),
              ),
            );
          }
        }

        // Punto donde se soltó, cuando está ocupado y se reubica.
        if (ajustado) {
          final deseado = preview.deseadoMinute ?? preview.startMinute;
          {
            children.add(
              Positioned(
                left: anchoHora + preview.dayIndex * colWidth + 4,
                top: topDe(deseado),
                width: colWidth - 8,
                height: altoPreview,
                child: Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.red.shade400.withValues(alpha: 0.8),
                      width: 1.5,
                    ),
                  ),
                  child: altoPreview >= 28
                      ? Text(
                          'Aquí hay otra tarea (${_formatMinuteOfDay(deseado)})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : null,
                ),
              ),
            );
          }
        }

        // Fantasma.
        children.add(
          Positioned(
            left: ghostLeft,
            top: topDe(preview.startMinute),
            width: ghostWidth,
            height: altoPreview,
            child: Container(
              clipBehavior: Clip.hardEdge,
              padding: EdgeInsets.symmetric(
                horizontal: 8,
                vertical: altoPreview < 34 ? 2 : 5,
              ),
              decoration: BoxDecoration(
                color: previewColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: previewColor, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: previewColor.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            preview.valido
                                ? (preview.reemplaza
                                      ? Icons.swap_horiz_rounded
                                      : Icons.place_outlined)
                                : Icons.block_rounded,
                            size: 13,
                            color: previewColor,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              lineaTitulo,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: previewColor,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (altoPreview >= 40 && lineaDetalle != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 17, top: 1),
                          child: Text(
                            lineaDetalle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: previewColor.withValues(alpha: 0.9),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        return Positioned.fill(
          child: IgnorePointer(child: Stack(children: children)),
        );
      },
    );
  }

  String _formatMinuteOfDay(int minute) {
    final h = (minute ~/ 60).toString().padLeft(2, '0');
    final m = (minute % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  bool _puedeReemplazarPreventiva({
    required int prioridadCorrectiva,
    required int prioridadPreventiva,
  }) {
    if (prioridadCorrectiva <= 1) return true;
    if (prioridadCorrectiva == 2) return prioridadPreventiva >= 2;
    return prioridadPreventiva >= 3;
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
    final end = start.add(Duration(days: _dias));
    final dd = DateTime(d.year, d.month, d.day);
    return !dd.isBefore(start) && dd.isBefore(end);
  }

  DateTime _ensureEndAfterStart(DateTime start, DateTime end) {
    if (end.isAfter(start)) return end;
    return start.add(const Duration(minutes: 1));
  }

  List<_WeekTaskPlacement> _buildTaskPlacements() {
    final spansByDay = List.generate(_dias, (_) => <_WeekTaskSpan>[]);

    for (final t in widget.tareas) {
      final inicioOriginal = t.fechaInicio.toLocal();
      if (!_isWithinWeek(inicioOriginal)) continue;

      final day = _dayIndex(inicioOriginal);
      if (day < 0 || day >= _dias) continue;

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
    final minVisual = Duration(minutes: (18 / pxPorMin).ceil());

    for (int day = 0; day < _dias; day++) {
      final daySpans = spansByDay[day];
      if (daySpans.isEmpty) continue;

      // Solo se reparten el ancho las tareas que se solapan de verdad; ver
      // utils/week_layout.dart.
      final layout = layoutWeekDayTasks([
        for (final span in daySpans)
          WeekLayoutInput(
            inicio: span.inicio,
            fin: _ensureEndAfterStart(span.inicio, span.fin),
          ),
      ], minVisual: minVisual);

      for (var i = 0; i < daySpans.length; i++) {
        out.add(
          _WeekTaskPlacement(
            tarea: daySpans[i].tarea,
            dayIndex: day,
            inicio: daySpans[i].inicio,
            fin: daySpans[i].fin,
            lane: layout[i].lane,
            laneCount: layout[i].laneCount,
            laneSpan: layout[i].laneSpan,
            visualFin: layout[i].visualFin,
          ),
        );
      }
    }

    return out;
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
    _rebuildDerivedWeekDataIfNeeded();
    final taskPlacements = _taskPlacementsCache;

    final bg = Colors.white;
    final line = Colors.grey.shade300;
    final text = Colors.grey.shade900;
    final subtext = Colors.grey.shade700;

    return LayoutBuilder(
      builder: (context, c) {
        final minDayCol = c.maxWidth < 700 ? 96.0 : 120.0;
        final available = c.maxWidth - anchoHora;
        // Si un día tiene muchas tareas a la vez, se ensancha la columna
        // (la grilla ya se desplaza en horizontal) para que cada carril
        // conserve un ancho en el que se alcance a leer el nombre.
        final maxCarriles = taskPlacements.fold<int>(
          1,
          (m, pl) => pl.laneCount > m ? pl.laneCount : m,
        );
        final anchoBase = (available / _dias).clamp(minDayCol, 9999.0);
        final anchoNecesario = (maxCarriles * 64.0 + 12).clamp(0.0, 560.0);
        final colWidth = anchoBase > anchoNecesario
            ? anchoBase
            : anchoNecesario;
        final totalWidth = anchoHora + colWidth * _dias;

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
                        ...List.generate(_dias, (i) {
                          final d = widget.weekStart.add(Duration(days: i));
                          final label = [
                            "Lun",
                            "Mar",
                            "Mié",
                            "Jue",
                            "Vie",
                            "Sáb",
                            "Dom",
                          ][(d.weekday - 1)];
                          final fest = widget.esFestivo(d);
                          final festivoNombre = widget.nombreFestivo(d);
                          final celda = SizedBox(
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
                          if (widget.onFocoDia == null || _dias <= 1) {
                            return celda;
                          }
                          return MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => widget.onFocoDia!(d),
                              child: celda,
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
                                    ...List.generate(_dias, (_) {
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

                              if (widget.scaleMinutes < 60)
                                ...List.generate(
                                  hours * (60 ~/ widget.scaleMinutes),
                                  (i) {
                                    final minutes =
                                        (i + 1) * widget.scaleMinutes;
                                    if (minutes % 60 == 0) {
                                      return const SizedBox.shrink();
                                    }
                                    final top = minutes * pxPorMin;
                                    return Positioned(
                                      left: anchoHora,
                                      right: 0,
                                      top: top,
                                      child: Container(
                                        height: 1,
                                        color: line.withValues(alpha: 0.45),
                                      ),
                                    );
                                  },
                                ),
                              ...List.generate(_dias, (dayIndex) {
                                final descanso = _descansoDia(dayIndex);
                                if (descanso == null) {
                                  return const SizedBox.shrink();
                                }
                                final top =
                                    (descanso.start - (_horaInicio * 60)) *
                                    pxPorMin;
                                final height =
                                    (descanso.end - descanso.start) * pxPorMin;
                                return Positioned(
                                  left: anchoHora + dayIndex * colWidth,
                                  width: colWidth,
                                  top: top,
                                  height: height,
                                  child: Container(
                                    color: Colors.orange.withValues(
                                      alpha: 0.12,
                                    ),
                                  ),
                                );
                              }),
                              ValueListenableBuilder<bool>(
                                valueListenable:
                                    _weekCorrectivaDragActiveNotifier,
                                builder: (context, dragActivo, _) {
                                  return ValueListenableBuilder<bool>(
                                    valueListenable:
                                        _weekExcluidaDragActiveNotifier,
                                    builder: (context, dragExcluidaActiva, _) {
                                      return ValueListenableBuilder<bool>(
                                        valueListenable:
                                            _weekEspecialDragActiveNotifier,
                                        builder:
                                            (context, dragEspecialActiva, _) {
                                              if (dragActivo ||
                                                  dragExcluidaActiva ||
                                                  dragEspecialActiva) {
                                                return const SizedBox.shrink();
                                              }
                                              return Stack(
                                                children: _buildTapTargets(
                                                  context,
                                                  colWidth,
                                                ),
                                              );
                                            },
                                      );
                                    },
                                  );
                                },
                              ),
                              ValueListenableBuilder<bool>(
                                valueListenable:
                                    _weekExcluidaDragActiveNotifier,
                                builder: (context, dragActivo, _) {
                                  if (!dragActivo) {
                                    return const SizedBox.shrink();
                                  }
                                  return Stack(
                                    children: _buildExcluidaDropTargets(
                                      colWidth,
                                    ),
                                  );
                                },
                              ),
                              ValueListenableBuilder<bool>(
                                valueListenable:
                                    _weekEspecialDragActiveNotifier,
                                builder: (context, dragActivo, _) {
                                  if (!dragActivo) {
                                    return const SizedBox.shrink();
                                  }
                                  return Stack(
                                    children: _buildEspecialDropTargets(
                                      colWidth,
                                    ),
                                  );
                                },
                              ),
                              ...taskPlacements.map((placement) {
                                final t = placement.tarea;
                                final ini = placement.inicio;
                                final fin = placement.fin;

                                final startMin = _minutesFromStart(ini);
                                final durMin = fin.difference(ini).inMinutes;

                                const dayPadding = 6.0;
                                const laneGap = 3.0;
                                final laneCount = placement.laneCount;
                                // Ancho de la tarjeta: el ancho útil del día
                                // repartido entre los carriles simultáneos.
                                final laneW =
                                    ((colWidth - (dayPadding * 2)) -
                                        laneGap * (laneCount - 1)) /
                                    laneCount;
                                final fullWidth =
                                    laneW * placement.laneSpan +
                                    laneGap * (placement.laneSpan - 1);
                                final left =
                                    anchoHora +
                                    placement.dayIndex * colWidth +
                                    dayPadding +
                                    placement.lane * (laneW + laneGap);
                                final top = startMin * pxPorMin;
                                final colorBase =
                                    _cronogramaColorBaseTareaSemana(t);
                                final fill = colorBase.withValues(alpha: 0.12);
                                final border = colorBase.withValues(
                                  alpha: 0.55,
                                );
                                // Distintivo visual (necesidades operativas):
                                // solo se marca si esta tarea en concreto cae
                                // fuera del horario GENERAL del conjunto -no
                                // basta con que la plaza tenga horario
                                // especial configurado; si coincide con el
                                // horario general (p.ej. un todero-salvavidas
                                // trabajando en su franja de lunes que ya
                                // cubre el horario del conjunto) no se marca.
                                final horarioEspecial =
                                    t.tieneHorarioEspecial &&
                                    tareaFueraDeHorarioGeneral(
                                      horariosConjunto: widget.horariosConjunto,
                                      inicio: ini,
                                      fin: fin,
                                    );

                                final horaIni = DateFormat('HH:mm').format(ini);
                                final horaFinStr = DateFormat(
                                  'HH:mm',
                                ).format(fin);
                                final esCorrectiva =
                                    (t.tipo ?? '').trim().toUpperCase() ==
                                    'CORRECTIVA';

                                final alturaReal =
                                    (durMin <= 0 ? 1 : durMin) * pxPorMin;
                                final alturaVisual =
                                    (placement.visualFin ?? placement.fin)
                                        .difference(placement.inicio)
                                        .inSeconds /
                                    60 *
                                    pxPorMin;
                                final height = math
                                    .max(
                                      alturaReal,
                                      math.min(18.0, alturaVisual),
                                    )
                                    .clamp(1.0, 9999.0);

                                final padV = height < 30
                                    ? 1.0
                                    : (height < 42 ? 3.0 : 8.0);

                                final card = GestureDetector(
                                  onTap: () {
                                    final pendiente =
                                        widget.pendienteEnUbicacion;
                                    if (pendiente != null) {
                                      _intentarProgramarEspecialSobreTarea(
                                        dragged: _DraggedWeekEspecial(
                                          pendiente: pendiente,
                                        ),
                                        tareaObjetivo: t,
                                      );
                                      return;
                                    }
                                    widget.onTapTarea(t);
                                  },
                                  child: Container(
                                    clipBehavior: Clip.hardEdge,
                                    padding: EdgeInsets.fromLTRB(
                                      fullWidth < 84 ? 7 : 10,
                                      padV,
                                      fullWidth < 84 ? 3 : 5,
                                      padV,
                                    ),
                                    decoration: BoxDecoration(
                                      color: fill,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: horarioEspecial
                                            ? Colors.orange.shade700
                                            : border,
                                        width: horarioEspecial ? 2 : 1,
                                      ),
                                    ),
                                    child: LayoutBuilder(
                                      builder: (context, box) {
                                        final h = box.maxHeight;
                                        final w = box.maxWidth;
                                        final tiny = h < 26;
                                        final compact = h < 54;
                                        // Carriles estrechos (varias tareas a
                                        // la vez): menos texto, más líneas de
                                        // título.
                                        final narrow = w < 84;

                                        final equipo =
                                            t.operariosIds.toSet().length > 1;
                                        final titulo =
                                            _esBloqueDespuesDeAlmuerzo(t)
                                            ? 'Después del almuerzo · ${t.descripcion}'
                                            : t.descripcion;
                                        final fontTitulo = tiny
                                            ? 8.0
                                            : (compact || narrow ? 10.0 : 12.0);
                                        final mostrarHora = !compact;
                                        final operarios = t.operariosNombres
                                            .map((n) => n.trim())
                                            .where((n) => n.isNotEmpty)
                                            .toSet()
                                            .join(', ');
                                        final mostrarOperarios =
                                            h >= 72 &&
                                            !narrow &&
                                            operarios.isNotEmpty;
                                        // Alturas deterministas (height
                                        // fijo en los TextStyle) para calcular
                                        // cuántas líneas caben sin desbordar.
                                        final reservado =
                                            (mostrarHora ? 14.0 : 0.0) +
                                            (mostrarOperarios ? 12.0 : 0.0);
                                        final maxLineasTitulo =
                                            ((h - reservado) /
                                                    (fontTitulo * 1.2))
                                                .floor()
                                                .clamp(1, 8);
                                        final lineasTitulo = narrow
                                            ? maxLineasTitulo
                                            : (compact ? 1 : 2).clamp(
                                                1,
                                                maxLineasTitulo,
                                              );
                                        final tooltipTarea = [
                                          t.descripcion,
                                          '$horaIni - $horaFinStr',
                                          if (operarios.isNotEmpty) operarios,
                                        ].join('\n');
                                        return Stack(
                                          fit: StackFit.expand,
                                          clipBehavior: Clip.none,
                                          children: [
                                            // Franja de color a la izquierda
                                            // (estilo Teams/Outlook).
                                            Positioned(
                                              left: fullWidth < 84 ? -7 : -10,
                                              top: -padV,
                                              bottom: -padV,
                                              width: fullWidth < 84 ? 3 : 4,
                                              child: ColoredBox(
                                                color: colorBase,
                                              ),
                                            ),
                                            Padding(
                                              padding: EdgeInsets.only(
                                                right: equipo && w >= 110
                                                    ? 18
                                                    : 0,
                                              ),
                                              child: Tooltip(
                                                message: tooltipTarea,
                                                waitDuration: const Duration(
                                                  milliseconds: 250,
                                                ),
                                                // ClipRect + OverflowBox: si
                                                // aun así el texto no cabe
                                                // (fuentes distintas, zoom),
                                                // se recorta en vez de
                                                // lanzar overflow.
                                                child: ClipRect(
                                                  child: OverflowBox(
                                                    alignment:
                                                        Alignment.topLeft,
                                                    minHeight: 0,
                                                    maxHeight: double.infinity,
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          titulo,
                                                          maxLines:
                                                              lineasTitulo,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            color: text,
                                                            fontSize:
                                                                fontTitulo,
                                                            height: 1.2,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                        ),
                                                        if (mostrarHora) ...[
                                                          const SizedBox(
                                                            height: 2,
                                                          ),
                                                          Text(
                                                            narrow
                                                                ? horaIni
                                                                : '$horaIni - $horaFinStr',
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: TextStyle(
                                                              color: subtext,
                                                              fontSize: 10,
                                                              height: 1.2,
                                                            ),
                                                          ),
                                                        ],
                                                        if (mostrarOperarios)
                                                          Text(
                                                            operarios,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: TextStyle(
                                                              color: subtext,
                                                              fontSize: 9.5,
                                                              height: 1.2,
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            if (equipo)
                                              Positioned(
                                                right: 0,
                                                bottom: 0,
                                                child: Tooltip(
                                                  message:
                                                      'Tarea compartida por ${t.operariosIds.toSet().length} operarios',
                                                  child: Icon(
                                                    Icons.groups_2_outlined,
                                                    size: (tiny || narrow)
                                                        ? 11
                                                        : 15,
                                                    color: subtext,
                                                  ),
                                                ),
                                              ),
                                            if (horarioEspecial)
                                              Positioned(
                                                right: 0,
                                                top: 0,
                                                child: Tooltip(
                                                  message:
                                                      t
                                                          .necesidadesEtiquetas
                                                          .isEmpty
                                                      ? 'Fuera del horario general del conjunto (horario especial de la plaza)'
                                                      : 'Fuera del horario general del conjunto: horario especial de ${t.necesidadesEtiquetas.join(', ')}',
                                                  child: Icon(
                                                    Icons.schedule,
                                                    size: (tiny || narrow)
                                                        ? 11
                                                        : 15,
                                                    color:
                                                        Colors.orange.shade700,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                );

                                final draggableCard =
                                    esCorrectiva &&
                                        widget.onMoveCorrectiva != null
                                    ? LongPressDraggable<_DraggedWeekTask>(
                                        data: _DraggedWeekTask(
                                          tarea: t,
                                          duracionMinutos: durMin <= 0
                                              ? 1
                                              : durMin,
                                        ),
                                        maxSimultaneousDrags:
                                            _moviendoCorrectiva ? 0 : 1,
                                        onDragStarted: () {
                                          _weekCorrectivaDragActiveNotifier
                                                  .value =
                                              true;
                                        },
                                        onDragEnd: (_) {
                                          _weekCorrectivaDragActiveNotifier
                                                  .value =
                                              false;
                                          _setEspecialPreview(null);
                                        },
                                        onDraggableCanceled: (_, __) {
                                          _weekCorrectivaDragActiveNotifier
                                                  .value =
                                              false;
                                          _setEspecialPreview(null);
                                        },
                                        feedback: Material(
                                          color: Colors.transparent,
                                          child: SizedBox(
                                            width: fullWidth,
                                            child: card,
                                          ),
                                        ),
                                        childWhenDragging: Opacity(
                                          opacity: 0.35,
                                          child: card,
                                        ),
                                        child: card,
                                      )
                                    : card;

                                final excluidaDropTarget =
                                    DragTarget<_DraggedWeekExcluida>(
                                      onWillAcceptWithDetails: (details) {
                                        return widget
                                                    .onProgramExcluidaComoCorrectiva !=
                                                null &&
                                            (t.tipo ?? '')
                                                    .trim()
                                                    .toUpperCase() ==
                                                'PREVENTIVA' &&
                                            _puedeReemplazarPreventiva(
                                              prioridadCorrectiva: details
                                                  .data
                                                  .excluida
                                                  .prioridad,
                                              prioridadPreventiva: t.prioridad,
                                            );
                                      },
                                      onMove: (details) =>
                                          _actualizarPreviewReemplazo(
                                            objetivo: t,
                                            dayIndex: placement.dayIndex,
                                            duracionMinutos: details
                                                .data
                                                .excluida
                                                .duracionMinutos,
                                            titulo: details
                                                .data
                                                .excluida
                                                .descripcion,
                                            color: _kColorPreviewExcluida,
                                          ),
                                      onLeave: (_) => _setEspecialPreview(null),
                                      onAcceptWithDetails: (details) async {
                                        _setEspecialPreview(null);
                                        await _intentarProgramarExcluidaSobreTarea(
                                          dragged: details.data,
                                          tareaObjetivo: t,
                                        );
                                      },
                                      builder:
                                          (
                                            context,
                                            candidateData,
                                            rejectedData,
                                          ) {
                                            var dropState =
                                                _ExcluidaDropState.none;
                                            if (candidateData.isNotEmpty) {
                                              final dragged =
                                                  candidateData.first;
                                              if (dragged == null) {
                                                dropState =
                                                    _ExcluidaDropState.blocked;
                                              } else {
                                                final allow =
                                                    _puedeReemplazarPreventiva(
                                                      prioridadCorrectiva:
                                                          dragged
                                                              .excluida
                                                              .prioridad,
                                                      prioridadPreventiva:
                                                          t.prioridad,
                                                    );
                                                dropState = allow
                                                    ? _ExcluidaDropState.allowed
                                                    : _ExcluidaDropState
                                                          .blocked;
                                              }
                                            } else if (rejectedData
                                                .isNotEmpty) {
                                              dropState =
                                                  _ExcluidaDropState.blocked;
                                            }
                                            if (dropState ==
                                                _ExcluidaDropState.none) {
                                              return draggableCard;
                                            }
                                            final borderColor =
                                                dropState ==
                                                    _ExcluidaDropState.allowed
                                                ? Colors.green.shade700
                                                : Colors.red.shade700;
                                            final overlayColor =
                                                dropState ==
                                                    _ExcluidaDropState.allowed
                                                ? Colors.green.withValues(
                                                    alpha: 0.14,
                                                  )
                                                : Colors.red.withValues(
                                                    alpha: 0.14,
                                                  );
                                            return Container(
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: borderColor,
                                                  width: 2,
                                                ),
                                                color: overlayColor,
                                              ),
                                              child: draggableCard,
                                            );
                                          },
                                    );

                                // AnimatedPositioned con clave por tarea: al reordenar, excluir o
                                // cambiar de carril, la tarjeta se desliza y se
                                // redimensiona en vez de saltar.
                                return AnimatedPositioned(
                                  key: ValueKey('tarea-${t.id}'),
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                  left: left,
                                  top: top,
                                  width: fullWidth,
                                  height: height,
                                  child: DragTarget<_DraggedWeekEspecial>(
                                    onWillAcceptWithDetails: (details) {
                                      return widget
                                                  .onProgramarActividadEspecial !=
                                              null &&
                                          (t.tipo ?? '').trim().toUpperCase() ==
                                              'PREVENTIVA' &&
                                          _puedeReemplazarPreventiva(
                                            prioridadCorrectiva: details
                                                .data
                                                .pendiente
                                                .prioridad,
                                            prioridadPreventiva: t.prioridad,
                                          );
                                    },
                                    onMove: (details) =>
                                        _actualizarPreviewReemplazo(
                                          objetivo: t,
                                          dayIndex: placement.dayIndex,
                                          duracionMinutos: details
                                              .data
                                              .pendiente
                                              .duracionMinutos,
                                          titulo: details
                                              .data
                                              .pendiente
                                              .descripcion,
                                          color: _kColorPreviewEspecial,
                                        ),
                                    onLeave: (_) => _setEspecialPreview(null),
                                    onAcceptWithDetails: (details) async {
                                      _setEspecialPreview(null);
                                      await _intentarProgramarEspecialSobreTarea(
                                        dragged: details.data,
                                        tareaObjetivo: t,
                                      );
                                    },
                                    builder: (context, candidateData, rejectedData) {
                                      final dragged = candidateData.isNotEmpty
                                          ? candidateData.first
                                          : rejectedData.isNotEmpty
                                          ? rejectedData.first
                                          : null;
                                      var dropState = _EspecialDropState.none;
                                      if (candidateData.isNotEmpty) {
                                        if (dragged == null) {
                                          dropState =
                                              _EspecialDropState.blocked;
                                        } else {
                                          final allow =
                                              _puedeReemplazarPreventiva(
                                                prioridadCorrectiva:
                                                    dragged.pendiente.prioridad,
                                                prioridadPreventiva:
                                                    t.prioridad,
                                              );
                                          dropState = allow
                                              ? _EspecialDropState.allowed
                                              : _EspecialDropState.blocked;
                                        }
                                      } else if (rejectedData.isNotEmpty) {
                                        dropState = _EspecialDropState.blocked;
                                      }
                                      if (dropState ==
                                          _EspecialDropState.none) {
                                        return excluidaDropTarget;
                                      }
                                      final borderColor =
                                          dropState ==
                                              _EspecialDropState.allowed
                                          ? const Color(0xFF6D28D9)
                                          : Colors.red.shade700;
                                      final overlayColor =
                                          dropState ==
                                              _EspecialDropState.allowed
                                          ? const Color(
                                              0xFF7C3AED,
                                            ).withValues(alpha: 0.16)
                                          : Colors.red.withValues(alpha: 0.14);
                                      return Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: borderColor,
                                            width: 2,
                                          ),
                                          color: overlayColor,
                                        ),
                                        padding: const EdgeInsets.all(4),
                                        child: Tooltip(
                                          message: dragged == null
                                              ? 'No se puede reemplazar esta tarea.'
                                              : dropState ==
                                                    _EspecialDropState.allowed
                                              ? 'La preventiva "${t.descripcion}" será reemplazada por "${dragged.pendiente.descripcion}".'
                                              : 'La preventiva "${t.descripcion}" no puede ser reemplazada por "${dragged.pendiente.descripcion}".',
                                          child: Center(
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Text(
                                                dragged == null
                                                    ? 'No se puede reemplazar'
                                                    : '${t.descripcion} → ${dragged.pendiente.descripcion}',
                                                maxLines: 1,
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                );
                              }),
                              _buildEspecialPreviewLayer(
                                colWidth: colWidth,
                                heightGrid: heightGrid,
                              ),
                              ValueListenableBuilder<bool>(
                                valueListenable:
                                    _weekCorrectivaDragActiveNotifier,
                                builder: (context, dragActivo, _) {
                                  if (!dragActivo ||
                                      widget.onMoveCorrectiva == null) {
                                    return const SizedBox.shrink();
                                  }
                                  return Stack(
                                    children: List.generate(_dias, (dayIndex) {
                                      return Positioned(
                                        left: anchoHora + dayIndex * colWidth,
                                        top: 0,
                                        width: colWidth,
                                        height: heightGrid,
                                        child: Builder(
                                          builder: (targetContext) {
                                            return DragTarget<_DraggedWeekTask>(
                                              onWillAcceptWithDetails:
                                                  (details) {
                                                    return !_moviendoCorrectiva;
                                                  },
                                              onMove: (details) {
                                                final box =
                                                    targetContext
                                                            .findRenderObject()
                                                        as RenderBox?;
                                                final local = box
                                                    ?.globalToLocal(
                                                      details.offset,
                                                    );
                                                _actualizarPreviewEnHueco(
                                                  duracionMinutos: details
                                                      .data
                                                      .duracionMinutos,
                                                  titulo: details
                                                      .data
                                                      .tarea
                                                      .descripcion,
                                                  color: _kColorPreviewMover,
                                                  dayIndex: dayIndex,
                                                  localDy: local?.dy ?? 0,
                                                  excluirTareaId:
                                                      details.data.tarea.id,
                                                  permiteFestivo: details
                                                      .data
                                                      .tarea
                                                      .tieneTrabajaFestivos,
                                                );
                                              },
                                              onLeave: (_) =>
                                                  _setEspecialPreview(null),
                                              onAcceptWithDetails: (details) async {
                                                _setEspecialPreview(null);
                                                final box =
                                                    targetContext
                                                            .findRenderObject()
                                                        as RenderBox?;
                                                final local = box
                                                    ?.globalToLocal(
                                                      details.offset,
                                                    );
                                                await _intentarMoverCorrectivaSemana(
                                                  dragged: details.data,
                                                  dayIndex: dayIndex,
                                                  localDy: local?.dy ?? 0,
                                                );
                                              },
                                              builder: (context, _, __) =>
                                                  const SizedBox.expand(),
                                            );
                                          },
                                        ),
                                      );
                                    }),
                                  );
                                },
                              ),
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
  final bool collapsed;
  final VoidCallback? onToggle;

  const _SidebarSimple({
    required this.title,
    required this.items,
    this.child,
    this.collapsed = false,
    this.onToggle,
  });

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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: collapsed
                          ? 'Expandir $title'
                          : 'Colapsar $title',
                      onPressed: onToggle,
                      icon: Icon(
                        collapsed
                            ? Icons.keyboard_double_arrow_right_rounded
                            : Icons.keyboard_double_arrow_left_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (collapsed)
                  const Expanded(child: SizedBox.shrink())
                else
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ...items.map(
                            (s) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                '- $s',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                          if (child != null) ...[const Divider(), child!],
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

class _SidebarAgendaDia extends StatelessWidget {
  final DateTime weekStart;
  final int dayIndex;
  final ValueChanged<int> onDayIndexChanged;
  final _SidebarAgendaModo modo;
  final ValueChanged<_SidebarAgendaModo>? onModoChanged;
  final bool verExcluidasMes;
  final ValueChanged<bool> onVerExcluidasMesChanged;
  final List<TareaModel> tareasSemana;
  final List<PreventivaExcluidaBorradorModel> excluidasMes;
  final List<ActividadEspecialPendiente> actividadesEspeciales;
  final Widget? masOpcionesButton;
  final Widget Function(ActividadEspecialPendiente) buildActividadEspecial;
  final List<PreventivaExcluidaBorradorModel> Function(DateTime fecha)
  excluirPorFecha;
  final void Function(TareaModel t) onTapTarea;
  final void Function(PreventivaExcluidaBorradorModel item)? onTapExcluida;

  const _SidebarAgendaDia({
    required this.weekStart,
    required this.dayIndex,
    required this.onDayIndexChanged,
    required this.modo,
    required this.onModoChanged,
    required this.verExcluidasMes,
    required this.onVerExcluidasMesChanged,
    required this.tareasSemana,
    required this.excluidasMes,
    required this.actividadesEspeciales,
    required this.masOpcionesButton,
    required this.buildActividadEspecial,
    required this.excluirPorFecha,
    required this.onTapTarea,
    required this.onTapExcluida,
  });

  @override
  Widget build(BuildContext context) {
    final fecha = weekStart.add(Duration(days: dayIndex));
    final tareasDia = tareasSemana.where((t) {
      final d = t.fechaInicio.toLocal();
      return d.year == fecha.year &&
          d.month == fecha.month &&
          d.day == fecha.day;
    }).toList()..sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));
    final excluidasDia = excluirPorFecha(fecha);
    final excluidas = verExcluidasMes ? excluidasMes : excluidasDia;

    Widget buildTarea(TareaModel t) {
      final ini = t.fechaInicio.toLocal();
      final fin = t.fechaFin.toLocal();
      final ubicacion = t.ubicacionNombre?.trim() ?? '';
      final zonaFinal = t.elementoNombre?.trim() ?? '';
      final contextoUbicacion = [
        if (ubicacion.isNotEmpty) 'Ubicación: $ubicacion',
        if (zonaFinal.isNotEmpty) 'Zona final: $zonaFinal',
      ].join(' · ');
      return InkWell(
        onTap: () => onTapTarea(t),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
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
              if (contextoUbicacion.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  contextoUbicacion,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                "${DateFormat('HH:mm').format(ini)} - ${DateFormat('HH:mm').format(fin)}",
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
      );
    }

    Widget buildExcluida(PreventivaExcluidaBorradorModel item) {
      final operarios = item.operariosNombres.isEmpty
          ? 'Sin operario sugerido'
          : item.operariosNombres.join(', ');
      final card = InkWell(
        onTap: onTapExcluida == null ? null : () => onTapExcluida!(item),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.22)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.descripcion,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'P${item.prioridad} • ${item.duracionLabel}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 4),
              Text(
                operarios,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 6),
              Text(
                'Mantén presionado y arrastra para programarla como ${etiquetaCorrectiva(minuscula: true)}.',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.orange.shade900,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );

      return LongPressDraggable<_DraggedWeekExcluida>(
        data: _DraggedWeekExcluida(excluida: item),
        maxSimultaneousDrags: 1,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        onDragStarted: () => _weekExcluidaDragActiveNotifier.value = true,
        onDragEnd: (_) {
          _weekExcluidaDragActiveNotifier.value = false;
          _setEspecialPreview(null);
        },
        onDraggableCanceled: (_, __) {
          _weekExcluidaDragActiveNotifier.value = false;
          _setEspecialPreview(null);
        },
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(width: 280, child: card),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: card),
        child: card,
      );
    }

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
                if (modo == _SidebarAgendaModo.agenda) ...[
                  const Text(
                    'Agenda',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  if (masOpcionesButton != null) ...[
                    const SizedBox(width: 4),
                    masOpcionesButton!,
                  ],
                ] else
                  const Text(
                    'Excluidas',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                const Spacer(),
                DropdownButton<int>(
                  value: dayIndex,
                  items: List.generate(7, (i) {
                    final d = weekStart.add(Duration(days: i));
                    final label = [
                      'Lun',
                      'Mar',
                      'Mié',
                      'Jue',
                      'Vie',
                      'Sáb',
                      'Dom',
                    ][i];
                    return DropdownMenuItem(
                      value: i,
                      child: Text('$label ${d.day}'),
                    );
                  }),
                  onChanged: (v) {
                    if (v == null) return;
                    onDayIndexChanged(v);
                  },
                ),
              ],
            ),
            if (onModoChanged != null) ...[
              const SizedBox(height: 6),
              SegmentedButton<_SidebarAgendaModo>(
                segments: const [
                  ButtonSegment<_SidebarAgendaModo>(
                    value: _SidebarAgendaModo.agenda,
                    label: Text('Agenda'),
                  ),
                  ButtonSegment<_SidebarAgendaModo>(
                    value: _SidebarAgendaModo.excluidas,
                    label: Text('Excluidas'),
                  ),
                ],
                selected: {modo},
                onSelectionChanged: (value) => onModoChanged!(value.first),
              ),
            ],
            if (modo == _SidebarAgendaModo.excluidas) ...[
              const SizedBox(height: 6),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(value: false, label: Text('Día')),
                  ButtonSegment<bool>(value: true, label: Text('Mes')),
                ],
                selected: {verExcluidasMes},
                onSelectionChanged: (value) =>
                    onVerExcluidasMesChanged(value.first),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              DateFormat('EEEE dd MMMM', 'es').format(fecha),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            if (modo == _SidebarAgendaModo.excluidas) ...[
              const SizedBox(height: 4),
              Text(
                'Standby del día: ${excluidasDia.length} • mes: ${excluidasMes.length}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              ),
            ],
            const Divider(height: 18),
            Expanded(
              child: modo == _SidebarAgendaModo.agenda
                  ? ListView(
                      children: [
                        if (tareasDia.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 18),
                            child: Center(
                              child: Text(
                                'Sin tareas este día',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        for (var i = 0; i < tareasDia.length; i++) ...[
                          if (i > 0) const SizedBox(height: 8),
                          buildTarea(tareasDia[i]),
                        ],
                        if (actividadesEspeciales.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.only(top: 14, bottom: 8),
                            child: Text(
                              'Actividades especiales pendientes',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: Color(0xFF5B21B6),
                              ),
                            ),
                          ),
                          for (final pendiente in actividadesEspeciales) ...[
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: buildActividadEspecial(pendiente),
                            ),
                          ],
                        ],
                      ],
                    )
                  : (excluidas.isEmpty
                        ? const Center(
                            child: Text(
                              'No hay excluidas en standby para esta vista.',
                              style: TextStyle(fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.separated(
                            itemCount: excluidas.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) =>
                                buildExcluida(excluidas[i]),
                          )),
            ),
          ],
        ),
      ),
    );
  }
}

class _MinuteRange {
  final int? tareaId;
  final int start;
  final int end;

  const _MinuteRange({this.tareaId, required this.start, required this.end});
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

  String get disponiblesHorasLabel => formatHoursMinutes(disponiblesMin);
  String get ocupadasHorasLabel => formatHoursMinutes(ocupadasMin);
  String get libresHorasLabel =>
      formatHoursMinutes((disponiblesMin - ocupadasMin).clamp(0, 1 << 30));
  String get porcentajeTexto =>
      '${(porcentajeOcupacion * 100).clamp(0, 999).toStringAsFixed(0)}%';
}

class _OperarioSemanaResumen {
  final String nombre;
  final String cargo;
  final int disponiblesMin;
  final int ocupadasMin;

  const _OperarioSemanaResumen({
    required this.nombre,
    required this.cargo,
    required this.disponiblesMin,
    required this.ocupadasMin,
  });

  double get porcentajeOcupacion =>
      disponiblesMin <= 0 ? 0 : ocupadasMin / disponiblesMin;

  String get disponiblesHorasLabel => formatHoursMinutes(disponiblesMin);
  String get ocupadasHorasLabel => formatHoursMinutes(ocupadasMin);
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

  /// Fila de una tarea excluida: no está programada, se muestra para su
  /// seguimiento durante el mes.
  final bool esExcluida;

  /// Id de la excluida cuando [esExcluida] es true.
  final int? excluidaId;
  final Map<int, String> porDia;

  _FilaCrono({
    required this.frecuencia,
    required this.diagnostico,
    required this.ubicacion,
    required this.objeto,
    required this.responsable,
    required this.esCorrectiva,
    required this.porDia,
    this.esExcluida = false,
    this.excluidaId,
  });
}
