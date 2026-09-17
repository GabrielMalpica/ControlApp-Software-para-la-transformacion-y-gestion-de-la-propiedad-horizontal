import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/gerente_api.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/model/usuario_model.dart';
import 'package:flutter_application_1/repositories/usuario_repository.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/utils/enums/usuario_enums.dart';
import 'package:flutter_application_1/utils/enums/usuario_enums_service.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:intl/intl.dart';

import 'package:flutter_application_1/service/app_feedback.dart';
import 'package:flutter_application_1/widgets/skeleton.dart';

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
  final GerenteApi _gerenteApi = GerenteApi();

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
  String? tallaCamisa, tallaPantalon, tallaCalzado;
  String? rolSeleccionado;

  // ✅ NUEVOS
  bool activo = true;
  String? patronJornada;

  // Traslado de conjunto (solo aplica a operarios)
  List<Conjunto> _conjuntos = [];
  bool _cargandoConjuntos = true;
  String? _errorConjuntos;
  String? _conjuntoSeleccionadoNit;
  String? _conjuntoOriginalNit;

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
    tallaCamisa = u.tallaCamisa;
    tallaPantalon = u.tallaPantalon;
    tallaCalzado = u.tallaCalzado;
    tipoContrato = u.tipoContrato;
    jornada = u.jornadaLaboral;

    // ✅ Inicializar nuevos campos (asegúrate que existan en tu Usuario model)
    activo = u.activo;
    patronJornada = jornada == 'MEDIO_TIEMPO' ? u.patronJornada : null;

    _conjuntoSeleccionadoNit = u.conjuntoNit;
    _conjuntoOriginalNit = u.conjuntoNit;

    _cargarEnums();
    _cargarConjuntos();
  }

  Future<void> _cargarConjuntos() async {
    try {
      final lista = await _gerenteApi.listarConjuntos();
      setState(() {
        _conjuntos = lista;
        _cargandoConjuntos = false;
        _errorConjuntos = null;
      });
    } catch (e) {
      setState(() {
        _cargandoConjuntos = false;
        _errorConjuntos = AppError.messageOf(e);
      });
    }
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

    setState(() => _guardando = true);

    if (rolSeleccionado == 'operario') {
      final trasladoOk = await _asegurarTrasladoConjunto();
      if (!trasladoOk) {
        if (mounted) setState(() => _guardando = false);
        return;
      }
    }

    try {
      final cambios = <String, dynamic>{
        'nombre': _nombreCtrl.text,
        'correo': _correoCtrl.text,
        'rol': rolSeleccionado,
        'telefono': _telefonoCtrl.text,
        'direccion': _direccionCtrl.text.trim().isEmpty
            ? null
            : _direccionCtrl.text.trim(),
        if (fechaNacimiento != null)
          'fechaNacimiento': DateFormat('yyyy-MM-dd').format(fechaNacimiento!),
        'estadoCivil': estadoCivilSeleccionado,
        'numeroHijos': numeroHijos,
        'padresVivos': padresVivos,
        'tipoSangre': tipoSangre,
        'eps': eps,
        'fondoPensiones': fondo,
        'tallaCamisa': tallaCamisa,
        'tallaPantalon': tallaPantalon,
        'tallaCalzado': tallaCalzado,
        'tipoContrato': tipoContrato,
        'jornadaLaboral': jornada,

        // ✅ NUEVOS
        'activo': activo,
        'patronJornada': jornada == 'MEDIO_TIEMPO' ? patronJornada : null,
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

  /// Si el conjunto seleccionado cambió respecto al actual, intenta
  /// trasladar al operario. Si tiene tareas abiertas, ofrece cerrarlas en
  /// bloque (completadas o no completadas) y reintenta el traslado.
  /// Devuelve `false` si el usuario canceló y el guardado debe abortarse.
  Future<bool> _asegurarTrasladoConjunto() async {
    final destino = _conjuntoSeleccionadoNit;
    if (destino == null ||
        destino.trim().isEmpty ||
        destino == _conjuntoOriginalNit) {
      return true;
    }

    try {
      await _gerenteApi.trasladarOperario(
        operarioCedula: widget.usuario.cedula,
        conjuntoDestinoNit: destino,
      );
      _conjuntoOriginalNit = destino;
      return true;
    } on TareasAbiertasException catch (e) {
      if (!mounted) return false;
      final resultado = await _mostrarDialogoTareasAbiertas(e.cantidad);
      if (resultado == null) {
        if (!mounted) return false;
        AppFeedback.showFromSnackBar(
          context,
          const SnackBar(
            content: Text(
              'Traslado cancelado. No se guardaron los cambios.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return false;
      }

      await _gerenteApi.cerrarTareasAbiertasOperario(
        operarioCedula: widget.usuario.cedula,
        resultado: resultado,
      );
      await _gerenteApi.trasladarOperario(
        operarioCedula: widget.usuario.cedula,
        conjuntoDestinoNit: destino,
      );
      _conjuntoOriginalNit = destino;
      return true;
    }
  }

  Future<String?> _mostrarDialogoTareasAbiertas(int cantidad) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Tareas abiertas'),
        content: Text(
          'Este operario tiene $cantidad tarea(s) abierta(s). Para trasladarlo '
          'a otro conjunto primero debes cerrarlas. ¿Cómo quieres cerrarlas?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('NO_COMPLETADA'),
            child: const Text('No completadas'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop('COMPLETADA'),
            child: const Text('Completadas'),
          ),
        ],
      ),
    );
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
      return const Scaffold(body: SkeletonList());
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
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: tallaCamisa,
                        items: enums.tallasCamisa
                            .map(
                              (t) => DropdownMenuItem(
                                value: t,
                                child: Text(prettyEnum(t)),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => tallaCamisa = v),
                        decoration: const InputDecoration(
                          labelText: 'Talla camisa (opcional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: tallaPantalon,
                        items: enums.tallasPantalon
                            .map(
                              (t) => DropdownMenuItem(
                                value: t,
                                child: Text(prettyEnum(t)),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => tallaPantalon = v),
                        decoration: const InputDecoration(
                          labelText: 'Talla pantalón (opcional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: tallaCalzado,
                        items: enums.tallasCalzado
                            .map(
                              (t) => DropdownMenuItem(
                                value: t,
                                child: Text(prettyEnum(t)),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => tallaCalzado = v),
                        decoration: const InputDecoration(
                          labelText: 'Talla calzado (opcional)',
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
                      if (rolSeleccionado == 'operario') ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Conjunto asignado',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        if (_cargandoConjuntos)
                          const LinearProgressIndicator()
                        else if (_errorConjuntos != null)
                          Text(
                            'Error cargando conjuntos: $_errorConjuntos',
                            style: const TextStyle(color: Colors.red),
                          )
                        else if (_conjuntos.isEmpty)
                          const Text(
                            'No hay conjuntos creados.',
                            style: TextStyle(color: Colors.grey),
                          )
                        else
                          DropdownButtonFormField<String>(
                            initialValue:
                                _conjuntos.any(
                                  (c) => c.nit == _conjuntoSeleccionadoNit,
                                )
                                ? _conjuntoSeleccionadoNit
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'Conjunto',
                              helperText:
                                  'Cambiar el conjunto traslada al operario. '
                                  'Si tiene tareas abiertas se pedirá cerrarlas.',
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
                          ),
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

