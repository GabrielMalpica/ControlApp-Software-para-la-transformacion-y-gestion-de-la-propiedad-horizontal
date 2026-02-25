import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/gerente_api.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';

import '../../service/theme.dart';
import '../../model/usuario_model.dart';
import '../../repositories/usuario_repository.dart';
import '../../utils/enums/usuario_enums.dart';
import '../../utils/enums/usuario_enums_service.dart';

import 'package:flutter_application_1/service/app_feedback.dart';

class CrearUsuarioPage extends StatefulWidget {
  final String nit;

  const CrearUsuarioPage({super.key, required this.nit});

  @override
  State<CrearUsuarioPage> createState() => _CrearUsuarioPageState();
}

class _CrearUsuarioPageState extends State<CrearUsuarioPage> {
  final _formKey = GlobalKey<FormState>();

  final UsuarioRepository _usuarioRepository = UsuarioRepository();
  final GerenteApi _gerenteApi = GerenteApi();
  final UsuarioEnumsService _enumsService = UsuarioEnumsService();

  // 🔹 Enums cargados desde el backend
  UsuarioEnums? _enums;
  bool _cargandoEnums = true;
  String? _errorEnums;

  // 🔹 Controladores
  final _nombreCtrl = TextEditingController();
  final _correoCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _cedulaCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _observacionesOperarioCtrl = TextEditingController();

  // 🔹 Variables generales usuario
  String? rolSeleccionado; // Rol (enum backend)
  String? estadoCivilSeleccionado;
  DateTime? fechaNacimiento;
  bool padresVivos = true;
  int numeroHijos = 0;

  String? tipoSangre, eps, fondo, tipoContrato, jornada;
  String? tallaCamisa, tallaPantalon, tallaCalzado;

  // ✅ NUEVO
  bool activo = true;
  String? patronJornada; // enum backend

  // 🔹 Para operario
  final Set<String> funcionesSeleccionadas = {}; // TipoFuncion[]
  bool cursoSalvamentoAcuatico = false;
  bool cursoAlturas = false;
  bool examenIngreso = false;
  DateTime? fechaIngresoOperario;

  bool _isSaving = false;

  List<Conjunto> _conjuntos = [];
  bool _cargandoConjuntos = true;
  String? _errorConjuntos;
  String? _conjuntoSeleccionadoNit;

  @override
  void initState() {
    super.initState();
    _cargarEnums();
    _cargarConjuntos();
  }

  Future<void> _cargarConjuntos() async {
    try {
      final lista = await _gerenteApi.listarConjuntos();
      setState(() {
        _conjuntos = lista;
        final fromDashboardNit = widget.nit;
        final existe = lista.any((c) => c.nit == fromDashboardNit);
        _conjuntoSeleccionadoNit = existe
            ? fromDashboardNit
            : (lista.isNotEmpty ? lista.first.nit : null);
        _cargandoConjuntos = false;
        _errorConjuntos = null;
      });
    } catch (e) {
      setState(() {
        _cargandoConjuntos = false;
        _errorConjuntos = e.toString();
      });
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

  // 🔹 Selector genérico de fecha
  Future<void> _seleccionarFecha({
    required ValueChanged<DateTime> onSelected,
    DateTime? initial,
    String? helpText,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(1950),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: helpText,
    );
    if (picked != null) onSelected(picked);
  }

  // 🔹 Helper para mostrar enums bonitos
  String prettyEnum(String raw) {
    if (raw.isEmpty) return raw;
    final withSpaces = raw.toLowerCase().replaceAll('_', ' ');
    return withSpaces[0].toUpperCase() + withSpaces.substring(1);
  }

  // 🔹 Construir el objeto Usuario que el backend espera
  Usuario _buildUsuarioFromForm() {
    return Usuario(
      cedula: _cedulaCtrl.text,
      nombre: _nombreCtrl.text,
      correo: _correoCtrl.text,
      rol: rolSeleccionado!, // enum Rol
      telefono: BigInt.parse(_telefonoCtrl.text),
      fechaNacimiento: fechaNacimiento ?? DateTime.now(),
      direccion: _direccionCtrl.text.isEmpty ? null : _direccionCtrl.text,
      estadoCivil: estadoCivilSeleccionado,
      numeroHijos: numeroHijos,
      padresVivos: padresVivos,
      tipoSangre: tipoSangre,
      eps: eps,
      fondoPensiones: fondo,
      tallaCamisa: tallaCamisa,
      tallaPantalon: tallaPantalon,
      tallaCalzado: tallaCalzado,
      tipoContrato: tipoContrato,
      jornadaLaboral: jornada,

      // ✅ NUEVO
      activo: activo,
      patronJornada: (rolSeleccionado == 'operario' && jornada == 'MEDIO_TIEMPO')
          ? patronJornada
          : null,
    );
  }

  // 🔹 Guardar usuario (crear usuario + asignar rol)
  Future<void> _guardarUsuario() async {
    if (!_formKey.currentState!.validate()) return;

    if (rolSeleccionado == null) {
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(
          content: Text("Seleccione un rol para el usuario"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // ✅ Validación patrón de medio tiempo
    if (rolSeleccionado == 'operario' && jornada == 'MEDIO_TIEMPO') {
      if (patronJornada == null || patronJornada!.isEmpty) {
        AppFeedback.showFromSnackBar(
          context,
          const SnackBar(
            content: Text("Seleccione el patrón de medio tiempo"),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    // Validaciones extra para operario
    if (rolSeleccionado == 'operario') {
      if (funcionesSeleccionadas.isEmpty) {
        AppFeedback.showFromSnackBar(
          context,
          const SnackBar(
            content: Text("Seleccione al menos una función para el operario"),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      if (fechaIngresoOperario == null) {
        AppFeedback.showFromSnackBar(
          context,
          const SnackBar(
            content: Text("Seleccione la fecha de ingreso del operario"),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    final usuario = _buildUsuarioFromForm();

    setState(() => _isSaving = true);

    Usuario? usuarioCreado;

    try {
      // 1️⃣ Crear el usuario base
      usuarioCreado = await _usuarioRepository.crearUsuario(usuario);

      // 2️⃣ Asignar el rol correspondiente usando endpoints del gerente
      switch (rolSeleccionado) {
        case 'operario':
          await _gerenteApi.asignarOperario(
            usuarioId: usuarioCreado.cedula,
            funciones: funcionesSeleccionadas.toList(),
            cursoSalvamentoAcuatico: cursoSalvamentoAcuatico,
            cursoAlturas: cursoAlturas,
            examenIngreso: examenIngreso,
            fechaIngreso: fechaIngresoOperario!,
            observaciones: _observacionesOperarioCtrl.text,
          );

          if (_conjuntoSeleccionadoNit != null &&
              _conjuntoSeleccionadoNit!.trim().isNotEmpty) {
            await _gerenteApi.asignarOperarioAConjunto(
              conjuntoNit: _conjuntoSeleccionadoNit!,
              operarioCedula: usuarioCreado.cedula,
            );
          }
          break;

        case 'supervisor':
          await _gerenteApi.asignarSupervisor(usuarioId: usuarioCreado.cedula);
          break;

        case 'administrador':
          await _gerenteApi.asignarAdministrador(
            usuarioId: usuarioCreado.cedula,
            conjuntoId: widget.nit,
          );
          break;

        case 'jefe_operaciones':
          await _gerenteApi.asignarJefeOperaciones(
            usuarioId: usuarioCreado.cedula,
          );
          break;
      }

      if (!mounted) return;
      await _mostrarGuardadoYVolverMenu();
    } catch (e) {
      if (usuarioCreado != null) {
        try {
          await _usuarioRepository.eliminarUsuario(usuarioCreado.cedula);
        } catch (_) {
          // Si falla la compensación, conservamos el error original
        }
      }

      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text("❌ Error al crear usuario: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _correoCtrl.dispose();
    _telefonoCtrl.dispose();
    _direccionCtrl.dispose();
    _cedulaCtrl.dispose();
    _observacionesOperarioCtrl.dispose();
    super.dispose();
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
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
      return;
    }

    Navigator.pushNamedAndRemoveUntil(context, '/home-gerente', (route) => false);
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
            "Crear Usuario",
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
        title: Text(
          "Crear Usuario - Proyecto ${widget.nit}",
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "🧑‍💼 Registro de Nuevo Usuario",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: AppTheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 16),

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

                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth > 600;
                          return Column(
                            children: [
                              Flex(
                                direction: isWide
                                    ? Axis.horizontal
                                    : Axis.vertical,
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: TextFormField(
                                        controller: _nombreCtrl,
                                        decoration: const InputDecoration(
                                          labelText: "Nombre completo",
                                          border: OutlineInputBorder(),
                                        ),
                                        validator: (v) => v == null || v.isEmpty
                                            ? 'Ingrese el nombre completo'
                                            : null,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: TextFormField(
                                        controller: _cedulaCtrl,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText: "Cédula",
                                          border: OutlineInputBorder(),
                                        ),
                                        validator: (v) => v == null || v.isEmpty
                                            ? 'Ingrese la cédula'
                                            : null,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Flex(
                                direction: isWide
                                    ? Axis.horizontal
                                    : Axis.vertical,
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: TextFormField(
                                        controller: _correoCtrl,
                                        decoration: const InputDecoration(
                                          labelText: "Correo electrónico",
                                          border: OutlineInputBorder(),
                                        ),
                                        validator: (v) =>
                                            v == null || !v.contains('@')
                                            ? 'Correo inválido'
                                            : null,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: TextFormField(
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
                                    ),
                                  ),
                                ],
                              ),
                              Flex(
                                direction: isWide
                                    ? Axis.horizontal
                                    : Axis.vertical,
                                children: [
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: InkWell(
                                        onTap: () => _seleccionarFecha(
                                          onSelected: (d) => setState(
                                            () => fechaNacimiento = d,
                                          ),
                                          initial: fechaNacimiento,
                                          helpText: "Fecha de nacimiento",
                                        ),
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
                                    ),
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: TextFormField(
                                        controller: _direccionCtrl,
                                        decoration: const InputDecoration(
                                          labelText: "Dirección (opcional)",
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
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
                            onPressed: () => setState(() {
                              if (numeroHijos > 0) numeroHijos--;
                            }),
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
                        title: const Text("¿Padres vivos? (opcional)"),
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

              // ───────── CARD INFO LABORAL GENERAL ─────────
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
                            "Información laboral general",
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
                        value: rolSeleccionado,
                        items: enums.roles
                            .map(
                              (r) => DropdownMenuItem(
                                value: r,
                                child: Text(prettyEnum(r)),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          setState(() {
                            rolSeleccionado = v;

                            // si deja de ser operario, no aplica patrón
                            if (rolSeleccionado != 'operario') {
                              patronJornada = null;
                            }

                          });
                        },
                        decoration: const InputDecoration(
                          labelText: "Rol",
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) =>
                            v == null ? 'Seleccione un rol' : null,
                      ),
                      const SizedBox(height: 12),

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

                            // ✅ patrón solo aplica a operario en medio tiempo
                            if (rolSeleccionado != 'operario' ||
                                jornada != 'MEDIO_TIEMPO') {
                              patronJornada = null;
                            }
                          });
                        },
                        decoration: const InputDecoration(
                          labelText: "Jornada laboral (opcional)",
                          border: OutlineInputBorder(),
                        ),
                      ),

                      // ✅ Dropdown patrón (solo operario + medio tiempo)
                      if (rolSeleccionado == 'operario' &&
                          jornada == 'MEDIO_TIEMPO') ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: patronJornada,
                          items: enums.patronesJornada
                              .where((p) => p.startsWith('MEDIO_'))
                              .map(
                                (p) => DropdownMenuItem(
                                  value: p,
                                  child: Text(prettyEnum(p)),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => patronJornada = v),
                          decoration: const InputDecoration(
                            labelText: "Patrón de medio tiempo (obligatorio)",
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            if (rolSeleccionado == 'operario' &&
                                jornada == 'MEDIO_TIEMPO') {
                              if (v == null || v.isEmpty) {
                                return "Seleccione el patrón de medio tiempo";
                              }
                            }
                            return null;
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ───────── CARD INFO OPERARIO (CONDICIONAL) ─────────
              if (rolSeleccionado == 'operario') ...[
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
                            Icon(
                              Icons.construction_outlined,
                              color: AppTheme.primary,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              "Configuración de Operario",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "Funciones (obligatorio, puede seleccionar varias)",
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: enums.tiposFuncion.map((tipo) {
                            final selected = funcionesSeleccionadas.contains(
                              tipo,
                            );
                            return FilterChip(
                              label: Text(prettyEnum(tipo)),
                              selected: selected,
                              onSelected: (value) {
                                setState(() {
                                  if (value) {
                                    funcionesSeleccionadas.add(tipo);
                                  } else {
                                    funcionesSeleccionadas.remove(tipo);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "Formación y estado laboral",
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        SwitchListTile(
                          title: const Text(
                            "Curso de salvamento acuático (opcional)",
                          ),
                          value: cursoSalvamentoAcuatico,
                          onChanged: (v) =>
                              setState(() => cursoSalvamentoAcuatico = v),
                        ),
                        SwitchListTile(
                          title: const Text(
                            "Curso de trabajo en alturas (opcional)",
                          ),
                          value: cursoAlturas,
                          onChanged: (v) => setState(() => cursoAlturas = v),
                        ),
                        SwitchListTile(
                          title: const Text("Examen de ingreso (opcional)"),
                          value: examenIngreso,
                          onChanged: (v) => setState(() => examenIngreso = v),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () => _seleccionarFecha(
                            onSelected: (d) =>
                                setState(() => fechaIngresoOperario = d),
                            initial: fechaIngresoOperario,
                            helpText: "Fecha de ingreso",
                          ),
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: "Fecha de ingreso (obligatoria)",
                              border: OutlineInputBorder(),
                            ),
                            child: Text(
                              fechaIngresoOperario == null
                                  ? "Seleccionar fecha"
                                  : "${fechaIngresoOperario!.day}/${fechaIngresoOperario!.month}/${fechaIngresoOperario!.year}",
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _observacionesOperarioCtrl,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: "Observaciones (opcional)",
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (_cargandoConjuntos)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  )
                else if (_errorConjuntos != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Error cargando conjuntos: $_errorConjuntos',
                      style: const TextStyle(color: Colors.red),
                    ),
                  )
                else if (_conjuntos.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: _conjuntoSeleccionadoNit,
                    decoration: const InputDecoration(
                      labelText: "Asignar al conjunto",
                      border: OutlineInputBorder(),
                    ),
                    items: _conjuntos
                        .map(
                          (c) => DropdownMenuItem<String>(
                            value: c.nit,
                            child: Text(c.nombre),
                          ),
                        )
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _conjuntoSeleccionadoNit = v),
                  )
                else
                  const Text(
                    "No hay conjuntos creados para asignar.",
                    style: TextStyle(color: Colors.grey),
                  ),
                const SizedBox(height: 16),
              ],

              const SizedBox(height: 20),

              // ───────── BOTÓN GUARDAR ─────────
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _guardarUsuario,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(_isSaving ? "Guardando..." : "Guardar Usuario"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    textStyle: const TextStyle(fontSize: 16),
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
