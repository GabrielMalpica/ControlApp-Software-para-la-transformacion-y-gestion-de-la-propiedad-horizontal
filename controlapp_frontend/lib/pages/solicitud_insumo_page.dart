import 'package:flutter/material.dart';
import '../service/theme.dart';
import '../api/inventario_api.dart';
import '../api/solicitud_insumo_api.dart';
import '../model/inventario_item_model.dart';
import '../model/insumo_model.dart';
import '../model/solicitud_insumo_model.dart';
import '../service/app_constants.dart';

class SolicitudInsumoPage extends StatefulWidget {
  final String conjuntoNit;
  const SolicitudInsumoPage({super.key, required this.conjuntoNit});

  @override
  State<SolicitudInsumoPage> createState() => _SolicitudInsumoPageState();
}

class _SolicitudInsumoPageState extends State<SolicitudInsumoPage> {
  final InventarioApi _api = InventarioApi();

  // ✅ Nuevo: API de solicitud (la que realmente hace POST /solicitud-insumo)
  late final SolicitudInsumoApi _solApi;

  bool _cargando = false;

  List<InventarioItemResponse> _bajos = [];
  List<InsumoResponse> _catalogo = [];

  // carrito: insumoId -> cantidad
  final Map<int, int> _carrito = {};

  String _q = '';

  @override
  void initState() {
    super.initState();

    _solApi = SolicitudInsumoApi(
      baseUrl: AppConstants.baseUrl,
      // authToken: ... si lo manejas
    );

    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final bajos = await _api.listarInsumosBajos(widget.conjuntoNit);

      // ✅ OJO: tu método está usando AppConstants.empresaNit, está bien
      final cat = await _api.listarCatalogoInsumosEmpresa(
        AppConstants.empresaNit,
      );

      if (!mounted) return;
      setState(() {
        _bajos = bajos;
        _catalogo = cat;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error cargando solicitud: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _sumar(int insumoId, {int delta = 1}) {
    setState(() {
      final actual = _carrito[insumoId] ?? 0;
      final nuevo = actual + delta;
      if (nuevo <= 0) {
        _carrito.remove(insumoId);
      } else {
        _carrito[insumoId] = nuevo;
      }
    });
  }

  Future<void> _enviar() async {
    if (_carrito.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No has agregado insumos a la solicitud.'),
        ),
      );
      return;
    }

    setState(() => _cargando = true);

    try {
      // ✅ Convertimos carrito a lista tipada (lo que pide el backend: items[])
      final items = _carrito.entries
          .map(
            (e) =>
                SolicitudInsumoItemRequest(insumoId: e.key, cantidad: e.value),
          )
          .toList();

      final req = SolicitudInsumoRequest(
        conjuntoId: widget.conjuntoNit,
        empresaId: AppConstants
            .empresaNit, // opcional, pero útil si tu backend lo guarda
        items: items, // ✅ clave "items" garantizada
      );

      await _solApi.crearSolicitud(req);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Solicitud enviada ✅')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al enviar solicitud: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogoFiltrado = _catalogo.where((x) {
      if (_q.trim().isEmpty) return true;
      final t = _q.toLowerCase();
      return x.nombre.toLowerCase().contains(t) ||
          x.unidad.toLowerCase().contains(t);
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: const Text(
          'Solicitud de insumos',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: _cargar,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(12),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _carrito.isEmpty
                      ? 'Carrito vacío'
                      : 'Ítems: ${_carrito.length} · Total: ${_carrito.values.fold<int>(0, (a, b) => a + b)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _cargando ? null : _enviar,
                icon: const Icon(Icons.send),
                label: const Text('Enviar'),
              ),
            ],
          ),
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionTitle('Recomendados (bajo stock / agotados)'),
                const SizedBox(height: 8),
                _bajos.isEmpty
                    ? _hint(
                        'No hay insumos bajos. Hoy el inventario está “en control” 😄',
                      )
                    : Column(
                        children: _bajos.map((x) {
                          final esAgotado = x.agotado;
                          return Card(
                            child: ListTile(
                              leading: Icon(
                                esAgotado
                                    ? Icons.warning_amber_rounded
                                    : Icons.report,
                                color: esAgotado
                                    ? Colors.black54
                                    : AppTheme.red,
                              ),
                              title: Text(
                                x.nombre,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                'Stock: ${x.cantidad} ${x.unidad}'
                                '${x.umbralUsado != null ? " · Umbral ${x.umbralUsado}" : ""}',
                              ),
                              trailing: _qtyControls(x.insumoId),
                            ),
                          );
                        }).toList(),
                      ),

                const SizedBox(height: 14),
                const Divider(),

                _sectionTitle('Catálogo de la empresa'),
                const SizedBox(height: 10),
                TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Buscar en catálogo...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onChanged: (v) => setState(() => _q = v),
                ),
                const SizedBox(height: 10),

                ...catalogoFiltrado.map((i) {
                  return Card(
                    child: ListTile(
                      leading: Icon(Icons.inventory, color: AppTheme.primary),
                      title: Text(
                        i.nombre,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Unidad: ${i.unidad} · ${i.categoria.name}',
                      ),
                      trailing: _qtyControls(i.id),
                    ),
                  );
                }),

                const SizedBox(height: 80),
              ],
            ),
    );
  }

  Widget _qtyControls(int insumoId) {
    final qty = _carrito[insumoId] ?? 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Quitar',
          onPressed: () => _sumar(insumoId, delta: -1),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Text('$qty', style: const TextStyle(fontWeight: FontWeight.w700)),
        IconButton(
          tooltip: 'Agregar',
          onPressed: () => _sumar(insumoId, delta: 1),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }

  Widget _sectionTitle(String t) => Text(
    t,
    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
  );

  Widget _hint(String t) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.black12),
    ),
    child: Text(t),
  );
}
