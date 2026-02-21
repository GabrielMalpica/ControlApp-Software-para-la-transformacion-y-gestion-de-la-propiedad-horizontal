import 'package:flutter/material.dart';
import 'package:flutter_application_1/model/usuario_model.dart';
import 'package:flutter_application_1/repositories/usuario_repository.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/utils/enums/usuario_enums.dart';
import 'package:flutter_application_1/utils/enums/usuario_enums_service.dart';

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

  // ✅ NUEVOS
  bool activo = true;
  String? patronJornada;

  bool _guardando = false;

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
    patronJornada = u.patronJornada;

    _cargarEnums();
  }

  String prettyPatronJornada(String? raw) {
    if (raw == null || raw.isEmpty) return "-";

    switch (raw) {
      case 'COMPLETA':
        return 'Completa (normal)';
      case 'MEDIO_LV4_S2':
        return 'Medio tiempo: L–V 4h + S 2h';
      case 'MEDIO_LX8_V6':
        return 'Medio tiempo: L 8h + X 8h + V 6h';
      default:
        // fallback por si mañana agregas más
        return prettyEnum(raw);
    }
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
        _errorEnums = e.toString();
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

  bool get _debeMostrarPatron {
    // ✅ Si jornada es MEDIO_TIEMPO, mostrar
    if (jornada == 'MEDIO_TIEMPO') return true;

    // ✅ Si ya viene guardado un patrón medio tiempo, también mostrarlo
    if ((patronJornada ?? '').startsWith('MEDIO_')) return true;

    return false;
  }

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

    setState(() => _guardando = true);

    try {
      final cambios = <String, dynamic>{
        'nombre': _nombreCtrl.text,
        'correo': _correoCtrl.text,
        'telefono': _telefonoCtrl.text,
        'direccion': _direccionCtrl.text.isEmpty
            ? null
            : _direccionCtrl.text.trim(),
        'fechaNacimiento': fechaNacimiento?.toIso8601String(),
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
        if (jornada == 'MEDIO_TIEMPO') 'patronJornada': patronJornada,
        if (jornada != 'MEDIO_TIEMPO') 'patronJornada': null,
      };

      await _usuarioRepository.editarUsuario(widget.usuario.cedula, cambios);

      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(
          content: Text("✅ Usuario actualizado correctamente"),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
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
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: "Fecha de nacimiento",
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            fechaNacimiento == null
                                ? "Seleccionar fecha"
                                : "${fechaNacimiento!.day}/${fechaNacimiento!.month}/${fechaNacimiento!.year}",
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
                        value: estadoCivilSeleccionado,
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
                        value: tipoSangre,
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
                        value: eps,
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
                        value: fondo,
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
                        value: tipoContrato,
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
                        value: jornada,
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
                            } else {
                              // MEDIO_TIEMPO: si venía COMPLETA, limpiar para obligar selección
                              if (patronJornada == 'COMPLETA') {
                                patronJornada = null;
                              }
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
                          value: patronJornada,
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
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 48,
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
                  label: Text(_guardando ? "Guardando..." : "Guardar cambios"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
