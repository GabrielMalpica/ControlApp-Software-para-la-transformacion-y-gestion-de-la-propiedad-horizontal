import 'package:flutter/material.dart';

import '../service/theme.dart';
import '../service/permission_service.dart';
import '../api/inventario_api.dart';
import '../model/inventario_item_model.dart';
import '../model/insumo_model.dart';
import '../model/movimiento_insumo_model.dart';
import 'solicitud_insumo_page.dart';

// ✅ Imports herramientas
import '../api/herramienta_api.dart';
import '../model/herramienta_model.dart';
import '../service/app_error.dart';

import 'package:flutter_application_1/service/app_feedback.dart';
import 'package:flutter_application_1/widgets/skeleton.dart';

enum TipoInventario { INSUMOS, HERRAMIENTAS }

class InventarioPage extends StatefulWidget {
  final String nit; // NIT conjunto
  final String empresaId; // ✅ NIT empresa (para catálogo)
  final bool soloInsumos;

  const InventarioPage({
    super.key,
    required this.nit,
    required this.empresaId,
    this.soloInsumos = false,
  });

  @override
  State<InventarioPage> createState() => _InventarioPageState();
}

class _InventarioPageState extends State<InventarioPage> {
  final InventarioApi _api = InventarioApi();

  // ✅ Tipo actual
  TipoInventario _tipoInventario = TipoInventario.INSUMOS;

  bool get _canCreateRequests =>
      PermissionService.instance.can('solicitudes.crear');
  bool get _canViewTools => PermissionService.instance.canAny([
    'herramientas.ver',
    'herramientas.gestionar',
  ]);
  bool get _canManageTools =>
      PermissionService.instance.can('herramientas.gestionar');
  bool get _canManageInventory =>
      PermissionService.instance.can('inventario.gestionar');

  /// Crear insumos personalizados queda reservado a gerente y jefe de
  /// operación, sin importar si otros roles tienen el permiso general
  /// 'inventario.gestionar' (ej. para agregar stock a insumos existentes).
  bool get _canCrearInsumoPersonalizado =>
      _canManageInventory &&
      PermissionService.instance.hasAnyRole(['gerente', 'jefe_operaciones']);

  // =============================
  // Herramientas
  // =============================
  final HerramientaApi _herrApi = HerramientaApi();
  bool _cargandoHerr = false;
  List<HerramientaStockResponse> _herrItems = [];

  // =============================
  // Insumos
  // =============================
  bool _cargando = false;
  List<InventarioItemResponse> _items = [];

  // Search
  String _q = '';

  // Tabla
  int _rowsPerPage = 8;
  int? _sortColumnIndex;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _cargar() async {
    if (_tipoInventario == TipoInventario.INSUMOS) {
      setState(() => _cargando = true);
      try {
        final data = await _api.listarInventarioConjunto(widget.nit);
        if (!mounted) return;
        setState(() => _items = data);
      } catch (e) {
        if (!mounted) return;
        AppFeedback.showFromSnackBar(
          context,
          SnackBar(
            content: Text('Error cargando inventario: $e'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        if (mounted) setState(() => _cargando = false);
      }
    } else {
      setState(() => _cargandoHerr = true);
      try {
        final raw = await _herrApi.listarStockConjunto(nitConjunto: widget.nit);

        final parsed = raw
            .whereType<Map>()
            .map(
              (e) =>
                  HerramientaStockResponse.fromJson(e.cast<String, dynamic>()),
            )
            .toList();

        if (!mounted) return;
        setState(() => _herrItems = parsed);
      } catch (e) {
        if (!mounted) return;
        AppFeedback.showFromSnackBar(
          context,
          SnackBar(
            content: Text('Error cargando herramientas: $e'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        if (mounted) setState(() => _cargandoHerr = false);
      }
    }
  }

  Future<void> _agregarStockInsumo(InventarioItemResponse item) async {
    final agregado = await showDialog<num>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AgregarStockDialog(item: item),
    );
    if (agregado == null) return;

    try {
      await _api.agregarStock(
        conjuntoNit: widget.nit,
        insumoId: item.insumoId,
        cantidad: agregado,
      );
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text(
            'Stock actualizado: $agregado ${item.unidad} de ${item.nombre}',
          ),
        ),
      );
      _cargar();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text(AppError.messageOf(e))),
      );
    }
  }

  Future<void> _registrarSalidaInsumo(InventarioItemResponse item) async {
    final salida = await showDialog<num>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RegistrarSalidaDialog(item: item),
    );
    if (salida == null) return;

    try {
      await _api.consumirStock(
        conjuntoNit: widget.nit,
        insumoId: item.insumoId,
        cantidad: salida,
      );
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text('Salida registrada: ${item.nombre}')),
      );
      _cargar();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text(AppError.messageOf(e))),
      );
    }
  }

  void _verKardexInsumo(InventarioItemResponse item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => KardexInsumoPage(
          nitConjunto: widget.nit,
          api: _api,
          item: item,
        ),
      ),
    );
  }

  Future<void> _editarInsumoPersonalizado(InventarioItemResponse item) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _InsumoPersonalizadoDialog(
        nitConjunto: widget.nit,
        api: _api,
        existente: item,
      ),
    );
    if (changed == true) _cargar();
  }

  Future<void> _confirmarEliminarInsumoPersonalizado(
    InventarioItemResponse item,
  ) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar insumo'),
        content: Text(
          '¿Eliminar "${item.nombre}" del inventario de este conjunto? '
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await _api.eliminarInsumoPersonalizado(
        conjuntoNit: widget.nit,
        insumoId: item.insumoId,
      );
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text('Insumo eliminado: ${item.nombre}')),
      );
      _cargar();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text(AppError.messageOf(e))),
      );
    }
  }

  // =============================
  // Filtro insumos
  // =============================
  List<InventarioItemResponse> get _filtrados {
    final t = _q.trim().toLowerCase();
    if (t.isEmpty) return List.of(_items);

    return _items.where((x) {
      return x.nombre.toLowerCase().contains(t) ||
          (x.categoria ?? '').toLowerCase().contains(t) ||
          x.unidad.toLowerCase().contains(t);
    }).toList();
  }

  // =============================
  // Filtro herramientas
  // =============================
  List<HerramientaStockResponse> get _herrFiltrados {
    final t = _q.trim().toLowerCase();
    if (t.isEmpty) return List.of(_herrItems);

    return _herrItems.where((x) {
      return x.nombre.toLowerCase().contains(t) ||
          x.unidad.toLowerCase().contains(t) ||
          x.estado.name.toLowerCase().contains(t) ||
          x.modoControl.name.toLowerCase().contains(t) ||
          x.tipoTenencia.name.toLowerCase().contains(t) ||
          (x.empresaIdFuente ?? '').toLowerCase().contains(t);
    }).toList();
  }

  Future<void> _devolverHerramientaPrestada(
    HerramientaStockResponse item,
  ) async {
    final controller = TextEditingController(text: item.cantidad.toString());

    try {
      final cantidad = await showDialog<num>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text('Devolver ${item.nombre}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Disponible prestado: ${item.cantidad} ${item.unidad}'),
                if (item.empresaIdFuente != null &&
                    item.empresaIdFuente!.trim().isNotEmpty)
                  Text('Empresa origen: ${item.empresaIdFuente}'),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Cantidad a devolver',
                    border: OutlineInputBorder(),
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
                  final parsed = num.tryParse(controller.text.trim());
                  if (parsed == null || parsed <= 0 || parsed > item.cantidad) {
                    AppFeedback.showFromSnackBar(
                      context,
                      const SnackBar(
                        content: Text('Cantidad inválida para la devolución'),
                      ),
                    );
                    return;
                  }
                  Navigator.pop(dialogContext, parsed);
                },
                child: const Text('Devolver'),
              ),
            ],
          );
        },
      );

      if (cantidad == null) return;

      await _herrApi.devolverPrestamoConjunto(
        nitConjunto: widget.nit,
        herramientaId: item.herramientaId,
        cantidad: cantidad,
        estado: item.estado.backendValue,
      );

      if (!mounted) return;

      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text('Prestamo devuelto: ${item.nombre}')),
      );
      _cargar();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text(AppError.messageOf(e))),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _cambiarEstadoHerramientaPropia(
    HerramientaStockResponse item,
  ) async {
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

      await _herrApi.cambiarEstadoStockConjunto(
        nitConjunto: widget.nit,
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
      await _cargar();
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

  // =============================
  // Sort insumos
  // =============================
  void _sort<T extends Comparable<T>>(
    int columnIndex,
    bool ascending,
    T Function(InventarioItemResponse d) getField,
  ) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;

      _items.sort((a, b) {
        final av = getField(a);
        final bv = getField(b);
        return ascending ? av.compareTo(bv) : bv.compareTo(av);
      });
    });
  }

  // =============================
  // Tabla insumos
  // =============================
  Widget _buildTablaInsumos() {
    final filtrados = _filtrados;

    if (_cargando) {
      return const SkeletonList();
    }

    if (filtrados.isEmpty) {
      return const Center(
        child: Text("Este conjunto no tiene insumos en inventario."),
      );
    }

    return Card(
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
                "Insumos",
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              showCheckboxColumn: false,
              availableRowsPerPage: const [8, 10, 20, 50],
              rowsPerPage: _rowsPerPage,
              onRowsPerPageChanged: (v) {
                if (v == null) return;
                setState(() => _rowsPerPage = v);
              },
              sortColumnIndex: _sortColumnIndex,
              sortAscending: _sortAscending,
              columns: [
                DataColumn(
                  label: const Text("Nombre"),
                  onSort: (i, asc) =>
                      _sort<String>(i, asc, (d) => d.nombre.toLowerCase()),
                ),
                DataColumn(
                  label: const Text("Categoria"),
                  onSort: (i, asc) => _sort<String>(
                    i,
                    asc,
                    (d) => (d.categoria ?? '').toLowerCase(),
                  ),
                ),
                DataColumn(
                  label: const Text("Unidad"),
                  onSort: (i, asc) =>
                      _sort<String>(i, asc, (d) => d.unidad.toLowerCase()),
                ),
                DataColumn(
                  numeric: true,
                  label: const Text("Disponible"),
                  onSort: (i, asc) => _sort<num>(i, asc, (d) => d.cantidad),
                ),
                const DataColumn(label: Text("Total disponible")),
                const DataColumn(label: Text("Estado")),
                if (_canManageInventory) const DataColumn(label: Text("Acciones")),
              ],
              source: _InventarioDataSource(
                data: filtrados,
                canManage: _canManageInventory,
                canManagePersonalizados: _canCrearInsumoPersonalizado,
                onAgregarStock: _agregarStockInsumo,
                onRegistrarSalida: _registrarSalidaInsumo,
                onVerKardex: _verKardexInsumo,
                onEditar: _editarInsumoPersonalizado,
                onEliminar: _confirmarEliminarInsumoPersonalizado,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =============================
  // Tabla herramientas
  // =============================
  Widget _buildTablaHerramientas() {
    final filtrados = _herrFiltrados;

    if (_cargandoHerr) {
      return const SkeletonList();
    }

    if (filtrados.isEmpty) {
      return const Center(
        child: Text("Este conjunto no tiene herramientas registradas."),
      );
    }

    return Card(
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
                "Herramientas",
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              showCheckboxColumn: false,
              availableRowsPerPage: const [8, 10, 20, 50],
              rowsPerPage: _rowsPerPage,
              onRowsPerPageChanged: (v) {
                if (v == null) return;
                setState(() => _rowsPerPage = v);
              },
              columns: const [
                DataColumn(label: Text("Nombre")),
                DataColumn(label: Text("Unidad")),
                DataColumn(label: Text("Propiedad")),
                DataColumn(numeric: true, label: Text("Disponible")),
                DataColumn(label: Text("Estado")),
                DataColumn(label: Text("Accion")),
              ],
              source: _HerramientaDataSource(
                data: filtrados,
                onDevolver: _canManageTools
                    ? _devolverHerramientaPrestada
                    : null,
                onCambiarEstado: _canManageTools
                    ? _cambiarEstadoHerramientaPropia
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =============================
  // UI helpers
  // =============================
  Widget _chipCount(String label, int n, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        "$label: $n",
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _ghostButton({
    required IconData icon,
    required String label,
    bool enabled = true,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: enabled ? Colors.black87 : Colors.black26,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: enabled ? Colors.black87 : Colors.black26,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Conteos insumos
    final bajos = _items.where((e) => e.estaBajo && !e.agotado).length;
    final agotados = _items.where((e) => e.agotado).length;

    // Conteos herramientas
    final operativas = _herrItems
        .where((e) => e.estado == EstadoHerramientaStock.OPERATIVA)
        .length;
    final danadas = _herrItems
        .where((e) => e.estado == EstadoHerramientaStock.DANADA)
        .length;
    final perdidas = _herrItems
        .where((e) => e.estado == EstadoHerramientaStock.PERDIDA)
        .length;
    final bajasHerr = _herrItems
        .where((e) => e.estado == EstadoHerramientaStock.BAJA)
        .length;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        elevation: 0,
        title: Text(
          "Inventario · ${widget.nit}",
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: "Refrescar",
            onPressed: _cargar,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ===== Toolbar superior =====
            Row(
              children: [
                const Spacer(),
                if (_tipoInventario == TipoInventario.INSUMOS &&
                    _canCrearInsumoPersonalizado) ...[
                  _ghostButton(
                    icon: Icons.add,
                    label: "Agregar insumo",
                    onTap: () async {
                      final changed = await showDialog<bool>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => _InsumoPersonalizadoDialog(
                          nitConjunto: widget.nit,
                          api: _api,
                        ),
                      );
                      if (changed == true) _cargar();
                    },
                  ),
                  const SizedBox(width: 8),
                ],
                if (_tipoInventario == TipoInventario.INSUMOS &&
                    _canCreateRequests)
                  _ghostButton(
                    icon: Icons.add_shopping_cart_outlined,
                    label: "Solicitar insumos",
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              SolicitudInsumoPage(conjuntoNit: widget.nit),
                        ),
                      );
                      _cargar();
                    },
                  ),
                if (_tipoInventario == TipoInventario.HERRAMIENTAS &&
                    _canManageTools)
                  _ghostButton(
                    icon: Icons.add,
                    label: "Registrar herramienta propia",
                    onTap: () async {
                      final changed = await showDialog<bool>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => _AgregarHerramientaDialog(
                          nitConjunto: widget.nit,
                          empresaId: widget.empresaId,
                          api: _herrApi,
                        ),
                      );

                      if (changed == true) {
                        _cargar(); // recarga tabla herramientas
                      }
                    },
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // ===== Selector =====
            Row(
              children: [
                ChoiceChip(
                  label: const Text("Insumos"),
                  selected: _tipoInventario == TipoInventario.INSUMOS,
                  onSelected: (_) {
                    setState(() {
                      _tipoInventario = TipoInventario.INSUMOS;
                      _q = '';
                    });
                    _cargar();
                  },
                ),
                if (!widget.soloInsumos && _canViewTools) ...[
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text("Herramientas"),
                    selected: _tipoInventario == TipoInventario.HERRAMIENTAS,
                    onSelected: (_) {
                      setState(() {
                        _tipoInventario = TipoInventario.HERRAMIENTAS;
                        _q = '';
                      });
                      _cargar();
                    },
                  ),
                ],
              ],
            ),

            const SizedBox(height: 12),

            if (_tipoInventario == TipoInventario.HERRAMIENTAS) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: const Text(
                  'Aqui ves solo herramientas que este conjunto ya tiene: propias del conjunto o prestadas por la empresa. El stock general de empresa se maneja en Herramientas de la empresa.',
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ===== Buscador + chips =====
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: TextField(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: _tipoInventario == TipoInventario.INSUMOS
                            ? "Buscar (nombre, categoría, unidad)"
                            : "Buscar (nombre, unidad, estado, modo, origen)",
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
                      onChanged: (v) => setState(() => _q = v),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (_tipoInventario == TipoInventario.INSUMOS) ...[
                  _chipCount("Bajos", bajos, AppTheme.red),
                  const SizedBox(width: 8),
                  _chipCount("Agotados", agotados, Colors.black54),
                ] else ...[
                  _chipCount("Operativas", operativas, AppTheme.green),
                  const SizedBox(width: 8),
                  _chipCount("Dañadas", danadas, AppTheme.red),
                  const SizedBox(width: 8),
                  _chipCount("Perdidas", perdidas, Colors.black54),
                  const SizedBox(width: 8),
                  _chipCount("Bajas", bajasHerr, Colors.black45),
                ],
              ],
            ),

            const SizedBox(height: 12),

            // ===== Tabla =====
            Expanded(
              child: _tipoInventario == TipoInventario.INSUMOS
                  ? _buildTablaInsumos()
                  : _buildTablaHerramientas(),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= DataSource INSUMOS =================

class _InventarioDataSource extends DataTableSource {
  final List<InventarioItemResponse> data;

  /// Puede agregar stock a cualquier insumo (catálogo o personalizado).
  final bool canManage;

  /// Puede editar/eliminar la definición de insumos personalizados.
  final bool canManagePersonalizados;
  final Future<void> Function(InventarioItemResponse item)? onAgregarStock;
  final Future<void> Function(InventarioItemResponse item)? onRegistrarSalida;
  final void Function(InventarioItemResponse item)? onVerKardex;
  final Future<void> Function(InventarioItemResponse item)? onEditar;
  final Future<void> Function(InventarioItemResponse item)? onEliminar;

  _InventarioDataSource({
    required this.data,
    this.canManage = false,
    this.canManagePersonalizados = false,
    this.onAgregarStock,
    this.onRegistrarSalida,
    this.onVerKardex,
    this.onEditar,
    this.onEliminar,
  });

  @override
  DataRow? getRow(int index) {
    if (index >= data.length) return null;
    final inv = data[index];

    final statusTxt = inv.agotado
        ? 'Agotado - comprar'
        : (inv.estaBajo ? 'Stock bajo' : 'Disponible');
    // "Agotado" es más urgente que "Stock bajo": un rojo más oscuro para que
    // resalte incluso más y no se pierda entre los insumos con stock bajo.
    final statusColor = inv.agotado
        ? const Color(0xFF8D2C21)
        : (inv.estaBajo ? AppTheme.red : AppTheme.green);

    return DataRow.byIndex(
      index: index,
      cells: [
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (inv.estaBajo || inv.agotado) ...[
                Tooltip(
                  message: inv.agotado ? 'Agotado' : 'Stock bajo',
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color: AppTheme.red,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  inv.nombre,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (inv.personalizado) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.blueGrey.withValues(alpha: 0.25),
                    ),
                  ),
                  child: const Text(
                    'Personalizado',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.blueGrey,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        DataCell(Text(inv.categoria ?? "-")),
        DataCell(Text(inv.unidad.isEmpty ? "-" : inv.unidad)),
        DataCell(Text(inv.disponibleTexto)),
        DataCell(
          Text(
            inv.totalDisponibleTexto ?? "-",
            style: TextStyle(
              color: inv.totalDisponibleTexto == null
                  ? Colors.black38
                  : Colors.black87,
              fontWeight: inv.totalDisponibleTexto == null
                  ? FontWeight.normal
                  : FontWeight.w600,
            ),
          ),
        ),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: statusColor.withValues(alpha: 0.25)),
            ),
            child: Text(
              statusTxt,
              style: TextStyle(color: statusColor, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        if (canManage)
          DataCell(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.add_box_outlined, size: 20),
                  tooltip: 'Agregar stock (ingreso)',
                  onPressed: onAgregarStock == null
                      ? null
                      : () => onAgregarStock!(inv),
                ),
                IconButton(
                  icon: const Icon(Icons.indeterminate_check_box_outlined, size: 20),
                  tooltip: 'Registrar salida',
                  onPressed: onRegistrarSalida == null
                      ? null
                      : () => onRegistrarSalida!(inv),
                ),
                IconButton(
                  icon: const Icon(Icons.receipt_long_outlined, size: 20),
                  tooltip: 'Ver kardex',
                  onPressed: onVerKardex == null
                      ? null
                      : () => onVerKardex!(inv),
                ),
                if (inv.personalizado && canManagePersonalizados) ...[
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    tooltip: 'Editar',
                    onPressed: onEditar == null
                        ? null
                        : () => onEditar!(inv),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: AppTheme.red,
                    ),
                    tooltip: 'Eliminar',
                    onPressed: onEliminar == null
                        ? null
                        : () => onEliminar!(inv),
                  ),
                ],
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

// ================= DataSource HERRAMIENTAS =================

class _HerramientaDataSource extends DataTableSource {
  final List<HerramientaStockResponse> data;
  final Future<void> Function(HerramientaStockResponse item)? onDevolver;
  final Future<void> Function(HerramientaStockResponse item)? onCambiarEstado;

  _HerramientaDataSource({
    required this.data,
    this.onDevolver,
    this.onCambiarEstado,
  });

  @override
  DataRow? getRow(int index) {
    if (index >= data.length) return null;
    final h = data[index];

    final estadoTxt = h.estado.label;
    final estadoColor = (h.estado == EstadoHerramientaStock.OPERATIVA)
        ? AppTheme.green
        : (h.estado == EstadoHerramientaStock.DANADA)
        ? AppTheme.red
        : Colors.black54;
    final tenenciaTxt = h.tipoTenencia == TipoTenenciaHerramienta.PRESTADA
        ? 'Prestada por empresa'
        : 'Propia del conjunto';
    final tenenciaColor = h.tipoTenencia == TipoTenenciaHerramienta.PRESTADA
        ? Colors.orange.shade700
        : Colors.blueGrey;

    return DataRow.byIndex(
      index: index,
      cells: [
        DataCell(
          Text(h.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        DataCell(Text(h.unidad.isEmpty ? "-" : h.unidad)),
        DataCell(
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: tenenciaColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: tenenciaColor.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  tenenciaTxt,
                  style: TextStyle(
                    color: tenenciaColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (h.empresaIdFuente != null && h.empresaIdFuente!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    h.empresaIdFuente!,
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ),
            ],
          ),
        ),
        DataCell(Text(h.cantidad.toString())),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: estadoColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: estadoColor.withValues(alpha: 0.25)),
            ),
            child: Text(
              estadoTxt,
              style: TextStyle(color: estadoColor, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (h.tipoTenencia == TipoTenenciaHerramienta.PROPIA &&
                  onCambiarEstado != null)
                IconButton(
                  tooltip: 'Cambiar estado',
                  onPressed: () => onCambiarEstado!(h),
                  icon: const Icon(Icons.sync_alt_outlined),
                ),
              if (h.tipoTenencia == TipoTenenciaHerramienta.PRESTADA &&
                  onDevolver != null)
                IconButton(
                  tooltip: 'Devolver a empresa',
                  onPressed: () => onDevolver!(h),
                  icon: const Icon(Icons.assignment_return_outlined),
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

// ================= ✅ DIALOG AGREGAR HERRAMIENTA =================

class _AgregarHerramientaDialog extends StatefulWidget {
  final String nitConjunto;
  final String empresaId;
  final HerramientaApi api;

  const _AgregarHerramientaDialog({
    required this.nitConjunto,
    required this.empresaId,
    required this.api,
  });

  @override
  State<_AgregarHerramientaDialog> createState() =>
      _AgregarHerramientaDialogState();
}

class _AgregarHerramientaDialogState extends State<_AgregarHerramientaDialog> {
  bool _loading = true;
  String? _error;

  List<HerramientaResponse> _catalogo = [];
  HerramientaResponse? _selected;

  final _cantidadCtrl = TextEditingController(text: "1");
  EstadoHerramientaStock _estado = EstadoHerramientaStock.OPERATIVA;

  @override
  void initState() {
    super.initState();
    _loadCatalogo();
  }

  @override
  void dispose() {
    _cantidadCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCatalogo() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      const pageSize = 100;
      const maxTotal = 300; // ajusta si quieres

      final List<HerramientaResponse> all = [];
      int skip = 0;

      while (all.length < maxTotal) {
        final out = await widget.api.listarHerramientas(
          empresaId: widget.empresaId,
          nombre: null,
          take: pageSize,
          skip: skip,
        );

        final data = (out["data"] as List?) ?? [];
        final parsed = data
            .whereType<Map>()
            .map((e) => HerramientaResponse.fromJson(e.cast<String, dynamic>()))
            .toList();

        all.addAll(parsed);

        // si ya no vienen más, paramos
        if (parsed.length < pageSize) break;

        skip += pageSize;
      }

      if (!mounted) return;

      setState(() {
        _catalogo = all;
        _selected = all.isNotEmpty ? all.first : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AppError.messageOf(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  num? _parseNumNullable(String v) {
    final s = v.trim();
    if (s.isEmpty) return null;
    return num.tryParse(s);
  }

  Future<void> _guardar() async {
    if (_selected == null) {
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(content: Text("Selecciona una herramienta")),
      );
      return;
    }

    final cant = _parseNumNullable(_cantidadCtrl.text);
    if (cant == null || cant <= 0) {
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text("Cantidad inválida")),
      );
      return;
    }

    try {
      await widget.api.upsertStockConjunto(
        nitConjunto: widget.nitConjunto,
        herramientaId: _selected!.id,
        cantidad: cant,
        estado: _estado.backendValue,
      );

      if (!mounted) return;

      Navigator.pop(context, true);

      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text("Herramienta agregada: ${_selected!.nombre}")),
      );
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(context, SnackBar(content: Text("$e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Registrar herramienta propia del conjunto"),
      content: SizedBox(
        width: 520,
        child: _loading
            ? const Padding(padding: EdgeInsets.all(12), child: SkeletonList())
            : _error != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text("Error: $_error"),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _loadCatalogo,
                    icon: const Icon(Icons.refresh),
                    label: const Text("Reintentar"),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<HerramientaResponse>(
                    initialValue: _selected,
                    decoration: const InputDecoration(
                      labelText: "Herramienta propia (catálogo)",
                      border: OutlineInputBorder(),
                    ),
                    items: _catalogo.map((h) {
                      return DropdownMenuItem(
                        value: h,
                        child: Text("${h.nombre} · ${h.unidad}"),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _selected = v),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _cantidadCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: "Cantidad",
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<EstadoHerramientaStock>(
                          initialValue: _estado,
                          decoration: const InputDecoration(
                            labelText: "Estado",
                            border: OutlineInputBorder(),
                          ),
                          items: EstadoHerramientaStock.values.map((e) {
                            return DropdownMenuItem(
                              value: e,
                              child: Text(e.label),
                            );
                          }).toList(),
                          onChanged: (v) => setState(
                            () =>
                                _estado = v ?? EstadoHerramientaStock.OPERATIVA,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_selected != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: Text(
                        "Modo de control: ${_selected!.modoControl.label}",
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Este registro crea stock propio del conjunto. Los prestamos desde empresa se devuelven aparte.',
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text("Cancelar"),
        ),
        ElevatedButton.icon(
          onPressed: _loading ? null : _guardar,
          icon: const Icon(Icons.save),
          label: const Text("Guardar"),
          style: AppTheme.saveButtonStyle,
        ),
      ],
    );
  }
}

// ================= DIALOG INSUMO PERSONALIZADO (crear / editar) =================

enum _ModoConteoInsumo { simple, empaque }

class _InsumoPersonalizadoDialog extends StatefulWidget {
  final String nitConjunto;
  final InventarioApi api;

  /// Si viene no-null, el diálogo edita este insumo en vez de crear uno nuevo.
  final InventarioItemResponse? existente;

  const _InsumoPersonalizadoDialog({
    required this.nitConjunto,
    required this.api,
    this.existente,
  });

  @override
  State<_InsumoPersonalizadoDialog> createState() =>
      _InsumoPersonalizadoDialogState();
}

class _InsumoPersonalizadoDialogState
    extends State<_InsumoPersonalizadoDialog> {
  /// Nombres de empaque/contenedor (modo "por empaques").
  static const List<String> _empaquesSugeridos = [
    'tarro',
    'caja',
    'paquete',
    'rollo',
    'bulto',
    'botella',
    'galón',
    'saco',
  ];

  /// Nombres de conteo simple, sin contenido medible (modo "por unidades").
  static const List<String> _unidadesSimplesSugeridas = [
    'unidad',
    'par',
    'resma',
    'kit',
    'juego',
  ];

  /// En qué se mide el contenido de cada empaque.
  static const List<String> _unidadesMedidaSugeridas = [
    'L',
    'ml',
    'gal',
    'kg',
    'g',
    'oz',
  ];

  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _unidadCtrl = TextEditingController();
  final _cantidadCtrl = TextEditingController(text: '0');
  final _umbralCtrl = TextEditingController();
  final _contenidoCtrl = TextEditingController();
  final _unidadContenidoCtrl = TextEditingController();

  CategoriaInsumo _categoria = CategoriaInsumo.LIMPIEZA;
  _ModoConteoInsumo _modo = _ModoConteoInsumo.simple;
  bool _saving = false;

  bool get _editando => widget.existente != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existente;
    if (e == null) return;

    _nombreCtrl.text = e.nombre;
    _unidadCtrl.text = e.unidad;
    _umbralCtrl.text = e.umbralUsado?.toString() ?? '';
    if (e.contenidoPorUnidad != null && e.unidadContenido != null) {
      _modo = _ModoConteoInsumo.empaque;
      _contenidoCtrl.text = _formatNum(e.contenidoPorUnidad!);
      _unidadContenidoCtrl.text = e.unidadContenido!;
    }
    final categoriasCoincidentes = CategoriaInsumo.values.where(
      (c) => c.backendValue == e.categoria,
    );
    if (categoriasCoincidentes.isNotEmpty) {
      _categoria = categoriasCoincidentes.first;
    }
  }

  static String _formatNum(num v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _unidadCtrl.dispose();
    _cantidadCtrl.dispose();
    _umbralCtrl.dispose();
    _contenidoCtrl.dispose();
    _unidadContenidoCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final umbralStr = _umbralCtrl.text.trim();
      final cantidadStr = _cantidadCtrl.text.trim();
      final contenidoStr = _contenidoCtrl.text.trim();
      final unidadContenidoStr = _unidadContenidoCtrl.text.trim();
      final esEmpaque = _modo == _ModoConteoInsumo.empaque;

      if (_editando) {
        await widget.api.editarInsumoPersonalizado(
          conjuntoNit: widget.nitConjunto,
          insumoId: widget.existente!.insumoId,
          nombre: _nombreCtrl.text.trim(),
          unidad: _unidadCtrl.text.trim(),
          categoria: _categoria,
          umbralBajo: umbralStr.isEmpty ? null : int.tryParse(umbralStr),
          limpiarContenido: !esEmpaque,
          contenidoPorUnidad: esEmpaque ? num.tryParse(contenidoStr) : null,
          unidadContenido: esEmpaque ? unidadContenidoStr : null,
        );
      } else {
        await widget.api.crearInsumoPersonalizado(
          conjuntoNit: widget.nitConjunto,
          nombre: _nombreCtrl.text.trim(),
          unidad: _unidadCtrl.text.trim(),
          categoria: _categoria,
          umbralBajo: umbralStr.isEmpty ? null : int.tryParse(umbralStr),
          cantidadInicial: cantidadStr.isEmpty
              ? null
              : num.tryParse(cantidadStr),
          contenidoPorUnidad: esEmpaque ? num.tryParse(contenidoStr) : null,
          unidadContenido: esEmpaque ? unidadContenidoStr : null,
        );
      }

      if (!mounted) return;
      Navigator.pop(context, true);
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text(
            _editando
                ? 'Insumo actualizado: ${_nombreCtrl.text.trim()}'
                : 'Insumo personalizado creado: ${_nombreCtrl.text.trim()}',
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
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _modoCard({
    required _ModoConteoInsumo modo,
    required IconData icon,
    required String titulo,
    required String subtitulo,
  }) {
    final seleccionado = _modo == modo;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _modo = modo),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: seleccionado
                ? AppTheme.green.withValues(alpha: 0.08)
                : Colors.transparent,
            border: Border.all(
              color: seleccionado ? AppTheme.green : Colors.black26,
              width: seleccionado ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: seleccionado ? AppTheme.green : Colors.black54),
              const SizedBox(height: 6),
              Text(
                titulo,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: seleccionado ? AppTheme.green : Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitulo,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _previewTotal() {
    final contenido = num.tryParse(_contenidoCtrl.text.trim());
    if (contenido == null) return '?';
    return _formatNum(4 * contenido);
  }

  @override
  Widget build(BuildContext context) {
    final esEmpaque = _modo == _ModoConteoInsumo.empaque;
    final unidadesChips = esEmpaque
        ? _empaquesSugeridos
        : _unidadesSimplesSugeridas;

    return AlertDialog(
      title: Text(
        _editando
            ? 'Editar insumo personalizado'
            : 'Agregar insumo personalizado',
      ),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_editando) ...[
                  const Text(
                    'Crea un insumo propio de este conjunto (no queda en el '
                    'catálogo de empresa ni es comprable desde la tienda).',
                    style: TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                ],
                TextFormField(
                  controller: _nombreCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del insumo',
                    hintText: 'Ej: Clorox, Detergente, Escoba',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().length < 2) {
                      return 'Ingresa un nombre válido (mínimo 2 caracteres)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                const Text(
                  '¿Cómo se cuenta?',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _modoCard(
                      modo: _ModoConteoInsumo.simple,
                      icon: Icons.checklist,
                      titulo: 'Por unidades',
                      subtitulo: 'Ej: escobas, sillas',
                    ),
                    const SizedBox(width: 10),
                    _modoCard(
                      modo: _ModoConteoInsumo.empaque,
                      icon: Icons.science_outlined,
                      titulo: 'Por empaques con contenido',
                      subtitulo: 'Ej: tarros, cajas, galones',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _unidadCtrl,
                  decoration: InputDecoration(
                    labelText: esEmpaque
                        ? '¿Cómo se llama el empaque?'
                        : 'Unidad de conteo',
                    hintText: esEmpaque
                        ? 'Ej: tarro, caja, galón'
                        : 'Ej: unidad, par, resma',
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Ingresa cómo se cuenta este insumo';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: unidadesChips
                      .map(
                        (u) => ActionChip(
                          label: Text(u),
                          onPressed: () {
                            setState(() => _unidadCtrl.text = u);
                          },
                        ),
                      )
                      .toList(),
                ),
                if (esEmpaque) ...[
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _contenidoCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: _unidadCtrl.text.trim().isEmpty
                                ? 'Cada empaque contiene'
                                : 'Cada "${_unidadCtrl.text.trim()}" contiene',
                            hintText: 'Ej: 1.8',
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                          validator: (v) {
                            if (!esEmpaque) return null;
                            final parsed = num.tryParse((v ?? '').trim());
                            if (parsed == null || parsed <= 0) {
                              return 'Ingresa un número mayor a 0';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _unidadContenidoCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Unidad de medida',
                            hintText: 'Ej: L, gal, kg',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            if (!esEmpaque) return null;
                            if (v == null || v.trim().isEmpty) {
                              return 'Requerido';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _unidadesMedidaSugeridas
                        .map(
                          (u) => ActionChip(
                            label: Text(u),
                            onPressed: () {
                              setState(() => _unidadContenidoCtrl.text = u);
                            },
                          ),
                        )
                        .toList(),
                  ),
                  if (_unidadCtrl.text.trim().isNotEmpty &&
                      num.tryParse(_contenidoCtrl.text.trim()) != null &&
                      _unidadContenidoCtrl.text.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Ej: 4 "${_unidadCtrl.text.trim()}" = '
                        '${_previewTotal()} ${_unidadContenidoCtrl.text.trim()}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                DropdownButtonFormField<CategoriaInsumo>(
                  initialValue: _categoria,
                  decoration: const InputDecoration(
                    labelText: 'Categoría',
                    border: OutlineInputBorder(),
                  ),
                  items: CategoriaInsumo.values
                      .map(
                        (c) => DropdownMenuItem(value: c, child: Text(c.label)),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _categoria = v ?? _categoria),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (!_editando) ...[
                      Expanded(
                        child: TextFormField(
                          controller: _cantidadCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Cantidad inicial',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            final parsed = num.tryParse((v ?? '').trim());
                            if (parsed == null) return 'Ingresa un número válido';
                            if (parsed < 0) return 'No puede ser negativo';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: TextFormField(
                        controller: _umbralCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Umbral bajo (opcional)',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final n = int.tryParse(v.trim());
                          if (n == null || n < 0) {
                            return 'Número entero válido';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                if (_editando) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'La cantidad en stock no se cambia aquí: usa las '
                    'opciones de agregar/consumir stock del inventario.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton.icon(
          onPressed: _saving ? null : _guardar,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(_editando ? Icons.check : Icons.save),
          label: Text(_saving ? 'Guardando...' : (_editando ? 'Actualizar' : 'Guardar')),
          style: AppTheme.saveButtonStyle,
        ),
      ],
    );
  }
}

// ================= DIALOG AGREGAR STOCK =================

class _AgregarStockDialog extends StatefulWidget {
  final InventarioItemResponse item;

  const _AgregarStockDialog({required this.item});

  @override
  State<_AgregarStockDialog> createState() => _AgregarStockDialogState();
}

class _AgregarStockDialogState extends State<_AgregarStockDialog> {
  final _formKey = GlobalKey<FormState>();
  final _cantidadCtrl = TextEditingController();

  @override
  void dispose() {
    _cantidadCtrl.dispose();
    super.dispose();
  }

  String? _previewTexto() {
    final agregar = num.tryParse(_cantidadCtrl.text.trim());
    if (agregar == null || agregar <= 0) return null;

    final nuevaCantidad = widget.item.cantidad + agregar;
    final contenido = widget.item.contenidoPorUnidad;
    final unidadContenido = widget.item.unidadContenido;
    if (contenido != null && unidadContenido != null) {
      final total = nuevaCantidad * contenido;
      final totalTxto = total == total.roundToDouble()
          ? total.toStringAsFixed(0)
          : total.toStringAsFixed(2);
      return 'Nuevo stock: $nuevaCantidad ${widget.item.unidad} '
          '($totalTxto $unidadContenido)';
    }
    return 'Nuevo stock: $nuevaCantidad ${widget.item.unidad}';
  }

  @override
  Widget build(BuildContext context) {
    final stockActual = widget.item.totalDisponibleTexto == null
        ? widget.item.disponibleTexto
        : '${widget.item.disponibleTexto} (${widget.item.totalDisponibleTexto})';

    return AlertDialog(
      title: const Text('Agregar stock'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.item.nombre,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                'Stock actual: $stockActual',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _cantidadCtrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Cantidad a agregar (${widget.item.unidad})',
                  hintText: 'Ej: 4',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  final parsed = num.tryParse((v ?? '').trim());
                  if (parsed == null || parsed <= 0) {
                    return 'Ingresa un número mayor a 0';
                  }
                  return null;
                },
              ),
              if (_previewTexto() != null) ...[
                const SizedBox(height: 8),
                Text(
                  _previewTexto()!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.black54,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, num.parse(_cantidadCtrl.text.trim()));
          },
          icon: const Icon(Icons.add),
          label: const Text('Agregar'),
          style: AppTheme.saveButtonStyle,
        ),
      ],
    );
  }
}

// ================= DIALOG REGISTRAR SALIDA =================

class _RegistrarSalidaDialog extends StatefulWidget {
  final InventarioItemResponse item;

  const _RegistrarSalidaDialog({required this.item});

  @override
  State<_RegistrarSalidaDialog> createState() =>
      _RegistrarSalidaDialogState();
}

class _RegistrarSalidaDialogState extends State<_RegistrarSalidaDialog> {
  final _formKey = GlobalKey<FormState>();
  final _cantidadCtrl = TextEditingController();
  final _observacionCtrl = TextEditingController();

  /// Si el insumo tiene contenido medible (ej. cada tarro = 1.8 L), la
  /// salida se registra en esa medida (litros usados), no en tarros: así
  /// piensa quien realmente usa el insumo ("gasté 1.5 L"), no en envases.
  bool get _enMedida =>
      widget.item.contenidoPorUnidad != null &&
      widget.item.unidadContenido != null;

  String get _unidadEntrada =>
      _enMedida ? widget.item.unidadContenido! : widget.item.unidad;

  /// Disponible expresado en la misma unidad que se está pidiendo.
  num get _disponibleEnUnidadEntrada =>
      _enMedida ? (widget.item.totalDisponible ?? 0) : widget.item.cantidad;

  @override
  void dispose() {
    _cantidadCtrl.dispose();
    _observacionCtrl.dispose();
    super.dispose();
  }

  /// Cantidad que de verdad se descuenta del stock (unidad de conteo, ej.
  /// tarros): si se pidió en la medida, se convierte dividiendo por el
  /// contenido de cada unidad.
  num? get _cantidadAEnviar {
    final ingresada = num.tryParse(_cantidadCtrl.text.trim());
    if (ingresada == null || ingresada <= 0) return null;
    if (!_enMedida) return ingresada;
    return ingresada / widget.item.contenidoPorUnidad!;
  }

  String? _previewTexto() {
    final aEnviar = _cantidadAEnviar;
    if (aEnviar == null || aEnviar > widget.item.cantidad) return null;

    final nuevaCantidad = widget.item.cantidad - aEnviar;
    // "Envases físicos" restantes, redondeado hacia arriba (ej. 2.5 L en
    // tarros de 1L siguen siendo 3 tarros, hasta llegar a 2L exactos).
    if (_enMedida) {
      final nuevoTotal = nuevaCantidad * widget.item.contenidoPorUnidad!;
      final envases = nuevaCantidad.ceil();
      final totalTxto = nuevoTotal == nuevoTotal.roundToDouble()
          ? nuevoTotal.toStringAsFixed(0)
          : nuevoTotal.toStringAsFixed(2);
      return 'Quedarán: $totalTxto ${widget.item.unidadContenido} '
          '(≈$envases ${widget.item.unidad})';
    }
    return 'Quedarán: $nuevaCantidad ${widget.item.unidad}';
  }

  @override
  Widget build(BuildContext context) {
    final stockActual = widget.item.totalDisponibleTexto == null
        ? widget.item.disponibleTexto
        : '${widget.item.disponibleTexto} (${widget.item.totalDisponibleTexto})';

    return AlertDialog(
      title: const Text('Registrar salida'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.item.nombre,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                'Stock actual: $stockActual',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
              const SizedBox(height: 4),
              const Text(
                'Para el consumo de una tarea, ciérrala desde la tarea: esto '
                'es solo para ajustes o salidas manuales.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _cantidadCtrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Cantidad de salida ($_unidadEntrada)',
                  hintText: 'Ej: 1',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  final parsed = num.tryParse((v ?? '').trim());
                  if (parsed == null || parsed <= 0) {
                    return 'Ingresa un número mayor a 0';
                  }
                  if (parsed > _disponibleEnUnidadEntrada) {
                    return 'No puede ser mayor al disponible '
                        '($_disponibleEnUnidadEntrada $_unidadEntrada)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _observacionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Motivo (opcional)',
                  hintText: 'Ej: ajuste de conteo, se dañó, etc.',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_previewTexto() != null) ...[
                const SizedBox(height: 8),
                Text(
                  _previewTexto()!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.black54,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, _cantidadAEnviar);
          },
          icon: const Icon(Icons.remove),
          label: const Text('Registrar salida'),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
        ),
      ],
    );
  }
}

// ================= PAGINA KARDEX =================

class KardexInsumoPage extends StatefulWidget {
  final String nitConjunto;
  final InventarioApi api;
  final InventarioItemResponse item;

  const KardexInsumoPage({
    super.key,
    required this.nitConjunto,
    required this.api,
    required this.item,
  });

  @override
  State<KardexInsumoPage> createState() => _KardexInsumoPageState();
}

class _KardexInsumoPageState extends State<KardexInsumoPage> {
  bool _cargando = true;
  String? _error;
  List<MovimientoInsumoResponse> _movimientos = const [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final data = await widget.api.listarMovimientos(
        conjuntoNit: widget.nitConjunto,
        insumoId: widget.item.insumoId,
      );
      if (!mounted) return;
      setState(() => _movimientos = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AppError.messageOf(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  bool get _enMedida =>
      widget.item.contenidoPorUnidad != null &&
      widget.item.unidadContenido != null;

  String _numTexto(num v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  /// Saldo (en unidad de conteo, ej. tarros) mostrado como "envases físicos"
  /// redondeados hacia arriba, más el total real en la medida si aplica.
  String _saldoTexto(num saldo) {
    if (!_enMedida) return '$saldo ${widget.item.unidad}';
    final total = saldo * widget.item.contenidoPorUnidad!;
    return '${saldo.ceil()} ${widget.item.unidad} '
        '(${_numTexto(total)} ${widget.item.unidadContenido})';
  }

  /// Cantidad de un movimiento, en la unidad con la que realmente se
  /// registró: los ingresos se compran por envase completo (tarros), las
  /// salidas se consumen por la medida real (litros) cuando el insumo la
  /// tiene configurada. El número guardado siempre es en unidad de conteo
  /// (puede ser fraccionario en salidas, ej. 0.56 tarro = 1 L de un tarro
  /// de 1.8 L), así que las salidas se muestran convertidas de vuelta.
  String _cantidadMovimientoTexto(MovimientoInsumoResponse m) {
    if (!_enMedida || m.esEntrada) return '${m.cantidad} ${widget.item.unidad}';
    final enMedida = m.cantidad * widget.item.contenidoPorUnidad!;
    return '${_numTexto(enMedida)} ${widget.item.unidadContenido}';
  }

  String _fecha(DateTime dt) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(dt.day)}/${dos(dt.month)}/${dt.year} ${dos(dt.hour)}:${dos(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Kardex - ${widget.item.nombre}')),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? ListView(
                children: [
                  const SizedBox(height: 40),
                  Center(
                    child: Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                ],
              )
            : _movimientos.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 40),
                  Center(child: Text('Sin movimientos registrados todavía.')),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: _movimientos.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final m = _movimientos[i];
                  final color = m.esEntrada ? AppTheme.green : AppTheme.red;
                  return ListTile(
                    leading: Icon(
                      m.esEntrada
                          ? Icons.arrow_circle_up_outlined
                          : Icons.arrow_circle_down_outlined,
                      color: color,
                    ),
                    title: Text(
                      '${m.esEntrada ? "+" : "-"}${_cantidadMovimientoTexto(m)}',
                      style: TextStyle(fontWeight: FontWeight.w700, color: color),
                    ),
                    subtitle: Text(
                      [
                        _fecha(m.fecha),
                        if (m.operario != null) 'Por ${m.operario}',
                        if (m.tareaDescripcion != null)
                          'Tarea: ${m.tareaDescripcion}',
                        if (m.observacion != null && m.observacion!.isNotEmpty)
                          m.observacion!,
                      ].join(' · '),
                    ),
                    trailing: Text(
                      'Saldo\n${_saldoTexto(m.saldo)}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12),
                    ),
                    isThreeLine: true,
                  );
                },
              ),
      ),
    );
  }
}

// ignore_for_file: constant_identifier_names
