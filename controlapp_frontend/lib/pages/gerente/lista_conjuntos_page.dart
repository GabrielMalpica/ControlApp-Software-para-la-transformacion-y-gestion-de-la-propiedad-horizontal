import 'package:flutter/material.dart';
import '../../service/theme.dart';
import '../../api/gerente_api.dart';
import '../../model/conjunto_model.dart';
import 'detalle_conjunto_page.dart';
import '../gerente/crear_conjunto_page.dart';

class ListaConjuntosPage extends StatefulWidget {
  final String nit;

  const ListaConjuntosPage({super.key, required this.nit});

  @override
  State<ListaConjuntosPage> createState() => _ListaConjuntosPageState();
}

class _ListaConjuntosPageState extends State<ListaConjuntosPage> {
  final GerenteApi _api = GerenteApi();
  late Future<List<Conjunto>> _futureConjuntos;

  @override
  void initState() {
    super.initState();
    _loadConjuntos();
  }

  void _loadConjuntos() {
    setState(() {
      _futureConjuntos = _api.listarConjuntos();
    });
  }

  Future<void> _confirmarEliminar(Conjunto c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar conjunto'),
        content: Text(
          '¿Seguro que deseas eliminar el conjunto "${c.nombre}" (${c.nit})?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _api.eliminarConjunto(c.nit);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Conjunto eliminado'),
          backgroundColor: Colors.green,
        ),
      );
      _loadConjuntos();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error al eliminar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Color _estadoColor(bool activo) => activo ? Colors.green : Colors.redAccent;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: const Text('Conjuntos', style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            tooltip: 'Crear conjunto',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CrearConjuntoPage(nit: widget.nit),
                ),
              ).then((_) => _loadConjuntos());
            },
            icon: const Icon(Icons.add_business, color: Colors.white),
          ),
        ],
      ),
      body: FutureBuilder<List<Conjunto>>(
        future: _futureConjuntos,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final conjuntos = snapshot.data ?? [];

          if (conjuntos.isEmpty) {
            return const Center(child: Text('No hay conjuntos registrados.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: conjuntos.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final c = conjuntos[index];
              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DetalleConjuntoPage(conjuntoNit: c.nit),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        // Icono
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.apartment,
                            color: Colors.blueGrey,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Info principal
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.nombre,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'NIT: ${c.nit}',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                c.direccion,
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Chip(
                                    label: Text(
                                      c.activo ? 'Activo' : 'Inactivo',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                      ),
                                    ),
                                    backgroundColor: _estadoColor(c.activo),
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  if (c.valorMensual != null)
                                    Chip(
                                      label: Text(
                                        '\$${c.valorMensual!.toStringAsFixed(0)} / mes',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                        ),
                                      ),
                                      backgroundColor: Colors.indigo,
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Botones acción
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Editar',
                              icon: const Icon(Icons.edit, size: 20),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => DetalleConjuntoPage(
                                      conjuntoNit: c.nit,
                                      modoEdicionBasico: true,
                                    ),
                                  ),
                                ).then((_) => _loadConjuntos());
                              },
                            ),
                            IconButton(
                              tooltip: 'Eliminar',
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 20,
                                color: Colors.redAccent,
                              ),
                              onPressed: () => _confirmarEliminar(c),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
