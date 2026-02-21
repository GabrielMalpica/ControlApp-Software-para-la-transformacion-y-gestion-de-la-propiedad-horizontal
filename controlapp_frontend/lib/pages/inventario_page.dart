import 'package:flutter/material.dart';

import '../service/theme.dart';
import '../service/session_service.dart';
import '../api/inventario_api.dart';
import '../model/inventario_item_model.dart';
import 'solicitud_insumo_page.dart';

// ✅ Imports herramientas
import '../api/herramienta_api.dart';
import '../model/herramienta_model.dart';

import 'package:flutter_application_1/service/app_feedback.dart';

enum TipoInventario { INSUMOS, HERRAMIENTAS }

class InventarioPage extends StatefulWidget {
  final String nit; // NIT conjunto
  final String empresaId; // ✅ NIT empresa (para catálogo)

  const InventarioPage({super.key, required this.nit, required this.empresaId});

  @override
  State<InventarioPage> createState() => _InventarioPageState();
}

class _InventarioPageState extends State<InventarioPage> {
  final InventarioApi _api = InventarioApi();
  final SessionService _session = SessionService();

  // ✅ Tipo actual
  TipoInventario _tipoInventario = TipoInventario.INSUMOS;
  bool _esGerente = false;

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
    _cargarRolUsuario();
    _cargar();
  }

  @override
  void dispose() {
    super.dispose();
  }

  // ✅ carga según tipo
  Future<void> _cargarRolUsuario() async {
    final rol = (await _session.getRol() ?? '').trim().toLowerCase();
    if (!mounted) return;
    setState(() => _esGerente = rol == 'gerente');
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
          x.modoControl.name.toLowerCase().contains(t);
    }).toList();
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
      return const Center(child: CircularProgressIndicator());
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
                  label: const Text("NAME"),
                  onSort: (i, asc) =>
                      _sort<String>(i, asc, (d) => d.nombre.toLowerCase()),
                ),
                DataColumn(
                  label: const Text("CATEGORY"),
                  onSort: (i, asc) => _sort<String>(
                    i,
                    asc,
                    (d) => (d.categoria ?? '').toLowerCase(),
                  ),
                ),
                DataColumn(
                  label: const Text("UNIT"),
                  onSort: (i, asc) =>
                      _sort<String>(i, asc, (d) => d.unidad.toLowerCase()),
                ),
                DataColumn(
                  numeric: true,
                  label: const Text("AVAILABLE"),
                  onSort: (i, asc) => _sort<num>(i, asc, (d) => d.cantidad),
                ),
                const DataColumn(label: Text("STATUS")),
              ],
              source: _InventarioDataSource(data: filtrados),
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
      return const Center(child: CircularProgressIndicator());
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
                DataColumn(label: Text("NAME")),
                DataColumn(label: Text("UNIT")),
                DataColumn(label: Text("CONTROL")),
                DataColumn(numeric: true, label: Text("AVAILABLE")),
                DataColumn(label: Text("STATE")),
              ],
              source: _HerramientaDataSource(data: filtrados),
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
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
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
                if (_tipoInventario == TipoInventario.INSUMOS)
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
                    _esGerente)
                  _ghostButton(
                    icon: Icons.add,
                    label: "Agregar herramienta",
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
            ),

            const SizedBox(height: 12),

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
                            : "Buscar (nombre, unidad, estado, modo)",
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

  _InventarioDataSource({required this.data});

  @override
  DataRow? getRow(int index) {
    if (index >= data.length) return null;
    final inv = data[index];

    final statusTxt = inv.agotado ? "Out" : (inv.estaBajo ? "Low" : "Ok");
    final statusColor = inv.agotado
        ? Colors.black54
        : (inv.estaBajo ? AppTheme.red : AppTheme.green);

    return DataRow.byIndex(
      index: index,
      cells: [
        DataCell(
          Text(inv.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        DataCell(Text(inv.categoria ?? "-")),
        DataCell(Text(inv.unidad.isEmpty ? "-" : inv.unidad)),
        DataCell(Text(inv.cantidad.toString())),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: statusColor.withOpacity(0.25)),
            ),
            child: Text(
              statusTxt,
              style: TextStyle(color: statusColor, fontWeight: FontWeight.w800),
            ),
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

  _HerramientaDataSource({required this.data});

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

    return DataRow.byIndex(
      index: index,
      cells: [
        DataCell(
          Text(h.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        DataCell(Text(h.unidad.isEmpty ? "-" : h.unidad)),
        DataCell(Text(h.modoControl.label)),
        DataCell(Text(h.cantidad.toString())),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: estadoColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: estadoColor.withOpacity(0.25)),
            ),
            child: Text(
              estadoTxt,
              style: TextStyle(color: estadoColor, fontWeight: FontWeight.w800),
            ),
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
      setState(() => _error = e.toString());
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
        SnackBar(content: Text("✅ Agregada: ${_selected!.nombre}")),
      );
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(context, SnackBar(content: Text("❌ $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Agregar herramienta al inventario"),
      content: SizedBox(
        width: 520,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              )
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
                    value: _selected,
                    decoration: const InputDecoration(
                      labelText: "Herramienta (catálogo)",
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
                          value: _estado,
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
        ),
      ],
    );
  }
}
