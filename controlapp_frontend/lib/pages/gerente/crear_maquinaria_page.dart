import 'package:flutter/material.dart';

import '../../api/empresa_api.dart';
import '../../api/gerente_api.dart';
import '../../model/conjunto_model.dart';
import '../../model/maquinaria_model.dart';
import '../../service/theme.dart';

import 'package:flutter_application_1/service/app_feedback.dart';

class CrearMaquinariaPage extends StatefulWidget {
  final String nit; // nit empresa
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

  PropietarioMaquinaria _prop = PropietarioMaquinaria.EMPRESA;
  String? _conjuntoPropId;

  List<Conjunto> _conjuntos = [];
  bool _loadingConjuntos = false;

  bool _saving = false;

  late final EmpresaApi _empresaApi;
  late final GerenteApi _gerenteApi;

  @override
  void initState() {
    super.initState();
    _empresaApi = EmpresaApi();
    _gerenteApi = GerenteApi();

    final m = widget.maquinaria;
    if (m != null) {
      _nombreCtrl.text = m.nombre;
      _marcaCtrl.text = m.marca;
      _tipo = m.tipo;
      _estado = m.estado;

      _prop = m.propietarioTipo!;
      _conjuntoPropId = m.conjuntoPropietarioId;

      if (_prop == PropietarioMaquinaria.CONJUNTO) {
        _cargarConjuntos(); // para que cargue el dropdown
      }
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _marcaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarConjuntos() async {
    setState(() => _loadingConjuntos = true);
    try {
      _conjuntos = await _gerenteApi.listarConjuntos();
    } finally {
      if (mounted) setState(() => _loadingConjuntos = false);
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    // Validación extra: si es CONJUNTO debe haber NIT
    if (_prop == PropietarioMaquinaria.CONJUNTO && _conjuntoPropId == null) {
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(
          content: Text('Selecciona el conjunto propietario.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final req = MaquinariaRequest(
        nombre: _nombreCtrl.text.trim(),
        marca: _marcaCtrl.text.trim(),
        tipo: _tipo,
        estado: _estado,
        propietarioTipo: _prop,
        conjuntoPropietarioId: _conjuntoPropId,
      );

      if (widget.modoEdicion && widget.maquinaria != null) {
        await _empresaApi.editarMaquinaria(widget.maquinaria!.id, req);
      } else {
        await _empresaApi.crearMaquinaria(req);
      }

      if (!mounted) return;
      await _mostrarGuardadoYVolverMenu();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text('Error al guardar maquinaria: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _mostrarGuardadoYVolverMenu() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Éxito'),
        content: const Text('Guardado correctamente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/home-gerente', (route) => false);
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
              TextFormField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre de la máquina',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().length < 2)
                    ? 'Nombre muy corto'
                    : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _marcaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Marca',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().length < 2)
                    ? 'Marca muy corta'
                    : null,
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<TipoMaquinariaFlutter>(
                value: _tipo,
                decoration: const InputDecoration(
                  labelText: 'Tipo de maquinaria',
                  border: OutlineInputBorder(),
                ),
                items: TipoMaquinariaFlutter.values
                    .map(
                      (t) => DropdownMenuItem(value: t, child: Text(t.label)),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _tipo = val);
                },
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<EstadoMaquinaria>(
                value: _estado,
                decoration: const InputDecoration(
                  labelText: 'Estado',
                  border: OutlineInputBorder(),
                ),
                items: EstadoMaquinaria.values
                    .map(
                      (e) => DropdownMenuItem(value: e, child: Text(e.label)),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _estado = val);
                },
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<PropietarioMaquinaria>(
                value: _prop,
                decoration: const InputDecoration(
                  labelText: 'Propietario',
                  border: OutlineInputBorder(),
                ),
                items: PropietarioMaquinaria.values
                    .map(
                      (p) => DropdownMenuItem(value: p, child: Text(p.label)),
                    )
                    .toList(),
                onChanged: (val) async {
                  if (val == null) return;
                  setState(() {
                    _prop = val;
                    _conjuntoPropId = null;
                  });

                  if (val == PropietarioMaquinaria.CONJUNTO) {
                    await _cargarConjuntos();
                  }
                },
              ),

              if (_prop == PropietarioMaquinaria.CONJUNTO) ...[
                const SizedBox(height: 12),
                _loadingConjuntos
                    ? const Center(child: CircularProgressIndicator())
                    : DropdownButtonFormField<String>(
                        value: _conjuntoPropId,
                        decoration: const InputDecoration(
                          labelText: 'Conjunto propietario',
                          border: OutlineInputBorder(),
                        ),
                        items: _conjuntos
                            .map(
                              (c) => DropdownMenuItem(
                                value: c.nit,
                                child: Text(c.nombre),
                              ),
                            )
                            .toList(),
                        validator: (v) =>
                            v == null ? 'Selecciona un conjunto' : null,
                        onChanged: (v) => setState(() => _conjuntoPropId = v),
                      ),
              ],

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
