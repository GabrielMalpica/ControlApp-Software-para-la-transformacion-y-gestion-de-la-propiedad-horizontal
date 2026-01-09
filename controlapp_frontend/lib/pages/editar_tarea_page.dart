import 'package:flutter/material.dart';

import '../api/tarea_api.dart';
import '../api/gerente_api.dart';
import '../model/conjunto_model.dart';
import '../model/tarea_model.dart';
import '../model/usuario_model.dart';
import '../service/theme.dart';

class EditarTareaPage extends StatefulWidget {
  final String nit; // NIT del conjunto
  final TareaModel tarea; // tarea a editar

  const EditarTareaPage({super.key, required this.nit, required this.tarea});

  @override
  State<EditarTareaPage> createState() => _EditarTareaPageState();
}

class _EditarTareaPageState extends State<EditarTareaPage> {
  final _formKey = GlobalKey<FormState>();

  final TareaApi _tareaApi = TareaApi();
  final GerenteApi _gerenteApi = GerenteApi();

  // Controllers
  final _descripcionCtrl = TextEditingController();
  final _duracionCtrl = TextEditingController();
  final _observacionesCtrl = TextEditingController();

  DateTime? fechaInicio;
  DateTime? fechaFin;

  bool _cargandoInicial = true;
  bool _guardando = false;

  // Conjunto / ubicaciones / elementos
  Conjunto? _conjuntoSeleccionado;
  List<UbicacionConElementos> _ubicaciones = [];
  UbicacionConElementos? _ubicacionSeleccionada;

  List<Elemento> _elementos = [];
  Elemento? _elementoSeleccionado;

  // Operarios del conjunto
  List<Usuario> _operarios = [];
  final List<int> _operariosSeleccionadosIds = []; // 👈 IDs numéricos (cédula)

  // Supervisores
  List<Usuario> _supervisores = [];
  int? _supervisorId; // 👈 también numérico

  @override
  void initState() {
    super.initState();
    _initFromTarea();
    _cargarDatosIniciales();
  }

  void _initFromTarea() {
    final t = widget.tarea;
    _descripcionCtrl.text = t.descripcion;
    _duracionCtrl.text = t.duracionHoras.toString();
    _observacionesCtrl.text = t.observaciones ?? '';

    fechaInicio = t.fechaInicio;
    fechaFin = t.fechaFin;

    // supervisorId viene como int? en TareaModel
    _supervisorId = t.supervisorId;

    // operariosIds viene como List<int> en TareaModel
    _operariosSeleccionadosIds
      ..clear()
      ..addAll(t.operariosIds);
  }

  Future<void> _cargarDatosIniciales() async {
    try {
      // 1) Cargar conjuntos (con ubicaciones + operarios)
      final conjuntos = await _gerenteApi.listarConjuntos();

      // encontrar el conjunto correspondiente al NIT
      final conjunto = conjuntos.firstWhere(
        (c) => c.nit == widget.nit,
        orElse: () => conjuntos.first,
      );

      // 2) Supervisores
      final supervisores = await _gerenteApi.listarSupervisores();

      setState(() {
        _conjuntoSeleccionado = conjunto;
        _ubicaciones = conjunto.ubicaciones;
        _operarios = conjunto.operarios;
        _supervisores = supervisores;
        _cargandoInicial = false;
      });

      // 3) Preseleccionar ubicación y elemento de la tarea
      _preseleccionarUbicacionYElemento();
    } catch (e) {
      if (!mounted) return;
      _cargandoInicial = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error cargando datos iniciales: $e'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() {});
    }
  }

  void _preseleccionarUbicacionYElemento() {
    final t = widget.tarea;

    if (_ubicaciones.isEmpty) return;

    final ubic = _ubicaciones.where((u) => u.id == t.ubicacionId).toList();
    if (ubic.isNotEmpty) {
      _ubicacionSeleccionada = ubic.first;
      _elementos = _ubicacionSeleccionada!.elementos;

      final elems = _elementos.where((e) => e.id == t.elementoId).toList();
      if (elems.isNotEmpty) {
        _elementoSeleccionado = elems.first;
      }
    }

    setState(() {});
  }

  Future<void> _seleccionarFechaInicio() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: fechaInicio ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() => fechaInicio = picked);
    }
  }

  Future<void> _seleccionarFechaFin() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: fechaFin ?? (fechaInicio ?? DateTime.now()),
      firstDate: fechaInicio ?? DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() => fechaFin = picked);
    }
  }

  Future<void> _mostrarSelectorOperarios() async {
    if (_operarios.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay operarios en este conjunto')),
      );
      return;
    }

    final seleccionTemp = Set<int>.from(_operariosSeleccionadosIds);

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Seleccionar operarios'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _operarios.length,
                  itemBuilder: (_, index) {
                    final op = _operarios[index];

                    // Usamos la cédula numérica como ID
                    final opId = int.tryParse(op.cedula) ?? 0;
                    if (opId == 0) return const SizedBox.shrink();

                    final checked = seleccionTemp.contains(opId);
                    return CheckboxListTile(
                      value: checked,
                      title: Text(op.nombre),
                      subtitle: Text('Cédula: ${op.cedula}'),
                      onChanged: (v) {
                        if (v == true) {
                          seleccionTemp.add(opId);
                        } else {
                          seleccionTemp.remove(opId);
                        }
                        setStateDialog(() {});
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Aceptar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok == true) {
      setState(() {
        _operariosSeleccionadosIds
          ..clear()
          ..addAll(seleccionTemp);
      });
    }
  }

  Future<void> _guardarCambios() async {
    if (!_formKey.currentState!.validate()) return;

    final conjunto = _conjuntoSeleccionado;
    if (conjunto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay conjunto seleccionado')),
      );
      return;
    }

    if (fechaInicio == null || fechaFin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccione fecha de inicio y fin')),
      );
      return;
    }

    if (_ubicacionSeleccionada == null || _elementoSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccione ubicación y elemento')),
      );
      return;
    }

    final duracion = int.tryParse(_duracionCtrl.text);
    if (duracion == null || duracion <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Duración inválida')));
      return;
    }

    if (_operariosSeleccionadosIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccione al menos un operario')),
      );
      return;
    }

    setState(() => _guardando = true);

    try {
      final req = TareaRequest(
        descripcion: _descripcionCtrl.text.trim(),
        fechaInicio: fechaInicio!,
        fechaFin: fechaFin!,
        duracionHoras: duracion,
        ubicacionId: _ubicacionSeleccionada!.id,
        elementoId: _elementoSeleccionado!.id,
        conjuntoId: conjunto.nit,
        supervisorId: _supervisorId, // 👈 int?
        operariosIds: _operariosSeleccionadosIds, // 👈 List<int>
        observaciones: _observacionesCtrl.text.trim().isEmpty
            ? null
            : _observacionesCtrl.text.trim(),
      );

      await _tareaApi.editarTarea(widget.tarea.id, req);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Tarea actualizada correctamente'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al actualizar tarea: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargandoInicial) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.primary,
          title: const Text(
            "Editar tarea",
            style: TextStyle(color: Colors.white),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: const Text(
          "Editar tarea",
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                "1. Dónde se realizará",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),

              // Conjunto (solo lectura, ya viene por NIT)
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: "Conjunto",
                  border: OutlineInputBorder(),
                ),
                child: Text(_conjuntoSeleccionado?.nombre ?? widget.nit),
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<int>(
                value: _ubicacionSeleccionada?.id,
                decoration: const InputDecoration(
                  labelText: "Ubicación",
                  border: OutlineInputBorder(),
                ),
                items: _ubicaciones
                    .map(
                      (u) =>
                          DropdownMenuItem(value: u.id, child: Text(u.nombre)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  final u = _ubicaciones.firstWhere((x) => x.id == value);
                  setState(() {
                    _ubicacionSeleccionada = u;
                    _elementos = u.elementos;
                    _elementoSeleccionado = null;
                  });
                },
                validator: (v) => v == null ? 'Seleccione una ubicación' : null,
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<int>(
                value: _elementoSeleccionado?.id,
                decoration: const InputDecoration(
                  labelText: "Elemento",
                  border: OutlineInputBorder(),
                ),
                items: _elementos
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.id, child: Text(e.nombre)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  final el = _elementos.firstWhere((x) => x.id == value);
                  setState(() => _elementoSeleccionado = el);
                },
                validator: (v) => v == null ? 'Seleccione un elemento' : null,
              ),
              const SizedBox(height: 24),

              const Text(
                "2. Qué se va a hacer",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),

              TextFormField(
                controller: _descripcionCtrl,
                decoration: const InputDecoration(
                  labelText: "Descripción de la tarea",
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
                validator: (v) =>
                    v == null || v.isEmpty ? 'Ingrese una descripción' : null,
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _seleccionarFechaInicio,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: "Fecha inicio",
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          fechaInicio == null
                              ? "Seleccionar"
                              : "${fechaInicio!.day}/${fechaInicio!.month}/${fechaInicio!.year}",
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: _seleccionarFechaFin,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: "Fecha fin",
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          fechaFin == null
                              ? "Seleccionar"
                              : "${fechaFin!.day}/${fechaFin!.month}/${fechaFin!.year}",
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _duracionCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Duración estimada (horas)",
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Ingrese duración en horas' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _observacionesCtrl,
                decoration: const InputDecoration(
                  labelText: "Observaciones (opcional)",
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 24),

              const Text(
                "3. Quiénes la ejecutan",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),

              InkWell(
                onTap: _mostrarSelectorOperarios,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: "Operarios",
                    border: OutlineInputBorder(),
                  ),
                  child: Text(
                    _operariosSeleccionadosIds.isEmpty
                        ? "Seleccionar operario(s)"
                        : "${_operariosSeleccionadosIds.length} operario(s) seleccionado(s)",
                  ),
                ),
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<int>(
                value: _supervisorId,
                decoration: const InputDecoration(
                  labelText: "Supervisor (opcional)",
                  border: OutlineInputBorder(),
                ),
                items: _supervisores
                    .map(
                      (s) => DropdownMenuItem(
                        value: int.tryParse(s.cedula) ?? 0,
                        child: Text(s.nombre),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() => _supervisorId = value);
                },
              ),
              const SizedBox(height: 32),

              ElevatedButton.icon(
                onPressed: _guardando ? null : _guardarCambios,
                icon: _guardando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(_guardando ? "Guardando..." : "Guardar cambios"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
