import 'package:flutter/material.dart';
import '../../api/gerente_api.dart';
import 'package:flutter_application_1/api/conjunto_api.dart';
import 'package:flutter_application_1/model/usuario_model.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/utils/pickers/file_pick_bridge.dart';
import 'package:flutter_application_1/utils/pickers/selected_upload_file.dart';

import 'package:flutter_application_1/service/app_feedback.dart';

const _diasSemana = <String>[
  'LUNES',
  'MARTES',
  'MIERCOLES',
  'JUEVES',
  'VIERNES',
  'SABADO',
  'DOMINGO',
];

/// Roles disponibles para una necesidad/plaza. Coincide con el enum
/// TipoFuncion del backend (schema.prisma).
const _rolesNecesidad = <String>[
  'TODERO',
  'SALVAVIDAS',
  'ASEO',
  'PISCINERO',
  'JARDINERO',
];

const _etiquetaRol = <String, String>{
  'TODERO': 'Todero',
  'SALVAVIDAS': 'Salvavidas',
  'ASEO': 'Aseo',
  'PISCINERO': 'Piscinero',
  'JARDINERO': 'Jardinero',
};

/// "Todero-Salvavidas" para una plaza combinada; "Todero" para una sola.
String _etiquetaRoles(Iterable<String> roles) =>
    roles.map((r) => _etiquetaRol[r] ?? r).join('-');

class _HorarioDia {
  TimeOfDay? apertura;
  TimeOfDay? cierre;
  TimeOfDay? descansoInicio;
  TimeOfDay? descansoFin;

  bool get completo => apertura != null && cierre != null;

  bool get descansoCompleto => descansoInicio != null && descansoFin != null;
}

/// Horario especial de una necesidad para un día concreto: puede tener su
/// propio almuerzo/descanso, igual que el horario general, pero a una hora
/// distinta (ej. la plaza entra más tarde y almuerza más tarde).
class _NecesidadHorarioDia {
  bool activo = false;
  TimeOfDay? apertura;
  TimeOfDay? cierre;
  TimeOfDay? descansoInicio;
  TimeOfDay? descansoFin;

  bool get completo => activo && apertura != null && cierre != null;

  bool get descansoCompleto => descansoInicio != null && descansoFin != null;
}

/// Necesidad operativa (plaza/cargo) capturada localmente durante la
/// creación del conjunto. Se envía al backend (POST .../necesidades) recién
/// después de que el conjunto exista, igual que el mapa (ver F.3 del plan).
class _NecesidadForm {
  // Casi siempre un solo rol, pero admite combinaciones (ej.
  // Todero-Salvavidas): quien ocupe la plaza debe tener TODOS los roles
  // seleccionados aquí.
  final Set<String> roles;
  final TextEditingController etiquetaCtrl;
  // Ejemplo mostrado como placeholder (ej. "Todero #1"), no un valor
  // precargado: si el usuario no escribe nada se usa como etiqueta real.
  final String etiquetaSugerida;
  bool horarioEspecial = false;
  final Map<String, _NecesidadHorarioDia> horariosPorDia = {
    for (final d in _diasSemana) d: _NecesidadHorarioDia(),
  };

  _NecesidadForm({required this.roles, required this.etiquetaSugerida})
    : etiquetaCtrl = TextEditingController();

  void dispose() => etiquetaCtrl.dispose();
}

class CrearConjuntoPage extends StatefulWidget {
  final String nit; // NIT de la empresa

  const CrearConjuntoPage({super.key, required this.nit});

  @override
  State<CrearConjuntoPage> createState() => _CrearConjuntoPageState();
}

class _CrearConjuntoPageState extends State<CrearConjuntoPage> {
  final _formKey = GlobalKey<FormState>();

  final _nitConjuntoCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _correoCtrl = TextEditingController();
  final _valorMensualCtrl = TextEditingController();
  final _consignasCtrl = TextEditingController();
  final _valorAgregadoCtrl = TextEditingController();

  final GerenteApi _gerenteApi = GerenteApi();
  final ConjuntoApi _conjuntoApi = ConjuntoApi();
  bool _isSaving = false;

  // Admin seleccionado
  List<Usuario> _administradores = [];
  String? _adminSeleccionadoId;

  // tipos de servicio seleccionados
  final Set<String> _tiposServicioSeleccionados = {};

  // fecha inicio contrato
  DateTime? _fechaInicioContrato;

  // horarios por día
  late final Map<String, _HorarioDia> _horariosPorDia;

  // ubicaciones (nombre + lista de elementos simples)
  final List<_UbicacionForm> _ubicaciones = [];

  // necesidades operativas (plazas/cargos)
  final List<_NecesidadForm> _necesidades = [];

  // mapa del conjunto (opcional, ver F.3 del plan)
  SelectedUploadFile? _mapaSeleccionado;

  @override
  void initState() {
    super.initState();
    _horariosPorDia = {for (final d in _diasSemana) d: _HorarioDia()};
    _cargarAdministradores();
  }

  Future<void> _cargarAdministradores() async {
    try {
      // usamos el listarUsuarios(rol: 'administrador')
      final admins = await _gerenteApi.listarUsuarios(rol: 'administrador');
      setState(() {
        _administradores = admins;
      });
    } catch (e) {
      // solo mostramos snack si algo falla
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text('Error cargando administradores: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Helpers

  String _formatTimeOfDay(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  TimeOfDay? _horaReferenciaAnterior({
    required String dia,
    required bool esApertura,
    required bool esDescansoInicio,
    required bool esDescansoFin,
  }) {
    final indexDia = _diasSemana.indexOf(dia);
    if (indexDia <= 0) return null;

    for (var i = indexDia - 1; i >= 0; i--) {
      final anterior = _horariosPorDia[_diasSemana[i]]!;
      final candidata = esApertura
          ? anterior.apertura
          : esDescansoInicio
          ? anterior.descansoInicio
          : esDescansoFin
          ? anterior.descansoFin
          : anterior.cierre;
      if (candidata != null) return candidata;
    }

    return null;
  }

  List<String> _splitPorLineas(String raw) {
    return raw
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<void> _seleccionarFechaInicioContrato() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fechaInicioContrato ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      helpText: 'Fecha de inicio del contrato',
    );
    if (picked != null) {
      setState(() => _fechaInicioContrato = picked);
    }
  }

  Future<void> _seleccionarHora({
    required String dia,
    required bool esApertura,
    bool esDescansoInicio = false,
    bool esDescansoFin = false,
  }) async {
    final horario = _horariosPorDia[dia]!;

    TimeOfDay initial;
    if (esApertura) {
      initial =
          horario.apertura ??
          _horaReferenciaAnterior(
            dia: dia,
            esApertura: true,
            esDescansoInicio: false,
            esDescansoFin: false,
          ) ??
          const TimeOfDay(hour: 8, minute: 0);
    } else if (esDescansoInicio) {
      initial =
          horario.descansoInicio ??
          _horaReferenciaAnterior(
            dia: dia,
            esApertura: false,
            esDescansoInicio: true,
            esDescansoFin: false,
          ) ??
          const TimeOfDay(hour: 12, minute: 0);
    } else if (esDescansoFin) {
      initial =
          horario.descansoFin ??
          _horaReferenciaAnterior(
            dia: dia,
            esApertura: false,
            esDescansoInicio: false,
            esDescansoFin: true,
          ) ??
          const TimeOfDay(hour: 13, minute: 0);
    } else {
      initial =
          horario.cierre ??
          _horaReferenciaAnterior(
            dia: dia,
            esApertura: false,
            esDescansoInicio: false,
            esDescansoFin: false,
          ) ??
          const TimeOfDay(hour: 17, minute: 0);
    }

    final picked = await showTimePicker(context: context, initialTime: initial);

    if (picked != null) {
      setState(() {
        if (esApertura) {
          horario.apertura = picked;
        } else if (esDescansoInicio) {
          horario.descansoInicio = picked;
        } else if (esDescansoFin) {
          horario.descansoFin = picked;
        } else {
          horario.cierre = picked;
        }
      });
    }
  }

  // Ubicaciones (simples)
  void _agregarUbicacion() {
    setState(() {
      _ubicaciones.add(_UbicacionForm());
    });
  }

  void _eliminarUbicacion(int index) {
    setState(() {
      _ubicaciones.removeAt(index);
    });
  }

  // Necesidades operativas (plazas/cargos)
  String _claveRoles(Set<String> roles) => (roles.toList()..sort()).join('+');

  String _etiquetaSugerida(Set<String> roles) {
    final clave = _claveRoles(roles);
    final existentes = _necesidades
        .where((n) => _claveRoles(n.roles) == clave)
        .length;
    return '${_etiquetaRoles(roles)} #${existentes + 1}';
  }

  void _agregarNecesidad() {
    setState(() {
      final rolesIniciales = {_rolesNecesidad[0]};
      _necesidades.add(
        _NecesidadForm(
          roles: rolesIniciales,
          etiquetaSugerida: _etiquetaSugerida(rolesIniciales),
        ),
      );
    });
  }

  void _eliminarNecesidad(int index) {
    setState(() {
      _necesidades.removeAt(index).dispose();
    });
  }

  Future<void> _seleccionarHoraNecesidad({
    required _NecesidadHorarioDia horario,
    required bool esApertura,
    bool esDescansoInicio = false,
    bool esDescansoFin = false,
  }) async {
    final TimeOfDay defecto;
    final TimeOfDay? actual;
    if (esApertura) {
      actual = horario.apertura;
      defecto = const TimeOfDay(hour: 8, minute: 0);
    } else if (esDescansoInicio) {
      actual = horario.descansoInicio;
      defecto = const TimeOfDay(hour: 12, minute: 0);
    } else if (esDescansoFin) {
      actual = horario.descansoFin;
      defecto = const TimeOfDay(hour: 13, minute: 0);
    } else {
      actual = horario.cierre;
      defecto = const TimeOfDay(hour: 17, minute: 0);
    }
    final picked = await showTimePicker(
      context: context,
      initialTime: actual ?? defecto,
    );
    if (picked != null) {
      setState(() {
        if (esApertura) {
          horario.apertura = picked;
        } else if (esDescansoInicio) {
          horario.descansoInicio = picked;
        } else if (esDescansoFin) {
          horario.descansoFin = picked;
        } else {
          horario.cierre = picked;
        }
      });
    }
  }

  Future<void> _seleccionarMapa() async {
    final archivos = await UniversalFilePick.pick(
      allowMultiple: false,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (archivos.isEmpty) return;
    setState(() => _mapaSeleccionado = archivos.first);
  }

  /// Crea las necesidades ya cargadas contra el conjunto recién creado. Es
  /// una llamada de seguimiento (igual que el mapa, ver F.3 del plan): si
  /// alguna falla no revierte la creación del conjunto, solo se avisa.
  Future<List<String>> _crearNecesidadesPendientes(String conjuntoNit) async {
    final errores = <String>[];
    for (final n in _necesidades) {
      final texto = n.etiquetaCtrl.text.trim();
      final etiqueta = texto.isEmpty ? n.etiquetaSugerida : texto;
      if (etiqueta.isEmpty || n.roles.isEmpty) continue;
      final horarios = n.horarioEspecial
          ? n.horariosPorDia.entries
                .where((e) => e.value.completo)
                .map(
                  (e) => HorarioConjunto(
                    dia: e.key,
                    horaApertura: _formatTimeOfDay(e.value.apertura!),
                    horaCierre: _formatTimeOfDay(e.value.cierre!),
                    descansoInicio: e.value.descansoCompleto
                        ? _formatTimeOfDay(e.value.descansoInicio!)
                        : null,
                    descansoFin: e.value.descansoCompleto
                        ? _formatTimeOfDay(e.value.descansoFin!)
                        : null,
                  ),
                )
                .toList()
          : const <HorarioConjunto>[];
      try {
        await _conjuntoApi.crearNecesidad(
          conjuntoNit: conjuntoNit,
          roles: n.roles.toList(),
          etiqueta: etiqueta,
          horarioEspecial: n.horarioEspecial,
          horarios: horarios,
        );
      } catch (e) {
        errores.add('$etiqueta: $e');
      }
    }
    return errores;
  }

  Future<void> _guardarConjunto() async {
    if (!_formKey.currentState!.validate()) return;

    if (_tiposServicioSeleccionados.isEmpty) {
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(
          content: Text('Seleccione al menos un tipo de servicio'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_fechaInicioContrato == null) {
      AppFeedback.showFromSnackBar(
        context,
        const SnackBar(
          content: Text('Seleccione la fecha de inicio del contrato'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // valor mensual
    double? valorMensual;
    if (_valorMensualCtrl.text.trim().isNotEmpty) {
      valorMensual = double.tryParse(_valorMensualCtrl.text.trim());
      if (valorMensual == null) {
        AppFeedback.showFromSnackBar(
          context,
          const SnackBar(
            content: Text('Valor mensual inválido'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    // payload de horarios
    final List<Map<String, String>> horariosPayload = [];
    _horariosPorDia.forEach((dia, h) {
      if (h.completo) {
        final apertura = _formatTimeOfDay(h.apertura!);
        final cierre = _formatTimeOfDay(h.cierre!);
        if (apertura.compareTo(cierre) >= 0) {
          // validación simple: apertura < cierre
          return;
        }
        final payload = {
          'dia': dia,
          'horaApertura': apertura,
          'horaCierre': cierre,
        };

        if (h.descansoCompleto) {
          payload['descansoInicio'] = _formatTimeOfDay(h.descansoInicio!);
          payload['descansoFin'] = _formatTimeOfDay(h.descansoFin!);
        }

        horariosPayload.add(payload);
      }
    });

    // payload de ubicaciones
    final List<Map<String, dynamic>> ubicacionesPayload = _ubicaciones
        .where((u) => u.nombreCtrl.text.trim().isNotEmpty)
        .map((u) => u.toPayload())
        .toList();

    setState(() => _isSaving = true);

    try {
      final nitConjunto = _nitConjuntoCtrl.text.trim();
      await _gerenteApi.crearConjunto(
        nitConjunto: nitConjunto,
        nombre: _nombreCtrl.text.trim(),
        direccion: _direccionCtrl.text.trim(),
        correo: _correoCtrl.text.trim(),
        empresaId: widget.nit,
        administradorId: _adminSeleccionadoId,
        tiposServicio: _tiposServicioSeleccionados.toList(),
        valorMensual: valorMensual,
        consignasEspeciales: _splitPorLineas(_consignasCtrl.text),
        valorAgregado: _splitPorLineas(_valorAgregadoCtrl.text),
        fechaInicioContrato: _fechaInicioContrato,
        horarios: horariosPayload,
        ubicaciones: ubicacionesPayload,
      );

      // El conjunto ya existe: las necesidades se crean en llamadas de
      // seguimiento (igual que el mapa) porque ConjuntoNecesidadService
      // exige que el conjunto exista antes de aceptar una plaza.
      final erroresNecesidades = _necesidades.isEmpty
          ? const <String>[]
          : await _crearNecesidadesPendientes(nitConjunto);

      String? errorMapa;
      if (_mapaSeleccionado != null) {
        try {
          await _conjuntoApi.subirMapaConjunto(
            conjuntoNit: nitConjunto,
            archivo: _mapaSeleccionado!,
          );
        } catch (e) {
          errorMapa = e.toString();
        }
      }

      if (!mounted) return;
      if (erroresNecesidades.isNotEmpty || errorMapa != null) {
        final partes = <String>[
          if (erroresNecesidades.isNotEmpty)
            '${erroresNecesidades.length} necesidad(es) no se pudieron guardar',
          if (errorMapa != null) 'el mapa no se pudo subir',
        ];
        AppFeedback.showFromSnackBar(
          context,
          SnackBar(
            content: Text(
              'Conjunto creado, pero ${partes.join(' y ')}. '
              'Complétalo desde el detalle del conjunto o Mapa de Áreas.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }

      if (!mounted) return;
      await _mostrarGuardadoYVolverMenu();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showFromSnackBar(
        context,
        SnackBar(
          content: Text('❌ Error al crear conjunto: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  void dispose() {
    _nitConjuntoCtrl.dispose();
    _nombreCtrl.dispose();
    _direccionCtrl.dispose();
    _correoCtrl.dispose();
    _valorMensualCtrl.dispose();
    _consignasCtrl.dispose();
    _valorAgregadoCtrl.dispose();
    for (final u in _ubicaciones) {
      u.dispose();
    }
    for (final n in _necesidades) {
      n.dispose();
    }
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

    Navigator.pushNamedAndRemoveUntil(
      context,
      '/home-gerente',
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: const Text(
          'Crear Conjunto',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // DATOS BÁSICOS
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.apartment, color: AppTheme.primary),
                          const SizedBox(width: 8),
                          const Text(
                            'Datos generales',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _nitConjuntoCtrl,
                        decoration: const InputDecoration(
                          labelText: 'NIT del conjunto',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => v == null || v.isEmpty
                            ? 'Ingrese el NIT del conjunto'
                            : null,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _nombreCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nombre del conjunto',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Ingrese el nombre' : null,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _direccionCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Dirección',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => v == null || v.isEmpty
                            ? 'Ingrese la dirección'
                            : null,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _correoCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Correo de contacto',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => v == null || !v.contains('@')
                            ? 'Correo inválido'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      // FECHA INICIO CONTRATO
                      InkWell(
                        onTap: _seleccionarFechaInicioContrato,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Fecha inicio de contrato',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            _fechaInicioContrato == null
                                ? 'Seleccionar fecha'
                                : '${_fechaInicioContrato!.day}/${_fechaInicioContrato!.month}/${_fechaInicioContrato!.year}',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ADMIN Y TIPOS DE SERVICIO
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.badge, color: AppTheme.primary),
                          const SizedBox(width: 8),
                          const Text(
                            'Administración y servicios',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // ADMIN
                      DropdownButtonFormField<String>(
                        initialValue: _adminSeleccionadoId,
                        items: _administradores
                            .map(
                              (u) => DropdownMenuItem(
                                value: u.cedula,
                                child: Text('${u.nombre} (${u.cedula})'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() {
                          _adminSeleccionadoId = v;
                        }),
                        decoration: const InputDecoration(
                          labelText: 'Administrador (opcional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Tipos de servicio',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children:
                            const [
                              'ASEO',
                              'PISCINA',
                              'JARDINERIA', // <-- Ajusta si tu enum tiene tilde o no
                              'MANTENIMIENTOS_LOCATIVOS',
                              'SALVAMENTO_ACUATICO',
                            ].map((tipo) {
                              return Builder(
                                builder: (context) {
                                  final selected = _tiposServicioSeleccionados
                                      .contains(tipo);
                                  return FilterChip(
                                    label: Text(tipo),
                                    selected: selected,
                                    onSelected: (v) {
                                      _tiposServicioSeleccionados.contains(
                                        tipo,
                                      );
                                      (context as Element).markNeedsBuild();
                                      if (v) {
                                        _tiposServicioSeleccionados.add(tipo);
                                      } else {
                                        _tiposServicioSeleccionados.remove(
                                          tipo,
                                        );
                                      }
                                    },
                                  );
                                },
                              );
                            }).toList(),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _valorMensualCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Valor mensual (opcional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 4),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Operarios del conjunto (opcional)',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '¿Cuántos operarios va a tener este conjunto y qué rol '
                          'cumple cada uno? (ej. 2 × Todero, 1 × Salvavidas). '
                          'El horario especial de cada cargo -si aplica- se '
                          'configura más abajo, después del horario general. El '
                          'operario que ocupe cada cargo se asigna luego desde el '
                          'detalle del conjunto.',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (int i = 0; i < _necesidades.length; i++)
                        _NecesidadRolWidget(
                          necesidad: _necesidades[i],
                          onEliminar: () => _eliminarNecesidad(i),
                          onChanged: () => setState(() {}),
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _agregarNecesidad,
                          icon: const Icon(Icons.add),
                          label: const Text('Agregar operario/cargo'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // HORARIOS
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.access_time, color: AppTheme.primary),
                          const SizedBox(width: 8),
                          const Text(
                            'Horarios por día (opcional)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Column(
                        children: _diasSemana.map((dia) {
                          final h = _horariosPorDia[dia]!;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 90,
                                  child: Text(
                                    dia,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => _seleccionarHora(
                                      dia: dia,
                                      esApertura: true,
                                    ),
                                    child: Text(
                                      h.apertura == null
                                          ? 'Apertura'
                                          : _formatTimeOfDay(h.apertura!),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => _seleccionarHora(
                                      esApertura: false,
                                      dia: dia,
                                      esDescansoInicio: true,
                                    ),
                                    child: Text(
                                      h.descansoInicio == null
                                          ? 'Desc. ini'
                                          : _formatTimeOfDay(h.descansoInicio!),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => _seleccionarHora(
                                      dia: dia,
                                      esDescansoFin: true,
                                      esApertura: false,
                                    ),
                                    child: Text(
                                      h.descansoFin == null
                                          ? 'Desc. fin'
                                          : _formatTimeOfDay(h.descansoFin!),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => _seleccionarHora(
                                      dia: dia,
                                      esApertura: false,
                                    ),
                                    child: Text(
                                      h.cierre == null
                                          ? 'Cierre'
                                          : _formatTimeOfDay(h.cierre!),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // HORARIOS ESPECIALES POR CARGO (solo para los operarios/roles
              // definidos arriba, en Administración y servicios; no todos
              // necesitan uno: el que no se configure aquí usa el horario
              // general del conjunto de la sección anterior).
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.schedule, color: AppTheme.primary),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Horarios especiales por cargo (opcional)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'No todos los cargos necesitan un horario propio: '
                          'actívalo solo para los que lo requieran (puede '
                          'exceder el horario general o cubrir días en que el '
                          'conjunto no opera). El resto sigue el horario '
                          'general definido arriba.',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_necesidades.isEmpty)
                        Text(
                          'Primero agrega operarios/cargos en '
                          '"Administración y servicios".',
                          style: TextStyle(color: Colors.grey.shade600),
                        )
                      else
                        for (int i = 0; i < _necesidades.length; i++)
                          _NecesidadHorarioEspecialWidget(
                            necesidad: _necesidades[i],
                            onChanged: () => setState(() {}),
                            onSeleccionarHora:
                                ({
                                  required h,
                                  required esApertura,
                                  esDescansoInicio = false,
                                  esDescansoFin = false,
                                }) => _seleccionarHoraNecesidad(
                                  horario: h,
                                  esApertura: esApertura,
                                  esDescansoInicio: esDescansoInicio,
                                  esDescansoFin: esDescansoFin,
                                ),
                          ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // MAPA DEL CONJUNTO (opcional)
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.map_outlined, color: AppTheme.primary),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Mapa del conjunto (opcional)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _mapaSeleccionado?.name ??
                                  'Ningún archivo seleccionado',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: _seleccionarMapa,
                            icon: const Icon(Icons.upload_file),
                            label: Text(
                              _mapaSeleccionado == null
                                  ? 'Adjuntar imagen'
                                  : 'Cambiar',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'También puedes cargarlo después desde Mapa de Áreas.',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // CONSIGNAS Y VALOR AGREGADO + UBICACIONES
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.sticky_note_2_outlined,
                            color: AppTheme.primary,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Consignas y valor agregado',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _consignasCtrl,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText:
                              'Consignas especiales (una por línea, opcional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _valorAgregadoCtrl,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText:
                              'Valor agregado (una línea por ítem, opcional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // UBICACIONES BÁSICAS
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            color: AppTheme.primary,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Ubicaciones, subzonas y áreas (opcional)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Column(
                        children: [
                          for (int i = 0; i < _ubicaciones.length; i++)
                            _UbicacionWidget(
                              ubicacion: _ubicaciones[i],
                              onEliminar: () => _eliminarUbicacion(i),
                              onChanged: () => setState(() {}),
                            ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: _agregarUbicacion,
                              icon: const Icon(Icons.add),
                              label: const Text('Agregar ubicación'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              Align(
                alignment: Alignment.centerLeft,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _guardarConjunto,
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
                  label: Text(_isSaving ? 'Guardando...' : 'Guardar'),
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

class _ZonaForm {
  final TextEditingController nombreCtrl = TextEditingController();
  final TextEditingController areasCtrl = TextEditingController();

  Map<String, dynamic>? toPayload() {
    final nombre = nombreCtrl.text.trim();
    final areas = areasCtrl.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (nombre.isEmpty) return null;
    return {
      'nombre': nombre,
      'hijos': areas
          .map((area) => {'nombre': area, 'hijos': const []})
          .toList(),
    };
  }

  void dispose() {
    nombreCtrl.dispose();
    areasCtrl.dispose();
  }
}

class _UbicacionForm {
  final TextEditingController nombreCtrl = TextEditingController();
  final List<_ZonaForm> zonas = [];

  void agregarZona() => zonas.add(_ZonaForm());

  void eliminarZona(int index) {
    zonas[index].dispose();
    zonas.removeAt(index);
  }

  Map<String, dynamic> toPayload() {
    return {
      'nombre': nombreCtrl.text.trim(),
      'elementos': zonas
          .map((zona) => zona.toPayload())
          .whereType<Map<String, dynamic>>()
          .toList(),
    };
  }

  void dispose() {
    nombreCtrl.dispose();
    for (final zona in zonas) {
      zona.dispose();
    }
  }
}

/// Fila de "Administración y servicios": solo rol + etiqueta. Cuántos
/// operarios va a tener el conjunto y qué rol cumple cada uno se define
/// aquí, independientemente de si luego se les da un horario especial.
class _NecesidadRolWidget extends StatelessWidget {
  final _NecesidadForm necesidad;
  final VoidCallback onEliminar;
  final VoidCallback onChanged;

  const _NecesidadRolWidget({
    required this.necesidad,
    required this.onEliminar,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Rol(es): puedes combinar varios (ej. Todero + Salvavidas)',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: onEliminar,
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: _rolesNecesidad.map((r) {
              final selected = necesidad.roles.contains(r);
              return FilterChip(
                label: Text(_etiquetaRol[r] ?? r),
                selected: selected,
                onSelected: (v) {
                  if (v) {
                    necesidad.roles.add(r);
                  } else if (necesidad.roles.length > 1) {
                    necesidad.roles.remove(r);
                  } else {
                    // Al menos un rol debe quedar seleccionado.
                    return;
                  }
                  onChanged();
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: necesidad.etiquetaCtrl,
            decoration: InputDecoration(
              labelText: 'Etiqueta',
              hintText: 'ej. "${necesidad.etiquetaSugerida}"',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sección "Horarios especiales por cargo": se muestra DESPUÉS del horario
/// general del conjunto. Solo aplica a los cargos ya definidos en
/// Administración y servicios, y no todos necesitan uno -el switch queda
/// apagado por defecto y el cargo sigue el horario general hasta que se
/// active-.
class _NecesidadHorarioEspecialWidget extends StatelessWidget {
  final _NecesidadForm necesidad;
  final VoidCallback onChanged;
  final Future<void> Function({
    required _NecesidadHorarioDia h,
    required bool esApertura,
    bool esDescansoInicio,
    bool esDescansoFin,
  })
  onSeleccionarHora;

  const _NecesidadHorarioEspecialWidget({
    required this.necesidad,
    required this.onChanged,
    required this.onSeleccionarHora,
  });

  String _formatHora(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: const Color(0xFFF7FAF8),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.badge_outlined, size: 16, color: AppTheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: ListenableBuilder(
                    listenable: necesidad.etiquetaCtrl,
                    builder: (context, _) {
                      final etiqueta = necesidad.etiquetaCtrl.text.trim();
                      final rolLabel = _etiquetaRoles(necesidad.roles);
                      final etiquetaMostrada = etiqueta.isEmpty
                          ? necesidad.etiquetaSugerida
                          : etiqueta;
                      return Text(
                        '$etiquetaMostrada · $rolLabel',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      );
                    },
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Horario especial'),
              subtitle: const Text(
                'Sobrescribe el horario general del conjunto para este cargo '
                '(puede exceder su horario o cubrir días en que no opera).',
                style: TextStyle(fontSize: 11),
              ),
              value: necesidad.horarioEspecial,
              onChanged: (v) {
                necesidad.horarioEspecial = v;
                onChanged();
              },
            ),
            if (necesidad.horarioEspecial)
              Column(
                children: _diasSemana.map((dia) {
                  final h = necesidad.horariosPorDia[dia]!;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 28,
                              child: Checkbox(
                                value: h.activo,
                                onChanged: (v) {
                                  h.activo = v ?? false;
                                  onChanged();
                                },
                              ),
                            ),
                            Text(
                              dia,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        if (h.activo)
                          Padding(
                            padding: const EdgeInsets.only(left: 28),
                            child: Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => onSeleccionarHora(
                                      h: h,
                                      esApertura: true,
                                    ),
                                    child: Text(
                                      h.apertura == null
                                          ? 'Entrada'
                                          : _formatHora(h.apertura!),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => onSeleccionarHora(
                                      h: h,
                                      esApertura: false,
                                      esDescansoInicio: true,
                                    ),
                                    child: Text(
                                      h.descansoInicio == null
                                          ? 'Desc. ini'
                                          : _formatHora(h.descansoInicio!),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => onSeleccionarHora(
                                      h: h,
                                      esApertura: false,
                                      esDescansoFin: true,
                                    ),
                                    child: Text(
                                      h.descansoFin == null
                                          ? 'Desc. fin'
                                          : _formatHora(h.descansoFin!),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => onSeleccionarHora(
                                      h: h,
                                      esApertura: false,
                                    ),
                                    child: Text(
                                      h.cierre == null
                                          ? 'Salida'
                                          : _formatHora(h.cierre!),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _UbicacionWidget extends StatelessWidget {
  final _UbicacionForm ubicacion;
  final VoidCallback onEliminar;
  final VoidCallback onChanged;

  const _UbicacionWidget({
    required this.ubicacion,
    required this.onEliminar,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Row(
              children: [
                const Text(
                  'Ubicación',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onEliminar,
                ),
              ],
            ),
            TextField(
              controller: ubicacion.nombreCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre de la ubicación',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Subzonas o categorias internas',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
            ...ubicacion.zonas.asMap().entries.map((entry) {
              final index = entry.key;
              final zona = entry.value;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: const Color(0xFFF7FAF8),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Subzona',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () {
                              ubicacion.eliminarZona(index);
                              onChanged();
                            },
                          ),
                        ],
                      ),
                      TextField(
                        controller: zona.nombreCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nombre de la subzona',
                          hintText:
                              'Ej: Zona verde, zona humeda, zona transitiva',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: zona.areasCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Áreas finales (una por línea)',
                          hintText: 'Ej: Parque, Piscina, Pasillo 1',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  ubicacion.agregarZona();
                  onChanged();
                },
                icon: const Icon(Icons.add),
                label: const Text('Agregar subzona'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
