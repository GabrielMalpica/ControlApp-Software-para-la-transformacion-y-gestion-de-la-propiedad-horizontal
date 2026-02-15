import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/inventario_api.dart';
import 'package:flutter_application_1/api/operario_api.dart';

import '../api/tarea_api.dart';
import '../model/inventario_item_model.dart';
import '../model/tarea_model.dart';
import '../service/session_service.dart';
import '../service/theme.dart';
import '../widgets/cerrar_tarea_sheet.dart';
import 'editar_tarea_page.dart';

class TareasPage extends StatefulWidget {
  final String nit;

  const TareasPage({super.key, required this.nit});

  @override
  State<TareasPage> createState() => _TareasPageState();
}

class _TareasPageState extends State<TareasPage> {
  final TareaApi _tareaApi = TareaApi();
  final OperarioApi _operarioApi = OperarioApi();
  final InventarioApi _inventarioApi = InventarioApi();
  final SessionService _session = SessionService();

  bool _cargando = true;
  String? _error;
  List<TareaModel> _tareas = [];
  String? _rol;
  int? _operarioId;

  String? _rol;
  int? _operarioId;

  // filtros para vista operario
  String _filtroOperario = 'HOY';

  String? _rol;
  int? _operarioId;
  String _filtroOperario = 'HOY';

  @override
  void initState() {
    super.initState();
    _cargarSesion();
    _cargarTareas();
  }

  Future<void> _cargarSesion() async {
    final rol = await _session.getRol();
    final userId = await _session.getUserId();
    if (!mounted) return;
    setState(() {
      _rol = rol;
      _operarioId = int.tryParse(userId ?? '');
    });
  }

  Future<void> _cargarTareas() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      List<TareaModel> lista;

      if (_esOperario()) {
        if (_operarioId == null) {
          throw Exception(
            'No se pudo identificar el operario (userId inválido en sesión).',
          );
        }
        lista = await _operarioApi.listarTareasOperario(
          operarioId: _operarioId!,
        );
      } else {
        lista = await _tareaApi.listarTareasPorConjunto(widget.nit);
      }

      if (!mounted) return;
      setState(() => _tareas = lista);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _eliminarTarea(TareaModel tarea) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar tarea'),
        content: Text('¿Seguro que deseas eliminar la tarea:\n\n"${tarea.descripcion}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

  bool _esVencida(TareaModel t) {
    final e = (t.estado ?? '').toUpperCase();
    if (e == 'APROBADA' || e == 'COMPLETADA') return false;
    return t.fechaFin.isBefore(DateTime.now());
  }

    try {
      await _tareaApi.eliminarTarea(tarea.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tarea eliminada correctamente')),
      );
      await _cargarTareas();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al eliminar tarea: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
    final entries = map.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return {for (final e in entries) e.key: e.value};
  }

  String _fmtDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yy = d.year.toString();
    return '$dd/$mm/$yy';
  }

  Color _colorPorEstado(String? estado) {
    switch ((estado ?? '').toUpperCase()) {
      case 'ASIGNADA':
        return Colors.orange;
      case 'EN_PROCESO':
        return Colors.blue;
      case 'PENDIENTE_APROBACION':
        return Colors.deepPurple;
      case 'COMPLETADA':
      case 'APROBADA':
        return Colors.green;
      case 'RECHAZADA':
      case 'NO_COMPLETADA':
      case 'CANCELADA':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _labelEstado(String? estado) {
    switch ((estado ?? '').toUpperCase()) {
      case 'ASIGNADA':
        return 'Asignada';
      case 'EN_PROCESO':
        return 'En proceso';
      case 'PENDIENTE_APROBACION':
        return 'Pendiente aprobación';
      case 'COMPLETADA':
        return 'Completada';
      case 'RECHAZADA':
        return 'Rechazada';
      case 'CANCELADA':
        return 'Cancelada';
      default:
        return 'Sin estado';
    }
  }

  String _formatearFecha(DateTime f) {
    final d = f.day.toString().padLeft(2, '0');
    final m = f.month.toString().padLeft(2, '0');
    final y = f.year.toString();
    final hh = f.hour.toString().padLeft(2, '0');
    final mm = f.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $hh:$mm';
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _esVencida(TareaModel t) {
    final estado = (t.estado ?? '').toUpperCase();
    if (estado == 'APROBADA' || estado == 'COMPLETADA') return false;
    return t.fechaFin.isBefore(DateTime.now());
  }

  bool _esPendiente(TareaModel t) {
    final estado = (t.estado ?? '').toUpperCase();
    return estado == 'ASIGNADA' || estado == 'EN_PROCESO';
  }

  List<TareaModel> get _tareasFiltradasOperario {
    final now = DateTime.now();
    final hoy = _dayOnly(now);

    return _tareas.where((t) {
      switch (_filtroOperario) {
        case 'HOY':
          return _dayOnly(t.fechaInicio) == hoy || _dayOnly(t.fechaFin) == hoy;
        case 'PENDIENTES':
          return _esPendiente(t);
        case 'VENCIDAS':
          return _esVencida(t);
        case 'RECHAZADAS':
          return (t.estado ?? '').toUpperCase() == 'RECHAZADA';
        case 'PENDIENTE_APROBACION':
          return (t.estado ?? '').toUpperCase() == 'PENDIENTE_APROBACION';
        case 'TODAS':
        default:
          return true;
      }
    }).toList()
      ..sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));
  }

  Map<DateTime, List<TareaModel>> _agruparPorDia(List<TareaModel> input) {
    final out = <DateTime, List<TareaModel>>{};
    for (final t in input) {
      final k = _dayOnly(t.fechaInicio);
      out.putIfAbsent(k, () => []).add(t);
    }

    final sorted = out.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return {for (final e in sorted) e.key: e.value};
  }

  bool _esOperario() => (_rol ?? '').toLowerCase() == 'operario';

  bool _puedeCerrar(TareaModel t) {
    final e = (t.estado ?? '').toUpperCase();
    return e == 'ASIGNADA' || e == 'EN_PROCESO' || e == 'COMPLETADA';
  }

  Future<void> _cerrarComoOperario(TareaModel t) async {
    if (_operarioId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo resolver el operario de sesión.')),
      );
      return;
    }

    List<InventarioItemResponse> inventarioRaw = [];
    try {
      inventarioRaw = await _inventarioApi.listarInventarioConjunto(widget.nit);
    } catch (_) {}

    final result = await showModalBottomSheet<CerrarTareaResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CerrarTareaSheet(
        tarea: t,
        inventario: inventarioRaw,
      ),
    );

    if (result == null) return;

    try {
      await _operarioApi.cerrarTareaConEvidencias(
        operarioId: _operarioId!,
        tareaId: t.id,
        observaciones: result.observaciones,
        insumosUsados: result.insumosUsados,
        evidenciaPaths: const [],
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Tarea cerrada por operario. Quedó PENDIENTE_APROBACION.'),
        ),
      );
      await _cargarTareas();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error cerrando tarea: $e')),
      );
    }
  }

  Widget _taskTile(TareaModel t) {
    final c = _estadoColor(t.estado);
    final estado = (t.estado ?? 'SIN_ESTADO').replaceAll('_', ' ');

  Future<void> _cerrarComoOperario(TareaModel t) async {
    if (_operarioId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo resolver el operario de sesión.')),
      );
      return;
    }

    List<InventarioItemResponse> inventarioRaw = [];
    try {
      inventarioRaw = await _inventarioApi.listarInventarioConjunto(widget.nit);
    } catch (_) {}

    final result = await showModalBottomSheet<CerrarTareaResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CerrarTareaSheet(tarea: t, inventario: inventarioRaw),
    );

    if (result == null) return;

    try {
      await _operarioApi.cerrarTareaConEvidencias(
        operarioId: _operarioId!,
        tareaId: t.id,
        observaciones: result.observaciones,
        insumosUsados: result.insumosUsados,
        evidenciaPaths: const [],
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Tarea cerrada por operario. Quedó PENDIENTE_APROBACION.'),
        ),
      );
      await _cargarTareas();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error cerrando tarea: $e')),
      );
    }
  }

  Widget _tileTarea(TareaModel tarea) {
    final colorEstado = _colorPorEstado(tarea.estado);
    final labelEstado = _labelEstado(tarea.estado);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: ListTile(
        contentPadding: const EdgeInsets.all(14),
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: colorEstado.withOpacity(0.14),
          child: Icon(Icons.assignment_turned_in, color: colorEstado),
        ),
        title: Text(
          tarea.descripcion,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('🕒 ${_formatearFecha(tarea.fechaInicio)} - ${_formatearFecha(tarea.fechaFin)}'),
              if (tarea.ubicacionNombre != null || tarea.elementoNombre != null)
                Text(
                  '📍 ${tarea.ubicacionNombre ?? '-'} / ${tarea.elementoNombre ?? '-'}',
                ),
              if (_esVencida(tarea))
                const Text(
                  '⚠️ Tarea vencida',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.circle, size: 9, color: colorEstado),
                  const SizedBox(width: 6),
                  Text(
                    labelEstado,
                    style: TextStyle(color: colorEstado, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        ),
        trailing: _esOperario()
            ? (_puedeCerrar(tarea)
                  ? IconButton(
                      tooltip: 'Cerrar tarea',
                      icon: const Icon(Icons.task_alt, color: Colors.green),
                      onPressed: () => _cerrarComoOperario(tarea),
                    )
                  : null)
            : IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                tooltip: 'Eliminar tarea',
                onPressed: () => _eliminarTarea(tarea),
              ),
        onTap: _esOperario()
            ? null
            : () async {
                final actualizado = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditarTareaPage(nit: widget.nit, tarea: tarea),
                  ),
                );
                if (actualizado == true) _cargarTareas();
              },
      ),
    );
  }

  Widget _filtrosOperario() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Filtros rápidos',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final f in const [
                  'HOY',
                  'PENDIENTES',
                  'VENCIDAS',
                  'RECHAZADAS',
                  'PENDIENTE_APROBACION',
                  'TODAS',
                ])
                  ChoiceChip(
                    label: Text(f.replaceAll('_', ' ')),
                    selected: _filtroOperario == f,
                    onSelected: (_) => setState(() => _filtroOperario = f),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _listaOperario() {
    final filtradas = _tareasFiltradasOperario;
    if (filtradas.isEmpty) {
      return const Center(
        child: Text('No hay tareas para el filtro seleccionado.'),
      );
    }

    final grouped = _agruparPorDia(filtradas);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      children: [
        _filtrosOperario(),
        const SizedBox(height: 10),
        const Text(
          'Tu TODO de tareas por día',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 8),
        ...grouped.entries.map((entry) {
          final day = entry.key;
          final tasks = entry.value;
          final fecha =
              '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}/${day.year}';
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ExpansionTile(
              initiallyExpanded: true,
              title: Text('$fecha • ${tasks.length} tarea(s)'),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    children: tasks.map(_tileTarea).toList(),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _listaGeneral() {
    if (_tareas.isEmpty) {
      return const Center(
        child: Text('No hay tareas asignadas para este conjunto.'),
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _tareas.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _tileTarea(_tareas[i]),
    );
  }

  Widget _cuerpo() {
    if (_cargando) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 40),
              const SizedBox(height: 12),
              Text('Error al cargar tareas:\n$_error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _cargarTareas,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargarTareas,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _tareas.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final tarea = _tareas[index];
          final colorEstado = _colorPorEstado(tarea.estado);
          final labelEstado = _labelEstado(tarea.estado);

          return Card(
            margin: const EdgeInsets.only(bottom: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 3,
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: CircleAvatar(
                radius: 22,
                backgroundColor: colorEstado.withOpacity(0.15),
                child: Icon(Icons.assignment, color: colorEstado, size: 24),
              ),
              title: Text(
                tarea.descripcion,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "📅 ${_formatearFecha(tarea.fechaInicio)}"
                      " → ${_formatearFecha(tarea.fechaFin)}  "
                      "• ⏱ ${tarea.duracionMinutos} h",
                    ),
                    const SizedBox(height: 4),
                    Text("👷 Operarios: ${_resumenOperarios(tarea)}"),
                    if (tarea.supervisorNombre != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          "🧑‍💼 Supervisor: ${tarea.supervisorNombre}",
                        ),
                      ),
                    if (tarea.observaciones != null &&
                        tarea.observaciones!.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          "📝 ${tarea.observaciones}",
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.circle, size: 10, color: colorEstado),
                        const SizedBox(width: 6),
                        Text(
                          labelEstado,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: colorEstado,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              trailing: _esOperario()
                  ? (_puedeCerrar(tarea)
                        ? IconButton(
                            icon: const Icon(Icons.task_alt, color: Colors.green),
                            tooltip: 'Cerrar tarea',
                            onPressed: () => _cerrarComoOperario(tarea),
                          )
                        : null)
                  : IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      tooltip: 'Eliminar tarea',
                      onPressed: () => _eliminarTarea(tarea),
                    ),
              // Tap para editar
              onTap: () async {
                final actualizado = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        EditarTareaPage(nit: widget.nit, tarea: tarea),
                  ),
                );

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.primary;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: primary,
        title: Text(
          _esOperario()
              ? 'Mis tareas'
              : 'Tareas - Conjunto ${widget.nit}',
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(onPressed: _cargarTareas, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cuerpo(),
    );
  }
}
