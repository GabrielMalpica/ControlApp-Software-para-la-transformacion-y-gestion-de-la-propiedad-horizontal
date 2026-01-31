import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/supervisor_api.dart';
import 'package:flutter_application_1/api/inventario_api.dart';
import 'package:flutter_application_1/model/inventario_item_model.dart';
import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/pdf/cronograma_pdf.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:intl/intl.dart';

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
        return Colors.orange.shade800;
      case 'APROBADA':
        return Colors.green.shade700;
      case 'RECHAZADA':
        return Colors.red.shade800;
      case 'EN_PROCESO':
        return Colors.blue.shade700;
      case 'ASIGNADA':
        return Colors.indigo.shade700;
      case 'NO_COMPLETADA':
        return Colors.red.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  bool _puedeCerrar(TareaModel t) {
    final e = (t.estado ?? '').toUpperCase();
    return e == 'ASIGNADA' || e == 'EN_PROCESO' || e == 'COMPLETADA';
  }

  Future<void> _accionCerrar(TareaModel t) async {
    List<InventarioItemResponse> inventario;
    try {
      inventario = await _inventarioApi.listarInventarioConjunto(widget.nit);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⚠️ No pude cargar inventario: $e')),
      );
      // igual dejamos cerrar sin insumos si quieres; pero mejor permitir cerrar con inventario vacío:
      inventario = [];
    }

    // 2) Abrir sheet
    final res = await showModalBottomSheet<_CerrarResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CerrarTareaSheet(tarea: t, inventario: inventario),
    );

    if (res == null) return;

    try {
      // ✅ fase 1: multipart, pero sin fotos reales todavía (evidenciaPaths vacío)
      await _api.cerrarTareaConEvidencias(
        tareaId: t.id,
        observaciones: res.observaciones,
        insumosUsados: res.insumosUsados,
        evidenciaPaths: const [],
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
    // Si quieres L-S: weekStart + 5

    // Filtrar tareas del operario (ya vienen filtradas por _filtradas)
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

            // ✅ SOLO CERRAR
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

// ====================== cerrar tarea sheet ======================

class _CerrarResult {
  final String? observaciones;

  /// [{insumoId: 1, cantidad: 0.3}, ...]
  final List<Map<String, num>> insumosUsados;

  _CerrarResult({required this.insumosUsados, this.observaciones});
}

class _CerrarTareaSheet extends StatefulWidget {
  final TareaModel tarea;
  final List<InventarioItemResponse> inventario;

  const _CerrarTareaSheet({required this.tarea, required this.inventario});

  @override
  State<_CerrarTareaSheet> createState() => _CerrarTareaSheetState();
}

class _CerrarTareaSheetState extends State<_CerrarTareaSheet> {
  final _obsCtrl = TextEditingController();

  // filas de consumo
  final List<_ConsumoRow> _rows = [];

  @override
  void initState() {
    super.initState();
    if (widget.inventario.isNotEmpty) _rows.add(_ConsumoRow());
  }

  @override
  void dispose() {
    _obsCtrl.dispose();
    for (final r in _rows) {
      r.qtyCtrl.dispose();
    }
    super.dispose();
  }

  List<Map<String, num>> _buildInsumosUsados() {
    final out = <Map<String, num>>[];
    for (final r in _rows) {
      if (r.insumoId == null) continue;
      final qty = num.tryParse(r.qtyCtrl.text.trim());
      if (qty == null || qty <= 0) continue;
      out.add({'insumoId': r.insumoId!, 'cantidad': qty});
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final alto = MediaQuery.of(context).size.height * 0.82;

    return SizedBox(
      height: alto,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Cerrar tarea',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Text(
              widget.tarea.descripcion,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),

            // ✅ Evidencias simuladas (no se mandan todavía)
            Card(
              elevation: 0,
              color: Colors.amber.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  '📸 Evidencias: por ahora simuladas (PC). '
                  'Más adelante conectamos selector de archivos/cámara.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ✅ Maquinaria asignada a la tarea (solo mostrar)
            if (widget.tarea.maquinariasAsignadas.isNotEmpty) ...[
              const Text(
                'Maquinaria asignada',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.tarea.maquinariasAsignadas.map((m) {
                  return Chip(
                    avatar: const Icon(Icons.precision_manufacturing, size: 18),
                    label: Text(m.nombre),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ] else ...[
              Text(
                'Maquinaria asignada: ninguna.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
            ],

            // ✅ Herramientas asignadas a la tarea (solo mostrar)
            if (widget.tarea.herramientasAsignadas.isNotEmpty) ...[
              const Text(
                'Herramientas asignadas',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Column(
                children: widget.tarea.herramientasAsignadas.map((h) {
                  final qty = h.cantidad;
                  final estado = (h.estado ?? '').toUpperCase();

                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.handyman, size: 20),
                    title: Text(h.nombre),
                    subtitle: estado.isEmpty ? null : Text('Estado: $estado'),
                    trailing: Text('x$qty'),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ] else ...[
              Text(
                'Herramientas asignadas: ninguna.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
            ],

            // ✅ Insumos usados
            Row(
              children: [
                const Text(
                  'Insumos usados',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: widget.inventario.isEmpty
                      ? null
                      : () => setState(() => _rows.add(_ConsumoRow())),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Agregar'),
                ),
              ],
            ),

            if (widget.inventario.isEmpty)
              Text(
                'No hay inventario disponible (o no se pudo cargar). Puedes cerrar sin insumos.',
                style: TextStyle(color: Colors.grey.shade700),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: _rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final row = _rows[i];

                    InventarioItemResponse? item;
                    if (row.insumoId != null) {
                      try {
                        item = widget.inventario.firstWhere(
                          (x) => x.insumoId == row.insumoId,
                        );
                      } catch (_) {
                        item = null;
                      }
                    }

                    return Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            DropdownButtonFormField<int>(
                              value: row.insumoId,
                              decoration: const InputDecoration(
                                labelText: 'Insumo',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: widget.inventario.map((x) {
                                return DropdownMenuItem<int>(
                                  value: x.insumoId,
                                  child: Text(
                                    '${x.nombre} (${x.cantidad} ${x.unidad})',
                                  ),
                                );
                              }).toList(),
                              onChanged: (v) =>
                                  setState(() => row.insumoId = v),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: row.qtyCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: 'Cantidad usada',
                                hintText: item == null
                                    ? 'Ej: 0.5'
                                    : 'En ${item.unidad}',
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                if (item != null)
                                  Expanded(
                                    child: Text(
                                      'Stock: ${item.cantidad} ${item.unidad}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                IconButton(
                                  tooltip: 'Quitar',
                                  onPressed: () => setState(() {
                                    row.qtyCtrl.dispose();
                                    _rows.removeAt(i);
                                  }),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

            const SizedBox(height: 10),
            TextField(
              controller: _obsCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Observaciones (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(
                    context,
                    _CerrarResult(
                      insumosUsados: _buildInsumosUsados(),
                      observaciones: _obsCtrl.text.trim().isEmpty
                          ? null
                          : _obsCtrl.text.trim(),
                    ),
                  );
                },
                icon: const Icon(Icons.send),
                label: const Text('Cerrar y enviar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsumoRow {
  int? insumoId;
  final TextEditingController qtyCtrl = TextEditingController();
}
