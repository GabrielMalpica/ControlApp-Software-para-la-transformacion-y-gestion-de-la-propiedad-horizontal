// lib/pages/cronograma_preventivas_borrador_page.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/cronograma_api.dart';
import '../model/tarea_model.dart';
import '../service/theme.dart';

class CronogramaPreventivasBorradorPage extends StatefulWidget {
  final String nit;
  final int anio;
  final int mes;

  const CronogramaPreventivasBorradorPage({
    super.key,
    required this.nit,
    required this.anio,
    required this.mes,
  });

  @override
  State<CronogramaPreventivasBorradorPage> createState() =>
      _CronogramaPreventivasBorradorPageState();
}

class _CronogramaPreventivasBorradorPageState
    extends State<CronogramaPreventivasBorradorPage> {
  final _cronogramaApi = CronogramaApi();

  bool _loading = true;
  bool _publicando = false;
  String? _error;

  late int _daysInMonth;
  late DateTime _inicioMes;

  /// Todas las tareas preventivas en borrador de ese mes
  List<TareaModel> _tareasMes = [];

  /// Resumen por día
  List<_DiaResumen> _diasResumen = [];

  @override
  void initState() {
    super.initState();
    _initMes();
    _cargarDatos();
  }

  void _initMes() {
    _inicioMes = DateTime(widget.anio, widget.mes, 1);
    _daysInMonth = DateUtils.getDaysInMonth(widget.anio, widget.mes);
  }

  Future<void> _cargarDatos() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final lista = await _cronogramaApi.cronogramaMensual(
        nit: widget.nit,
        anio: widget.anio,
        mes: widget.mes,
        borrador: true,
        tipo: 'PREVENTIVA',
      );

      // Confiamos en que el backend ya filtra por tipo
      setState(() {
        _tareasMes = lista;
        _recalcularResumenDias();
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  bool get _hayTareas => _tareasMes.isNotEmpty;

  Future<void> _publicarCronograma() async {
    if (!_hayTareas || _publicando) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Publicar cronograma'),
        content: const Text(
          '¿Seguro que quieres publicar el cronograma de tareas preventivas '
          'para este mes? Ya no se podrán editar como borrador.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Publicar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() {
      _publicando = true;
    });

    try {
      final res = await _cronogramaApi.publicarCronogramaPreventivas(
        nit: widget.nit,
        anio: widget.anio,
        mes: widget.mes,
        consolidar: false,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cronograma publicado. Publicadas: ${res['publicadas'] ?? res['publicadasSimples'] ?? '-'}',
          ),
        ),
      );

      await _cargarDatos();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error publicando cronograma: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _publicando = false;
        });
      }
    }
  }

  void _recalcularResumenDias() {
    _diasResumen = [];
    for (int dia = 1; dia <= _daysInMonth; dia++) {
      final tareasDia = _tareasMes.where((t) {
        final f = t.fechaInicio;
        return f.year == widget.anio && f.month == widget.mes && f.day == dia;
      }).toList();

      _diasResumen.add(
        _DiaResumen(
          dia: dia,
          total: tareasDia.length,
          preventivas: tareasDia.length,
        ),
      );
    }
  }

  _DiaResumen _getResumenDia(int dia) {
    return _diasResumen.firstWhere(
      (d) => d.dia == dia,
      orElse: () => _DiaResumen(dia: dia, total: 0, preventivas: 0),
    );
  }

  List<TareaModel> _tareasDeDia(int dia) {
    return _tareasMes.where((t) {
      final f = t.fechaInicio;
      return f.year == widget.anio && f.month == widget.mes && f.day == dia;
    }).toList();
  }

  // ===== bloques por hora =====
  List<_BloqueHora> _generarBloquesDia(DateTime fecha) {
    const int horaInicioJornada = 8;
    const int horaFinJornada = 16;
    const bool excluirAlmuerzo = true;
    const int horaAlmuerzoInicio = 13;
    const int horaAlmuerzoFin = 14;

    final List<_BloqueHora> bloques = [];

    for (int h = horaInicioJornada; h < horaFinJornada; h++) {
      if (excluirAlmuerzo && h >= horaAlmuerzoInicio && h < horaAlmuerzoFin) {
        continue;
      }

      final inicio = DateTime(fecha.year, fecha.month, fecha.day, h, 0);
      final fin = inicio.add(const Duration(hours: 1));

      final tareasBloque = _tareasMes.where((t) {
        return t.fechaInicio.isBefore(fin) && t.fechaFin.isAfter(inicio);
      }).toList();

      bloques.add(_BloqueHora(inicio: inicio, fin: fin, tareas: tareasBloque));
    }

    return bloques;
  }

  Future<void> _abrirDia(int dia) async {
    final fechaBase = DateTime(widget.anio, widget.mes, dia);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final mediaQuery = MediaQuery.of(ctx);
        final alto = mediaQuery.size.height * 0.8;
        final bloques = _generarBloquesDia(fechaBase);

        _BloqueHora? bloqueSeleccionado;

        return StatefulBuilder(
          builder: (context, setModalState) {
            void seleccionarBloque(_BloqueHora b) {
              setModalState(() {
                bloqueSeleccionado = b;
              });
            }

            return SizedBox(
              height: alto,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Tareas borrador - $dia ${DateFormat.MMMM('es').format(fechaBase)}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: Row(
                      children: [
                        // Bloques horarios
                        Expanded(
                          flex: 2,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(8),
                            itemCount: bloques.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 4),
                            itemBuilder: (context, index) {
                              final b = bloques[index];
                              final horaIni = TimeOfDay.fromDateTime(
                                b.inicio,
                              ).format(ctx);
                              final horaFin = TimeOfDay.fromDateTime(
                                b.fin,
                              ).format(ctx);
                              final count = b.tareas.length;

                              final seleccionado =
                                  bloqueSeleccionado == b; // misma ref

                              return Card(
                                color: seleccionado
                                    ? AppTheme.primary.withOpacity(0.1)
                                    : Colors.white,
                                child: ListTile(
                                  title: Text('$horaIni - $horaFin'),
                                  subtitle: Text(
                                    '$count ${count == 1 ? 'tarea' : 'tareas'}',
                                  ),
                                  onTap: () => seleccionarBloque(b),
                                ),
                              );
                            },
                          ),
                        ),

                        // Tareas del bloque seleccionado
                        Expanded(
                          flex: 3,
                          child: bloqueSeleccionado == null
                              ? const Center(
                                  child: Text(
                                    'Selecciona un bloque para ver las tareas.',
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.all(8),
                                  itemCount: bloqueSeleccionado!.tareas.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 8),
                                  itemBuilder: (context, index) {
                                    final t = bloqueSeleccionado!.tareas[index];
                                    return _buildTareaTile(t, ctx);
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    setState(() {
      _recalcularResumenDias();
    });
  }

  /// Tile de tarea dentro de un bloque (resumen)
  Widget _buildTareaTile(TareaModel t, BuildContext ctx) {
    final horaIni = TimeOfDay.fromDateTime(t.fechaInicio).format(ctx);
    final horaFin = TimeOfDay.fromDateTime(t.fechaFin).format(ctx);
    final dur = t.duracionHoras;

    final operarios = t.operariosNombres.isEmpty
        ? 'Sin asignar'
        : t.operariosNombres.join(', ');

    final supervisor =
        t.supervisorNombre ??
        (t.supervisorId != null ? 'ID ${t.supervisorId}' : 'Sin supervisor');

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 2,
      child: ListTile(
        title: Text(
          t.descripcion,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '⏱ $dur h  •  $horaIni - $horaFin',
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              '🧑‍💼 Supervisor: $supervisor',
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              '👷 Operarios: $operarios',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        onTap: () => _mostrarDetalleTarea(t, ctx),
      ),
    );
  }

  /// Modal con TODA la información de la tarea
  void _mostrarDetalleTarea(TareaModel t, BuildContext ctx) {
    final fechaIniStr = DateFormat(
      'dd/MM/yyyy HH:mm',
      'es',
    ).format(t.fechaInicio);
    final fechaFinStr = DateFormat('dd/MM/yyyy HH:mm', 'es').format(t.fechaFin);

    final evidenciasTxt = (t.evidencias ?? []).isEmpty
        ? 'Sin evidencias'
        : t.evidencias!.join('\n');

    final insumosCount = (t.insumosUsados ?? []).length;

    final operarios = t.operariosNombres.isEmpty
        ? 'Sin asignar'
        : t.operariosNombres.join(', ');

    final conjuntoLabel = t.conjuntoNombre ?? t.conjuntoId ?? '—';
    final ubicacionLabel =
        t.ubicacionNombre ?? 'ID ${t.ubicacionId.toString()}';
    final elementoLabel = t.elementoNombre ?? 'ID ${t.elementoId.toString()}';

    final supervisorLabel =
        t.supervisorNombre ??
        (t.supervisorId != null ? 'ID ${t.supervisorId}' : '—');

    final maquinariaLista = t.maquinariaPlan ?? const [];
    final maquinariaTxt = maquinariaLista.isEmpty
        ? 'Sin maquinaria planificada'
        : maquinariaLista
              .map((m) {
                String base = 'ID ${m.maquinariaId ?? '-'}';
                if (m.tipo != null && m.tipo!.trim().isNotEmpty) {
                  base += ' – ${m.tipo}';
                }
                if (m.cantidad != null) {
                  base += ' (${m.cantidad} h / unidades)';
                }
                return base;
              })
              .join('\n');

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Material(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Detalle de la tarea',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _infoRow('ID', t.id.toString()),
                          _infoRow('Descripción', t.descripcion),
                          _infoRow('Estado', t.estado ?? '—'),
                          _infoRow('Tipo', t.tipo ?? '—'),
                          _infoRow('Frecuencia', t.frecuencia ?? '—'),
                          const SizedBox(height: 8),
                          _infoRow('Fecha inicio', fechaIniStr),
                          _infoRow('Fecha fin', fechaFinStr),
                          _infoRow('Duración (horas)', '${t.duracionHoras}'),
                          const SizedBox(height: 8),
                          _infoRow('Conjunto', conjuntoLabel),
                          _infoRow('Ubicación', ubicacionLabel),
                          _infoRow('Elemento', elementoLabel),
                          _infoRow('Supervisor', supervisorLabel),
                          const SizedBox(height: 8),
                          _infoRow('Operarios', operarios),
                          const SizedBox(height: 8),
                          _infoRow('Maquinaria planificada', maquinariaTxt),
                          const SizedBox(height: 8),
                          _infoRow('Observaciones', t.observaciones ?? '—'),
                          _infoRow(
                            'Obs. rechazo',
                            t.observacionesRechazo ?? '—',
                          ),
                          const SizedBox(height: 8),
                          _infoRow('Evidencias', evidenciasTxt),
                          _infoRow(
                            'Insumos usados',
                            insumosCount == 0
                                ? 'Sin insumos registrados'
                                : '$insumosCount ítem(s)',
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Future<void> _moverTareaADia(TareaModel t, int nuevoDia) async {
    final antiguaInicio = t.fechaInicio;
    final antiguaFin = t.fechaFin;

    final duracionHoras =
        ((antiguaFin.millisecondsSinceEpoch -
                    antiguaInicio.millisecondsSinceEpoch) /
                3_600_000)
            .round();

    final nuevaFechaInicio = DateTime(
      widget.anio,
      widget.mes,
      nuevoDia,
      antiguaInicio.hour,
      antiguaInicio.minute,
    );

    final nuevaFechaFin = nuevaFechaInicio.add(Duration(hours: duracionHoras));

    setState(() {
      final idx = _tareasMes.indexWhere((x) => x.id == t.id);
      if (idx != -1) {
        _tareasMes[idx] = t.copyWith(
          fechaInicio: nuevaFechaInicio,
          fechaFin: nuevaFechaFin,
          duracionHoras: duracionHoras,
        );
        _recalcularResumenDias();
      }
    });

    // TODO: endpoint de reprogramación cuando lo tengas
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.primary;
    final mesNombre = DateFormat.MMMM('es').format(_inicioMes).toUpperCase();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: primary,
        title: const Text(
          'Cronograma preventivas (borrador)',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(onPressed: _cargarDatos, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 40,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Error cargando cronograma:\n$_error',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _cargarDatos,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          : _buildCalendario(mesNombre),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildCalendario(String mesNombre) {
    final now = DateTime.now();
    final esMismoMes = now.year == widget.anio && now.month == widget.mes;

    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth < 600
        ? 7
        : screenWidth < 1000
        ? 10
        : 14;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Text(
                  '$mesNombre ${widget.anio}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                _buildLegend(Colors.grey.shade200, 'Sin tareas'),
                const SizedBox(width: 8),
                _buildLegend(
                  AppTheme.primary.withOpacity(0.2),
                  'Con preventivas',
                ),
                const SizedBox(width: 8),
                _buildLegend(Colors.blue.shade100, 'Hoy'),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              itemCount: _daysInMonth,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
                childAspectRatio: 1,
              ),
              itemBuilder: (context, index) {
                final dia = index + 1;
                final resumen = _getResumenDia(dia);
                final isToday = esMismoMes && now.day == dia;

                return DragTarget<TareaModel>(
                  onWillAccept: (t) => t != null,
                  onAccept: (t) => _moverTareaADia(t, dia),
                  builder: (context, candidateData, rejectedData) {
                    final hasCandidate = candidateData.isNotEmpty;

                    Color baseColor;
                    if (resumen.preventivas > 0) {
                      baseColor = AppTheme.primary.withOpacity(0.15);
                    } else {
                      baseColor = Colors.grey.shade100;
                    }

                    if (isToday) {
                      baseColor = Colors.blue.shade100;
                    }
                    if (hasCandidate) {
                      baseColor = Colors.greenAccent.withOpacity(0.4);
                    }

                    return GestureDetector(
                      onTap: () => _abrirDia(dia),
                      child: Container(
                        decoration: BoxDecoration(
                          color: baseColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: resumen.preventivas > 0
                                ? AppTheme.primary
                                : Colors.grey.shade300,
                            width: 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              dia.toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            if (resumen.preventivas > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '${resumen.preventivas} prev.',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final puedePublicar = _hayTareas && !_loading && !_publicando;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: puedePublicar ? _publicarCronograma : null,
            icon: _publicando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.publish),
            label: Text(
              _publicando
                  ? 'Publicando...'
                  : _hayTareas
                  ? 'Publicar cronograma'
                  : 'No hay tareas para publicar',
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegend(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}

class _DiaResumen {
  final int dia;
  final int total;
  final int preventivas;

  _DiaResumen({
    required this.dia,
    required this.total,
    required this.preventivas,
  });
}

class _BloqueHora {
  final DateTime inicio;
  final DateTime fin;
  final List<TareaModel> tareas;

  _BloqueHora({required this.inicio, required this.fin, required this.tareas});
}
