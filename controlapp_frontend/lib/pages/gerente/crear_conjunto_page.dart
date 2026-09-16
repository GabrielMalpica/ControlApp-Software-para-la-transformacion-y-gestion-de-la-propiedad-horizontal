import 'package:flutter/material.dart';
import '../../api/gerente_api.dart';
import 'package:flutter_application_1/api/conjunto_api.dart';
import 'package:flutter_application_1/model/usuario_model.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/service/theme.dart';

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
const _rolesNecesidad = <String>['TODERO', 'SALVAVIDAS', 'ASEO', 'PISCINERO'];

const _etiquetaRol = <String, String>{
  'TODERO': 'Todero',
  'SALVAVIDAS': 'Salvavidas',
  'ASEO': 'Aseo',
  'PISCINERO': 'Piscinero',
};

class _HorarioDia {
  TimeOfDay? apertura;
  TimeOfDay? cierre;
  TimeOfDay? descansoInicio;
  TimeOfDay? descansoFin;

  bool get completo => apertura != null && cierre != null;

  bool get descansoCompleto => descansoInicio != null && descansoFin != null;
}

/// Horario especial de una necesidad para un día concreto: más simple que
/// _HorarioDia del conjunto (sin descanso) para mantener manejable el
/// formulario cuando se editan varias plazas a la vez.
class _NecesidadHorarioDia {
  bool activo = false;
  TimeOfDay? apertura;
  TimeOfDay? cierre;

  bool get completo => activo && apertura != null && cierre != null;
}

/// Necesidad operativa (plaza/cargo) capturada localmente durante la
/// creación del conjunto. Se envía al backend (POST .../necesidades) recién
/// después de que el conjunto exista, igual que el mapa (ver F.3 del plan).
class _NecesidadForm {
  String rol;
  final TextEditingController etiquetaCtrl;
  bool horarioEspecial = false;
  final Map<String, _NecesidadHorarioDia> horariosPorDia = {
    for (final d in _diasSemana) d: _NecesidadHorarioDia(),
  };

  _NecesidadForm({required this.rol, required String etiquetaInicial})
    : etiquetaCtrl = TextEditingController(text: etiquetaInicial);

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
  String _etiquetaSugerida(String rol) {
    final base = _etiquetaRol[rol] ?? rol;
    final existentes = _necesidades.where((n) => n.rol == rol).length;
    return '$base #${existentes + 1}';
  }

  void _agregarNecesidad() {
    setState(() {
      final rolInicial = _rolesNecesidad[0];
      _necesidades.add(
        _NecesidadForm(
          rol: rolInicial,
          etiquetaInicial: _etiquetaSugerida(rolInicial),
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
  }) async {
    final initial =
        (esApertura ? horario.apertura : horario.cierre) ??
        TimeOfDay(hour: esApertura ? 8 : 17, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      setState(() {
        if (esApertura) {
          horario.apertura = picked;
        } else {
          horario.cierre = picked;
        }
      });
    }
  }

  /// Crea las necesidades ya cargadas contra el conjunto recién creado. Es
  /// una llamada de seguimiento (igual que el mapa, ver F.3 del plan): si
  /// alguna falla no revierte la creación del conjunto, solo se avisa.
  Future<List<String>> _crearNecesidadesPendientes(String conjuntoNit) async {
    final errores = <String>[];
    for (final n in _necesidades) {
      final etiqueta = n.etiquetaCtrl.text.trim();
      if (etiqueta.isEmpty) continue;
      final horarios = n.horarioEspecial
          ? n.horariosPorDia.entries
                .where((e) => e.value.completo)
                .map(
                  (e) => HorarioConjunto(
                    dia: e.key,
                    horaApertura: _formatTimeOfDay(e.value.apertura!),
                    horaCierre: _formatTimeOfDay(e.value.cierre!),
                  ),
                )
                .toList()
          : const <HorarioConjunto>[];
      try {
        await _conjuntoApi.crearNecesidad(
          conjuntoNit: conjuntoNit,
          rol: n.rol,
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

      if (!mounted) return;
      if (erroresNecesidades.isNotEmpty) {
        AppFeedback.showFromSnackBar(
          context,
          SnackBar(
            content: Text(
              'Conjunto creado, pero ${erroresNecesidades.length} necesidad(es) no se pudieron guardar. '
              'Agrégalas desde el detalle del conjunto.',
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

              // NECESIDADES OPERATIVAS (PLAZAS/CARGOS)
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
                          Icon(Icons.badge_outlined, color: AppTheme.primary),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Necesidades de operarios (opcional)',
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
                          'Define los cargos que necesita el conjunto (ej. Todero #1, '
                          'Salvavidas #1). Sin horario especial, cada plaza usa el '
                          'horario general de arriba; el operario que la ocupe se '
                          'asigna después, desde el detalle del conjunto.',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (int i = 0; i < _necesidades.length; i++)
                        _NecesidadWidget(
                          necesidad: _necesidades[i],
                          onEliminar: () => _eliminarNecesidad(i),
                          onChanged: () => setState(() {}),
                          onSeleccionarHora: (h, esApertura) =>
                              _seleccionarHoraNecesidad(
                                horario: h,
                                esApertura: esApertura,
                              ),
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _agregarNecesidad,
                          icon: const Icon(Icons.add),
                          label: const Text('Agregar necesidad'),
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

class _NecesidadWidget extends StatelessWidget {
  final _NecesidadForm necesidad;
  final VoidCallback onEliminar;
  final VoidCallback onChanged;
  final void Function(_NecesidadHorarioDia horario, bool esApertura)
  onSeleccionarHora;

  const _NecesidadWidget({
    required this.necesidad,
    required this.onEliminar,
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
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: necesidad.rol,
                    items: _rolesNecesidad
                        .map(
                          (r) => DropdownMenuItem(
                            value: r,
                            child: Text(_etiquetaRol[r] ?? r),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      necesidad.rol = v;
                      onChanged();
                    },
                    decoration: const InputDecoration(
                      labelText: 'Rol',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onEliminar,
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: necesidad.etiquetaCtrl,
              decoration: const InputDecoration(
                labelText: 'Etiqueta (ej. "Todero #1")',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Horario especial'),
              subtitle: const Text(
                'Sobrescribe el horario general del conjunto para esta plaza '
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
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
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
                        SizedBox(
                          width: 84,
                          child: Text(dia, style: const TextStyle(fontSize: 12)),
                        ),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: h.activo
                                ? () => onSeleccionarHora(h, true)
                                : null,
                            child: Text(
                              h.apertura == null
                                  ? 'Entrada'
                                  : _formatHora(h.apertura!),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: h.activo
                                ? () => onSeleccionarHora(h, false)
                                : null,
                            child: Text(
                              h.cierre == null ? 'Salida' : _formatHora(h.cierre!),
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
