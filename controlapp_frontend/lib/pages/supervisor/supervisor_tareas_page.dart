import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/supervisor_api.dart';
import 'package:flutter_application_1/api/inventario_api.dart';
import 'package:flutter_application_1/model/inventario_item_model.dart';
import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/pdf/cronograma_pdf.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:intl/intl.dart';
import 'package:flutter_application_1/widgets/cerrar_tarea_sheet.dart';

class SupervisorTareasPage extends StatefulWidget {
  final String nit; // conjunto

  const SupervisorTareasPage({super.key, required this.nit});

  @override
  State<SupervisorTareasPage> createState() => _SupervisorTareasPageState();
}

class _SupervisorTareasPageState extends State<SupervisorTareasPage> {
  final _api = SupervisorApi();
  final _inventarioApi = InventarioApi();

  bool _loading = true;
  String? _error;

  List<TareaModel> _tareas = [];

  // filtros
  String _filtroEstado = 'TODOS';
  String _filtroOperario = 'TODOS';
  List<String> _operariosDisponibles = [];

  int _semanaImprimir = 1;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  // Lunes como inicio
  DateTime _startOfWeekMonday(DateTime d) {
    final dd = _dayOnly(d);
    final diff = dd.weekday - DateTime.monday; // 0 si es lunes
    return dd.subtract(Duration(days: diff));
  }

  Future<void> _cargar() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _api.listarTareas(conjuntoId: widget.nit);
      _tareas = data;
      _reconstruirOperarios();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _reconstruirOperarios() {
    final setOps = <String>{};
    for (final t in _tareas) {
      for (final n in t.operariosNombres) {
        final s = n.trim();
        if (s.isNotEmpty) setOps.add(s);
      }
    }
    _operariosDisponibles = setOps.toList()..sort();
  }

  List<TareaModel> get _filtradas {
    return _tareas.where((t) {
      if (_filtroEstado != 'TODOS') {
        if ((t.estado ?? '') != _filtroEstado) return false;
      }
      if (_filtroOperario != 'TODOS') {
        if (!t.operariosNombres.contains(_filtroOperario)) return false;
      }
      return true;
    }).toList();
  }

  Color _colorEstado(String? e) {
    final s = (e ?? '').toUpperCase();
    switch (s) {
      case 'PENDIENTE_APROBACION':
        return Colors.orange;
      case 'APROBADA':
        return Colors.green;
      case 'RECHAZADA':
        return Colors.red;
      case 'EN_PROCESO':
        return Colors.blue;
      case 'ASIGNADA':
        return Colors.indigo;
      case 'NO_COMPLETADA':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  bool _puedeCerrar(TareaModel t) {
    final e = (t.estado ?? '').toUpperCase();
    return e == 'ASIGNADA' || e == 'EN_PROCESO' || e == 'COMPLETADA';
  }

  Future<void> _accionCerrar(TareaModel t) async {
    List<InventarioItemResponse> inventario = [];
    try {
      inventario = await _inventarioApi.listarInventarioConjunto(widget.nit);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⚠️ No pude cargar inventario: $e')),
      );
      // seguimos con inventario vacío
    }

    final res = await showModalBottomSheet<CerrarTareaResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CerrarTareaSheet(tarea: t, inventario: inventario),
    );

    if (res == null) return;

    try {
      await _api.cerrarTareaConEvidencias(
        tareaId: t.id,
        observaciones: res.observaciones,
        insumosUsados: res.insumosUsados,
        evidencias: res.evidencias,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Tarea cerrada. Quedó PENDIENTE_APROBACION.'),
        ),
      );
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('❌ Error cerrando: $e')));
    }
  }

  DateTime _weekStartOfMonthByIndex(int year, int month, int weekIndex) {
    final firstDay = DateTime(year, month, 1);
    final firstWeekStart = _startOfWeekMonday(firstDay);
    return firstWeekStart.add(Duration(days: 7 * (weekIndex - 1)));
  }

  Future<void> _imprimirSemanaSeleccionada() async {
    if (_filtroOperario == 'TODOS') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un operario en los filtros')),
      );
      return;
    }

    final now = DateTime.now();
    final year = now.year;
    final month = now.month;

    final weekStart = _weekStartOfMonthByIndex(year, month, _semanaImprimir);
    final weekEnd = weekStart.add(const Duration(days: 6)); // L-D

    final tareasSemana = _filtradas.where((t) {
      final d = _dayOnly(t.fechaInicio);
      return !d.isBefore(_dayOnly(weekStart)) && !d.isAfter(_dayOnly(weekEnd));
    }).toList();

    final conjuntoNombre = tareasSemana.isNotEmpty
        ? (tareasSemana.first.conjuntoNombre ?? widget.nit)
        : widget.nit;

    final payload = <String, dynamic>{
      'operarioNombre': _filtroOperario,
      'operarioId': '',
      'conjuntoNombre': conjuntoNombre,
      'anio': year,
      'mes': month,
      'semanaDelMes': _semanaImprimir,
      'weekStart': DateFormat('yyyy-MM-dd').format(weekStart),
      'weekEnd': DateFormat('yyyy-MM-dd').format(weekEnd),
      'tareas': tareasSemana
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
          children: [
            Row(
              children: [
                const Text(
                  'Filtros',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() {
                    _filtroEstado = 'TODOS';
                    _filtroOperario = 'TODOS';
                  }),
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('Limpiar'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _filtroEstado,
                    decoration: const InputDecoration(
                      labelText: 'Estado',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'TODOS', child: Text('Todos')),
                      DropdownMenuItem(
                        value: 'ASIGNADA',
                        child: Text('Asignada'),
                      ),
                      DropdownMenuItem(
                        value: 'EN_PROCESO',
                        child: Text('En proceso'),
                      ),
                      DropdownMenuItem(
                        value: 'COMPLETADA',
                        child: Text('Completada'),
                      ),
                      DropdownMenuItem(
                        value: 'PENDIENTE_APROBACION',
                        child: Text('Pendiente aprobación'),
                      ),
                      DropdownMenuItem(
                        value: 'APROBADA',
                        child: Text('Aprobada'),
                      ),
                      DropdownMenuItem(
                        value: 'RECHAZADA',
                        child: Text('Rechazada'),
                      ),
                      DropdownMenuItem(
                        value: 'NO_COMPLETADA',
                        child: Text('No completada'),
                      ),
                    ],
                    onChanged: (v) =>
                        setState(() => _filtroEstado = v ?? 'TODOS'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _filtroOperario,
                    decoration: const InputDecoration(
                      labelText: 'Operario',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'TODOS',
                        child: Text('Todos'),
                      ),
                      ..._operariosDisponibles.map(
                        (o) => DropdownMenuItem(value: o, child: Text(o)),
                      ),
                    ],
                    onChanged: (v) =>
                        setState(() => _filtroOperario = v ?? 'TODOS'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _semanaImprimir,
                    decoration: const InputDecoration(
                      labelText: 'Semana a imprimir',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: List.generate(6, (i) => i + 1)
                        .map(
                          (w) => DropdownMenuItem(
                            value: w,
                            child: Text('Semana $w'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _semanaImprimir = v ?? 1),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(TareaModel t) {
    final ini = t.fechaInicio.toLocal();
    final fin = t.fechaFin.toLocal();
    final rango =
        "${DateFormat('dd/MM HH:mm', 'es').format(ini)} - ${DateFormat('HH:mm', 'es').format(fin)}";

    final estado = (t.estado ?? '—').toUpperCase();
    final operarios = t.operariosNombres.isEmpty
        ? 'Sin asignar'
        : t.operariosNombres.join(', ');
    final ubic = t.ubicacionNombre ?? 'Ubicación ${t.ubicacionId}';

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.descripcion,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _colorEstado(t.estado).withOpacity(0.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: _colorEstado(t.estado).withOpacity(0.35),
                    ),
                  ),
                  child: Text(
                    estado,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _colorEstado(t.estado),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "📍 $ubic",
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            Text(
              "⏱ $rango • ${t.duracionBonita}",
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            Text(
              "👷 $operarios",
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _puedeCerrar(t) ? () => _accionCerrar(t) : null,
                  icon: const Icon(Icons.task_alt, size: 18),
                  label: const Text('Cerrar tarea'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Nota: El veredicto (aprobar/rechazar) lo hace el Jefe de Operaciones.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
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
          'Tareas (Supervisor)',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'Imprimir semana actual (según filtros)',
            onPressed: _imprimirSemanaSeleccionada,
            icon: const Icon(Icons.print, color: Colors.white),
          ),
          IconButton(
            onPressed: _cargar,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
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
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _buildFiltros(),
                  const SizedBox(height: 12),
                  if (_filtradas.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 50),
                      child: Center(
                        child: Text('No hay tareas con esos filtros.'),
                      ),
                    )
                  else
                    ..._filtradas.map(_tile),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}
