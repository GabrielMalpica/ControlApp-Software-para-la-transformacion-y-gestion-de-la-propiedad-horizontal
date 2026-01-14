// lib/pages/solicitudes_page.dart
import 'package:flutter/material.dart';
import '../service/theme.dart';
import '../api/solicitud_insumo_api.dart';
import '../service/app_constants.dart';

enum EstadoSolicitudUi { PENDIENTE, APROBADA }

extension EstadoSolicitudUiExt on EstadoSolicitudUi {
  String get label =>
      this == EstadoSolicitudUi.PENDIENTE ? 'Pendiente' : 'Aprobada';
}

class SolicitudesPage extends StatefulWidget {
  final String nit; // conjunto nit
  const SolicitudesPage({super.key, required this.nit});

  @override
  State<SolicitudesPage> createState() => _SolicitudesPageState();
}

class _SolicitudesPageState extends State<SolicitudesPage> {
  late final SolicitudInsumoApi _api;

  bool _cargando = false;
  String? _error;

  List<SolicitudInsumoResponse> _items = [];

  EstadoSolicitudUi? _estadoFiltro; // null = todos

  @override
  void initState() {
    super.initState();
    _api = SolicitudInsumoApi(baseUrl: AppConstants.baseUrl);
    _cargar();
  }

  Color _estadoColor(EstadoSolicitudUi estado) {
    return estado == EstadoSolicitudUi.PENDIENTE ? Colors.orange : Colors.green;
  }

  EstadoSolicitudUi _estadoDe(SolicitudInsumoResponse s) {
    return s.aprobado
        ? EstadoSolicitudUi.APROBADA
        : EstadoSolicitudUi.PENDIENTE;
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final data = await _api.listar(conjuntoId: widget.nit);

      // filtrar por estado (si aplica)
      final filtered = data.where((s) {
        if (_estadoFiltro == null) return true;
        return _estadoDe(s) == _estadoFiltro;
      }).toList();

      // ordenar por fecha desc (si viene)
      filtered.sort((a, b) {
        final fa = a.fechaSolicitud ?? DateTime.fromMillisecondsSinceEpoch(0);
        final fb = b.fechaSolicitud ?? DateTime.fromMillisecondsSinceEpoch(0);
        return fb.compareTo(fa);
      });

      if (!mounted) return;
      setState(() => _items = filtered);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _aprobar(SolicitudInsumoResponse s) async {
    try {
      await _api.aprobar(s.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Solicitud aprobada ✅')));
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error aprobando: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _rechazar(SolicitudInsumoResponse s) async {
    try {
      await _api.rechazar(s.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Solicitud rechazada 🧾')));
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error rechazando: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _mostrarDetalles(SolicitudInsumoResponse s) {
    final estado = _estadoDe(s);

    // Armamos una “mini descripción” bonita
    final resumen = s.items.isEmpty
        ? 'Solicitud de insumos'
        : 'Solicitud: ${s.items.take(2).map((it) => it.nombre ?? "Insumo ${it.insumoId}").join(", ")}${s.items.length > 2 ? "..." : ""}';

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Solicitud #${s.id} · Insumos'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Estado: ${estado.label}'),
              const SizedBox(height: 6),
              Text('Fecha: ${(s.fechaSolicitud ?? DateTime.now()).toLocal()}'),
              const SizedBox(height: 10),
              Text('Descripción: $resumen'),
              const SizedBox(height: 12),
              const Text(
                'Ítems solicitados',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (s.items.isEmpty)
                const Text('Sin detalle de ítems.')
              else
                ...s.items.map((it) {
                  final nombre = it.nombre ?? 'Insumo ${it.insumoId}';
                  final unidad = (it.unidad ?? '').trim();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(child: Text(nombre)),
                        Text(
                          unidad.isEmpty
                              ? '${it.cantidad}'
                              : '${it.cantidad} $unidad',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
          if (estado == EstadoSolicitudUi.PENDIENTE) ...[
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _rechazar(s);
              },
              child: const Text(
                'Rechazar',
                style: TextStyle(color: Colors.red),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _aprobar(s);
              },
              child: const Text('Aprobar'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _badge(EstadoSolicitudUi estado) {
    final c = _estadoColor(estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        estado.label,
        style: TextStyle(color: c, fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: Text(
          "Solicitudes - Proyecto ${widget.nit}",
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            tooltip: 'Refrescar',
            onPressed: _cargar,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filtro estado
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<EstadoSolicitudUi?>(
                    value: _estadoFiltro,
                    decoration: const InputDecoration(
                      labelText: 'Estado',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem<EstadoSolicitudUi?>(
                        value: null,
                        child: Text('Todos'),
                      ),
                      DropdownMenuItem<EstadoSolicitudUi?>(
                        value: EstadoSolicitudUi.PENDIENTE,
                        child: Text('Pendiente'),
                      ),
                      DropdownMenuItem<EstadoSolicitudUi?>(
                        value: EstadoSolicitudUi.APROBADA,
                        child: Text('Aprobada'),
                      ),
                    ],
                    onChanged: (v) {
                      setState(() => _estadoFiltro = v);
                      _cargar();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  tooltip: 'Limpiar filtro',
                  onPressed: () {
                    setState(() => _estadoFiltro = null);
                    _cargar();
                  },
                  icon: const Icon(Icons.filter_alt_off),
                ),
              ],
            ),
          ),

          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text('Error: $_error'))
                : _items.isEmpty
                ? const Center(child: Text('No hay solicitudes.'))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final s = _items[index];
                      final estado = _estadoDe(s);

                      final resumen = s.items.isEmpty
                          ? 'Solicitud de insumos'
                          : 'Solicitud: ${s.items.take(2).map((it) => it.nombre ?? "Insumo ${it.insumoId}").join(", ")}${s.items.length > 2 ? "..." : ""}';

                      final fecha = (s.fechaSolicitud ?? DateTime.now())
                          .toLocal();

                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        child: ListTile(
                          leading: Icon(
                            Icons.shopping_cart,
                            color: AppTheme.primary,
                          ),
                          title: Text(resumen),
                          subtitle: Text("Fecha: $fecha  |  Tipo: Insumos"),
                          trailing: _badge(estado),
                          onTap: () => _mostrarDetalles(s),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
