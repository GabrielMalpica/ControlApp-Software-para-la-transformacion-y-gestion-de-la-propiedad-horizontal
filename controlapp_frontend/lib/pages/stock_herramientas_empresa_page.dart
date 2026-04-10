import 'package:flutter/material.dart';

import '../api/herramienta_api.dart';
import '../model/herramienta_model.dart';
import '../service/app_constants.dart';
import '../service/app_error.dart';
import '../service/theme.dart';
import 'package:flutter_application_1/service/app_feedback.dart';

class StockHerramientasEmpresaPage extends StatefulWidget {
  final String? empresaId;

  const StockHerramientasEmpresaPage({super.key, this.empresaId});

  @override
  State<StockHerramientasEmpresaPage> createState() =>
      _StockHerramientasEmpresaPageState();
}

class _StockHerramientasEmpresaPageState
    extends State<StockHerramientasEmpresaPage> {
  final _api = HerramientaApi();

  bool _loading = false;
  String? _error;
  String _search = '';
  int _rowsPerPage = 8;
  List<HerramientaStockResponse> _items = [];

  String get _empresaId => widget.empresaId ?? AppConstants.empresaNit;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final raw = await _api.listarStockEmpresa(empresaId: _empresaId);
      final parsed = raw
          .whereType<Map>()
          .map(
            (e) => HerramientaStockResponse.fromJson(e.cast<String, dynamic>()),
          )
          .toList();

      if (!mounted) return;
      setState(() => _items = parsed);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AppError.messageOf(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<HerramientaStockResponse> get _filtrados {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return List.of(_items);

    return _items.where((item) {
      return [
        item.nombre,
        item.unidad,
        item.categoria.label,
        item.modoControl.label,
        item.estado.label,
      ].join(' ').toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _ajustar(
    HerramientaStockResponse item, {
    required bool sumar,
  }) async {
    final ctrl = TextEditingController();

    try {
      final cantidad = await showDialog<num>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(sumar ? 'Agregar stock' : 'Descontar stock'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.nombre,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text('Estado actual: ${item.estado.label}'),
              Text('Disponible: ${item.cantidad} ${item.unidad}'),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: sumar
                      ? 'Cantidad a agregar'
                      : 'Cantidad a descontar',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = num.tryParse(ctrl.text.trim());
                if (parsed == null || parsed <= 0) return;
                Navigator.pop(dialogContext, parsed);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      );

      if (cantidad == null) return;

      await _api.ajustarStockEmpresa(
        empresaId: _empresaId,
        herramientaId: item.herramientaId,
        delta: sumar ? cantidad : -cantidad,
        estado: item.estado.backendValue,
      );

      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text('Stock actualizado para ${item.nombre}.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text(AppError.messageOf(e))),
      );
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _cambiarEstado(HerramientaStockResponse item) async {
    final cantidadCtrl = TextEditingController(text: item.cantidad.toString());
    final estadosDisponibles = EstadoHerramientaStock.values
        .where((estado) => estado != item.estado)
        .toList();
    var estadoNuevo = estadosDisponibles.first;

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Text('Cambiar estado de ${item.nombre}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Disponible en ${item.estado.label}: ${item.cantidad} ${item.unidad}',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: cantidadCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Cantidad a mover',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<EstadoHerramientaStock>(
                    initialValue: estadoNuevo,
                    decoration: const InputDecoration(
                      labelText: 'Nuevo estado',
                      border: OutlineInputBorder(),
                    ),
                    items: estadosDisponibles
                        .map(
                          (estado) => DropdownMenuItem(
                            value: estado,
                            child: Text(estado.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => estadoNuevo = value);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Guardar'),
                ),
              ],
            ),
          );
        },
      );

      if (confirmed != true) return;

      final cantidad = num.tryParse(cantidadCtrl.text.trim());
      if (cantidad == null || cantidad <= 0 || cantidad > item.cantidad) {
        throw Exception('Ingresa una cantidad valida para mover de estado.');
      }

      await _api.cambiarEstadoStockEmpresa(
        empresaId: _empresaId,
        herramientaId: item.herramientaId,
        estadoActual: item.estado.backendValue,
        estadoNuevo: estadoNuevo.backendValue,
        cantidad: cantidad,
      );

      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text('Estado actualizado para ${item.nombre}.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text(AppError.messageOf(e))),
      );
    } finally {
      cantidadCtrl.dispose();
    }
  }

  Widget _chipCount(String label, int n, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        '$label: $n',
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _filtrados;
    final operativas = _items
        .where((e) => e.estado == EstadoHerramientaStock.OPERATIVA)
        .length;
    final danadas = _items
        .where((e) => e.estado == EstadoHerramientaStock.DANADA)
        .length;
    final perdidas = _items
        .where((e) => e.estado == EstadoHerramientaStock.PERDIDA)
        .length;
    final bajas = _items
        .where((e) => e.estado == EstadoHerramientaStock.BAJA)
        .length;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Stock de herramientas empresa'),
        backgroundColor: AppTheme.primary,
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: const Text(
                'Aqui ves el stock de herramientas de la empresa con el mismo enfoque del inventario por conjunto. Puedes sumar, descontar y mover cantidades entre estados.',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: TextField(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText:
                            'Buscar (nombre, unidad, categoria, control o estado)',
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      onChanged: (value) => setState(() => _search = value),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _chipCount('Operativas', operativas, AppTheme.green),
                const SizedBox(width: 8),
                _chipCount('Dañadas', danadas, AppTheme.red),
                const SizedBox(width: 8),
                _chipCount('Perdidas', perdidas, Colors.black54),
                const SizedBox(width: 8),
                _chipCount('Bajas', bajas, Colors.black45),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? _StateView(message: _error!, onRetry: _load)
                  : filtrados.isEmpty
                  ? const _EmptyView()
                  : Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: SingleChildScrollView(
                          child: Theme(
                            data: Theme.of(
                              context,
                            ).copyWith(dividerColor: Colors.grey.shade200),
                            child: PaginatedDataTable(
                              header: const Text(
                                'Herramientas empresa',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              showCheckboxColumn: false,
                              availableRowsPerPage: const [8, 10, 20, 50],
                              rowsPerPage: _rowsPerPage,
                              onRowsPerPageChanged: (value) {
                                if (value == null) return;
                                setState(() => _rowsPerPage = value);
                              },
                              columns: const [
                                DataColumn(label: Text('NAME')),
                                DataColumn(label: Text('UNIT')),
                                DataColumn(label: Text('CONTROL')),
                                DataColumn(
                                  numeric: true,
                                  label: Text('AVAILABLE'),
                                ),
                                DataColumn(label: Text('STATE')),
                                DataColumn(label: Text('ACTION')),
                              ],
                              source: _EmpresaHerramientaDataSource(
                                data: filtrados,
                                onAgregar: (item) =>
                                    _ajustar(item, sumar: true),
                                onDescontar: (item) =>
                                    _ajustar(item, sumar: false),
                                onCambiarEstado: _cambiarEstado,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmpresaHerramientaDataSource extends DataTableSource {
  final List<HerramientaStockResponse> data;
  final Future<void> Function(HerramientaStockResponse item) onAgregar;
  final Future<void> Function(HerramientaStockResponse item) onDescontar;
  final Future<void> Function(HerramientaStockResponse item) onCambiarEstado;

  _EmpresaHerramientaDataSource({
    required this.data,
    required this.onAgregar,
    required this.onDescontar,
    required this.onCambiarEstado,
  });

  @override
  DataRow? getRow(int index) {
    if (index >= data.length) return null;
    final item = data[index];

    final estadoColor = switch (item.estado) {
      EstadoHerramientaStock.OPERATIVA => AppTheme.green,
      EstadoHerramientaStock.DANADA => AppTheme.red,
      EstadoHerramientaStock.PERDIDA => Colors.black54,
      EstadoHerramientaStock.BAJA => Colors.black45,
    };

    return DataRow.byIndex(
      index: index,
      cells: [
        DataCell(
          Text(
            item.nombre,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        DataCell(Text(item.unidad.isEmpty ? '-' : item.unidad)),
        DataCell(Text(item.modoControl.label)),
        DataCell(Text(item.cantidad.toString())),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: estadoColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: estadoColor.withValues(alpha: 0.25)),
            ),
            child: Text(
              item.estado.label,
              style: TextStyle(color: estadoColor, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Descontar',
                onPressed: () => onDescontar(item),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              IconButton(
                tooltip: 'Agregar',
                onPressed: () => onAgregar(item),
                icon: const Icon(Icons.add_circle_outline),
              ),
              IconButton(
                tooltip: 'Cambiar estado',
                onPressed: () => onCambiarEstado(item),
                icon: const Icon(Icons.sync_alt_outlined),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => data.length;

  @override
  int get selectedRowCount => 0;
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No hay registros de stock en empresa para mostrar.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _StateView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _StateView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 56),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
