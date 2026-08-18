import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/gerente_api.dart';
import 'package:flutter_application_1/api/residentes_api.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/model/residente_admin_models.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/widgets/skeleton.dart';

class CrearResidentePage extends StatefulWidget {
  const CrearResidentePage({
    super.key,
    this.conjuntoFijoNit,
    this.conjuntoFijoNombre,
  });

  final String? conjuntoFijoNit;
  final String? conjuntoFijoNombre;

  @override
  State<CrearResidentePage> createState() => _CrearResidentePageState();
}

class _CrearResidentePageState extends State<CrearResidentePage> {
  final _formKey = GlobalKey<FormState>();
  final _residentesApi = ResidentesApi();
  final _gerenteApi = GerenteApi();

  final _cedulaCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _correoCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _sectorCtrl = TextEditingController();
  final _unidadCtrl = TextEditingController();

  List<Conjunto> _conjuntos = const [];
  String? _conjuntoNit;
  String _tipoUnidad = 'APARTAMENTO';
  bool _loadingConjuntos = false;
  bool _saving = false;
  String? _error;
  ResidenteCreado? _creado;

  bool get _conjuntoBloqueado =>
      widget.conjuntoFijoNit != null &&
      widget.conjuntoFijoNit!.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (_conjuntoBloqueado) {
      _conjuntoNit = widget.conjuntoFijoNit!.trim();
    } else {
      _cargarConjuntos();
    }
  }

  @override
  void dispose() {
    _cedulaCtrl.dispose();
    _nombreCtrl.dispose();
    _correoCtrl.dispose();
    _telefonoCtrl.dispose();
    _sectorCtrl.dispose();
    _unidadCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarConjuntos() async {
    setState(() {
      _loadingConjuntos = true;
      _error = null;
    });

    try {
      final conjuntos = await _gerenteApi.listarConjuntos();
      if (!mounted) return;
      setState(() {
        _conjuntos = conjuntos;
        _conjuntoNit = conjuntos.isNotEmpty ? conjuntos.first.nit : null;
        _loadingConjuntos = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingConjuntos = false;
        _error = AppError.messageOf(
          e,
          fallback: 'No se pudieron cargar los conjuntos.',
        );
      });
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if ((_conjuntoNit ?? '').isEmpty) {
      setState(() => _error = 'Selecciona un conjunto para continuar.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _creado = null;
    });

    try {
      final creado = await _residentesApi.crearResidenteManual(
        conjuntoId: _conjuntoNit!,
        cedula: _cedulaCtrl.text,
        nombre: _nombreCtrl.text,
        correo: _correoCtrl.text,
        telefono: _telefonoCtrl.text,
        tipoUnidad: _tipoUnidad,
        sector: _tipoUnidad == 'CASA' ? null : _sectorCtrl.text,
        unidad: _unidadCtrl.text,
      );

      if (!mounted) return;
      setState(() {
        _creado = creado;
        _saving = false;
      });
      _formKey.currentState!.reset();
      _cedulaCtrl.clear();
      _nombreCtrl.clear();
      _correoCtrl.clear();
      _telefonoCtrl.clear();
      _sectorCtrl.clear();
      _unidadCtrl.clear();
      _tipoUnidad = 'APARTAMENTO';
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = AppError.messageOf(
          e,
          fallback: 'No se pudo crear el residente.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear residente')),
      body: _loadingConjuntos
          ? const SkeletonList()
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Alta manual de residentes',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'El usuario queda creado con correo como acceso y cedula como contrasena temporal. En el primer ingreso se le exigira cambiarla.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 18),
                          if (_conjuntoBloqueado)
                            _ReadOnlyField(
                              label: 'Conjunto',
                              value:
                                  widget.conjuntoFijoNombre ??
                                  _conjuntoNit ??
                                  '',
                            )
                          else
                            DropdownButtonFormField<String>(
                              initialValue: _conjuntoNit,
                              decoration: const InputDecoration(
                                labelText: 'Conjunto',
                              ),
                              items: _conjuntos
                                  .map(
                                    (c) => DropdownMenuItem(
                                      value: c.nit,
                                      child: Text(c.nombre),
                                    ),
                                  )
                                  .toList(),
                              onChanged: _saving
                                  ? null
                                  : (value) =>
                                        setState(() => _conjuntoNit = value),
                            ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _cedulaCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Cedula',
                            ),
                            validator: (value) =>
                                (value == null || value.trim().length < 5)
                                ? 'Ingresa una cedula valida.'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _nombreCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nombre completo',
                            ),
                            validator: (value) =>
                                (value == null || value.trim().length < 3)
                                ? 'Ingresa el nombre del residente.'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _correoCtrl,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Correo',
                            ),
                            validator: (value) =>
                                (value == null || !value.contains('@'))
                                ? 'Ingresa un correo valido.'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _telefonoCtrl,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Teléfono (opcional)',
                            ),
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            initialValue: _tipoUnidad,
                            decoration: const InputDecoration(
                              labelText: 'Tipo de unidad',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'APARTAMENTO',
                                child: Text('Apartamento'),
                              ),
                              DropdownMenuItem(
                                value: 'CASA',
                                child: Text('Casa'),
                              ),
                              DropdownMenuItem(
                                value: 'OFICINA',
                                child: Text('Oficina'),
                              ),
                              DropdownMenuItem(
                                value: 'LOCAL',
                                child: Text('Local'),
                              ),
                            ],
                            onChanged: _saving
                                ? null
                                : (value) => setState(
                                    () => _tipoUnidad = value ?? 'APARTAMENTO',
                                  ),
                          ),
                          const SizedBox(height: 14),
                          if (_tipoUnidad != 'CASA') ...[
                            TextFormField(
                              controller: _sectorCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Sector / torre / bloque (opcional)',
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                          TextFormField(
                            controller: _unidadCtrl,
                            decoration: InputDecoration(
                              labelText: _tipoUnidad == 'CASA'
                                  ? 'Casa / unidad'
                                  : 'Apartamento / unidad',
                            ),
                            validator: (value) =>
                                (value == null || value.trim().isEmpty)
                                ? 'Ingresa la unidad residencial.'
                                : null,
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Text(
                              _error!,
                              style: const TextStyle(color: AppTheme.red),
                            ),
                          ],
                          const SizedBox(height: 18),
                          ElevatedButton.icon(
                            onPressed: _saving ? null : _guardar,
                            icon: const Icon(Icons.person_add_alt_1),
                            label: Text(
                              _saving ? 'Creando...' : 'Crear residente',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_creado != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: const Color(0xFFEAF6EE),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Residente creado correctamente',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: AppTheme.primaryDark),
                          ),
                          const SizedBox(height: 10),
                          Text('${_creado!.nombre} - ${_creado!.correo}'),
                          const SizedBox(height: 6),
                          Text('Conjunto: ${_creado!.conjuntoNombre}'),
                          const SizedBox(height: 6),
                          Text('Usuario: ${_creado!.credencialUsuario}'),
                          const SizedBox(height: 6),
                          Text(
                            'Contrasena temporal: ${_creado!.credencialTemporal}',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value,
      enabled: false,
      decoration: InputDecoration(labelText: label),
    );
  }
}
