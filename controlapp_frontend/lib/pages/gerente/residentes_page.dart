import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/gerente_api.dart';
import 'package:flutter_application_1/api/residentes_api.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/model/residente_admin_models.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/permission_service.dart';
import 'package:flutter_application_1/service/theme.dart';

class ResidentesPage extends StatefulWidget {
  const ResidentesPage({
    super.key,
    this.conjuntoFijoNit,
    this.conjuntoFijoNombre,
  });

  final String? conjuntoFijoNit;
  final String? conjuntoFijoNombre;

  @override
  State<ResidentesPage> createState() => _ResidentesPageState();
}

class _ResidentesPageState extends State<ResidentesPage> {
  final _residentesApi = ResidentesApi();
  final _gerenteApi = GerenteApi();
  final _searchCtrl = TextEditingController();

  List<Conjunto> _conjuntos = const [];
  String? _conjuntoNit;
  bool _loadingConjuntos = false;
  bool _loading = true;
  String? _error;
  List<ResidenteAdminItem> _residentes = const [];

  bool get _conjuntoBloqueado =>
      widget.conjuntoFijoNit != null &&
      widget.conjuntoFijoNit!.trim().isNotEmpty;

  bool _can(String permission) => PermissionService.instance.can(permission);

  @override
  void initState() {
    super.initState();
    if (_conjuntoBloqueado) {
      _conjuntoNit = widget.conjuntoFijoNit!.trim();
      _cargarResidentes();
    } else {
      _cargarConjuntos();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
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
      await _cargarResidentes();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingConjuntos = false;
        _loading = false;
        _error = AppError.messageOf(e);
      });
    }
  }

  Future<void> _cargarResidentes() async {
    if ((_conjuntoNit ?? '').isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _residentesApi.listarResidentes(
        conjuntoId: _conjuntoNit!,
        query: _searchCtrl.text,
      );
      if (!mounted) return;
      setState(() {
        _residentes = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppError.messageOf(e);
        _loading = false;
      });
    }
  }

  Future<void> _editar(ResidenteAdminItem item) async {
    final nombreCtrl = TextEditingController(text: item.nombre);
    final correoCtrl = TextEditingController(text: item.correo);
    final telefonoCtrl = TextEditingController(text: item.telefono);
    final sectorCtrl = TextEditingController(text: item.sector);
    final unidadCtrl = TextEditingController(text: item.unidad);
    String tipoUnidad = item.tipoUnidad;
    bool activo = item.activo;
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Editar residente'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nombreCtrl,
                      decoration: const InputDecoration(labelText: 'Nombre'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: correoCtrl,
                      decoration: const InputDecoration(labelText: 'Correo'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: telefonoCtrl,
                      decoration: const InputDecoration(labelText: 'Teléfono'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: tipoUnidad,
                      decoration: const InputDecoration(
                        labelText: 'Tipo de unidad',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'APARTAMENTO',
                          child: Text('Apartamento'),
                        ),
                        DropdownMenuItem(value: 'CASA', child: Text('Casa')),
                        DropdownMenuItem(
                          value: 'OFICINA',
                          child: Text('Oficina'),
                        ),
                        DropdownMenuItem(value: 'LOCAL', child: Text('Local')),
                      ],
                      onChanged: (value) => setDialogState(
                        () => tipoUnidad = value ?? 'APARTAMENTO',
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (tipoUnidad != 'CASA') ...[
                      TextField(
                        controller: sectorCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Sector / torre / bloque',
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    TextField(
                      controller: unidadCtrl,
                      decoration: const InputDecoration(labelText: 'Unidad'),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile.adaptive(
                      value: activo,
                      onChanged: (value) =>
                          setDialogState(() => activo = value),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Activo'),
                    ),
                    if (error != null)
                      Text(error!, style: const TextStyle(color: AppTheme.red)),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (nombreCtrl.text.trim().length < 3) {
                      setDialogState(() => error = 'Nombre inválido.');
                      return;
                    }
                    if (!correoCtrl.text.contains('@')) {
                      setDialogState(() => error = 'Correo inválido.');
                      return;
                    }
                    if (unidadCtrl.text.trim().isEmpty) {
                      setDialogState(() => error = 'La unidad es obligatoria.');
                      return;
                    }
                    Navigator.pop(dialogContext, true);
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) {
      nombreCtrl.dispose();
      correoCtrl.dispose();
      telefonoCtrl.dispose();
      sectorCtrl.dispose();
      unidadCtrl.dispose();
      return;
    }

    try {
      await _residentesApi.editarResidente(
        residenteId: item.id,
        conjuntoId: _conjuntoNit!,
        nombre: nombreCtrl.text,
        correo: correoCtrl.text,
        telefono: telefonoCtrl.text,
        activo: activo,
        tipoUnidad: tipoUnidad,
        sector: tipoUnidad == 'CASA' ? null : sectorCtrl.text,
        unidad: unidadCtrl.text,
      );
      await _cargarResidentes();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppError.messageOf(e))));
    } finally {
      nombreCtrl.dispose();
      correoCtrl.dispose();
      telefonoCtrl.dispose();
      sectorCtrl.dispose();
      unidadCtrl.dispose();
    }
  }

  Future<void> _eliminar(ResidenteAdminItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar residente'),
        content: Text(
          'Se eliminara a ${item.nombre} y su acceso a la app. Esta accion no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    try {
      await _residentesApi.eliminarResidente(
        residenteId: item.id,
        conjuntoId: _conjuntoNit!,
      );
      await _cargarResidentes();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppError.messageOf(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gestion de residentes')),
      body: _loadingConjuntos
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (_conjuntoBloqueado)
                        TextFormField(
                          initialValue:
                              widget.conjuntoFijoNombre ?? _conjuntoNit ?? '',
                          enabled: false,
                          decoration: const InputDecoration(
                            labelText: 'Conjunto',
                          ),
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
                          onChanged: (value) {
                            setState(() => _conjuntoNit = value);
                            _cargarResidentes();
                          },
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              decoration: const InputDecoration(
                                labelText:
                                    'Buscar por nombre, correo, cedula o unidad',
                              ),
                              onSubmitted: (_) => _cargarResidentes(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: _cargarResidentes,
                            icon: const Icon(Icons.search),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                      ? Center(child: Text(_error!))
                      : _residentes.isEmpty
                      ? const Center(
                          child: Text(
                            'No hay residentes registrados para este conjunto.',
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: _residentes.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final item = _residentes[index];
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: item.activo
                                      ? AppTheme.primary.withValues(alpha: 0.12)
                                      : AppTheme.red.withValues(alpha: 0.12),
                                  foregroundColor: item.activo
                                      ? AppTheme.primary
                                      : AppTheme.red,
                                  child: const Icon(Icons.person_outline),
                                ),
                                title: Text(item.nombre),
                                subtitle: Text(
                                  '${item.correo}\n${item.tipoUnidad} - ${item.ubicacion}',
                                ),
                                isThreeLine: true,
                                trailing: Wrap(
                                  spacing: 4,
                                  children: [
                                    if (_can('residentes.editar'))
                                      IconButton(
                                        tooltip: 'Editar',
                                        onPressed: () => _editar(item),
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                    if (_can('residentes.eliminar'))
                                      IconButton(
                                        tooltip: 'Eliminar',
                                        onPressed: () => _eliminar(item),
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: AppTheme.red,
                                        ),
                                      ),
                                  ],
                                ),
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
