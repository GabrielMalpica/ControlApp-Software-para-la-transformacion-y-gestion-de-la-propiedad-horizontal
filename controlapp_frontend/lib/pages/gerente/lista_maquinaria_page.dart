import 'package:flutter/material.dart';

import '../../api/empresa_api.dart';
import '../../model/maquinaria_model.dart';
import '../../service/theme.dart';
import 'crear_maquinaria_page.dart';

class ListaMaquinariaPage extends StatefulWidget {
  const ListaMaquinariaPage({super.key});

  @override
  State<ListaMaquinariaPage> createState() => _ListaMaquinariaPageState();
}

class _ListaMaquinariaPageState extends State<ListaMaquinariaPage> {
  final EmpresaApi _api = EmpresaApi();

  bool _cargando = false;
  List<MaquinariaResponse> _items = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final data = await _api.listarMaquinaria();
      if (!mounted) return;
      setState(() => _items = data);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cargar maquinaria: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _eliminar(MaquinariaResponse m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar maquinaria'),
        content: Text('¿Eliminar "${m.nombre}" (${m.marca})?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _api.eliminarMaquinaria(m.id);
      await _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Maquinaria eliminada')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al eliminar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _editar(MaquinariaResponse m) async {
    final actualizado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CrearMaquinariaPage(
          nit: '901191875-4',
          maquinaria: m, // 👈 le pasamos la maquinaria a editar
        ),
      ),
    );

    if (actualizado == true) {
      await _cargar();
    }
  }

  Future<void> _crearNueva() async {
    final creado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CrearMaquinariaPage(nit: '901191875-4'),
      ),
    );

    if (creado == true) {
      await _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.primary;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: primary,
        title: const Text(
          'Catálogo de maquinaria',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _crearNueva,
        child: const Icon(Icons.add),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? const Center(child: Text('No hay maquinaria registrada.'))
          : ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 0),
              itemBuilder: (context, index) {
                final m = _items[index];
                return ListTile(
                  title: Text('${m.nombre} (${m.marca})'),
                  subtitle: Text(
                    m.disponible
                        ? '${m.tipo.label} · ${m.estado.label} · Disponible'
                        : (m.conjuntoNombre != null
                              ? '${m.tipo.label} · ${m.estado.label} · Prestada a ${m.conjuntoNombre}'
                              : '${m.tipo.label} · ${m.estado.label} · Prestada'),
                  ),

                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _editar(m),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _eliminar(m),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
