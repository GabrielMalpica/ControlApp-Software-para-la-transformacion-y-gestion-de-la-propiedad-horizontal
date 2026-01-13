import 'package:flutter/material.dart';
import 'package:flutter_application_1/model/usuario_model.dart';

import '../api/tarea_api.dart';
import '../api/gerente_api.dart';
import '../api/empresa_api.dart';
import '../api/cronograma_api.dart';
import '../repositories/maquinaria_repository.dart';

import '../model/conjunto_model.dart';
import '../model/maquinaria_model.dart';
import '../service/theme.dart';

class CrearTareaPage extends StatefulWidget {
  final String nit;

  const CrearTareaPage({super.key, required this.nit});

  @override
  State<CrearTareaPage> createState() => _CrearTareaPageState();
}

class _CrearTareaPageState extends State<CrearTareaPage> {
  final _formKey = GlobalKey<FormState>();

  // APIs
  final TareaApi _tareaApi = TareaApi();
  final GerenteApi _gerenteApi = GerenteApi();
  final EmpresaApi _empresaApi = EmpresaApi();
  final MaquinariaRepository _maquinariaRepo = MaquinariaRepository();
  final CronogramaApi _cronogramaApi = CronogramaApi();

  // Controllers
  final _descripcionCtrl = TextEditingController();
  final _duracionCtrl = TextEditingController(); // ahora en MINUTOS
  final _observacionesCtrl = TextEditingController();

  // Fechas y horas
  DateTime? fechaInicio; // solo fecha
  DateTime? fechaFin; // solo fecha (mismo día por ahora)
  TimeOfDay? _horaInicio;

  // Estado de carga / guardado
  bool _cargandoInicial = true;
  bool _guardando = false;

  // Conjuntos
  List<Conjunto> _conjuntos = [];
  Conjunto? _conjuntoSeleccionado;

  // Ubicaciones / elementos
  List<UbicacionConElementos> _ubicaciones = [];
  UbicacionConElementos? _ubicacionSeleccionada;

  List<Elemento> _elementos = [];
  Elemento? _elementoSeleccionado;

  // Operarios del conjunto
  List<Usuario> _operarios = [];
  final List<int> _operariosSeleccionadosIds = []; // usamos cédula como int

  // Supervisores
  List<Usuario> _supervisores = [];
  int? _supervisorId; // cédula como int

  // Maquinaria disponible y seleccionada
  List<MaquinariaResponse> _maquinariaDisponible = [];
  final List<int> _maquinariaSeleccionadaIds = [];

  int? _limiteMinSemana;

  int _prioridad = 2;
  List<Map<String, dynamic>> _insumosDisponibles = [];
  final List<Map<String, dynamic>> _insumosSeleccionados = [];
  bool _cargandoInsumos = false;

  @override
  void initState() {
    super.initState();
    _cargarInicial();
  }

  @override
  void dispose() {
    _descripcionCtrl.dispose();
    _duracionCtrl.dispose();
    _observacionesCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarLimiteSemana(String conjuntoNit) async {
    try {
      final limite = await _empresaApi.getLimiteMinSemanaPorConjunto();
      if (!mounted) return;
      setState(() => _limiteMinSemana = limite);
    } catch (_) {
      if (!mounted) return;
      setState(() => _limiteMinSemana = null);
    }
  }

  /// Carga conjuntos, supervisores y maquinaria disponible
  Future<void> _cargarInicial() async {
    try {
      final conjuntos = await _gerenteApi.listarConjuntos();
      final supervisores = await _gerenteApi.listarSupervisores();
      final maquinariaDisp = await _empresaApi.listarMaquinariaDisponible();

      Conjunto? seleccionado;
      if (conjuntos.isNotEmpty) {
        seleccionado = conjuntos.firstWhere(
          (c) => c.nit == widget.nit,
          orElse: () => conjuntos.first,
        );
      }

      if (!mounted) return;
      setState(() {
        _conjuntos = conjuntos;
        _supervisores = supervisores;
        _maquinariaDisponible = maquinariaDisp;
        _cargandoInicial = false;
      });

      if (seleccionado != null) {
        _refrescarDatosConjunto(seleccionado);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargandoInicial = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error cargando datos iniciales: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Cuando cambia el conjunto, refrescamos ubicaciones, elementos y operarios
  void _refrescarDatosConjunto(Conjunto conjunto) {
    setState(() {
      _conjuntoSeleccionado = conjunto;

      _ubicaciones = conjunto.ubicaciones;
      _ubicacionSeleccionada = null;

      _elementos = [];
      _elementoSeleccionado = null;

      _operarios = conjunto.operarios;
      _operariosSeleccionadosIds.clear();

      _maquinariaSeleccionadaIds.clear();
      _supervisorId = null;
      _cargarLimiteSemana(conjunto.nit);
      _insumosSeleccionados.clear();
      //TODO: _cargarInsumosConjunto(conjunto.nit);
    });
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

  Future<void> _seleccionarHoraInicio() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _horaInicio ?? const TimeOfDay(hour: 8, minute: 0),
    );
    if (picked != null) {
      setState(() => _horaInicio = picked);
    }
  }

  /// Selección múltiple de operarios
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

  /// Selección múltiple de maquinaria
  Future<void> _mostrarSelectorMaquinaria() async {
    if (_maquinariaDisponible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay maquinaria disponible')),
      );
      return;
    }

    final seleccionTemp = Set<int>.from(_maquinariaSeleccionadaIds);

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Maquinaria a prestar'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _maquinariaDisponible.length,
                  itemBuilder: (_, index) {
                    final m = _maquinariaDisponible[index];
                    final checked = seleccionTemp.contains(m.id);
                    return CheckboxListTile(
                      value: checked,
                      title: Text('${m.nombre} (${m.marca})'),
                      subtitle: Text(m.tipo.label),
                      onChanged: (v) {
                        if (v == true) {
                          seleccionTemp.add(m.id);
                        } else {
                          seleccionTemp.remove(m.id);
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
        _maquinariaSeleccionadaIds
          ..clear()
          ..addAll(seleccionTemp);
      });
    }
  }

  DateTime _combinarFechaYHora(DateTime fecha, TimeOfDay hora) {
    return DateTime(fecha.year, fecha.month, fecha.day, hora.hour, hora.minute);
  }

  bool _intervalosSeSolapan(
    DateTime aInicio,
    DateTime aFin,
    DateTime bInicio,
    DateTime bFin,
  ) {
    return aInicio.isBefore(bFin) && bInicio.isBefore(aFin);
  }

  DateTime _inicioSemana(DateTime d) {
    // lunes = 1, domingo = 7
    final diff = d.weekday - DateTime.monday; // 0 para lunes
    return DateTime(d.year, d.month, d.day).subtract(Duration(days: diff));
  }

  /// Valida solapes y minutos semanales con las tareas ya existentes
  Future<bool> _validarDisponibilidad(
    DateTime inicio,
    DateTime fin,
    int duracionMinutos,
  ) async {
    final conjunto = _conjuntoSeleccionado;
    if (conjunto == null || _operariosSeleccionadosIds.isEmpty) {
      return true;
    }

    try {
      final tareasMes = await _cronogramaApi.listarPorConjuntoYMes(
        nit: conjunto.nit,
        anio: inicio.year,
        mes: inicio.month,
      );

      // 1) Validar solapes por operario
      for (final t in tareasMes) {
        final coincideOperario = t.operariosIds.any(
          (idOp) => _operariosSeleccionadosIds.contains(idOp),
        );
        if (!coincideOperario) continue;

        if (_intervalosSeSolapan(inicio, fin, t.fechaInicio, t.fechaFin)) {
          final opIdsSeleccionadosSet = _operariosSeleccionadosIds.toSet();
          final opNombresChoque = <String>[];

          for (int i = 0; i < t.operariosIds.length; i++) {
            final idOp = t.operariosIds[i];
            if (opIdsSeleccionadosSet.contains(idOp)) {
              if (i < t.operariosNombres.length &&
                  t.operariosNombres[i].isNotEmpty) {
                opNombresChoque.add(t.operariosNombres[i]);
              } else {
                opNombresChoque.add('Operario $idOp');
              }
            }
          }

          final textoOperarios = opNombresChoque.isEmpty
              ? 'operario(s) seleccionado(s)'
              : opNombresChoque.join(', ');

          await showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Solape de agenda'),
              content: Text(
                'La tarea se solapa con otra tarea existente para $textoOperarios.\n\n'
                'Tarea existente: "${t.descripcion}"\n'
                'Horario: ${t.fechaInicio} - ${t.fechaFin}',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Aceptar'),
                ),
              ],
            ),
          );
          return false;
        }
      }

      // 2) Validar minutos semanales por operario
      final inicioSemana = _inicioSemana(inicio);
      final finSemana = inicioSemana.add(const Duration(days: 6));
      final limiteMinutosSemana = _limiteMinSemana ?? (42 * 60);

      for (final opId in _operariosSeleccionadosIds) {
        int minutosSemana = 0;

        for (final t in tareasMes) {
          if (!t.operariosIds.contains(opId)) continue;

          final dentroSemana = _intervalosSeSolapan(
            inicioSemana,
            finSemana,
            t.fechaInicio,
            t.fechaFin,
          );
          if (!dentroSemana) continue;

          minutosSemana += t.duracionMinutos;
        }

        final minutosConNueva = minutosSemana + duracionMinutos;

        // Nombre operario
        String opNombre;
        final idx = _operarios.indexWhere(
          (u) => int.tryParse(u.cedula) == opId,
        );
        if (idx != -1) {
          opNombre = _operarios[idx].nombre;
        } else {
          opNombre = 'Operario $opId';
        }

        if (minutosConNueva > limiteMinutosSemana) {
          final hSemana = (minutosSemana / 60).toStringAsFixed(1);
          final hConNueva = (minutosConNueva / 60).toStringAsFixed(1);

          await showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Límite semanal superado'),
              content: Text(
                '$opNombre ya tiene asignadas $hSemana h en esta semana.\n\n'
                'Con esta tarea sumaría $hConNueva h, superando el límite de $_limiteMinSemana h.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Aceptar'),
                ),
              ],
            ),
          );
          return false;
        } else {
          final disponiblesMin = limiteMinutosSemana - minutosSemana;
          final disponiblesH = (disponiblesMin / 60).toStringAsFixed(1);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$opNombre tiene ${(minutosSemana / 60).toStringAsFixed(1)} h asignadas esta semana. '
                'Le quedan $disponiblesH h disponibles.',
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }

      return true;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo validar la disponibilidad: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
  }

  void _onSuccess() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Tarea creada correctamente'),
        backgroundColor: Colors.green,
      ),
    );
    Navigator.pop(context, true);
  }

  String _fmtDateTime(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day}/${d.month}/${d.year} $hh:$mm';
  }

  Future<bool?> _dialogSugerenciaHorario(DateTime ini, DateTime fin) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("No hay espacio en ese horario"),
        content: Text(
          "A esa hora no hay disponibilidad.\n\n"
          "Sugerencia: ${_fmtDateTime(ini)} → ${_fmtDateTime(fin)}",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Usar sugerencia"),
          ),
        ],
      ),
    );
  }

  Future<List<int>?> _dialogReemplazo(List<dynamic> reemplazables) async {
    final selected = <int>{};

    return showDialog<List<int>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: const Text("Reemplazar preventivas"),
              content: SizedBox(
                width: double.maxFinite,
                child: reemplazables.isEmpty
                    ? const Text("No hay preventivas reemplazables (P2 o P3).")
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: reemplazables.length,
                        itemBuilder: (_, i) {
                          final t = reemplazables[i] as Map<String, dynamic>;
                          final id = int.parse(t['id'].toString());
                          final desc = (t['descripcion'] ?? '').toString();
                          final ini = DateTime.parse(
                            t['fechaInicio'].toString(),
                          ).toLocal();
                          final fin = DateTime.parse(
                            t['fechaFin'].toString(),
                          ).toLocal();
                          final p = t['prioridad'] != null
                              ? int.tryParse(t['prioridad'].toString())
                              : null;

                          final checked = selected.contains(id);

                          return CheckboxListTile(
                            value: checked,
                            title: Text(desc.isEmpty ? 'Tarea $id' : desc),
                            subtitle: Text(
                              'ID: $id | ${_fmtDateTime(ini)} - ${_fmtDateTime(fin)}'
                              '${p != null ? " | P$p" : ""}',
                            ),
                            onChanged: (v) {
                              if (v == true) {
                                selected.add(id);
                              } else {
                                selected.remove(id);
                              }
                              setStateDialog(() {});
                            },
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text("Cancelar"),
                ),
                ElevatedButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.pop(ctx, selected.toList()),
                  child: const Text("Reemplazar y crear correctiva"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _guardarTarea() async {
    if (!_formKey.currentState!.validate()) return;

    final conjunto = _conjuntoSeleccionado;
    if (conjunto == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Seleccione un conjunto')));
      return;
    }

    if (fechaInicio == null || fechaFin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccione fecha de inicio y fin')),
      );
      return;
    }

    if (_horaInicio == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccione la hora de inicio')),
      );
      return;
    }

    // Por ahora correctiva de un día
    final mismoDia =
        fechaInicio!.year == fechaFin!.year &&
        fechaInicio!.month == fechaFin!.month &&
        fechaInicio!.day == fechaFin!.day;
    if (!mismoDia) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por ahora debe ser dentro de un solo día.'),
        ),
      );
      return;
    }

    if (_ubicacionSeleccionada == null || _elementoSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccione ubicación y elemento')),
      );
      return;
    }

    final duracionMin = int.tryParse(_duracionCtrl.text.trim());
    if (duracionMin == null || duracionMin <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Duración (minutos) inválida')),
      );
      return;
    }

    if (_operariosSeleccionadosIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccione al menos un operario')),
      );
      return;
    }

    final inicio = _combinarFechaYHora(fechaInicio!, _horaInicio!);
    final fin = inicio.add(Duration(minutes: duracionMin));

    if (_prioridad != 1) {
      final disponible = await _validarDisponibilidad(inicio, fin, duracionMin);
      if (!disponible) return;
    }

    setState(() => _guardando = true);

    try {
      final req = TareaRequest(
        descripcion: _descripcionCtrl.text.trim(),
        fechaInicio: inicio,
        fechaFin: fin,
        duracionMinutos: duracionMin,
        ubicacionId: _ubicacionSeleccionada!.id,
        elementoId: _elementoSeleccionado!.id,
        conjuntoId: conjunto.nit,
        supervisorId: _supervisorId,
        operariosIds: _operariosSeleccionadosIds,
        prioridad: _prioridad,
        tipo: "CORRECTIVA",
        observaciones: _observacionesCtrl.text.trim().isEmpty
            ? null
            : _observacionesCtrl.text.trim(),
      );

      final resp = await _tareaApi.crearTarea(req);

      // ✅ Caso “needsReplacement”
      if (resp['needsReplacement'] == true) {
        // 1) sugerencia de horario si viene
        if (resp['suggestedInicio'] != null && resp['suggestedFin'] != null) {
          final sugIni = DateTime.parse(
            resp['suggestedInicio'].toString(),
          ).toLocal();
          final sugFin = DateTime.parse(
            resp['suggestedFin'].toString(),
          ).toLocal();

          final usar = await _dialogSugerenciaHorario(sugIni, sugFin);
          if (usar == true) {
            final req2 = TareaRequest(
              descripcion: req.descripcion,
              fechaInicio: sugIni,
              fechaFin: sugFin,
              duracionMinutos: req.duracionMinutos,
              ubicacionId: req.ubicacionId,
              elementoId: req.elementoId,
              conjuntoId: req.conjuntoId,
              supervisorId: req.supervisorId,
              operariosIds: req.operariosIds,
              prioridad: req.prioridad,
              tipo: req.tipo,
              observaciones: req.observaciones,
            );

            final resp2 = await _tareaApi.crearTarea(req2);
            if (resp2['needsReplacement'] != true) {
              _onSuccess();
              return;
            }
          }
        }

        // 2) reemplazo: mostrar reemplazables
        final reemplazables = (resp['reemplazables'] as List?) ?? [];
        final ids = await _dialogReemplazo(reemplazables);

        if (ids != null && ids.isNotEmpty) {
          await _tareaApi.crearTareaConReemplazo(
            tarea: req,
            reemplazarIds: ids,
          );
          _onSuccess();
          return;
        }

        // Canceló
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Operación cancelada.')));
        return;
      }

      // ✅ Caso normal: creada
      _onSuccess();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al crear tarea: $e'),
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
            "Crear tarea correctiva",
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
          "Crear tarea correctiva",
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
              // 1. DÓNDE
              const Text(
                "1. Dónde se realizará",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),

              DropdownButtonFormField<String>(
                initialValue: _conjuntoSeleccionado?.nit,
                decoration: const InputDecoration(
                  labelText: "Conjunto",
                  border: OutlineInputBorder(),
                ),
                items: _conjuntos
                    .map(
                      (c) =>
                          DropdownMenuItem(value: c.nit, child: Text(c.nombre)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  final c = _conjuntos.firstWhere((x) => x.nit == value);
                  _refrescarDatosConjunto(c);
                },
                validator: (v) => v == null ? 'Seleccione un conjunto' : null,
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<int>(
                initialValue: _ubicacionSeleccionada?.id,
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
                initialValue: _elementoSeleccionado?.id,
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

              // 2. QUÉ
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
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Ingrese una descripción'
                    : null,
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<int>(
                value: _prioridad,
                decoration: const InputDecoration(
                  labelText: "Prioridad",
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 1, child: Text("1 - Alta")),
                  DropdownMenuItem(value: 2, child: Text("2 - Media")),
                  DropdownMenuItem(value: 3, child: Text("3 - Baja")),
                ],
                onChanged: (v) => setState(() => _prioridad = v ?? 2),
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

              InkWell(
                onTap: _seleccionarHoraInicio,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: "Hora de inicio",
                    border: OutlineInputBorder(),
                  ),
                  child: Text(
                    _horaInicio == null
                        ? "Seleccionar"
                        : _horaInicio!.format(context),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _duracionCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Duración estimada (minutos)",
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Ingrese duración en minutos';
                  }
                  final m = int.tryParse(v.trim());
                  if (m == null || m <= 0) return 'Minutos inválidos';
                  return null;
                },
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

              // 3. QUIÉNES
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
                initialValue: _supervisorId,
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
                onChanged: (value) => setState(() => _supervisorId = value),
              ),
              const SizedBox(height: 24),

              // 4. MAQUINARIA
              const Text(
                "4. Con qué maquinaria",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),

              InkWell(
                onTap: _mostrarSelectorMaquinaria,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: "Maquinaria a prestar (opcional)",
                    border: OutlineInputBorder(),
                  ),
                  child: Text(
                    _maquinariaSeleccionadaIds.isEmpty
                        ? "Sin maquinaria asociada"
                        : "${_maquinariaSeleccionadaIds.length} máquina(s) seleccionada(s)",
                  ),
                ),
              ),
              const SizedBox(height: 32),

              ElevatedButton.icon(
                onPressed: _guardando ? null : _guardarTarea,
                icon: _guardando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(_guardando ? "Guardando..." : "Guardar tarea"),
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
