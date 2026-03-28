import 'package:flutter/material.dart';
import 'package:flutter_application_1/model/usuario_model.dart';

import '../api/tarea_api.dart';
import '../api/gerente_api.dart';
import '../api/empresa_api.dart';
import '../api/cronograma_api.dart';
import '../api/herramienta_api.dart';

import '../model/conjunto_model.dart';
import '../model/herramienta_model.dart';
import '../model/maquinaria_model.dart';
import '../service/app_constants.dart';
import '../service/app_router.dart';
import '../service/theme.dart';
import '../utils/schedule_utils.dart';
import '../widgets/section_card.dart';
import '../widgets/searchable_select_field.dart';

import 'package:flutter_application_1/service/app_feedback.dart';

class CrearTareaPage extends StatefulWidget {
  final String nit;

  const CrearTareaPage({super.key, required this.nit});

  @override
  State<CrearTareaPage> createState() => _CrearTareaPageState();
}

class _CrearTareaPageState extends State<CrearTareaPage> {
  final _formKey = GlobalKey<FormState>();

  // APIs
  final TareaApi _tareaApi = TareaApi();
  final GerenteApi _gerenteApi = GerenteApi();
  final EmpresaApi _empresaApi = EmpresaApi();
  final CronogramaApi _cronogramaApi = CronogramaApi();
  final HerramientaApi _herramientaApi = HerramientaApi();

  // Controllers
  final _descripcionCtrl = TextEditingController();
  final _duracionCtrl = TextEditingController(); // minutos
  final _observacionesCtrl = TextEditingController();

  // Fechas y horas
  DateTime? fechaInicio; // fecha
  DateTime? fechaFin; // fecha
  TimeOfDay? _horaInicio;

  bool _cargandoInicial = true;
  bool _guardando = false;

  // Conjuntos
  List<Conjunto> _conjuntos = [];
  Conjunto? _conjuntoSeleccionado;

  // Ubicaciones / elementos
  List<UbicacionConElementos> _ubicaciones = [];
  UbicacionConElementos? _ubicacionSeleccionada;

  List<Elemento> _elementos = [];
  Elemento? _elementoSeleccionado;

  // Operarios
  List<Usuario> _operarios = [];
  final List<String> _operariosSeleccionadosIds = [];

  // Supervisores
  List<Usuario> _supervisores = [];
  String? _supervisorId;

  // Maquinaria
  List<MaquinariaResponse> _maquinariaDisponible = [];
  final List<int> _maquinariaSeleccionadaIds = [];

  // Herramientas
  List<HerramientaDisponibilidadResponse> _herramientasDisponibles = [];
  final Map<int, num> _herramientasSeleccionadas = {};

  int? _limiteMinSemana;

  int _prioridad = 2;

  @override
  void initState() {
    super.initState();
    _cargarInicial();
  }

  @override
  void dispose() {
    _descripcionCtrl.dispose();
    _duracionCtrl.dispose();
    _observacionesCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarLimiteSemana(String conjuntoNit) async {
    try {
      final limite = await _empresaApi.getLimiteMinSemanaPorConjunto();
      if (!mounted) return;
      setState(() => _limiteMinSemana = limite);
    } catch (_) {
      if (!mounted) return;
      setState(() => _limiteMinSemana = null);
    }
  }

  void _informarAutoReemplazos(List<dynamic> autoReplaced) {
    if (!mounted) return;
    if (autoReplaced.isEmpty) return;

    final ids = autoReplaced
        .map((e) => (e is Map ? e['id'] : null)?.toString())
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toList();

    final texto = ids.isEmpty
        ? 'Se reemplazó automáticamente una tarea de prioridad 3.'
        : 'Se reemplazó automáticamente la(s) tarea(s) P3: ${ids.join(", ")}.';

    AppFeedback.showFromSnackBar(context, SnackBar(content: Text(texto)));
  }

  List<int> _toIntIds(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => int.tryParse(e.toString())).whereType<int>().toList();
  }

  void _informarNoCompletadasPorReemplazo(dynamic idsRaw) {
    if (!mounted) return;
    final ids = _toIntIds(idsRaw);
    if (ids.isEmpty) return;
    final texto = ids.length == 1
        ? '1 preventiva quedó en NO_COMPLETADA por reemplazo.'
        : '${ids.length} preventivas quedaron en NO_COMPLETADA por reemplazo.';
    AppFeedback.showFromSnackBar(context, SnackBar(content: Text(texto)));
  }

  Future<void> _cargarInicial() async {
    try {
      final conjuntos = await _gerenteApi.listarConjuntos();
      final supervisores = await _gerenteApi.listarSupervisores();
      final maquinariaDisp = await _empresaApi.listarMaquinariaDisponible();

      Conjunto? seleccionado;
      if (conjuntos.isNotEmpty) {
        seleccionado = conjuntos.firstWhere(
          (c) => c.nit == widget.nit,
          orElse: () => conjuntos.first,
        );
      }

      if (!mounted) return;
      setState(() {
        _conjuntos = conjuntos;
        _supervisores = supervisores;
        _maquinariaDisponible = maquinariaDisp;
        _cargandoInicial = false;
      });

      if (seleccionado != null) _refrescarDatosConjunto(seleccionado);
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargandoInicial = false);
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text('Error cargando datos iniciales: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _refrescarDatosConjunto(Conjunto conjunto) {
    setState(() {
      _conjuntoSeleccionado = conjunto;

      _ubicaciones = conjunto.ubicaciones;
      _ubicacionSeleccionada = null;

      _elementos = [];
      _elementoSeleccionado = null;

      _operarios = conjunto.operarios;
      _operariosSeleccionadosIds.clear();

      _maquinariaSeleccionadaIds.clear();
      _herramientasSeleccionadas.clear();
      _supervisorId = null;
    });

    _cargarLimiteSemana(conjunto.nit);
    _cargarHerramientasConjunto(conjunto.nit);
  }

  Future<void> _cargarHerramientasConjunto(String conjuntoNit) async {
    try {
      final raw = await _herramientaApi.listarDisponibilidadConjunto(
        nitConjunto: conjuntoNit,
        empresaId: AppConstants.empresaNit,
      );
      if (!mounted) return;
      setState(() {
        _herramientasDisponibles = raw
            .whereType<Map>()
            .map(
              (e) => HerramientaDisponibilidadResponse.fromJson(
                e.cast<String, dynamic>(),
              ),
            )
            .where((h) => h.totalDisponible > 0)
            .toList();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _herramientasDisponibles = []);
    }
  }

  Future<void> _seleccionarFechaInicio() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: fechaInicio ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => fechaInicio = picked);
  }

  Future<void> _seleccionarFechaFin() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: fechaFin ?? (fechaInicio ?? DateTime.now()),
      firstDate: fechaInicio ?? DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => fechaFin = picked);
  }

  Future<void> _seleccionarHoraInicio() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _horaInicio ?? const TimeOfDay(hour: 8, minute: 0),
    );
    if (picked != null) setState(() => _horaInicio = picked);
  }

  Future<void> _mostrarSelectorOperarios() async {
    if (_operarios.isEmpty) {
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(content: Text('No hay operarios en este conjunto')),
      );
      return;
    }

    final seleccionTemp = Set<String>.from(_operariosSeleccionadosIds);

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Seleccionar operarios'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _operarios.length,
                  itemBuilder: (_, index) {
                    final op = _operarios[index];
                    final opId = op.cedula.trim();
                    if (opId.isEmpty) return const SizedBox.shrink();
                    final checked = seleccionTemp.contains(opId);
                    return CheckboxListTile(
                      value: checked,
                      title: Text(op.nombre),
                      subtitle: Text('Cédula: ${op.cedula}'),
                      onChanged: (v) {
                        if (v == true) {
                          seleccionTemp.add(opId);
                        } else {
                          seleccionTemp.remove(opId);
                        }
                        setStateDialog(() {});
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Aceptar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok == true) {
      setState(() {
        _operariosSeleccionadosIds
          ..clear()
          ..addAll(seleccionTemp);
      });
    }
  }

  Future<void> _mostrarSelectorMaquinaria() async {
    if (_maquinariaDisponible.isEmpty) {
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(content: Text('No hay maquinaria disponible')),
      );
      return;
    }

    final seleccionTemp = Set<int>.from(_maquinariaSeleccionadaIds);

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final filtered = _maquinariaDisponible.where((m) {
              final q = query.trim().toLowerCase();
              if (q.isEmpty) return true;
              return [
                m.nombre,
                m.marca,
                m.tipo.label,
              ].join(' ').toLowerCase().contains(q);
            }).toList();

            return AlertDialog(
              title: const Text('Maquinaria a prestar'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Buscar maquinaria',
                        hintText: 'Nombre, marca o tipo',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (value) => setStateDialog(() => query = value),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        itemBuilder: (_, index) {
                          final m = filtered[index];
                          final checked = seleccionTemp.contains(m.id);
                          return CheckboxListTile(
                            value: checked,
                            title: Text('${m.nombre} (${m.marca})'),
                            subtitle: Text(m.tipo.label),
                            onChanged: (v) {
                              if (v == true) {
                                seleccionTemp.add(m.id);
                              } else {
                                seleccionTemp.remove(m.id);
                              }
                              setStateDialog(() {});
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Aceptar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok == true) {
      setState(() {
        _maquinariaSeleccionadaIds
          ..clear()
          ..addAll(seleccionTemp);
      });
    }
  }

  Future<void> _mostrarSelectorHerramientas() async {
    if (_herramientasDisponibles.isEmpty) {
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(content: Text('No hay herramientas disponibles')),
      );
      return;
    }

    final seleccionTemp = Map<int, num>.from(_herramientasSeleccionadas);

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final filtered = _herramientasDisponibles.where((h) {
              final q = query.trim().toLowerCase();
              if (q.isEmpty) return true;
              return [h.nombre, h.unidad, h.categoria.label]
                  .join(' ')
                  .toLowerCase()
                  .contains(q);
            }).toList();

            return AlertDialog(
              title: const Text('Herramientas para la tarea'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Buscar herramienta',
                        hintText: 'Nombre, unidad o categoria',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (value) => setStateDialog(() => query = value),
                    ),
                    const SizedBox(height: 12),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Si hay stock propio del conjunto se usa primero. Si no alcanza, la reserva sale del stock de empresa.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        itemBuilder: (_, index) {
                          final h = filtered[index];
                          final actual = seleccionTemp[h.herramientaId];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(h.nombre),
                            subtitle: Text(
                              '${h.categoria.label} · conjunto: ${h.disponibleConjunto} · empresa: ${h.disponibleEmpresa} · total: ${h.totalDisponible}',
                            ),
                            trailing: SizedBox(
                              width: 96,
                              child: TextFormField(
                                initialValue:
                                    actual != null ? actual.toString() : '',
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Cant.',
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (value) {
                                  final parsed = num.tryParse(value.trim());
                                  if (parsed == null || parsed <= 0) {
                                    seleccionTemp.remove(h.herramientaId);
                                  } else {
                                    seleccionTemp[h.herramientaId] = parsed;
                                  }
                                },
                              ),
                            ),
                            isThreeLine: true,
                            dense: false,
                            leading: Icon(
                              h.disponibleConjunto > 0
                                  ? Icons.home_repair_service_outlined
                                  : Icons.inventory_2_outlined,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Aceptar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok == true) {
      setState(() {
        _herramientasSeleccionadas
          ..clear()
          ..addAll(seleccionTemp);
      });
    }
  }

  DateTime _combinarFechaYHora(DateTime fecha, TimeOfDay hora) {
    return DateTime(fecha.year, fecha.month, fecha.day, hora.hour, hora.minute);
  }

  int _minutosDelDia(DateTime d) => d.hour * 60 + d.minute;

  String _nombreDiaEs(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'lunes';
      case DateTime.tuesday:
        return 'martes';
      case DateTime.wednesday:
        return 'miercoles';
      case DateTime.thursday:
        return 'jueves';
      case DateTime.friday:
        return 'viernes';
      case DateTime.saturday:
        return 'sabado';
      case DateTime.sunday:
        return 'domingo';
      default:
        return 'dia';
    }
  }

  String? _validarDentroHorarioConjunto(DateTime inicio, DateTime fin) {
    final conjunto = _conjuntoSeleccionado;
    if (conjunto == null) return null;

    if (!fin.isAfter(inicio)) {
      return 'La hora de fin debe ser posterior a la hora de inicio.';
    }

    final mismoDia =
        inicio.year == fin.year &&
        inicio.month == fin.month &&
        inicio.day == fin.day;
    if (!mismoDia) {
      return 'La correctiva debe iniciar y terminar el mismo dia, dentro del horario del conjunto.';
    }

    final horarios = conjunto.horarios;
    if (horarios.isEmpty) {
      return 'El conjunto no tiene horarios configurados. Configuralos antes de agendar correctivas.';
    }

    final horariosDelDia = horarios
        .where((h) => weekdayFromScheduleDay(h.dia) == inicio.weekday)
        .toList();
    if (horariosDelDia.isEmpty) {
      return 'El conjunto no tiene horario para ${_nombreDiaEs(inicio.weekday)}.';
    }

    final iniMin = _minutosDelDia(inicio);
    final finMin = _minutosDelDia(fin);

    bool hayHorarioValido = false;
    final rangosPermitidos = <String>[];

    for (final h in horariosDelDia) {
      final apertura = parseHourToMinutes(h.horaApertura);
      final cierre = parseHourToMinutes(h.horaCierre);
      if (apertura == null || cierre == null || cierre <= apertura) continue;

      hayHorarioValido = true;

      final descansoInicio = parseHourToMinutes(h.descansoInicio);
      final descansoFin = parseHourToMinutes(h.descansoFin);
      final tieneDescanso =
          descansoInicio != null &&
          descansoFin != null &&
          descansoInicio > apertura &&
          descansoFin < cierre &&
          descansoFin > descansoInicio;

      if (!tieneDescanso) {
        rangosPermitidos.add(
          '${formatMinutesAsHour(apertura)}-${formatMinutesAsHour(cierre)}',
        );
        if (iniMin >= apertura && finMin <= cierre) return null;
        continue;
      }

      rangosPermitidos.add(
        '${formatMinutesAsHour(apertura)}-${formatMinutesAsHour(descansoInicio)} y ${formatMinutesAsHour(descansoFin)}-${formatMinutesAsHour(cierre)}',
      );
      final cabeAntesDescanso = iniMin >= apertura && finMin <= descansoInicio;
      final cabeDespuesDescanso = iniMin >= descansoFin && finMin <= cierre;
      if (cabeAntesDescanso || cabeDespuesDescanso) return null;
    }

    if (!hayHorarioValido) {
      return 'El horario de ${_nombreDiaEs(inicio.weekday)} esta mal configurado en el conjunto.';
    }

    final detalle = rangosPermitidos.isEmpty
        ? ''
        : ' Horario permitido: ${rangosPermitidos.join(' | ')}.';
    return 'Solo se puede agendar dentro del horario del conjunto.$detalle';
  }

  DateTime _inicioSemana(DateTime d) {
    final diff = d.weekday - DateTime.monday;
    return DateTime(d.year, d.month, d.day).subtract(Duration(days: diff));
  }

  // ✅ SOLO valida límite semanal. NO valida solapes (eso lo hace backend).
  Future<bool> _validarLimiteSemanal(
    DateTime inicio,
    int duracionMinutos,
  ) async {
    final conjunto = _conjuntoSeleccionado;
    if (conjunto == null || _operariosSeleccionadosIds.isEmpty) return true;

    try {
      final tareasMes = await _cronogramaApi.listarPorConjuntoYMes(
        nit: conjunto.nit,
        anio: inicio.year,
        mes: inicio.month,
      );

      final inicioSemana = _inicioSemana(inicio);
      final finSemana = inicioSemana.add(const Duration(days: 6));
      final limiteMinutosSemana = _limiteMinSemana ?? (42 * 60);

      bool solapaSemana(
        DateTime aIni,
        DateTime aFin,
        DateTime bIni,
        DateTime bFin,
      ) {
        return aIni.isBefore(bFin) && bIni.isBefore(aFin);
      }

      for (final opId in _operariosSeleccionadosIds) {
        int minutosSemana = 0;

        for (final t in tareasMes) {
          if (!t.operariosIds.contains(opId)) continue;

          final dentroSemana = solapaSemana(
            inicioSemana,
            finSemana,
            t.fechaInicio,
            t.fechaFin,
          );
          if (!dentroSemana) continue;

          minutosSemana += t.duracionMinutos;
        }

        final minutosConNueva = minutosSemana + duracionMinutos;

        if (minutosConNueva > limiteMinutosSemana) {
          if (!mounted) return false;
          await showDialog(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Límite semanal superado'),
              content: Text(
                'El operario $opId supera el límite semanal.\n\n'
                'Actual: ${(minutosSemana / 60).toStringAsFixed(1)} h\n'
                'Con nueva: ${(minutosConNueva / 60).toStringAsFixed(1)} h\n'
                'Límite: ${(limiteMinutosSemana / 60).toStringAsFixed(1)} h',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Aceptar'),
                ),
              ],
            ),
          );
          return false;
        }
      }

      return true;
    } catch (e) {
      if (!mounted) return false;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text('No se pudo validar límite semanal: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
  }

  Future<void> _onSuccess() async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Éxito'),
        content: const Text('Tarea correctiva creada correctamente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
      return;
    }

    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRouter.homeGerente,
      (route) => false,
    );
  }

  String _fmtDateTime(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day}/${d.month}/${d.year} $hh:$mm';
  }

  // ✅ NUEVO: helpers de fechas para el diálogo de ajuste
  DateTime? _parseDt(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }

  String _fmtHora(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _fmtFecha(DateTime d) => '${d.day}/${d.month}/${d.year}';

  // ✅ NUEVO: diálogo para avisar ajuste automático
  Future<void> _mostrarAjusteHorarioDialog({
    required DateTime? solicitadaIni,
    required DateTime? solicitadaFin,
    required DateTime? asignadaIni,
    required DateTime? asignadaFin,
    String? motivo,
  }) async {
    if (!mounted) return;

    String linea(String titulo, DateTime? a, DateTime? b) {
      if (a == null || b == null) return '$titulo: (no disponible)';
      final fecha = _fmtFecha(a);
      final rango = '${_fmtHora(a)} → ${_fmtHora(b)}';
      return '$titulo: $fecha  $rango';
    }

    final texto = [
      '⚠️ No había disponibilidad en el horario que seleccionaste.',
      if ((motivo ?? '').trim().isNotEmpty) '\n$motivo',
      '\n${linea("Solicitado", solicitadaIni, solicitadaFin)}',
      linea('Programado', asignadaIni, asignadaFin),
    ].join('\n');

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Horario ajustado automáticamente'),
        content: Text(texto),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  bool _backendOk(dynamic resp) {
    if (resp is Map) {
      if (resp['ok'] == true) return true;
      if (resp['id'] != null) return true;
      if (resp['createdIds'] != null) return true;
    }
    return false;
  }

  Future<void> _mostrarErrorBackend(dynamic resp) async {
    String msg = 'No se pudo crear la tarea.';
    String? reason;

    DateTime? sugIni;
    DateTime? sugFin;

    if (resp is Map) {
      msg = (resp['message'] ?? resp['error'] ?? msg).toString();
      reason = resp['reason']?.toString();

      if (resp['suggestedInicio'] != null && resp['suggestedFin'] != null) {
        sugIni = DateTime.parse(resp['suggestedInicio'].toString()).toLocal();
        sugFin = DateTime.parse(resp['suggestedFin'].toString()).toLocal();
      }
    } else {
      msg = resp.toString();
    }

    String extra = '';
    switch ((reason ?? '').toUpperCase()) {
      case 'INICIO_ANTES_APERTURA':
        extra = 'La hora seleccionada está antes de la apertura del conjunto.';
        break;
      case 'INICIO_EN_DESCANSO':
        extra = 'La hora seleccionada cae dentro del descanso del conjunto.';
        break;
      case 'FUERA_DE_JORNADA':
        extra = 'La tarea se sale del horario de operación del conjunto.';
        break;
      case 'SIN_HORARIO_DIA':
        extra = 'Ese día no tiene horario configurado para el conjunto.';
        break;
      case 'HAY_SOLAPE_CON_TAREAS_EXISTENTES':
        extra = 'Se cruza con otras tareas ya programadas.';
        break;
    }

    if (sugIni != null && sugFin != null) {
      final usar = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('No se puede crear en ese horario'),
          content: Text(
            '${extra.isEmpty ? '' : '$extra\n\n'}'
            '$msg\n\n'
            'Sugerencia: ${_fmtDateTime(sugIni!)} → ${_fmtDateTime(sugFin!)}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cerrar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Usar sugerencia'),
            ),
          ],
        ),
      );

      if (usar == true) {
        setState(() {
          fechaInicio = DateTime(sugIni!.year, sugIni.month, sugIni.day);
          fechaFin = DateTime(sugFin!.year, sugFin.month, sugFin.day);
          _horaInicio = TimeOfDay(hour: sugIni.hour, minute: sugIni.minute);
        });

        final nuevaDur = sugFin.difference(sugIni).inMinutes;
        if (nuevaDur > 0) _duracionCtrl.text = nuevaDur.toString();

        if (!mounted) return;
        AppFeedback.showFromSnackBar(
          context,
          const SnackBar(content: Text('✅ Sugerencia aplicada al formulario.')),
        );
      }

      return;
    }

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('No se pudo crear la tarea'),
        content: Text('${extra.isEmpty ? '' : '$extra\n\n'}$msg'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  Future<String?> _dialogMoverOReemplazar(DateTime ini, DateTime fin) {
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("No hay espacio en esa hora"),
        content: Text(
          "La hora solicitada está ocupada.\n\n"
          "Sugerencia disponible: ${_fmtDateTime(ini)} → ${_fmtDateTime(fin)}\n\n"
          "¿Deseas mover la correctiva a ese hueco o reemplazar la tarea preventiva que bloquea?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text("Cancelar"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, "MOVE"),
            child: const Text("Mover a sugerencia"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, "REPLACE"),
            child: const Text("Reemplazar preventiva"),
          ),
        ],
      ),
    );
  }

  int _intValue(dynamic value, {int fallback = 0}) {
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  List<Map<String, dynamic>> _parseReemplazoTareas(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  Color _reemplazoAccentColor({
    required bool critical,
    required bool noticeOnly,
  }) {
    if (noticeOnly) return const Color(0xFF1D4ED8);
    if (critical) return const Color(0xFFB91C1C);
    return const Color(0xFFD97706);
  }

  Color _reemplazoSoftColor({
    required bool critical,
    required bool noticeOnly,
  }) {
    if (noticeOnly) return const Color(0xFFDBEAFE);
    if (critical) return const Color(0xFFFEE2E2);
    return const Color(0xFFFFF7ED);
  }

  String _resumenReglaReemplazo({
    required int prioridadCorrectiva,
    required int prioridadObjetivo,
    required bool noticeOnly,
    required bool critical,
    required int cantidad,
  }) {
    final plural = cantidad == 1 ? 'preventiva' : 'preventivas';
    if (noticeOnly) {
      return 'La correctiva P$prioridadCorrectiva reemplazara '
          '$cantidad $plural P$prioridadObjetivo para liberar este horario.';
    }
    if (critical) {
      return 'Alerta: la correctiva P$prioridadCorrectiva reemplazara '
          '$cantidad $plural P$prioridadObjetivo. Esta confirmacion es critica.';
    }
    return 'La correctiva P$prioridadCorrectiva reemplazara '
        '$cantidad $plural P$prioridadObjetivo. Confirma para continuar.';
  }

  String _tituloDialogoReemplazo({
    required int prioridadCorrectiva,
    required int prioridadObjetivo,
    required bool noticeOnly,
    required bool critical,
    String? fallbackTitle,
  }) {
    final backendTitle = (fallbackTitle ?? '').trim();
    if (backendTitle.isNotEmpty) return backendTitle;
    if (noticeOnly) {
      return 'Aviso de reemplazo automatico P$prioridadObjetivo';
    }
    if (critical) {
      return 'Alerta: correctiva P$prioridadCorrectiva sobre preventiva P$prioridadObjetivo';
    }
    return 'Confirmar reemplazo P$prioridadCorrectiva sobre P$prioridadObjetivo';
  }

  String _etiquetaSeveridadReemplazo({
    required bool critical,
    required bool noticeOnly,
    required int prioridadObjetivo,
  }) {
    if (noticeOnly) return 'Aviso P$prioridadObjetivo';
    if (critical) return 'Critico P$prioridadObjetivo';
    return 'Confirmar P$prioridadObjetivo';
  }

  String _detalleTareaReemplazo(Map<String, dynamic> tarea) {
    final id = _intValue(tarea['id']);
    final prioridad = _intValue(tarea['prioridad'], fallback: 3);
    final desc = (tarea['descripcion'] ?? '').toString().trim();
    final ini = _parseDt(tarea['fechaInicio']);
    final fin = _parseDt(tarea['fechaFin']);
    final horario = (ini != null && fin != null)
        ? '${_fmtFecha(ini)} ${_fmtHora(ini)} -> ${_fmtHora(fin)}'
        : 'Horario no disponible';
    final ref = '#$id | P$prioridad';
    return desc.isEmpty ? '$ref | $horario' : '$ref | $desc | $horario';
  }

  String _previewTareasReemplazo(List<Map<String, dynamic>> tareas) {
    if (tareas.isEmpty) return 'Sin detalle adicional.';
    final lineas = tareas.take(2).map(_detalleTareaReemplazo).toList();
    if (tareas.length > 2) {
      lineas.add('y ${tareas.length - 2} mas...');
    }
    return lineas.join('\n');
  }

  Future<Map<String, dynamic>?> _dialogElegirReemplazo(
    List<Map<String, dynamic>> opciones, {
    String? title,
  }) async {
    if (opciones.isEmpty) return null;
    if (opciones.length == 1) return opciones.first;

    var selectedIndex = 0;
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          return AlertDialog(
            title: Text(title ?? 'Elegir reemplazo de preventiva'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: opciones.length,
                itemBuilder: (_, i) {
                  final o = opciones[i];
                  final critical = o['critical'] == true;
                  final noticeOnly = o['noticeOnly'] == true;
                  final prioridadObjetivo = _intValue(
                    o['prioridadObjetivo'],
                    fallback: 3,
                  );
                  final accent = _reemplazoAccentColor(
                    critical: critical,
                    noticeOnly: noticeOnly,
                  );
                  final soft = _reemplazoSoftColor(
                    critical: critical,
                    noticeOnly: noticeOnly,
                  );
                  final tareas = _parseReemplazoTareas(o['tareas']);
                  final resumen = (o['resumen'] ?? 'Opcion ${i + 1}')
                      .toString()
                      .trim();
                  final selected = selectedIndex == i;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: soft,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected
                            ? accent
                            : accent.withValues(alpha: 0.35),
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setStateDialog(() => selectedIndex = i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Icon(
                                selected
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_off_rounded,
                                color: accent,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    resumen,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.78,
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      _etiquetaSeveridadReemplazo(
                                        critical: critical,
                                        noticeOnly: noticeOnly,
                                        prioridadObjetivo: prioridadObjetivo,
                                      ),
                                      style: TextStyle(
                                        color: accent,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(_previewTareasReemplazo(tareas)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, opciones[selectedIndex]),
                child: const Text('Continuar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<bool> _dialogConfirmarDetalleReemplazo(
    Map<String, dynamic> opcion, {
    required int prioridadCorrectiva,
    String? fallbackTitle,
  }) async {
    final critical = opcion['critical'] == true;
    final noticeOnly = opcion['noticeOnly'] == true;
    final prioridadObjetivo = _intValue(
      opcion['prioridadObjetivo'],
      fallback: 3,
    );
    final tareas = _parseReemplazoTareas(opcion['tareas']);
    final accent = _reemplazoAccentColor(
      critical: critical,
      noticeOnly: noticeOnly,
    );
    final soft = _reemplazoSoftColor(
      critical: critical,
      noticeOnly: noticeOnly,
    );
    final resumen = (opcion['resumen'] ?? '').toString().trim();
    final textoRegla = _resumenReglaReemplazo(
      prioridadCorrectiva: prioridadCorrectiva,
      prioridadObjetivo: prioridadObjetivo,
      noticeOnly: noticeOnly,
      critical: critical,
      cantidad: tareas.isEmpty ? 1 : tareas.length,
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          _tituloDialogoReemplazo(
            prioridadCorrectiva: prioridadCorrectiva,
            prioridadObjetivo: prioridadObjetivo,
            noticeOnly: noticeOnly,
            critical: critical,
            fallbackTitle: fallbackTitle,
          ),
          style: TextStyle(color: accent),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: soft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: accent.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    textoRegla,
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (resumen.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(resumen),
                ],
                if (tareas.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    noticeOnly
                        ? 'Preventivas que se reemplazaran'
                        : 'Preventivas afectadas',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  ...tareas.map(
                    (t) => Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: soft.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(_detalleTareaReemplazo(t)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(noticeOnly ? 'Volver' : 'Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: accent),
            onPressed: () => Navigator.pop(context, true),
            child: Text(noticeOnly ? 'Entendido, continuar' : 'Si, reemplazar'),
          ),
        ],
      ),
    );

    return ok == true;
  }

  Future<String?> _dialogAccionReemplazo() {
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("¿Qué hacer con la preventiva reemplazada?"),
        content: const Text(
          "Puedes reprogramarla en otra franja o marcarla como no completada por reemplazo.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text("Cancelar"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, "CANCELAR"),
            child: const Text("Marcar no completada"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, "REPROGRAMAR"),
            child: const Text("Reprogramar preventiva"),
          ),
        ],
      ),
    );
  }

  Future<String?> _dialogMotivoReemplazo({required bool critical}) async {
    final ctrl = TextEditingController();
    final out = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: critical ? const Color(0xFFFEE2E2) : null,
        title: Text(
          "Motivo del reemplazo",
          style: TextStyle(color: critical ? const Color(0xFFB91C1C) : null),
        ),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: "Escribe el motivo (obligatorio)",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            style: critical
                ? ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    minimumSize: const Size(0, 38),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  )
                : AppTheme.saveButtonStyle,
            onPressed: () {
              final txt = ctrl.text.trim();
              if (txt.length < 3) return;
              Navigator.pop(context, txt);
            },
            child: const Text("Guardar"),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return out;
  }

  List<Map<String, dynamic>> _parseReprogramacionSlots(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  Future<Map<String, dynamic>?> _dialogSeleccionarSlotReprogramacion({
    required Map<String, dynamic> tarea,
  }) {
    final slots = _parseReprogramacionSlots(tarea['slots']);
    final tareaId = _intValue(tarea['tareaId']);
    final prioridad = _intValue(tarea['prioridad'], fallback: 3);
    final descripcion = (tarea['descripcion'] ?? '').toString().trim();

    if (slots.isEmpty) {
      return showDialog<Map<String, dynamic>?>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Sin horarios disponibles'),
          content: Text(
            'No encontramos franjas disponibles para reprogramar la preventiva '
            '#$tareaId${descripcion.isNotEmpty ? ' ($descripcion)' : ''}.\n\n'
            'Puedes volver y elegir marcarla como no completada.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      );
    }

    var selectedIndex = 0;
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text('Reprogramar preventiva #$tareaId'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    descripcion.isEmpty
                        ? 'Selecciona una nueva franja para la preventiva P$prioridad.'
                        : '$descripcion\n\nSelecciona una nueva franja para la preventiva P$prioridad.',
                  ),
                  const SizedBox(height: 14),
                  ...List.generate(slots.length, (index) {
                    final slot = slots[index];
                    final ini = _parseDt(slot['fechaInicio']);
                    final fin = _parseDt(slot['fechaFin']);
                    final label = (ini != null && fin != null)
                        ? '${_fmtFecha(ini)} | ${_fmtHora(ini)} -> ${_fmtHora(fin)}'
                        : 'Horario no disponible';
                    final selected = index == selectedIndex;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFFDBEAFE)
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFF2563EB)
                              : Colors.grey.shade300,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: RadioListTile<int>(
                        value: index,
                        groupValue: selectedIndex,
                        onChanged: (value) {
                          if (value == null) return;
                          setStateDialog(() => selectedIndex = value);
                        },
                        title: Text(label),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, {
                'tareaId': tareaId,
                'fechaInicio': slots[selectedIndex]['fechaInicio'],
                'fechaFin': slots[selectedIndex]['fechaFin'],
              }),
              child: const Text('Usar horario'),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>?> _dialogSeleccionarReprogramaciones(
    List<Map<String, dynamic>> tareas,
  ) async {
    final seleccionadas = <Map<String, dynamic>>[];

    for (final tarea in tareas) {
      final slot = await _dialogSeleccionarSlotReprogramacion(tarea: tarea);
      if (!mounted) return null;
      if (slot == null) return null;
      seleccionadas.add(slot);
    }

    return seleccionadas;
  }

  Future<void> _guardarTarea() async {
    if (!_formKey.currentState!.validate()) return;

    final conjunto = _conjuntoSeleccionado;
    if (conjunto == null) {
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text('Seleccione un conjunto')),
      );
      return;
    }

    if (fechaInicio == null || fechaFin == null) {
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(content: Text('Seleccione fecha de inicio y fin')),
      );
      return;
    }

    if (_horaInicio == null) {
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(content: Text('Seleccione la hora de inicio')),
      );
      return;
    }

    final mismoDia =
        fechaInicio!.year == fechaFin!.year &&
        fechaInicio!.month == fechaFin!.month &&
        fechaInicio!.day == fechaFin!.day;
    if (!mismoDia) {
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(
          content: Text('Por ahora debe ser dentro de un solo día.'),
        ),
      );
      return;
    }

    if (_ubicacionSeleccionada == null || _elementoSeleccionado == null) {
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(content: Text('Seleccione ubicación y elemento')),
      );
      return;
    }

    final duracionMin = int.tryParse(_duracionCtrl.text.trim());
    if (duracionMin == null || duracionMin <= 0) {
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(content: Text('Duración (minutos) inválida')),
      );
      return;
    }

    if (_operariosSeleccionadosIds.isEmpty) {
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(content: Text('Seleccione al menos un operario')),
      );
      return;
    }

    final inicio = _combinarFechaYHora(fechaInicio!, _horaInicio!);
    final fin = inicio.add(Duration(minutes: duracionMin));

    final errorHorario = _validarDentroHorarioConjunto(inicio, fin);
    if (errorHorario != null) {
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text(errorHorario)),
      );
      return;
    }

    final okSemana = await _validarLimiteSemanal(inicio, duracionMin);
    if (!mounted) return;
    if (!okSemana) return;

    setState(() => _guardando = true);

    try {
        final req = TareaRequest(
        descripcion: _descripcionCtrl.text.trim(),
        fechaInicio: inicio,
        fechaFin: fin,
        duracionMinutos: duracionMin,
        ubicacionId: _ubicacionSeleccionada!.id,
        elementoId: _elementoSeleccionado!.id,
        conjuntoId: conjunto.nit,
        supervisorId: _supervisorId,
        operariosIds: _operariosSeleccionadosIds,
        prioridad: _prioridad,
        tipo: "CORRECTIVA",
          observaciones: _observacionesCtrl.text.trim().isEmpty
              ? null
              : _observacionesCtrl.text.trim(),
          maquinariaIds: _maquinariaSeleccionadaIds,
          herramientas: _herramientasSeleccionadas.entries
              .map(
                (e) => {
                  'herramientaId': e.key,
                  'cantidad': e.value,
                },
              )
              .toList(),
        );

      final resp = await _tareaApi.crearTarea(req);
      if (!mounted) return;

      // ✅ CAMBIO: si fue OK, mostrar AlertDialog si el backend ajustó horario
      if (_backendOk(resp)) {
        final autoOk = (resp['autoReplaced'] as List?) ?? const [];
        _informarAutoReemplazos(autoOk);
        _informarNoCompletadasPorReemplazo(resp['noCompletadasIds']);

        final solIni = _parseDt(resp['solicitadaInicio']);
        final solFin = _parseDt(resp['solicitadaFin']);
        final asgIni = _parseDt(resp['asignadaInicio']);
        final asgFin = _parseDt(resp['asignadaFin']);

        final motivo = (resp['motivoAjuste'] ?? '').toString();

        final flag = resp['ajustadaAutomaticamente'] == true;

        final cambio =
            (solIni != null &&
                asgIni != null &&
                solFin != null &&
                asgFin != null)
            ? (solIni != asgIni || solFin != asgFin)
            : false;

        final tieneMotivo = motivo.trim().isNotEmpty;

        if (flag || cambio || tieneMotivo) {
          await _mostrarAjusteHorarioDialog(
            solicitadaIni: solIni,
            solicitadaFin: solFin,
            asignadaIni: asgIni,
            asignadaFin: asgFin,
            motivo: motivo,
          );
          if (!mounted) return;
        }

        await _onSuccess();
        return;
      }

      // Caso: conflicto con preventiva y requiere decision de reemplazo.
      if (resp['needsReplacement'] == true) {
        final respMap = resp.cast<String, dynamic>();
        final autoReplaced = (respMap['autoReplaced'] as List?) ?? const [];
        _informarAutoReemplazos(autoReplaced);

        final sugIni = _parseDt(respMap['suggestedInicio']);
        final sugFin = _parseDt(respMap['suggestedFin']);
        final decisionMode = (respMap['decisionMode'] ?? 'REEMPLAZAR')
            .toString()
            .toUpperCase();

        if (decisionMode == 'MOVER_O_REEMPLAZAR' &&
            sugIni != null &&
            sugFin != null) {
          final decision = await _dialogMoverOReemplazar(sugIni, sugFin);
          if (!mounted) return;
          if (decision == 'MOVE') {
            final req2 = TareaRequest(
              descripcion: req.descripcion,
              fechaInicio: sugIni,
              fechaFin: sugFin,
              duracionMinutos: req.duracionMinutos,
              ubicacionId: req.ubicacionId,
              elementoId: req.elementoId,
              conjuntoId: req.conjuntoId,
              supervisorId: req.supervisorId,
              operariosIds: req.operariosIds,
                prioridad: req.prioridad,
                tipo: req.tipo,
                observaciones: req.observaciones,
                maquinariaIds: req.maquinariaIds,
                herramientas: req.herramientas,
              );

            final resp2 = await _tareaApi.crearTarea(req2);
            if (!mounted) return;
            if (_backendOk(resp2)) {
              final auto2 = (resp2['autoReplaced'] as List?) ?? const [];
              _informarAutoReemplazos(auto2);
              _informarNoCompletadasPorReemplazo(resp2['noCompletadasIds']);
              await _onSuccess();
              return;
            }

            await _mostrarErrorBackend(resp2);
            return;
          }

          if (decision != 'REPLACE') {
            AppFeedback.showFromSnackBar(
              context,
              const SnackBar(content: Text('Operacion cancelada.')),
            );
            return;
          }
        }

        List<int> toIds(dynamic raw) {
          if (raw is! List) return const [];
          return raw
              .map((e) => int.tryParse(e.toString()))
              .whereType<int>()
              .toList();
        }

        String resumenFallback(Map<String, dynamic> t) {
          final id = t['id'];
          final prioridad = t['prioridad'];
          final desc = (t['descripcion'] ?? '').toString().trim();
          final base = 'Reemplazar preventiva ID $id (P$prioridad)';
          return desc.isEmpty ? base : '$base - $desc';
        }

        final opcionesAutoRaw = (respMap['opcionesAuto'] as List?) ?? const [];
        final opcionesConfirmRaw =
            (respMap['opcionesConfirmacion'] as List?) ?? const [];
        final opcionesDisponibles = <Map<String, dynamic>>[];

        for (final raw in opcionesAutoRaw) {
          if (raw is! Map) continue;
          final o = raw.cast<String, dynamic>();
          final ids = toIds(o['reemplazarIds']);
          if (ids.isEmpty) continue;
          final prioridadObjetivo = _intValue(
            o['prioridadObjetivo'],
            fallback: 3,
          );
          opcionesDisponibles.add({
            ...o,
            'reemplazarIds': ids,
            'requiresConfirm': false,
            'requiresAction': true,
            'requiresReason': false,
            'critical': false,
            'noticeOnly': true,
            'prioridadObjetivo': prioridadObjetivo,
            'tareas': _parseReemplazoTareas(o['tareas']),
            'resumen': (o['resumen'] ?? 'Reemplazo automatico').toString(),
          });
        }

        for (final raw in opcionesConfirmRaw) {
          if (raw is! Map) continue;
          final o = raw.cast<String, dynamic>();
          final ids = toIds(o['reemplazarIds']);
          if (ids.isEmpty) continue;
          final prioridadObjetivo =
              int.tryParse((o['prioridadObjetivo'] ?? '').toString()) ?? 3;
          final tipoConfirm = (o['tipoConfirmacion'] ?? '').toString();
          final critical =
              tipoConfirm.toUpperCase() == 'CONFIRM_DANGER' ||
              prioridadObjetivo == 1;
          opcionesDisponibles.add({
            ...o,
            'reemplazarIds': ids,
            'requiresConfirm': true,
            'requiresAction': true,
            'requiresReason': prioridadObjetivo <= 2,
            'critical': critical,
            'noticeOnly': false,
            'prioridadObjetivo': prioridadObjetivo,
            'tareas': _parseReemplazoTareas(o['tareas']),
            'resumen': (o['resumen'] ?? 'Requiere confirmacion de reemplazo')
                .toString(),
          });
        }

        if (opcionesDisponibles.isEmpty) {
          final reemplazables = (respMap['reemplazables'] as List?) ?? const [];
          final replacementPriority =
              int.tryParse((respMap['replacementPriority'] ?? '').toString()) ??
              3;
          final fallbackCritical =
              respMap['criticalConfirmation'] == true ||
              replacementPriority == 1;
          final fallbackRequiresReason =
              respMap['confirmationRequiresReason'] == true ||
              replacementPriority <= 2;
          final fallbackNoticeOnly =
              replacementPriority == 3 &&
              !fallbackCritical &&
              !fallbackRequiresReason;

          for (final raw in reemplazables) {
            if (raw is! Map) continue;
            final t = raw.cast<String, dynamic>();
            final id = int.tryParse((t['id'] ?? '').toString());
            if (id == null) continue;
            opcionesDisponibles.add({
              'reemplazarIds': [id],
              'resumen': resumenFallback(t),
              'requiresConfirm': !fallbackNoticeOnly,
              'requiresAction': !fallbackNoticeOnly,
              'requiresReason': fallbackRequiresReason,
              'critical': fallbackCritical,
              'noticeOnly': fallbackNoticeOnly,
              'prioridadObjetivo': replacementPriority,
              'tareas': [t],
            });
          }
        }

        if (opcionesDisponibles.isEmpty) {
          await _mostrarErrorBackend(respMap);
          return;
        }

        final seleccion = await _dialogElegirReemplazo(
          opcionesDisponibles,
          title: 'Elegir preventiva a reemplazar',
        );
        if (!mounted) return;
        if (seleccion == null) {
          AppFeedback.showFromSnackBar(
            context,
            SnackBar(content: Text('Operacion cancelada.')),
          );
          return;
        }

        final idsSeleccionados = toIds(seleccion['reemplazarIds']);
        if (idsSeleccionados.isEmpty) {
          await _mostrarErrorBackend(respMap);
          return;
        }

        final confirmacionCritica = seleccion['critical'] == true;
        final confirmado = await _dialogConfirmarDetalleReemplazo(
          seleccion,
          prioridadCorrectiva: req.prioridad,
        );
        if (!mounted) return;
        if (!confirmado) {
          AppFeedback.showFromSnackBar(
            context,
            const SnackBar(content: Text('Operacion cancelada.')),
          );
          return;
        }

        final requiereAccion = seleccion['requiresAction'] == true;
        final requiereMotivo = seleccion['requiresReason'] == true;

        String? accionReemplazadas;
        String? motivoReemplazo;
        if (requiereAccion) {
          accionReemplazadas = await _dialogAccionReemplazo();
          if (!mounted) return;
          if (accionReemplazadas == null) {
            AppFeedback.showFromSnackBar(
              context,
              const SnackBar(content: Text('Operacion cancelada.')),
            );
            return;
          }

          if (requiereMotivo) {
            motivoReemplazo = await _dialogMotivoReemplazo(
              critical: confirmacionCritica,
            );
            if (!mounted) return;
            if (motivoReemplazo == null || motivoReemplazo.trim().isEmpty) {
              AppFeedback.showFromSnackBar(
                context,
                const SnackBar(content: Text('Debe ingresar un motivo.')),
              );
              return;
            }
          }
        }

        Map<String, dynamic> resp3;
        if (accionReemplazadas == 'REPROGRAMAR') {
          final previewResp = await _tareaApi.crearTareaConReemplazo(
            tarea: req,
            reemplazarIds: idsSeleccionados,
            accionReemplazadas: accionReemplazadas,
            motivoReemplazo: motivoReemplazo,
          );
          if (!mounted) return;

          if (previewResp['needsReprogrammingSelection'] == true) {
            final opcionesReprogramacion = _parseReemplazoTareas(
              previewResp['opcionesReprogramacion'],
            );
            final seleccionReprogramacion =
                await _dialogSeleccionarReprogramaciones(
                  opcionesReprogramacion,
                );
            if (!mounted) return;
            if (seleccionReprogramacion == null ||
                seleccionReprogramacion.isEmpty) {
              AppFeedback.showFromSnackBar(
                context,
                const SnackBar(content: Text('Operacion cancelada.')),
              );
              return;
            }

            resp3 = await _tareaApi.crearTareaConReemplazo(
              tarea: req,
              reemplazarIds: idsSeleccionados,
              accionReemplazadas: accionReemplazadas,
              motivoReemplazo: motivoReemplazo,
              reprogramaciones: seleccionReprogramacion,
            );
          } else {
            resp3 = previewResp;
          }
        } else {
          resp3 = await _tareaApi.crearTareaConReemplazo(
            tarea: req,
            reemplazarIds: idsSeleccionados,
            accionReemplazadas: accionReemplazadas,
            motivoReemplazo: motivoReemplazo,
          );
        }
        if (!mounted) return;

        if (resp3['needsReprogrammingSelection'] == true) {
          AppFeedback.showFromSnackBar(
            context,
            SnackBar(
              content: Text(
                (resp3['message'] ??
                        'Debes seleccionar nuevamente la franja de reprogramacion.')
                    .toString(),
              ),
            ),
          );
          return;
        }

        if (_backendOk(resp3)) {
          final auto3 = (resp3['autoReplaced'] as List?) ?? const [];
          _informarAutoReemplazos(auto3);
          _informarNoCompletadasPorReemplazo(resp3['noCompletadasIds']);

          final canceladasSinCupo =
              (resp3['canceladasSinCupoIds'] as List?) ?? const [];
          if (canceladasSinCupo.isNotEmpty) {
            AppFeedback.showFromSnackBar(
              context,
              SnackBar(
                content: Text(
                  'Preventivas canceladas por falta de cupo: ${canceladasSinCupo.length}',
                ),
              ),
            );
          }

          await _onSuccess();
          return;
        }

        await _mostrarErrorBackend(resp3);
        return;
      }

      await _mostrarErrorBackend(resp);
      return;
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text('Error al crear tarea: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargandoInicial) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.primary,
          title: const Text(
            "Crear tarea correctiva",
            style: TextStyle(color: Colors.white),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: const Text(
          "Crear tarea correctiva",
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionCard(
                title: '1. Dónde se realizará',
                subtitle:
                    'Selecciona el conjunto, la ubicación y el elemento antes de programar la correctiva.',
                child: Column(
                  children: [
                    FormField<String>(
                      initialValue: _conjuntoSeleccionado?.nit,
                      validator: (v) =>
                          v == null ? 'Seleccione un conjunto' : null,
                      builder: (field) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SearchableSelectField<String>(
                              label: 'Conjunto',
                              value: field.value,
                              prefixIcon: const Icon(Icons.apartment_rounded),
                              searchHint: 'Buscar conjunto o NIT',
                              options: _conjuntos
                                  .map(
                                    (c) => SearchableSelectOption<String>(
                                      value: c.nit,
                                      label: c.nombre,
                                      subtitle: 'NIT: ${c.nit}',
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                field.didChange(value);
                                if (value == null) return;
                                final c = _conjuntos.firstWhere(
                                  (x) => x.nit == value,
                                );
                                _refrescarDatosConjunto(c);
                              },
                            ),
                            if (field.hasError) ...[
                              const SizedBox(height: 6),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Text(
                                  field.errorText!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      initialValue: _ubicacionSeleccionada?.id,
                      decoration: const InputDecoration(labelText: 'Ubicación'),
                      items: _ubicaciones
                          .map(
                            (u) => DropdownMenuItem(
                              value: u.id,
                              child: Text(u.nombre),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        final u = _ubicaciones.firstWhere((x) => x.id == value);
                        setState(() {
                          _ubicacionSeleccionada = u;
                          _elementos = u.elementos;
                          _elementoSeleccionado = null;
                        });
                      },
                      validator: (v) =>
                          v == null ? 'Seleccione una ubicación' : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      initialValue: _elementoSeleccionado?.id,
                      decoration: const InputDecoration(labelText: 'Elemento'),
                      items: _elementos
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.id,
                              child: Text(e.nombre),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        final el = _elementos.firstWhere((x) => x.id == value);
                        setState(() => _elementoSeleccionado = el);
                      },
                      validator: (v) =>
                          v == null ? 'Seleccione un elemento' : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SectionCard(
                title: '2. Qué se va a hacer',
                subtitle:
                    'Define la descripcion, prioridad, horario y observaciones de la tarea.',
                child: Column(
                  children: [
                    TextFormField(
                      controller: _descripcionCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Descripción de la tarea',
                      ),
                      maxLines: 2,
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Ingrese una descripción'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      initialValue: _prioridad,
                      decoration: const InputDecoration(labelText: 'Prioridad'),
                      items: const [
                        DropdownMenuItem(value: 1, child: Text("1 - Alta")),
                        DropdownMenuItem(value: 2, child: Text("2 - Media")),
                        DropdownMenuItem(value: 3, child: Text("3 - Baja")),
                      ],
                      onChanged: (v) => setState(() => _prioridad = v ?? 2),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: _seleccionarFechaInicio,
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: "Fecha inicio",
                                border: OutlineInputBorder(),
                              ),
                              child: Text(
                                fechaInicio == null
                                    ? "Seleccionar"
                                    : "${fechaInicio!.day}/${fechaInicio!.month}/${fechaInicio!.year}",
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: _seleccionarFechaFin,
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: "Fecha fin",
                                border: OutlineInputBorder(),
                              ),
                              child: Text(
                                fechaFin == null
                                    ? "Seleccionar"
                                    : "${fechaFin!.day}/${fechaFin!.month}/${fechaFin!.year}",
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: _seleccionarHoraInicio,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: "Hora de inicio",
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          _horaInicio == null
                              ? "Seleccionar"
                              : _horaInicio!.format(context),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _duracionCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "Duración estimada (minutos)",
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Ingrese duración en minutos';
                        }
                        final m = int.tryParse(v.trim());
                        if (m == null || m <= 0) return 'Minutos inválidos';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _observacionesCtrl,
                      decoration: const InputDecoration(
                        labelText: "Observaciones (opcional)",
                      ),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SectionCard(
                title: '3. Quiénes la ejecutan',
                subtitle:
                    'Asigna operarios y, si aplica, un supervisor responsable para el seguimiento.',
                child: Column(
                  children: [
                    InkWell(
                      onTap: _mostrarSelectorOperarios,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: "Operarios",
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          _operariosSeleccionadosIds.isEmpty
                              ? "Seleccionar operario(s)"
                              : "${_operariosSeleccionadosIds.length} operario(s) seleccionado(s)",
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _supervisorId,
                      decoration: const InputDecoration(
                        labelText: 'Supervisor (opcional)',
                      ),
                      items: _supervisores
                          .map((s) {
                            final id = s.cedula.trim();
                            if (id.isEmpty) return null;
                            return DropdownMenuItem(
                              value: id,
                              child: Text(s.nombre),
                            );
                          })
                          .whereType<DropdownMenuItem<String>>()
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _supervisorId = value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SectionCard(
                title: '4. Con qué maquinaria',
                subtitle:
                    'Relaciona la maquinaria necesaria para evitar olvidos en la ejecucion.',
                child: InkWell(
                  onTap: _mostrarSelectorMaquinaria,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: "Maquinaria a prestar (opcional)",
                      border: OutlineInputBorder(),
                    ),
                    child: Text(
                      _maquinariaSeleccionadaIds.isEmpty
                          ? "Sin maquinaria asociada"
                          : "${_maquinariaSeleccionadaIds.length} máquina(s) seleccionada(s)",
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SectionCard(
                title: '5. Con qué herramientas',
                subtitle:
                    'Selecciona cantidades disponibles del conjunto o de la empresa para esta correctiva.',
                child: InkWell(
                  onTap: _mostrarSelectorHerramientas,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Herramientas (opcional)',
                      border: OutlineInputBorder(),
                    ),
                    child: Text(
                      _herramientasSeleccionadas.isEmpty
                          ? 'Sin herramientas asociadas'
                          : '${_herramientasSeleccionadas.length} herramienta(s) seleccionada(s)',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _guardando ? null : _guardarTarea,
                icon: _guardando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(_guardando ? "Guardando..." : "Guardar"),
                style: AppTheme.saveButtonStyle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
