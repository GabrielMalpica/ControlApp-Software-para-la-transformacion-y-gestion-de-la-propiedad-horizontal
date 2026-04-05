import 'package:flutter/material.dart';
import 'package:flutter_application_1/model/usuario_model.dart';
import 'package:flutter_application_1/repositories/usuario_repository.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/utils/enums/usuario_enums.dart';
import 'package:flutter_application_1/utils/enums/usuario_enums_service.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:intl/intl.dart';

import 'package:flutter_application_1/service/app_feedback.dart';

class EditarUsuarioPage extends StatefulWidget {
  final Usuario usuario;

  const EditarUsuarioPage({super.key, required this.usuario});

  @override
  State<EditarUsuarioPage> createState() => _EditarUsuarioPageState();
}

class _EditarUsuarioPageState extends State<EditarUsuarioPage> {
  final _formKey = GlobalKey<FormState>();
  final UsuarioRepository _usuarioRepository = UsuarioRepository();
  final UsuarioEnumsService _enumsService = UsuarioEnumsService();

  // Enums
  UsuarioEnums? _enums;
  bool _cargandoEnums = true;
  String? _errorEnums;

  // Controllers
  late TextEditingController _nombreCtrl;
  late TextEditingController _correoCtrl;
  late TextEditingController _telefonoCtrl;
  late TextEditingController _cedulaCtrl;
  late TextEditingController _direccionCtrl;

  // Campos adicionales
  DateTime? fechaNacimiento;
  String? estadoCivilSeleccionado;
  int numeroHijos = 0;
  bool padresVivos = true;
  String? tipoSangre, eps, fondo, tipoContrato, jornada;
  String? rolSeleccionado;
  final List<_DisponibilidadPeriodoForm> _disponibilidadPeriodos = [];

  // ✅ NUEVOS
  bool activo = true;
  String? patronJornada;

  bool _guardando = false;

  String get _fechaNacimientoLabel => fechaNacimiento == null
      ? 'Seleccionar fecha'
      : DateFormat('dd/MM/yyyy').format(fechaNacimiento!);

  @override
  void initState() {
    super.initState();

    final u = widget.usuario;

    _nombreCtrl = TextEditingController(text: u.nombre);
    _correoCtrl = TextEditingController(text: u.correo);
    _telefonoCtrl = TextEditingController(text: u.telefono.toString());
    _cedulaCtrl = TextEditingController(text: u.cedula);
    _direccionCtrl = TextEditingController(text: u.direccion ?? '');

    fechaNacimiento = u.fechaNacimiento;
    rolSeleccionado = u.rol;
    estadoCivilSeleccionado = u.estadoCivil;
    numeroHijos = u.numeroHijos ?? 0;
    padresVivos = u.padresVivos ?? true;
    tipoSangre = u.tipoSangre;
    eps = u.eps;
    fondo = u.fondoPensiones;
    tipoContrato = u.tipoContrato;
    jornada = u.jornadaLaboral;

    // ✅ Inicializar nuevos campos (asegúrate que existan en tu Usuario model)
    activo = u.activo;
    patronJornada = jornada == 'MEDIO_TIEMPO' ? u.patronJornada : null;
    _disponibilidadPeriodos.addAll(
      u.disponibilidadPeriodos.map(_DisponibilidadPeriodoForm.fromModel),
    );
    if (_disponibilidadPeriodos.isEmpty && u.rol == 'operario') {
      _disponibilidadPeriodos.add(_DisponibilidadPeriodoForm());
    }

    _cargarEnums();
  }

  String prettyPatronJornada(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    return prettyEnum(raw);
  }

  Future<void> _cargarEnums() async {
    try {
      final enums = await _enumsService.cargarEnumsUsuario();
      setState(() {
        _enums = enums;
        _cargandoEnums = false;
        _errorEnums = null;
      });
    } catch (e) {
      setState(() {
        _cargandoEnums = false;
        _errorEnums = AppError.messageOf(e);
      });
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _correoCtrl.dispose();
    _telefonoCtrl.dispose();
    _cedulaCtrl.dispose();
    _direccionCtrl.dispose();
    for (final item in _disponibilidadPeriodos) {
      item.dispose();
    }
    super.dispose();
  }

  String prettyEnum(String raw) {
    if (raw.isEmpty) return raw;
    final withSpaces = raw.toLowerCase().replaceAll('_', ' ');
    return withSpaces[0].toUpperCase() + withSpaces.substring(1);
  }

  Future<void> _seleccionarFechaNacimiento() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: fechaNacimiento ?? DateTime.now(),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      helpText: "Fecha de nacimiento",
    );
    if (picked != null) {
      setState(() => fechaNacimiento = picked);
    }
  }

  bool get _debeMostrarPatron => jornada == 'MEDIO_TIEMPO';

  Future<void> _guardarCambios() async {
    if (!_formKey.currentState!.validate()) return;

    // ✅ Validación extra recomendada
    if (_debeMostrarPatron &&
        (patronJornada == null || patronJornada!.isEmpty)) {
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(
          content: Text("Seleccione el patrón de medio tiempo"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (widget.usuario.rol == 'operario') {
      final periodos = _disponibilidadPeriodos
          .map((e) => e.toModel())
          .whereType<DisponibilidadOperarioPeriodo>()
          .toList();
      if (periodos.isEmpty) {
        AppFeedback.showFromSnackBar(
          context,
          const SnackBar(
            content: Text(
              'Registre al menos un periodo de disponibilidad para el operario',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      final periodoInvalido = periodos.any(
        (p) =>
            p.trabajaDomingo &&
            (p.diaDescanso == null || p.diaDescanso == 'DOMINGO'),
      );
      if (periodoInvalido) {
        AppFeedback.showFromSnackBar(
          context,
          const SnackBar(
            content: Text(
              'Si el operario trabaja domingo, debe tener un dia de descanso entre semana en ese periodo.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    setState(() => _guardando = true);

    try {
      final cambios = <String, dynamic>{
        'nombre': _nombreCtrl.text,
        'correo': _correoCtrl.text,
        'rol': rolSeleccionado,
        'telefono': _telefonoCtrl.text,
        'direccion': _direccionCtrl.text.isEmpty
            ? null
            : _direccionCtrl.text.trim(),
        'fechaNacimiento': fechaNacimiento == null
            ? null
            : DateFormat('yyyy-MM-dd').format(fechaNacimiento!),
        'estadoCivil': estadoCivilSeleccionado,
        'numeroHijos': numeroHijos,
        'padresVivos': padresVivos,
        'tipoSangre': tipoSangre,
        'eps': eps,
        'fondoPensiones': fondo,
        'tipoContrato': tipoContrato,
        'jornadaLaboral': jornada,

        // ✅ NUEVOS
        'activo': activo,
        'patronJornada': jornada == 'MEDIO_TIEMPO' ? patronJornada : null,
        if (widget.usuario.rol == 'operario')
          'disponibilidadPeriodos': _disponibilidadPeriodos
              .map((e) => e.toModel())
              .whereType<DisponibilidadOperarioPeriodo>()
              .map((e) => e.toJson())
              .toList(),
      };

      await _usuarioRepository.editarUsuario(widget.usuario.cedula, cambios);

      if (!mounted) return;
      await _mostrarGuardadoYVolverMenu();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text("❌ Error al actualizar usuario: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _mostrarGuardadoYVolverMenu() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Éxito'),
        content: const Text('Usuario actualizado correctamente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    if (_cargandoEnums) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_errorEnums != null || _enums == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: AppTheme.primary,
          title: const Text(
            "Editar usuario",
            style: TextStyle(color: Colors.white),
          ),
        ),
        body: Center(child: Text("Error cargando catálogos: $_errorEnums")),
      );
    }

    final enums = _enums!;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: const Text(
          "Editar usuario",
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // ───────── CARD DATOS BÁSICOS ─────────
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.person_outline, color: AppTheme.primary),
                          const SizedBox(width: 8),
                          const Text(
                            "Datos personales",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _nombreCtrl,
                        decoration: const InputDecoration(
                          labelText: "Nombre completo",
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => v == null || v.isEmpty
                            ? 'Ingrese el nombre completo'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _cedulaCtrl,
                        enabled: false,
                        decoration: const InputDecoration(
                          labelText: "Cédula",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _correoCtrl,
                        decoration: const InputDecoration(
                          labelText: "Correo electrónico",
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => v == null || !v.contains('@')
                            ? 'Correo inválido'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: rolSeleccionado,
                        items: enums.roles
                            .map(
                              (rol) => DropdownMenuItem(
                                value: rol,
                                child: Text(prettyEnum(rol)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => rolSeleccionado = value),
                        decoration: const InputDecoration(
                          labelText: 'Rol del usuario',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) => value == null || value.isEmpty
                            ? 'Seleccione un rol'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _telefonoCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: "Teléfono",
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => v == null || v.isEmpty
                            ? 'Ingrese un teléfono'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: _seleccionarFechaNacimiento,
                        borderRadius: BorderRadius.circular(12),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: "Fecha de nacimiento",
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.cake_outlined),
                            suffixIcon: Icon(Icons.edit_calendar_rounded),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _fechaNacimientoLabel,
                                  style: TextStyle(
                                    color: fechaNacimiento == null
                                        ? Colors.black54
                                        : Colors.black87,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _seleccionarFechaNacimiento,
                                child: const Text('Cambiar'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _direccionCtrl,
                        decoration: const InputDecoration(
                          labelText: "Dirección (opcional)",
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ───────── CARD INFO FAMILIAR Y SALUD ─────────
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.family_restroom, color: AppTheme.primary),
                          const SizedBox(width: 8),
                          const Text(
                            "Información familiar y salud",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text("Número de hijos: "),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                if (numeroHijos > 0) numeroHijos--;
                              });
                            },
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Text("$numeroHijos"),
                          IconButton(
                            onPressed: () => setState(() => numeroHijos++),
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                      SwitchListTile(
                        title: const Text("¿Padres vivos?"),
                        value: padresVivos,
                        onChanged: (v) => setState(() => padresVivos = v),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: estadoCivilSeleccionado,
                        items: enums.estadosCiviles
                            .map(
                              (e) => DropdownMenuItem(
                                value: e,
                                child: Text(prettyEnum(e)),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => estadoCivilSeleccionado = v),
                        decoration: const InputDecoration(
                          labelText: "Estado civil (opcional)",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: tipoSangre,
                        items: enums.tiposSangre
                            .map(
                              (t) => DropdownMenuItem(
                                value: t,
                                child: Text(prettyEnum(t)),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => tipoSangre = v),
                        decoration: const InputDecoration(
                          labelText: "Tipo de sangre (opcional)",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: eps,
                        items: enums.eps
                            .map(
                              (e) => DropdownMenuItem(
                                value: e,
                                child: Text(prettyEnum(e)),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => eps = v),
                        decoration: const InputDecoration(
                          labelText: "EPS (opcional)",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: fondo,
                        items: enums.fondosPensiones
                            .map(
                              (f) => DropdownMenuItem(
                                value: f,
                                child: Text(prettyEnum(f)),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => fondo = v),
                        decoration: const InputDecoration(
                          labelText: "Fondo de pensiones (opcional)",
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ───────── CARD INFO LABORAL ─────────
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.badge_outlined, color: AppTheme.primary),
                          const SizedBox(width: 8),
                          const Text(
                            "Información laboral",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // ✅ Switch Activo
                      SwitchListTile(
                        title: const Text("Usuario activo"),
                        value: activo,
                        onChanged: (v) => setState(() => activo = v),
                      ),
                      const SizedBox(height: 8),

                      DropdownButtonFormField<String>(
                        initialValue: tipoContrato,
                        items: enums.tiposContrato
                            .map(
                              (t) => DropdownMenuItem(
                                value: t,
                                child: Text(prettyEnum(t)),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => tipoContrato = v),
                        decoration: const InputDecoration(
                          labelText: "Tipo de contrato (opcional)",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),

                      DropdownButtonFormField<String>(
                        initialValue: jornada,
                        items: enums.jornadasLaborales
                            .map(
                              (j) => DropdownMenuItem(
                                value: j,
                                child: Text(prettyEnum(j)),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          setState(() {
                            jornada = v;

                            if (jornada != 'MEDIO_TIEMPO') {
                              patronJornada = null;
                            }
                          });
                        },
                        decoration: const InputDecoration(
                          labelText: "Jornada laboral (opcional)",
                          border: OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // ✅ Dropdown patrón (si aplica)
                      if (_debeMostrarPatron)
                        DropdownButtonFormField<String>(
                          initialValue: patronJornada,
                          items: enums.patronesJornada
                              .where((p) => p.startsWith('MEDIO_'))
                              .map(
                                (p) => DropdownMenuItem(
                                  value: p,
                                  child: Text(prettyPatronJornada(p)),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => patronJornada = v),
                          decoration: const InputDecoration(
                            labelText: "Patrón de medio tiempo (obligatorio)",
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            if (_debeMostrarPatron) {
                              if (v == null || v.isEmpty) {
                                return "Seleccione el patrón de medio tiempo";
                              }
                            }
                            return null;
                          },
                        ),
                      if (_debeMostrarPatron) ...[
                        const SizedBox(height: 8),
                        const _PatronJornadaHelpCard(),
                      ],
                      if (widget.usuario.rol == 'operario') ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Disponibilidad y descansos por periodo',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => setState(() {
                                _disponibilidadPeriodos.add(
                                  _DisponibilidadPeriodoForm(),
                                );
                              }),
                              icon: const Icon(Icons.add),
                              label: const Text('Agregar periodo'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const _DisponibilidadPeriodoHelpCard(),
                        const SizedBox(height: 8),
                        ..._disponibilidadPeriodos.asMap().entries.map((entry) {
                          final index = entry.key;
                          final item = entry.value;
                          return _DisponibilidadPeriodoCard(
                            item: item,
                            onChanged: () => setState(() {}),
                            onRemove: _disponibilidadPeriodos.length <= 1
                                ? null
                                : () => setState(() {
                                    item.dispose();
                                    _disponibilidadPeriodos.removeAt(index);
                                  }),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              Align(
                alignment: Alignment.centerLeft,
                child: ElevatedButton.icon(
                  onPressed: _guardando ? null : _guardarCambios,
                  icon: _guardando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(_guardando ? "Guardando..." : "Guardar"),
                  style: AppTheme.saveButtonStyle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DisponibilidadPeriodoForm {
  _DisponibilidadPeriodoForm();

  factory _DisponibilidadPeriodoForm.fromModel(
    DisponibilidadOperarioPeriodo model,
  ) {
    final item = _DisponibilidadPeriodoForm();
    item.id = model.id;
    item.fechaInicio = model.fechaInicio;
    item.fechaFin = model.fechaFin;
    item.trabajaDomingo = model.trabajaDomingo;
    item.diaDescanso = model.diaDescanso;
    item.observacionesCtrl.text = model.observaciones ?? '';
    return item;
  }

  int? id;
  DateTime? fechaInicio;
  DateTime? fechaFin;
  bool trabajaDomingo = false;
  String? diaDescanso;
  final TextEditingController observacionesCtrl = TextEditingController();

  DisponibilidadOperarioPeriodo? toModel() {
    if (fechaInicio == null) return null;
    return DisponibilidadOperarioPeriodo(
      id: id,
      fechaInicio: fechaInicio!,
      fechaFin: fechaFin,
      trabajaDomingo: trabajaDomingo,
      diaDescanso: diaDescanso,
      observaciones: observacionesCtrl.text.trim().isEmpty
          ? null
          : observacionesCtrl.text.trim(),
    );
  }

  void dispose() => observacionesCtrl.dispose();
}

class _DisponibilidadPeriodoCard extends StatelessWidget {
  const _DisponibilidadPeriodoCard({
    required this.item,
    required this.onChanged,
    this.onRemove,
  });

  final _DisponibilidadPeriodoForm item;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  Future<void> _pickDate(
    BuildContext context, {
    required DateTime? initial,
    required ValueChanged<DateTime> onSelected,
    required String helpText,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
      helpText: helpText,
    );
    if (picked != null) {
      onSelected(picked);
      onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    const dias = [
      'LUNES',
      'MARTES',
      'MIERCOLES',
      'JUEVES',
      'VIERNES',
      'SABADO',
      'DOMINGO',
    ];

    String fmt(DateTime? d) =>
        d == null ? 'Seleccionar fecha' : '${d.day}/${d.month}/${d.year}';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Periodo de disponibilidad',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            InkWell(
              onTap: () => _pickDate(
                context,
                initial: item.fechaInicio,
                onSelected: (d) => item.fechaInicio = d,
                helpText: 'Inicio del periodo',
              ),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Fecha inicio',
                  border: OutlineInputBorder(),
                ),
                child: Text(fmt(item.fechaInicio)),
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _pickDate(
                context,
                initial: item.fechaFin,
                onSelected: (d) => item.fechaFin = d,
                helpText: 'Fin del periodo',
              ),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Fecha fin (opcional)',
                  border: OutlineInputBorder(),
                ),
                child: Text(fmt(item.fechaFin)),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              initialValue: item.diaDescanso,
              decoration: const InputDecoration(
                labelText: 'Dia de descanso semanal',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Sin definir'),
                ),
                ...dias.map((d) => DropdownMenuItem(value: d, child: Text(d))),
              ],
              onChanged: (v) {
                item.diaDescanso = v;
                onChanged();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Trabaja domingos'),
              value: item.trabajaDomingo,
              onChanged: (v) {
                item.trabajaDomingo = v;
                onChanged();
              },
            ),
            TextField(
              controller: item.observacionesCtrl,
              onChanged: (_) => onChanged(),
              decoration: const InputDecoration(
                labelText: 'Observaciones del periodo (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatronJornadaHelpCard extends StatelessWidget {
  const _PatronJornadaHelpCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8F6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCE7E0)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Referencia de patrones',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 6),
          Text(
            'MEDIO_SEMANA_SABADO: lunes a viernes antes del almuerzo y sabado completo.',
          ),
          SizedBox(height: 4),
          Text(
            'MEDIO_SEMANA_SABADO_TARDE: lunes a viernes despues del almuerzo y sabado completo.',
          ),
          SizedBox(height: 4),
          Text(
            'MEDIO_DIAS_INTERCALADOS: lunes, miercoles, viernes y sabado completos.',
          ),
        ],
      ),
    );
  }
}

class _DisponibilidadPeriodoHelpCard extends StatelessWidget {
  const _DisponibilidadPeriodoHelpCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8F6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCE7E0)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Como funciona este periodo',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 6),
          Text(
            'Fecha inicio: desde que dia empieza a aplicar este esquema de trabajo.',
          ),
          SizedBox(height: 4),
          Text(
            'Fecha fin: hasta que dia aplica. Si lo dejas vacio, sigue vigente hasta nuevo aviso.',
          ),
          SizedBox(height: 4),
          Text(
            'Trabaja domingos: actívalo solo si en ese periodo el operario sí labora domingo.',
          ),
          SizedBox(height: 4),
          Text(
            'Dia de descanso semanal: indica qué dia descansa durante ese mismo periodo.',
          ),
        ],
      ),
    );
  }
}
