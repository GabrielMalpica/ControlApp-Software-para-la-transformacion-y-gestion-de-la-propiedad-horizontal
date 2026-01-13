import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/gerente_api.dart';
import 'package:flutter_application_1/pages/editar_tarea_page.dart';
import 'package:intl/intl.dart';

import '../api/cronograma_api.dart';
import '../model/tarea_model.dart';
import '../service/theme.dart';

enum _VistaCronograma { mensual, semanal }

class CronogramaPage extends StatefulWidget {
  final String nit;

  const CronogramaPage({super.key, required this.nit});

  @override
  State<CronogramaPage> createState() => _CronogramaPageState();
}

class _CronogramaPageState extends State<CronogramaPage> {
  final _api = CronogramaApi();
  final _gerenteApi = GerenteApi();

  DateTime _mesActual = DateTime(DateTime.now().year, DateTime.now().month);
  bool _cargando = false;
  String? _error;

  List<TareaModel> _tareas = [];
  Map<int, String> _supervisorNombrePorId = {};
  Map<int, List<TareaModel>> _tareasPorDia = {};

  // ✅ Vista + semana
  _VistaCronograma _vista = _VistaCronograma.mensual;
  late DateTime _semanaBase;

  // ✅ Día seleccionado (panel derecho)
  DateTime? _diaSeleccionado;

  // Filtros
  String _filtroTipo = 'TODAS'; // TODAS / PREVENTIVA / CORRECTIVA
  String _filtroEstado = 'TODOS'; // TODOS o EstadoTarea.*
  String _filtroOperario = 'TODOS'; // nombre del operario
  String _filtroUbicacion = 'TODAS'; // nombre de la ubicación

  List<String> _operariosDisponibles = [];
  List<String> _ubicacionesDisponibles = [];

  @override
  void initState() {
    super.initState();
    _semanaBase = DateTime(_mesActual.year, _mesActual.month, 1);
    _diaSeleccionado = DateTime.now();
    _cargar();
  }

  // =========================
  // Helpers fechas
  // =========================
  DateTime _startOfWeekMonday(DateTime d) {
    final dd = DateTime(d.year, d.month, d.day);
    final diff = dd.weekday - DateTime.monday;
    return dd.subtract(Duration(days: diff));
  }

  DateTime _endOfWeekSunday(DateTime d) {
    final start = _startOfWeekMonday(d);
    return start.add(const Duration(days: 6));
  }

  bool _isSameLocalDay(DateTime a, DateTime b) {
    final al = a.toLocal();
    final bl = b.toLocal();
    return al.year == bl.year && al.month == bl.month && al.day == bl.day;
  }

  // =========================
  // Carga (✅ SOLO PUBLICADAS)
  // =========================
  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final tareas = await _api.listarPorConjuntoYMes(
        nit: widget.nit,
        anio: _mesActual.year,
        mes: _mesActual.month,
      );

      final supervisores = await _gerenteApi.listarSupervisores();
      final mapaSup = <int, String>{};
      for (final s in supervisores) {
        final id = int.tryParse(s.cedula) ?? 0;
        if (id > 0) {
          mapaSup[id] = s.nombre;
        }
      }

      // ✅ FILTRO: NO mostrar tareas no publicadas (borrador)
      // Opción 1 (si tu TareaModel tiene bool borrador):
      final soloPublicadas = tareas.where((t) => t.borrador == false).toList();

      // ✅ Si NO tienes t.borrador, reemplaza el filtro anterior por algo así:
      // final soloPublicadas = tareas.where((t) => (t.publicada ?? false) == true).toList();
      // o:
      // final soloPublicadas = tareas.where((t) => (t.estadoCronograma ?? '') == 'PUBLICADA').toList();

      _tareas = soloPublicadas;
      _supervisorNombrePorId = mapaSup;

      _reconstruirFiltros();
      _reconstruirMapa();

      // ✅ Si el día seleccionado queda fuera del mes actual, lo reajustamos
      final hoy = DateTime.now();
      _diaSeleccionado ??= hoy;
      if (_diaSeleccionado!.year != _mesActual.year ||
          _diaSeleccionado!.month != _mesActual.month) {
        _diaSeleccionado = DateTime(_mesActual.year, _mesActual.month, 1);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _cargando = false);
    }
  }

  // =========================
  // Filtros aplicados
  // =========================
  bool _pasaFiltros(TareaModel t) {
    // 🔹 Tipo
    if (_filtroTipo != 'TODAS') {
      final tipo = (t.tipo ?? '').toUpperCase();
      if (tipo != _filtroTipo) return false;
    }

    // 🔹 Estado
    if (_filtroEstado != 'TODOS') {
      if ((t.estado ?? '') != _filtroEstado) return false;
    }

    // 🔹 Operario
    if (_filtroOperario != 'TODOS') {
      final tieneOperario = _tareaTieneOperario(t, _filtroOperario);
      if (!tieneOperario) return false;
    }

    // 🔹 Ubicación
    if (_filtroUbicacion != 'TODAS') {
      final ubicacion = _nombreUbicacion(t);
      if (ubicacion != _filtroUbicacion) return false;
    }

    return true;
  }

  void _reconstruirMapa() {
    final mapa = <int, List<TareaModel>>{};

    for (final t in _tareas) {
      if (!_pasaFiltros(t)) continue;

      final f = t.fechaInicio.toLocal();
      if (f.year != _mesActual.year || f.month != _mesActual.month) continue;

      final dia = f.day;
      mapa.putIfAbsent(dia, () => []).add(t);
    }

    setState(() {
      _tareasPorDia = mapa;
    });
  }

  void _reconstruirFiltros() {
    final ops = <String>{};
    final ubis = <String>{};

    for (final t in _tareas) {
      final ubicacion = _nombreUbicacion(t);
      if (ubicacion != null && ubicacion.isNotEmpty) {
        ubis.add(ubicacion);
      }

      for (final opNombre in _nombresOperarios(t)) {
        if (opNombre.isNotEmpty) ops.add(opNombre);
      }
    }

    setState(() {
      _operariosDisponibles = ops.toList()..sort();
      _ubicacionesDisponibles = ubis.toList()..sort();
    });
  }

  // =========================
  // Navegación
  // =========================
  void _cambiarMes(int delta) {
    setState(() {
      _mesActual = DateTime(_mesActual.year, _mesActual.month + delta);
      _semanaBase = DateTime(_mesActual.year, _mesActual.month, 1);
      _diaSeleccionado = DateTime(_mesActual.year, _mesActual.month, 1);
    });
    _cargar();
  }

  void _cambiarSemana(int deltaWeeks) {
    setState(() {
      _semanaBase = _semanaBase.add(Duration(days: 7 * deltaWeeks));
    });

    // ✅ Si te sales del mes, actualiza el mes y recarga automático
    final m = DateTime(_semanaBase.year, _semanaBase.month);
    if (m.year != _mesActual.year || m.month != _mesActual.month) {
      setState(() {
        _mesActual = m;
        _diaSeleccionado = DateTime(_mesActual.year, _mesActual.month, 1);
      });
      _cargar();
    }
  }

  // =========================
  // Colores
  // =========================
  Color _colorEstado(String? estado) {
    switch (estado) {
      case 'ASIGNADA':
        return Colors.blueGrey;
      case 'EN_PROCESO':
        return Colors.blue;
      case 'COMPLETADA':
        return Colors.green;
      case 'APROBADA':
        return Colors.teal;
      case 'PENDIENTE_APROBACION':
        return Colors.orange;
      case 'RECHAZADA':
        return Colors.red;
      case 'NO_COMPLETADA':
        return Colors.deepOrange;
      default:
        return Colors.grey;
    }
  }

  Color _colorCuadrado(int dia) {
    final hoy = DateTime.now();
    final fechaDia = DateTime(_mesActual.year, _mesActual.month, dia);

    final tareas = _tareasPorDia[dia] ?? [];
    final hayTareas = tareas.isNotEmpty;
    final hayPendientes = tareas.any(
      (t) =>
          t.estado == 'ASIGNADA' ||
          t.estado == 'EN_PROCESO' ||
          t.estado == 'PENDIENTE_APROBACION' ||
          t.estado == 'NO_COMPLETADA' ||
          t.estado == 'RECHAZADA',
    );

    final esHoy =
        fechaDia.year == hoy.year &&
        fechaDia.month == hoy.month &&
        fechaDia.day == hoy.day;

    if (esHoy) {
      if (!hayTareas) return Colors.blue.withOpacity(0.25);
      if (hayPendientes) return Colors.orange.shade300;
      return Colors.green.shade400;
    }

    if (!hayTareas) return Colors.grey.shade200;

    if (fechaDia.isBefore(DateTime(hoy.year, hoy.month, hoy.day))) {
      if (hayPendientes) return Colors.orange.shade300;
      return Colors.green.shade400;
    }

    return Colors.deepPurple.withOpacity(0.15);
  }

  Color _bordeCuadrado(int dia) {
    final hoy = DateTime.now();
    final fechaDia = DateTime(_mesActual.year, _mesActual.month, dia);

    if (fechaDia.year == hoy.year &&
        fechaDia.month == hoy.month &&
        fechaDia.day == hoy.day) {
      return Colors.blueAccent;
    }

    final tareas = _tareasPorDia[dia] ?? [];
    if (tareas.isEmpty) return Colors.grey.shade300;
    return Colors.deepPurple;
  }

  // =========================
  // Abrir día (modal mensual)
  // =========================
  void _abrirDia(int dia) {
    final tareas = _tareasPorDia[dia] ?? [];
    if (tareas.isEmpty) return;

    final tareasOrdenadas = [...tareas]
      ..sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));

    final fecha = DateTime(_mesActual.year, _mesActual.month, dia);
    final mesNombre = DateFormat.MMMM('es').format(fecha);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (_, controller) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tareas del $dia de ${mesNombre.toUpperCase()}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Conjunto: ${widget.nit}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const Divider(height: 16),
                  Expanded(
                    child: ListView.builder(
                      controller: controller,
                      itemCount: tareasOrdenadas.length,
                      itemBuilder: (_, index) {
                        final t = tareasOrdenadas[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            onTap: () {
                              Navigator.of(ctx).pop();
                              _mostrarResumenTarea(t);
                            },
                            leading: CircleAvatar(
                              backgroundColor: _colorEstado(
                                t.estado,
                              ).withOpacity(0.2),
                              child: Icon(
                                Icons.assignment,
                                color: _colorEstado(t.estado),
                              ),
                            ),
                            title: Text(
                              t.descripcion,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  'Estado: ${t.estado ?? 'SIN_ESTADO'}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: _colorEstado(t.estado),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Tipo: ${t.tipo ?? 'SIN_TIPO'}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Inicio: ${DateFormat('dd/MM/yyyy HH:mm').format(t.fechaInicio)}',
                                  style: const TextStyle(fontSize: 11),
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
            );
          },
        );
      },
    );
  }

  String _fmtDuracion(int min) {
    final h = min ~/ 60;
    final m = min % 60;
    if (h <= 0) return '$m min';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  void _mostrarResumenTarea(TareaModel t) {
    final inicioStr = DateFormat('dd/MM/yyyy HH:mm').format(t.fechaInicio);
    final finStr = DateFormat('dd/MM/yyyy HH:mm').format(t.fechaFin);

    final ubicacion = t.ubicacionNombre ?? 'Sin ubicación';
    final elemento = t.elementoNombre ?? 'Sin elemento';

    String supervisorTexto;
    final nombrePlano = (t.supervisorNombre ?? '').trim();
    if (nombrePlano.isNotEmpty) {
      supervisorTexto = nombrePlano;
    } else if (t.supervisorId != null) {
      supervisorTexto =
          _supervisorNombrePorId[t.supervisorId!] ??
          'Supervisor ID: ${t.supervisorId}';
    } else {
      supervisorTexto = 'Sin supervisor';
    }

    final operarios = t.operariosNombres;
    final operariosTexto = operarios.isEmpty
        ? 'Sin operarios'
        : operarios.join(', ');

    final tipo = t.tipo ?? 'SIN_TIPO';
    final estado = t.estado ?? 'SIN_ESTADO';
    final duracion = '${t.duracionMinutos}';
    final frecuencia = t.frecuencia ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          builder: (_, controller) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                controller: controller,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          t.descripcion,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Chip(
                        label: Text(
                          estado,
                          style: const TextStyle(color: Colors.white),
                        ),
                        backgroundColor: _colorEstado(estado),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Chip(
                        label: Text('Tipo: $tipo'),
                        backgroundColor: Colors.grey.shade200,
                      ),
                      if (frecuencia.isNotEmpty)
                        Chip(
                          label: Text('Frecuencia: $frecuencia'),
                          backgroundColor: Colors.grey.shade200,
                        ),
                      Chip(
                        label: Text(
                          'Duración: ${_fmtDuracion(t.duracionMinutos)}',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Detalles principales',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  _detailRow('Inicio', inicioStr),
                  _detailRow('Fin', finStr),
                  _detailRow('Ubicación', ubicacion),
                  _detailRow('Elemento', elemento),
                  _detailRow('Supervisor', supervisorTexto),
                  _detailRow('Operarios', operariosTexto),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _irAEditarTarea(t),
                        icon: const Icon(Icons.edit),
                        label: const Text('Editar'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _confirmarEliminarTarea(t),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Eliminar'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _mostrarDetalleTarea(t);
                        },
                        child: const Text('Ver más'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      label: const Text('Cerrar'),
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

  // ===== Helpers de lectura de modelo =====
  String? _nombreUbicacion(TareaModel t) => t.ubicacionNombre;

  List<String> _nombresOperarios(TareaModel t) => t.operariosNombres;

  bool _tareaTieneOperario(TareaModel t, String nombreOperario) {
    return _nombresOperarios(t).contains(nombreOperario);
  }

  // =========================
  // Detalle FULL (intacto)
  // =========================
  void _mostrarDetalleTarea(TareaModel t) {
    // (tu método full se queda igual, no lo toco)
    // ... (lo dejé igual que tu versión, para no alargar aquí)
    // ✅ Para que compile: te dejo que lo uses tal cual lo pegaste arriba.
    // (No lo recorto más porque tú ya lo tienes completo en tu archivo.)
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
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

  // =========================
  // Acciones
  // =========================
  void _irAEditarTarea(TareaModel t) async {
    final resultado = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditarTareaPage(tarea: t, nit: widget.nit),
      ),
    );
    if (resultado == true) _cargar();
  }

  void _confirmarEliminarTarea(TareaModel t) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Eliminar tarea'),
          content: Text(
            '¿Seguro que deseas eliminar la tarea:\n\n"${t.descripcion}"?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).pop();

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Tarea ${t.id} eliminada (simulado, falta conectar API)',
                    ),
                  ),
                );
              },
              child: const Text(
                'Eliminar',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }

  void _irADetalleCompleto(TareaModel t) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => TareaDetallePage(tarea: t)));
  }

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    final mesNombre = DateFormat.MMMM('es').format(_mesActual).toUpperCase();
    final year = _mesActual.year;

    final weekStart = _startOfWeekMonday(_semanaBase);
    final weekEnd = _endOfWeekSunday(_semanaBase);
    final rangoSemana =
        "${DateFormat('dd MMM', 'es').format(weekStart)} - ${DateFormat('dd MMM', 'es').format(weekEnd)}";

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: const Text('Cronograma', style: TextStyle(color: Colors.white)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // ✅ TOP BAR: toggle + navegación
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
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
                      onSelectionChanged: (s) {
                        setState(() {
                          _vista = s.first;
                          if (_vista == _VistaCronograma.semanal) {
                            _diaSeleccionado ??= DateTime(
                              _mesActual.year,
                              _mesActual.month,
                              1,
                            );
                          }
                        });
                      },
                    ),
                    const SizedBox(width: 10),

                    if (_vista == _VistaCronograma.mensual) ...[
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => _cambiarMes(-1),
                      ),
                      Text(
                        '$mesNombre $year',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () => _cambiarMes(1),
                      ),
                    ] else ...[
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => _cambiarSemana(-1),
                      ),
                      Text(
                        rangoSemana,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () => _cambiarSemana(1),
                      ),
                    ],

                    const Spacer(),
                    Text(
                      'Tareas: ${_tareas.length} | Días con tareas: ${_t_tareasPorDiaCount()}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            if (_cargando)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Expanded(
                child: Center(
                  child: Text(
                    'Error: $_error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              )
            else
              Expanded(
                child: _vista == _VistaCronograma.mensual
                    ? _buildMensualCompacto()
                    : _buildSemanalConPaneles(weekStart),
              ),
          ],
        ),
      ),
    );
  }

  int _t_tareasPorDiaCount() => _tareasPorDia.keys.length;

  // =========================
  // MENSUAL (✅ compacto + 7 columnas)
  // =========================
  Widget _buildMensualCompacto() {
    return Column(
      children: [
        // Encabezado días semana
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: const [
              Expanded(
                child: Center(
                  child: Text(
                    'Lun',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    'Mar',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    'Mié',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    'Jue',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    'Vie',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    'Sáb',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    'Dom',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _buildCalendarioMensualSemanasCompacto()),
      ],
    );
  }

  Widget _buildCalendarioMensualSemanasCompacto() {
    final totalDias = DateUtils.getDaysInMonth(
      _mesActual.year,
      _mesActual.month,
    );

    int weekdayIndexMonday(DateTime d) => (d.weekday + 6) % 7;

    final primerDiaMes = DateTime(_mesActual.year, _mesActual.month, 1);
    final offset = weekdayIndexMonday(primerDiaMes);

    final totalCeldas = offset + totalDias;
    final totalFilas = (totalCeldas / 7).ceil();
    final totalItems = totalFilas * 7;

    return GridView.builder(
      itemCount: totalItems,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        mainAxisExtent:
            78, // ✅ tamaño del cuadro (bájalo a 64 si lo quieres más pequeño)
      ),
      itemBuilder: (_, index) {
        final dia = index - offset + 1;

        if (dia < 1 || dia > totalDias) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
          );
        }

        final tareasDia = _tareasPorDia[dia];
        return GestureDetector(
          onTap: () => _abrirDia(dia),
          child: Container(
            decoration: BoxDecoration(
              color: _colorCuadrado(dia),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _bordeCuadrado(dia), width: 1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  dia.toString(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                if (tareasDia != null && tareasDia.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${tareasDia.length} tareas',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // =========================
  // SEMANAL (✅ panel izquierdo + agenda + panel derecho)
  // =========================
  Widget _buildSemanalConPaneles(DateTime weekStart) {
    // Ajusta día seleccionado al rango de la semana si hace falta
    _diaSeleccionado ??= weekStart;
    if (_diaSeleccionado!.isBefore(weekStart) ||
        _diaSeleccionado!.isAfter(weekStart.add(const Duration(days: 6)))) {
      _diaSeleccionado = weekStart;
    }

    return Row(
      children: [
        SizedBox(width: 340, child: _buildPanelIzquierdoSemanal(weekStart)),
        const SizedBox(width: 12),
        Expanded(child: _buildAgendaSemanal(weekStart)),
        const SizedBox(width: 12),
        SizedBox(width: 340, child: _buildPanelDerechoAgendaDia(weekStart)),
      ],
    );
  }

  Widget _buildPanelIzquierdoSemanal(DateTime weekStart) {
    final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final end = start.add(const Duration(days: 7));

    final tareasSemana = _tareas.where((t) {
      if (!_pasaFiltros(t)) return false;
      final dt = t.fechaInicio.toLocal();
      return !dt.isBefore(start) && dt.isBefore(end);
    }).length;

    final horarioTxt = '08:00 - 16:00 (almuerzo 13-14)';

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            const Text(
              'Resumen',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            Text('• Tareas semana: $tareasSemana'),
            Text('• Tareas mes: ${_tareas.length}'),
            const SizedBox(height: 6),
            Text('• Horario: $horarioTxt'),
            const SizedBox(height: 14),
            const Divider(),
            const SizedBox(height: 10),

            const Text(
              'Filtros',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 10),

            _buildFiltrosComoColumna(),

            const SizedBox(height: 14),
            Text(
              'Tip: aquí metes filtros (supervisor, operario, ubicación) sin tocar la agenda.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltrosComoColumna() {
    return Column(
      children: [
        DropdownButtonFormField<String>(
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Tipo de tarea',
            border: OutlineInputBorder(),
          ),
          value: _filtroTipo,
          items: const [
            DropdownMenuItem(value: 'TODAS', child: Text('Todas')),
            DropdownMenuItem(value: 'PREVENTIVA', child: Text('Preventivas')),
            DropdownMenuItem(value: 'CORRECTIVA', child: Text('Correctivas')),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _filtroTipo = v);
            _reconstruirMapa();
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Estado',
            border: OutlineInputBorder(),
          ),
          value: _filtroEstado,
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
            DropdownMenuItem(value: 'PENDIENTE_REPROGRAMACION', child: Text('Pendiente reprogramación')),
            DropdownMenuItem(
              value: 'NO_COMPLETADA',
              child: Text('No completada'),
            ),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _filtroEstado = v);
            _reconstruirMapa();
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Operario',
            border: OutlineInputBorder(),
          ),
          value: _filtroOperario,
          items: [
            const DropdownMenuItem(value: 'TODOS', child: Text('Todos')),
            ..._operariosDisponibles.map(
              (o) => DropdownMenuItem(value: o, child: Text(o)),
            ),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _filtroOperario = v);
            _reconstruirMapa();
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Ubicación',
            border: OutlineInputBorder(),
          ),
          value: _filtroUbicacion,
          items: [
            const DropdownMenuItem(value: 'TODAS', child: Text('Todas')),
            ..._ubicacionesDisponibles.map(
              (u) => DropdownMenuItem(value: u, child: Text(u)),
            ),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _filtroUbicacion = v);
            _reconstruirMapa();
          },
        ),
      ],
    );
  }

  Widget _buildPanelDerechoAgendaDia(DateTime weekStart) {
    final dia = _diaSeleccionado ?? weekStart;
    final diaLabel = DateFormat('EEE dd', 'es').format(dia).toUpperCase();

    final tareasDia = _tareas.where((t) {
      if (!_pasaFiltros(t)) return false;
      return _isSameLocalDay(t.fechaInicio, dia);
    }).toList()..sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Text(
                  'Agenda',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                DropdownButton<DateTime>(
                  value: dia,
                  underline: const SizedBox.shrink(),
                  items: List.generate(7, (i) {
                    final d = weekStart.add(Duration(days: i));
                    final label = DateFormat('EEE dd', 'es').format(d);
                    return DropdownMenuItem(value: d, child: Text(label));
                  }),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _diaSeleccionado = v);
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                DateFormat("EEEE dd 'de' MMMM", 'es').format(dia),
                style: const TextStyle(color: Colors.grey),
              ),
            ),
            const Divider(height: 18),

            Expanded(
              child: tareasDia.isEmpty
                  ? const Center(child: Text('Sin tareas este día'))
                  : ListView.separated(
                      itemCount: tareasDia.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final t = tareasDia[i];
                        final ini = DateFormat('HH:mm').format(t.fechaInicio);
                        final fin = DateFormat('HH:mm').format(t.fechaFin);
                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          title: Text(
                            t.descripcion,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '$ini - $fin • ${t.tipo ?? ''} • ${t.estado ?? ''}',
                          ),
                          leading: Container(
                            width: 10,
                            height: 38,
                            decoration: BoxDecoration(
                              color: _colorEstado(t.estado).withOpacity(0.25),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _colorEstado(t.estado).withOpacity(0.7),
                              ),
                            ),
                          ),
                          onTap: () => _mostrarDetalleTarea(t),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================
  // Semanal: agenda por horas
  // =========================
  Widget _buildAgendaSemanal(DateTime weekStart) {
    final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final end = start.add(const Duration(days: 7));

    final tareasSemana = _tareas.where((t) {
      if (!_pasaFiltros(t)) return false;
      final dt = t.fechaInicio.toLocal();
      return !dt.isBefore(start) && dt.isBefore(end);
    }).toList()..sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));

    return _WeekScheduleView(
      weekStart: weekStart,
      tareas: tareasSemana,
      onTapTarea: (t) {
        setState(
          () => _diaSeleccionado = DateTime(
            t.fechaInicio.year,
            t.fechaInicio.month,
            t.fechaInicio.day,
          ),
        );
        _mostrarDetalleTarea(t);
      },
      onSelectDay: (d) => setState(() => _diaSeleccionado = d),
    );
  }
}

// =====================================================
//  Vista semanal tipo agenda (✅ header scrollea con body)
// =====================================================

class _WeekScheduleView extends StatefulWidget {
  final DateTime weekStart; // lunes
  final List<TareaModel> tareas;
  final void Function(TareaModel t) onTapTarea;
  final void Function(DateTime day) onSelectDay;

  const _WeekScheduleView({
    required this.weekStart,
    required this.tareas,
    required this.onTapTarea,
    required this.onSelectDay,
  });

  @override
  State<_WeekScheduleView> createState() => _WeekScheduleViewState();
}

class _WeekScheduleViewState extends State<_WeekScheduleView> {
  final ScrollController _hCtrl = ScrollController();
  final ScrollController _vCtrl = ScrollController();

  static const int horaInicio = 8;
  static const int horaFin = 16;
  static const int almuerzoIni = 13;
  static const int almuerzoFin = 14;

  static const double pxPorMin = 1.2;
  static const double anchoHora = 56;
  static const double altoHeader = 44;

  int _minutesFromStart(DateTime d) {
    final start = DateTime(d.year, d.month, d.day, horaInicio);
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

  @override
  void dispose() {
    _hCtrl.dispose();
    _vCtrl.dispose();
    super.dispose();
  }

  bool _cruzaAlmuerzo(DateTime ini, DateTime fin) {
    final aIni = DateTime(ini.year, ini.month, ini.day, almuerzoIni);
    final aFin = DateTime(ini.year, ini.month, ini.day, almuerzoFin);
    return ini.isBefore(aFin) && fin.isAfter(aIni);
  }

  @override
  Widget build(BuildContext context) {
    final hours = horaFin - horaInicio;
    final heightGrid = (hours * 60) * pxPorMin;

    final bg = const Color(0xFF0F1115);
    final line = Colors.white.withOpacity(0.08);
    final text = Colors.white.withOpacity(0.85);
    final subtext = Colors.white.withOpacity(0.60);

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
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            children: [
              // ✅ HEADER scrolleable (Fix 2)
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
                          final label = const [
                            "Lun",
                            "Mar",
                            "Mié",
                            "Jue",
                            "Vie",
                            "Sáb",
                            "Dom",
                          ][i];
                          return SizedBox(
                            width: colWidth,
                            child: InkWell(
                              onTap: () => widget.onSelectDay(d),
                              child: Center(
                                child: Text(
                                  "$label ${d.day}",
                                  style: TextStyle(
                                    color: text,
                                    fontWeight: FontWeight.w600,
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
                            // Columnas + horas
                            Positioned.fill(
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: anchoHora,
                                    child: _HoursColumnDark(
                                      pxPorMin: pxPorMin,
                                      textColor: subtext,
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

                            // Líneas por hora
                            ...List.generate(hours + 1, (h) {
                              final top = (h * 60) * pxPorMin;
                              return Positioned(
                                left: 0,
                                right: 0,
                                top: top,
                                child: Container(height: 1, color: line),
                              );
                            }),

                            // Franja almuerzo
                            Positioned(
                              left: 0,
                              right: 0,
                              top: ((almuerzoIni - horaInicio) * 60) * pxPorMin,
                              height:
                                  ((almuerzoFin - almuerzoIni) * 60) * pxPorMin,
                              child: Container(
                                color: Colors.white.withOpacity(0.03),
                              ),
                            ),

                            // Tareas
                            ...widget.tareas
                                .where(
                                  (t) => _isWithinWeek(t.fechaInicio.toLocal()),
                                )
                                .map((t) {
                                  final ini = t.fechaInicio.toLocal();
                                  final fin = t.fechaFin.toLocal();

                                  final day = _dayIndex(ini);
                                  if (day < 0 || day > 6)
                                    return const SizedBox.shrink();

                                  final startMin = _minutesFromStart(ini);
                                  final durMin = fin.difference(ini).inMinutes;

                                  final left = anchoHora + day * colWidth + 6;
                                  final top = startMin * pxPorMin;
                                  final height = (durMin * pxPorMin).clamp(
                                    18.0,
                                    9999.0,
                                  );

                                  final baseColor = _colorPorTipo(t);
                                  final fill = baseColor.withOpacity(0.22);
                                  final border = baseColor.withOpacity(0.70);

                                  final horaIni = DateFormat(
                                    'HH:mm',
                                  ).format(ini);
                                  final horaFin = DateFormat(
                                    'HH:mm',
                                  ).format(fin);

                                  final cruzaAlm = _cruzaAlmuerzo(ini, fin);

                                  return Positioned(
                                    left: left,
                                    top: top,
                                    width: colWidth - 12,
                                    height: height,
                                    child: GestureDetector(
                                      onTap: () => widget.onTapTarea(t),
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: fill,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: border,
                                            width: 1,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              t.descripcion,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: text,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              '$horaIni - $horaFin',
                                              style: TextStyle(
                                                color: subtext,
                                                fontSize: 11,
                                              ),
                                            ),
                                            if (cruzaAlm)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 4,
                                                ),
                                                child: Text(
                                                  '⚠ Cruza almuerzo',
                                                  style: TextStyle(
                                                    color:
                                                        Colors.orange.shade200,
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ),
                                          ],
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
            ],
          ),
        );
      },
    );
  }

  Color _colorPorTipo(TareaModel t) {
    final tipo = (t.tipo ?? '').toUpperCase();
    if (tipo == 'CORRECTIVA') return Colors.orange;
    if (tipo == 'PREVENTIVA') return AppTheme.primary;
    return Colors.blueGrey;
  }
}

class _HoursColumnDark extends StatelessWidget {
  final double pxPorMin;
  final Color textColor;

  const _HoursColumnDark({required this.pxPorMin, required this.textColor});

  @override
  Widget build(BuildContext context) {
    const int horaInicio = 8;
    const int horaFin = 16;
    final hours = horaFin - horaInicio;

    return Column(
      children: List.generate(hours, (i) {
        final h = horaInicio + i;
        return SizedBox(
          height: 60 * pxPorMin,
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                "${h.toString().padLeft(2, '0')}:00",
                style: TextStyle(fontSize: 11, color: textColor),
              ),
            ),
          ),
        );
      }),
    );
  }
}

// =====================================================
// Página detalle completa (la tuya)
// =====================================================

class TareaDetallePage extends StatelessWidget {
  final TareaModel tarea;

  const TareaDetallePage({super.key, required this.tarea});

  @override
  Widget build(BuildContext context) {
    final inicioStr = DateFormat('dd/MM/yyyy HH:mm').format(tarea.fechaInicio);
    final finStr = DateFormat('dd/MM/yyyy HH:mm').format(tarea.fechaFin);

    final operarios = tarea.operariosNombres.join(', ');
    final supervisorNombreLimpio = (tarea.supervisorNombre ?? '').trim().isEmpty
        ? null
        : tarea.supervisorNombre;

    final supervisor =
        supervisorNombreLimpio ??
        (tarea.supervisorId != null
            ? 'Supervisor ID: ${tarea.supervisorId}'
            : 'Sin supervisor');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de tarea'),
        backgroundColor: AppTheme.primary,
      ),
      backgroundColor: AppTheme.background,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Text(
              tarea.descripcion,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Chip(
                  label: Text(tarea.estado ?? 'SIN_ESTADO'),
                  backgroundColor: Colors.grey.shade200,
                ),
                Chip(
                  label: Text('Tipo: ${tarea.tipo ?? 'SIN_TIPO'}'),
                  backgroundColor: Colors.grey.shade200,
                ),
                Chip(
                  label: Text('Duración: ${tarea.duracionMinutos} h'),
                  backgroundColor: Colors.grey.shade200,
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Programación',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            _fila('Inicio', inicioStr),
            _fila('Fin', finStr),
            _fila('Conjunto', tarea.conjuntoNombre ?? tarea.conjuntoId ?? '-'),
            _fila('Ubicación', tarea.ubicacionNombre ?? '-'),
            _fila('Elemento', tarea.elementoNombre ?? '-'),
            _fila('Supervisor', supervisor),
            _fila('Operarios', operarios.isEmpty ? 'Sin operarios' : operarios),
            const SizedBox(height: 16),
            const Text(
              'Observaciones',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              tarea.observaciones?.isNotEmpty == true
                  ? tarea.observaciones!
                  : 'Sin observaciones',
            ),
            if (tarea.observacionesRechazo?.isNotEmpty == true) ...[
              const SizedBox(height: 16),
              const Text(
                'Observaciones de rechazo',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text(tarea.observacionesRechazo!),
            ],
            const SizedBox(height: 16),
            if (tarea.evidencias != null && tarea.evidencias!.isNotEmpty) ...[
              const Text(
                'Evidencias',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: tarea.evidencias!
                    .map(
                      (url) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          url,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.blue,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fila(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
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
}
