import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/empresa_api.dart';
import '../../model/insumo_model.dart';

import 'package:flutter_application_1/service/app_feedback.dart';

class CrearInsumoPage extends StatefulWidget {
  final String nit; // NIT de la empresa

  const CrearInsumoPage({super.key, required this.nit});

  @override
  State<CrearInsumoPage> createState() => _CrearInsumoPageState();
}

class _CrearInsumoPageState extends State<CrearInsumoPage> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _unidadCtrl = TextEditingController();
  final _umbralCtrl = TextEditingController();

  CategoriaInsumo _categoria = CategoriaInsumo.LIMPIEZA;
  bool _saving = false;

  late final EmpresaApi _api;

  @override
  void initState() {
    super.initState();
    _api = EmpresaApi();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _unidadCtrl.dispose();
    _umbralCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    final nombre = _nombreCtrl.text.trim();
    final unidad = _unidadCtrl.text.trim();
    final umbralStr = _umbralCtrl.text.trim();
    final umbral = umbralStr.isEmpty ? null : int.tryParse(umbralStr);

    setState(() => _saving = true);

    try {
      final req = InsumoRequest(
        nombre: nombre,
        unidad: unidad,
        categoria: _categoria,
        umbralBajo: umbral,
      );

      // 🔽 SOLO ESTA LÍNEA IMPORTA
      final creado = await _api.crearInsumoCatalogo(req);

      if (!mounted) return;

      AppFeedback.showFromSnackBar(
        context,
        SnackBar(content: Text('Insumo creado: ${creado.nombre}')),
      );
      Navigator.of(context).pop(creado);
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text('Error al crear insumo: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // final primary = AppTheme.primary; // si tienes tu tema
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: primary,
        title: const Text(
          'Nuevo insumo (catálogo)',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Nombre
                    TextFormField(
                      controller: _nombreCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del insumo',
                        hintText: 'Ej: Hipoclorito, Detergente, etc.',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (value == null || value.trim().length < 2) {
                          return 'Ingresa un nombre válido (mínimo 2 caracteres)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Unidad
                    TextFormField(
                      controller: _unidadCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Unidad',
                        hintText: 'Ej: L, kg, und',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Ingresa la unidad de medida';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Categoría
                    DropdownButtonFormField<CategoriaInsumo>(
                      value: _categoria,
                      decoration: const InputDecoration(
                        labelText: 'Categoría',
                        border: OutlineInputBorder(),
                      ),
                      items: CategoriaInsumo.values.map((cat) {
                        return DropdownMenuItem(
                          value: cat,
                          child: Text(cat.label),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _categoria = value);
                      },
                    ),
                    const SizedBox(height: 16),

                    // Umbral bajo (opcional)
                    TextFormField(
                      controller: _umbralCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Umbral bajo (opcional)',
                        hintText: 'Ej: 10',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return null;
                        final n = int.tryParse(value.trim());
                        if (n == null || n < 0) {
                          return 'Ingresa un número entero válido';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _guardar,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save),
                        label: Text(
                          _saving ? 'Guardando...' : 'Guardar insumo',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
