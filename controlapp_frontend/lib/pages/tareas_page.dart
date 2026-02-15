import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/inventario_api.dart';
import 'package:flutter_application_1/api/operario_api.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../service/app_constants.dart';
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
  String _filtroOperario = 'HOY';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _cargarSesion();
    await _cargarTareas();
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

  bool _esOperario() => (_rol ?? '').toLowerCase() == 'operario';

  Future<void> _cargarTareas() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      List<TareaModel> lista;
      if (_esOperario()) {
        if (_operarioId == null) {
          throw Exception('No se pudo identificar el operario en sesión.');
        }
        lista = await _listarTareasOperarioDirecto(_operarioId!);
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

  Future<List<TareaModel>> _listarTareasOperarioDirecto(int operarioId) async {
    final token = await _session.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('Token requerido (no hay sesión guardada)');
    }

    final uri = Uri.parse(
      '${AppConstants.baseUrl}/operario/operarios/$operarioId/tareas',
    );

    final resp = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'x-empresa-id': AppConstants.empresaNit,
        'Accept': 'application/json',
      },
    );

    if (resp.statusCode != 200) {
      throw Exception(
        'Error al listar actividades del operario: ${resp.statusCode} - ${resp.body}',
      );
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! List) return [];

    return decoded
        .map((e) => TareaModel.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _esVencida(TareaModel t) {
    final e = (t.estado ?? '').toUpperCase();
    if (e == 'APROBADA' || e == 'COMPLETADA') return false;
    return t.fechaFin.isBefore(DateTime.now());
  }

  bool _esPendiente(TareaModel t) {
    final e = (t.estado ?? '').toUpperCase();
    return e == 'ASIGNADA' || e == 'EN_PROCESO';
  }

  List<TareaModel> get _tareasFiltradasOperario {
    final hoy = _dayOnly(DateTime.now());

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

  Map<DateTime, List<TareaModel>> _agruparPorDia(List<TareaModel> items) {
    final map = <DateTime, List<TareaModel>>{};
    for (final t in items) {
      final key = _dayOnly(t.fechaInicio);
      map.putIfAbsent(key, () => []).add(t);
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

  String _fmtDateTime(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '${_fmtDate(d)} $hh:$mi';
  }

  Color _estadoColor(String? estado) {
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

    List<InventarioItemResponse> inventario = [];
    try {
      inventario = await _inventarioApi.listarInventarioConjunto(widget.nit);
    } catch (_) {}

    final result = await showModalBottomSheet<CerrarTareaResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CerrarTareaSheet(tarea: t, inventario: inventario),
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
          content: Text('✅ Tarea cerrada. Quedó pendiente aprobación.'),
        ),
      );
      await _cargarTareas();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('❌ Error cerrando tarea: $e')));
    }
  }

  Widget _taskTile(TareaModel t) {
    final c = _estadoColor(t.estado);
    final estado = (t.estado ?? 'SIN_ESTADO').replaceAll('_', ' ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(t.descripcion, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🕒 ${_fmtDateTime(t.fechaInicio)} → ${_fmtDateTime(t.fechaFin)}'),
            if (t.ubicacionNombre != null || t.elementoNombre != null)
              Text('📍 ${t.ubicacionNombre ?? '-'} / ${t.elementoNombre ?? '-'}'),
            if (_esVencida(t))
              const Text(
                '⚠️ Vencida',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
            Row(
              children: [
                Icon(Icons.circle, size: 9, color: c),
                const SizedBox(width: 6),
                Text(estado, style: TextStyle(color: c, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
        trailing: _esOperario()
            ? (_puedeCerrar(t)
                  ? IconButton(
                      tooltip: 'Cerrar tarea',
                      icon: const Icon(Icons.task_alt, color: Colors.green),
                      onPressed: () => _cerrarComoOperario(t),
                    )
                  : null)
            : IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _eliminarTarea(t),
              ),
        onTap: _esOperario()
            ? null
            : () async {
                final updated = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditarTareaPage(nit: widget.nit, tarea: t),
                  ),
                );
                if (updated == true) _cargarTareas();
              },
      ),
    );
  }

  Future<void> _eliminarTarea(TareaModel tarea) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar tarea'),
        content: Text('¿Seguro que deseas eliminar "${tarea.descripcion}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (ok != true) return;
    try {
      await _tareaApi.eliminarTarea(tarea.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tarea eliminada correctamente')),
      );
      await _cargarTareas();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al eliminar tarea: $e')));
    }
  }

  Widget _buildOperarioBody() {
    final list = _tareasFiltradasOperario;
    if (list.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [_filters(), const SizedBox(height: 16), const Text('No hay actividades para este filtro.')],
      );
    }

    final grouped = _agruparPorDia(list);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      children: [
        _filters(),
        const SizedBox(height: 10),
        const Text('TODO por día', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 10),
        ...grouped.entries.map((e) {
          final day = e.key;
          final tasks = e.value;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ExpansionTile(
              initiallyExpanded: true,
              title: Text('${_fmtDate(day)} • ${tasks.length} actividad(es)'),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(children: tasks.map(_taskTile).toList()),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _filters() {
    const opts = [
      'HOY',
      'PENDIENTES',
      'VENCIDAS',
      'RECHAZADAS',
      'PENDIENTE_APROBACION',
      'TODAS',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final f in opts)
              ChoiceChip(
                label: Text(f.replaceAll('_', ' ')),
                selected: _filtroOperario == f,
                onSelected: (_) => setState(() => _filtroOperario = f),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneralBody() {
    if (_tareas.isEmpty) {
      return const Center(child: Text('No hay tareas asignadas para este conjunto.'));
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _tareas.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _taskTile(_tareas[i]),
    );
  }

  Widget _body() {
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
              Text('Error al cargar actividades:\n$_error', textAlign: TextAlign.center),
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
      child: _esOperario() ? _buildOperarioBody() : _buildGeneralBody(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: Text(
          _esOperario() ? 'Mis actividades' : 'Tareas - Conjunto ${widget.nit}',
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(onPressed: _cargarTareas, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _body(),
    );
  }
}
