import 'package:flutter/material.dart';
import 'package:flutter_application_1/model/usuario_model.dart';

import '../api/tarea_api.dart';
import '../api/gerente_api.dart';
import '../api/empresa_api.dart';
import '../api/cronograma_api.dart';

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
  final CronogramaApi _cronogramaApi = CronogramaApi();

  // Controllers
  final _descripcionCtrl = TextEditingController();
  final _duracionCtrl = TextEditingController(); // minutos
  final _observacionesCtrl = TextEditingController();

  // Fechas y horas
  DateTime? fechaInicio; // fecha
  DateTime? fechaFin; // fecha
  TimeOfDay? _horaInicio;

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

  // Operarios
  List<Usuario> _operarios = [];
  final List<String> _operariosSeleccionadosIds = [];

  // Supervisores
  List<Usuario> _supervisores = [];
  String? _supervisorId;

  // Maquinaria
  List<MaquinariaResponse> _maquinariaDisponible = [];
  final List<int> _maquinariaSeleccionadaIds = [];

  int? _limiteMinSemana;

  int _prioridad = 2;

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

      if (seleccionado != null) _refrescarDatosConjunto(seleccionado);
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
    });
  }

  Future<void> _seleccionarFechaInicio() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: fechaInicio ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => fechaInicio = picked);
  }

  Future<void> _seleccionarFechaFin() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: fechaFin ?? (fechaInicio ?? DateTime.now()),
      firstDate: fechaInicio ?? DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => fechaFin = picked);
  }

  Future<void> _seleccionarHoraInicio() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _horaInicio ?? const TimeOfDay(hour: 8, minute: 0),
    );
    if (picked != null) setState(() => _horaInicio = picked);
  }

  Future<void> _mostrarSelectorOperarios() async {
    if (_operarios.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay operarios en este conjunto')),
      );
      return;
    }

    final seleccionTemp = Set<String>.from(_operariosSeleccionadosIds);

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
                    final opId = op.cedula.trim();
                    if (opId.isEmpty) return const SizedBox.shrink();
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

  DateTime _inicioSemana(DateTime d) {
    final diff = d.weekday - DateTime.monday;
    return DateTime(d.year, d.month, d.day).subtract(Duration(days: diff));
  }

  // ✅ SOLO valida límite semanal. NO valida solapes (eso lo hace backend).
  Future<bool> _validarLimiteSemanal(
    DateTime inicio,
    int duracionMinutos,
  ) async {
    final conjunto = _conjuntoSeleccionado;
    if (conjunto == null || _operariosSeleccionadosIds.isEmpty) return true;

    try {
      final tareasMes = await _cronogramaApi.listarPorConjuntoYMes(
        nit: conjunto.nit,
        anio: inicio.year,
        mes: inicio.month,
      );

      final inicioSemana = _inicioSemana(inicio);
      final finSemana = inicioSemana.add(const Duration(days: 6));
      final limiteMinutosSemana = _limiteMinSemana ?? (42 * 60);

      bool solapaSemana(
        DateTime aIni,
        DateTime aFin,
        DateTime bIni,
        DateTime bFin,
      ) {
        return aIni.isBefore(bFin) && bIni.isBefore(aFin);
      }

      for (final opId in _operariosSeleccionadosIds) {
        int minutosSemana = 0;

        for (final t in tareasMes) {
          if (!t.operariosIds.contains(opId)) continue;

          final dentroSemana = solapaSemana(
            inicioSemana,
            finSemana,
            t.fechaInicio,
            t.fechaFin,
          );
          if (!dentroSemana) continue;

          minutosSemana += t.duracionMinutos;
        }

        final minutosConNueva = minutosSemana + duracionMinutos;

        if (minutosConNueva > limiteMinutosSemana) {
          await showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Límite semanal superado'),
              content: Text(
                'El operario $opId supera el límite semanal.\n\n'
                'Actual: ${(minutosSemana / 60).toStringAsFixed(1)} h\n'
                'Con nueva: ${(minutosConNueva / 60).toStringAsFixed(1)} h\n'
                'Límite: ${(limiteMinutosSemana / 60).toStringAsFixed(1)} h',
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

      return true;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo validar límite semanal: $e'),
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

  bool _backendOk(dynamic resp) {
    if (resp is Map) {
      // tu backend a veces responde {ok:true,...} y a veces devuelve la tarea creada (con id)
      if (resp['ok'] == true) return true;
      if (resp['id'] != null) return true;
      if (resp['createdIds'] != null) return true;
    }
    return false;
  }

  Future<void> _mostrarErrorBackend(dynamic resp) async {
    String msg = 'No se pudo crear la tarea.';
    String? reason;

    DateTime? sugIni;
    DateTime? sugFin;

    if (resp is Map) {
      msg = (resp['message'] ?? resp['error'] ?? msg).toString();
      reason = resp['reason']?.toString();

      if (resp['suggestedInicio'] != null && resp['suggestedFin'] != null) {
        sugIni = DateTime.parse(resp['suggestedInicio'].toString()).toLocal();
        sugFin = DateTime.parse(resp['suggestedFin'].toString()).toLocal();
      }
    } else {
      msg = resp.toString();
    }

    // Texto extra bonito según reason
    String extra = '';
    switch ((reason ?? '').toUpperCase()) {
      case 'INICIO_ANTES_APERTURA':
        extra = 'La hora seleccionada está antes de la apertura del conjunto.';
        break;
      case 'INICIO_EN_DESCANSO':
        extra = 'La hora seleccionada cae dentro del descanso del conjunto.';
        break;
      case 'FUERA_DE_JORNADA':
        extra = 'La tarea se sale del horario de operación del conjunto.';
        break;
      case 'SIN_HORARIO_DIA':
        extra = 'Ese día no tiene horario configurado para el conjunto.';
        break;
      case 'HAY_SOLAPE_CON_TAREAS_EXISTENTES':
        extra = 'Se cruza con otras tareas ya programadas.';
        break;
    }

    // Si hay sugerencia, ofrecer usarla
    if (sugIni != null && sugFin != null) {
      final usar = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('No se puede crear en ese horario'),
          content: Text(
            '${extra.isEmpty ? '' : '$extra\n\n'}'
            '$msg\n\n'
            'Sugerencia: ${_fmtDateTime(sugIni!)} → ${_fmtDateTime(sugFin!)}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cerrar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Usar sugerencia'),
            ),
          ],
        ),
      );

      if (usar == true) {
        // ✅ aplica sugerencia en el form para que el usuario la vea
        setState(() {
          fechaInicio = DateTime(sugIni!.year, sugIni.month, sugIni.day);
          fechaFin = DateTime(sugFin!.year, sugFin.month, sugFin.day);
          _horaInicio = TimeOfDay(hour: sugIni.hour, minute: sugIni.minute);
        });

        // opcional: ajustar duración si sugFin cambió
        final nuevaDur = sugFin.difference(sugIni).inMinutes;
        if (nuevaDur > 0) _duracionCtrl.text = nuevaDur.toString();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Sugerencia aplicada al formulario.')),
        );
      }

      return;
    }

    // Sin sugerencia: solo alert
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('No se pudo crear la tarea'),
        content: Text('${extra.isEmpty ? '' : '$extra\n\n'}$msg'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
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
              title: const Text("Reemplazar tareas (P2/P3)"),
              content: SizedBox(
                width: double.maxFinite,
                child: reemplazables.isEmpty
                    ? const Text("No hay tareas reemplazables (P2 o P3).")
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: reemplazables.length,
                        itemBuilder: (_, i) {
                          final t = reemplazables[i] as Map<String, dynamic>;
                          final id = int.parse(t['id'].toString());
                          final desc = (t['descripcion'] ?? '').toString();
                          final tipo = (t['tipo'] ?? '').toString();
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
                              'ID: $id | $tipo | ${_fmtDateTime(ini)} - ${_fmtDateTime(fin)}'
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
                  child: const Text("Reemplazar y crear correctiva P1"),
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

    // ✅ Solo límite semanal (no solapes)
    final okSemana = await _validarLimiteSemanal(inicio, duracionMin);
    if (!okSemana) return;

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
        maquinariaIds: _maquinariaSeleccionadaIds,
      );

      final resp = await _tareaApi.crearTarea(req);

      // ✅ 1) Caso reemplazo (correctiva P1)
      if (resp is Map && resp['needsReplacement'] == true) {
        // 1) sugerencia de horario (si la hay)
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

            // ✅ si ahora sí fue OK, salimos
            if (_backendOk(resp2)) {
              _onSuccess();
              return;
            }

            // si sigue pidiendo reemplazo o trae error, seguimos al flujo normal
            // (no hacemos return aquí)
          }
        }

        // 2) reemplazo manual
        final reemplazables = (resp['reemplazables'] as List?) ?? [];
        final ids = await _dialogReemplazo(reemplazables);

        if (ids != null && ids.isNotEmpty) {
          final resp3 = await _tareaApi.crearTareaConReemplazo(
            tarea: req,
            reemplazarIds: ids,
          );

          if (_backendOk(resp3)) {
            _onSuccess();
            return;
          }

          await _mostrarErrorBackend(resp3);
          return;
        }

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Operación cancelada.')));
        return;
      }

      // ✅ 2) Caso backend devuelve ok:false (como INICIO_ANTES_APERTURA)
      if (resp is Map && resp['ok'] == false) {
        await _mostrarErrorBackend(resp);
        return;
      }

      // ✅ 3) Caso normal: si es OK de verdad
      if (_backendOk(resp)) {
        _onSuccess();
        return;
      }

      // ✅ 4) Fallback: respuesta rara -> mostrar
      await _mostrarErrorBackend(resp);
      return;
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
                  if (v == null || v.trim().isEmpty)
                    return 'Ingrese duración en minutos';
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

              DropdownButtonFormField<String>(
                initialValue: _supervisorId,
                decoration: const InputDecoration(
                  labelText: "Supervisor (opcional)",
                  border: OutlineInputBorder(),
                ),
                items: _supervisores
                    .map((s) {
                      final id = s.cedula.trim();
                      if (id.isEmpty) return null;
                      return DropdownMenuItem(value: id, child: Text(s.nombre));
                    })
                    .whereType<DropdownMenuItem<String>>()
                    .toList(),
                onChanged: (value) => setState(() => _supervisorId = value),
              ),

              const SizedBox(height: 24),

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
