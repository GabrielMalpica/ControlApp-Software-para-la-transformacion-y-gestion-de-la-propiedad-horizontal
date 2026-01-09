import 'package:flutter/material.dart';

import '../../api/empresa_api.dart';
import '../../model/maquinaria_model.dart';
import '../../service/theme.dart';

class CrearMaquinariaPage extends StatefulWidget {
  final String nit; // por consistencia con otras páginas
  final MaquinariaResponse? maquinaria; // null = crear, no null = editar

  const CrearMaquinariaPage({super.key, required this.nit, this.maquinaria});

  bool get modoEdicion => maquinaria != null;

  @override
  State<CrearMaquinariaPage> createState() => _CrearMaquinariaPageState();
}

class _CrearMaquinariaPageState extends State<CrearMaquinariaPage> {
  final _formKey = GlobalKey<FormState>();

  final _nombreCtrl = TextEditingController();
  final _marcaCtrl = TextEditingController();

  TipoMaquinariaFlutter _tipo = TipoMaquinariaFlutter.OTRO;
  EstadoMaquinaria _estado = EstadoMaquinaria.OPERATIVA;
  bool _disponible = true;

  bool _saving = false;

  late final EmpresaApi _empresaApi;

  @override
  void initState() {
    super.initState();
    _empresaApi = EmpresaApi();

    // Si viene maquinaria → estamos editando → rellenamos campos
    final m = widget.maquinaria;
    if (m != null) {
      _nombreCtrl.text = m.nombre;
      _marcaCtrl.text = m.marca;
      _tipo = m.tipo;
      _estado = m.estado;
      _disponible = m.disponible;
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _marcaCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final req = MaquinariaRequest(
        nombre: _nombreCtrl.text.trim(),
        marca: _marcaCtrl.text.trim(),
        tipo: _tipo,
        estado: _estado,
        disponible: _disponible,
      );

      if (widget.modoEdicion && widget.maquinaria != null) {
        // 🔧 Modo edición
        await _empresaApi.editarMaquinaria(widget.maquinaria!.id, req);
      } else {
        // ➕ Modo creación
        await _empresaApi.crearMaquinaria(req);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.modoEdicion
                ? 'Maquinaria actualizada'
                : 'Maquinaria creada en el catálogo',
          ),
        ),
      );
      Navigator.of(context).pop(true); // <- esto hace que Lista recargue
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar maquinaria: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.modoEdicion;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: Text(
          isEdit ? 'Editar maquinaria' : 'Crear maquinaria',
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Nombre
              TextFormField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre de la máquina',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().length < 2) {
                    return 'Nombre muy corto';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Marca
              TextFormField(
                controller: _marcaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Marca',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().length < 2) {
                    return 'Marca muy corta';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Tipo
              DropdownButtonFormField<TipoMaquinariaFlutter>(
                value: _tipo,
                decoration: const InputDecoration(
                  labelText: 'Tipo de maquinaria',
                  border: OutlineInputBorder(),
                ),
                items: TipoMaquinariaFlutter.values.map((t) {
                  return DropdownMenuItem(value: t, child: Text(t.label));
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _tipo = val);
                },
              ),
              const SizedBox(height: 12),

              // Estado
              DropdownButtonFormField<EstadoMaquinaria>(
                value: _estado,
                decoration: const InputDecoration(
                  labelText: 'Estado',
                  border: OutlineInputBorder(),
                ),
                items: EstadoMaquinaria.values.map((e) {
                  return DropdownMenuItem(value: e, child: Text(e.label));
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _estado = val);
                },
              ),
              const SizedBox(height: 12),

              // Disponible
              SwitchListTile(
                title: const Text('Disponible'),
                value: _disponible,
                onChanged: (val) {
                  setState(() => _disponible = val);
                },
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(
                    _saving
                        ? (isEdit ? 'Guardando cambios...' : 'Guardando...')
                        : (isEdit ? 'Guardar cambios' : 'Guardar maquinaria'),
                  ),
                  onPressed: _saving ? null : _guardar,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
