import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/gerente_api.dart';
import 'package:flutter_application_1/model/usuario_model.dart';
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

class _HorarioDia {
  TimeOfDay? apertura;
  TimeOfDay? cierre;
  TimeOfDay? descansoInicio;
  TimeOfDay? descansoFin;

  bool get completo => apertura != null && cierre != null;

  bool get descansoCompleto => descansoInicio != null && descansoFin != null;
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
      initial = horario.apertura ?? const TimeOfDay(hour: 8, minute: 0);
    } else if (esDescansoInicio) {
      initial = horario.descansoInicio ?? const TimeOfDay(hour: 12, minute: 0);
    } else if (esDescansoFin) {
      initial = horario.descansoFin ?? const TimeOfDay(hour: 13, minute: 0);
    } else {
      initial = horario.cierre ?? const TimeOfDay(hour: 17, minute: 0);
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
        .map(
          (u) => {
            'nombre': u.nombreCtrl.text.trim(),
            'elementos': u.elementosCtrl.text
                .split('\n')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList(),
          },
        )
        .toList();

    setState(() => _isSaving = true);

    try {
      await _gerenteApi.crearConjunto(
        nitConjunto: _nitConjuntoCtrl.text.trim(),
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

      if (!mounted) return;
      Navigator.pop(context, true);
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
    super.dispose();
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
                        value: _adminSeleccionadoId,
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
                            'Ubicaciones y elementos (opcional)',
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

              SizedBox(
                width: double.infinity,
                height: 48,
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
                  label: Text(_isSaving ? 'Guardando...' : 'Guardar conjunto'),
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

class _UbicacionForm {
  final TextEditingController nombreCtrl = TextEditingController();
  final TextEditingController elementosCtrl = TextEditingController();

  void dispose() {
    nombreCtrl.dispose();
    elementosCtrl.dispose();
  }
}

class _UbicacionWidget extends StatelessWidget {
  final _UbicacionForm ubicacion;
  final VoidCallback onEliminar;

  const _UbicacionWidget({required this.ubicacion, required this.onEliminar});

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
            TextField(
              controller: ubicacion.elementosCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Elementos (uno por línea)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
