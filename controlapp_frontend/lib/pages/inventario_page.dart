import 'package:flutter/material.dart';
import '../service/theme.dart';
import '../api/inventario_api.dart';
import '../model/inventario_item_model.dart';
import 'solicitud_insumo_page.dart';

class InventarioPage extends StatefulWidget {
  final String nit; // NIT conjunto

  const InventarioPage({super.key, required this.nit});

  @override
  State<InventarioPage> createState() => _InventarioPageState();
}

class _InventarioPageState extends State<InventarioPage> {
  final InventarioApi _api = InventarioApi();

  bool _cargando = false;
  List<InventarioItemResponse> _items = [];
  String _q = '';

  // Tabla
  int _rowsPerPage =
      8; // ✅ permitido porque lo incluimos en availableRowsPerPage
  int? _sortColumnIndex;
  bool _sortAscending = true;

  // Selección (checkbox)
  final Set<int> _selectedInsumoIds = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final data = await _api.listarInventarioConjunto(widget.nit);
      if (!mounted) return;

      setState(() {
        _items = data;

        // Limpia selección de ítems que ya no existen (por si refresca)
        _selectedInsumoIds.removeWhere(
          (id) => !_items.any((x) => x.insumoId == id),
        );
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error cargando inventario: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  List<InventarioItemResponse> get _filtrados {
    final t = _q.trim().toLowerCase();
    if (t.isEmpty) return List.of(_items);

    return _items.where((x) {
      return x.nombre.toLowerCase().contains(t) ||
          (x.categoria ?? '').toLowerCase().contains(t) ||
          x.unidad.toLowerCase().contains(t);
    }).toList();
  }

  void _sort<T extends Comparable<T>>(
    int columnIndex,
    bool ascending,
    T Function(InventarioItemResponse d) getField,
  ) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;

      // Ordenamos la lista base para que paginación sea coherente
      _items.sort((a, b) {
        final av = getField(a);
        final bv = getField(b);
        return ascending ? av.compareTo(bv) : bv.compareTo(av);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _filtrados;

    final bajos = _items.where((e) => e.estaBajo && !e.agotado).length;
    final agotados = _items.where((e) => e.agotado).length;

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
            // ===== Toolbar superior tipo dashboard =====
            Row(
              children: [
                const Spacer(),

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
              ],
            ),

            const SizedBox(height: 12),

            // ===== Search + chips =====
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: TextField(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: "Buscar (nombre, categoría, unidad)",
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
                _chipCount("Bajos", bajos, AppTheme.red),
                const SizedBox(width: 8),
                _chipCount("Agotados", agotados, Colors.black54),
              ],
            ),

            const SizedBox(height: 12),

            // ===== Tabla =====
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator())
                  : filtrados.isEmpty
                  ? const Center(
                      child: Text(
                        "Este conjunto no tiene insumos en inventario.",
                      ),
                    )
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
                                "Products",
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),

                              // ✅ ESTO ES LO QUE ARREGLA TU ERROR
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
                                  onSort: (i, asc) => _sort<String>(
                                    i,
                                    asc,
                                    (d) => d.nombre.toLowerCase(),
                                  ),
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
                                  onSort: (i, asc) => _sort<String>(
                                    i,
                                    asc,
                                    (d) => d.unidad.toLowerCase(),
                                  ),
                                ),
                                DataColumn(
                                  numeric: true,
                                  label: const Text("AVAILABLE"),
                                  onSort: (i, asc) =>
                                      _sort<num>(i, asc, (d) => d.cantidad),
                                ),
                                const DataColumn(label: Text("THRESHOLD")),
                                const DataColumn(label: Text("STATUS")),
                              ],

                              source: _InventarioDataSource(
                                data: filtrados,
                                selectedIds: _selectedInsumoIds,
                                onSelectionChanged: () => setState(() {}),
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
}

// ================= DataSource =================

class _InventarioDataSource extends DataTableSource {
  final List<InventarioItemResponse> data;
  final Set<int> selectedIds; // insumoId
  final VoidCallback onSelectionChanged;

  _InventarioDataSource({
    required this.data,
    required this.selectedIds,
    required this.onSelectionChanged,
  });

  @override
  DataRow? getRow(int index) {
    if (index >= data.length) return null;
    final inv = data[index];

    final rowId = inv.insumoId;
    final isSelected = selectedIds.contains(rowId);

    final statusTxt = inv.agotado ? "Out" : (inv.estaBajo ? "Low" : "Ok");
    final statusColor = inv.agotado
        ? Colors.black54
        : (inv.estaBajo ? AppTheme.red : AppTheme.green);

    return DataRow.byIndex(
      index: index,
      selected: isSelected,
      onSelectChanged: (v) {
        if (v == null) return;

        if (v) {
          selectedIds.add(rowId);
        } else {
          selectedIds.remove(rowId);
        }

        onSelectionChanged();
        notifyListeners();
      },
      cells: [
        DataCell(
          Text(inv.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        DataCell(Text(inv.categoria ?? "-")),
        DataCell(Text(inv.unidad.isEmpty ? "-" : inv.unidad)),
        DataCell(Text(inv.cantidad.toString())),
        DataCell(Text(inv.umbralUsado?.toString() ?? "-")),
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
  int get selectedRowCount => selectedIds.length;
}
