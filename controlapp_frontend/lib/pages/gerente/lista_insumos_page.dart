import 'package:flutter/material.dart';

import '../../api/empresa_api.dart';
import '../../model/insumo_model.dart';
import '../../service/theme.dart';

import 'package:flutter_application_1/service/app_feedback.dart';

class ListaInsumosPage extends StatefulWidget {
  const ListaInsumosPage({super.key});

  @override
  State<ListaInsumosPage> createState() => _ListaInsumosPageState();
}

class _ListaInsumosPageState extends State<ListaInsumosPage> {
  final EmpresaApi _api = EmpresaApi();

  bool _cargando = false;
  List<InsumoResponse> _insumos = [];

  @override
  void initState() {
    super.initState();
    _cargarInsumos();
  }

  Future<void> _cargarInsumos() async {
    setState(() => _cargando = true);
    try {
      final data = await _api.listarCatalogo();
      if (!mounted) return;
      setState(() => _insumos = data);
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text('Error al cargar insumos: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _confirmarEliminar(InsumoResponse insumo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar insumo'),
        content: Text('¿Seguro que deseas eliminar "${insumo.nombre}"?'),
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
      await _api.eliminarInsumo(insumo.id);
      await _cargarInsumos();
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text('Insumo eliminado')),
      );
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text('Error al eliminar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _editarInsumo(InsumoResponse insumo) async {
    final nombreCtrl = TextEditingController(text: insumo.nombre);
    final unidadCtrl = TextEditingController(text: insumo.unidad);
    final umbralCtrl = TextEditingController(
      text: insumo.umbralBajo?.toString() ?? '',
    );
    CategoriaInsumo categoria = insumo.categoria;

    final formKey = GlobalKey<FormState>();

    final guardado = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Editar insumo'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: (v) {
                    if (v == null || v.trim().length < 2) {
                      return 'Nombre muy corto';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: unidadCtrl,
                  decoration: const InputDecoration(labelText: 'Unidad'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Unidad requerida';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<CategoriaInsumo>(
                  value: categoria,
                  decoration: const InputDecoration(labelText: 'Categoría'),
                  items: CategoriaInsumo.values.map((cat) {
                    return DropdownMenuItem(value: cat, child: Text(cat.label));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) categoria = val;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: umbralCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Umbral bajo (opcional)',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    final n = int.tryParse(v.trim());
                    if (n == null || n < 0) {
                      return 'Número inválido';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(context).pop(true);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (guardado != true) return;

    final umbralStr = umbralCtrl.text.trim();
    final umbral = umbralStr.isEmpty ? null : int.tryParse(umbralStr);

    try {
      final req = InsumoRequest(
        nombre: nombreCtrl.text.trim(),
        unidad: unidadCtrl.text.trim(),
        categoria: categoria,
        umbralBajo: umbral,
      );
      await _api.editarInsumo(insumo.id, req);
      await _cargarInsumos();
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text('Insumo actualizado')),
      );
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text('Error al actualizar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.primary;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: primary,
        title: const Text(
          'Catálogo de insumos',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: _cargarInsumos,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _insumos.isEmpty
          ? const Center(child: Text('No hay insumos en el catálogo.'))
          : ListView.separated(
              itemCount: _insumos.length,
              separatorBuilder: (_, __) => const Divider(height: 0),
              itemBuilder: (context, index) {
                final i = _insumos[index];
                return ListTile(
                  title: Text(i.nombre),
                  subtitle: Text(
                    '${i.unidad} · ${i.categoria.label} · Umbral: ${i.umbralBajo ?? '-'}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _editarInsumo(i),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _confirmarEliminar(i),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
