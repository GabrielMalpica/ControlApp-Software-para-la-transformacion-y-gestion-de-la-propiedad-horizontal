// lib/pages/cronograma_preventivas_borrador_page.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/cronograma_api.dart';
import '../model/tarea_model.dart';
import '../service/theme.dart';

enum _VistaCronograma { mensual, semanal }

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

  // ✅ ahora mes/año son mutables (para navegación)
  late int _anioActual;
  late int _mesActual; // 1..12

  late int _daysInMonth;
  late DateTime _inicioMes;

  /// Todas las tareas preventivas en borrador de ese mes
  List<TareaModel> _tareasMes = [];

  /// Resumen por día (mensual)
  List<_DiaResumen> _diasResumen = [];

  // Vista y semana seleccionada
  _VistaCronograma _vista = _VistaCronograma.mensual;
  late DateTime _semanaBase; // fecha dentro de la semana seleccionada

  @override
  void initState() {
    super.initState();
    _anioActual = widget.anio;
    _mesActual = widget.mes;

    _initMes();
    _semanaBase = DateTime(_anioActual, _mesActual, 1);
    _cargarDatos();
  }

  void _initMes() {
    _inicioMes = DateTime(_anioActual, _mesActual, 1);
    _daysInMonth = DateUtils.getDaysInMonth(_anioActual, _mesActual);
  }

  bool _isSameLocalDay(DateTime a, DateTime b) {
    final al = a.toLocal();
    final bl = b.toLocal();
    return al.year == bl.year && al.month == bl.month && al.day == bl.day;
  }

  bool _isInThisMonth(DateTime d) {
    final dl = d.toLocal();
    return dl.year == _anioActual && dl.month == _mesActual;
  }

  DateTime _startOfWeekMonday(DateTime d) {
    final dd = DateTime(d.year, d.month, d.day);
    final diff = dd.weekday - DateTime.monday; // monday=1
    return dd.subtract(Duration(days: diff));
  }

  DateTime _endOfWeekSunday(DateTime d) {
    final start = _startOfWeekMonday(d);
    return start.add(const Duration(days: 6));
  }

  List<TareaModel> _tareasSemana(DateTime semanaBase) {
    final start = _startOfWeekMonday(semanaBase);
    final end = start.add(const Duration(days: 7)); // exclusivo
    return _tareasMes.where((t) {
      final dt = t.fechaInicio.toLocal();
      return !dt.isBefore(start) && dt.isBefore(end);
    }).toList();
  }

  Future<void> _cambiarMes(int delta) async {
    int nuevoMes = _mesActual + delta;
    int nuevoAnio = _anioActual;

    if (nuevoMes == 13) {
      nuevoMes = 1;
      nuevoAnio++;
    } else if (nuevoMes == 0) {
      nuevoMes = 12;
      nuevoAnio--;
    }

    setState(() {
      _anioActual = nuevoAnio;
      _mesActual = nuevoMes;
      _initMes();
      _semanaBase = DateTime(_anioActual, _mesActual, 1);
    });

    await _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final lista = await _cronogramaApi.cronogramaMensual(
        nit: widget.nit,
        anio: _anioActual,
        mes: _mesActual,
        borrador: true,
        tipo: 'PREVENTIVA',
      );

      final filtradas = lista
          .where((t) => _isInThisMonth(t.fechaInicio))
          .toList();

      setState(() {
        _tareasMes = filtradas;
        _recalcularResumenDias();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
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

    setState(() => _publicando = true);

    try {
      final res = await _cronogramaApi.publicarCronogramaPreventivas(
        nit: widget.nit,
        anio: _anioActual,
        mes: _mesActual,
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
      if (mounted) setState(() => _publicando = false);
    }
  }

  void _recalcularResumenDias() {
    _diasResumen = [];
    for (int dia = 1; dia <= _daysInMonth; dia++) {
      final fechaDia = DateTime(_anioActual, _mesActual, dia);

      final tareasDia = _tareasMes.where((t) {
        return _isSameLocalDay(t.fechaInicio, fechaDia);
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

  // ===== bloques por hora (modal diario, se mantiene) =====
  List<_BloqueHora> _generarBloquesDia(DateTime fecha) {
    const int horaInicioJornada = 8;
    const int horaFinJornada = 16;
    const bool excluirAlmuerzo = true;
    const int horaAlmuerzoInicio = 13;
    const int horaAlmuerzoFin = 14;

    final fechaLocal = fecha.toLocal();
    final List<_BloqueHora> bloques = [];

    for (int h = horaInicioJornada; h < horaFinJornada; h++) {
      if (excluirAlmuerzo && h >= horaAlmuerzoInicio && h < horaAlmuerzoFin) {
        continue;
      }

      final inicio = DateTime(
        fechaLocal.year,
        fechaLocal.month,
        fechaLocal.day,
        h,
        0,
      );
      final fin = inicio.add(const Duration(hours: 1));

      final tareasDelDia = _tareasMes
          .where((t) => _isSameLocalDay(t.fechaInicio, fechaLocal))
          .toList();

      final tareasBloque = tareasDelDia.where((t) {
        final i = t.fechaInicio.toLocal();
        final f = t.fechaFin.toLocal();
        return i.isBefore(fin) && f.isAfter(inicio);
      }).toList();

      bloques.add(_BloqueHora(inicio: inicio, fin: fin, tareas: tareasBloque));
    }

    return bloques;
  }

  Future<void> _abrirDia(int dia) async {
    final fechaBase = DateTime(_anioActual, _mesActual, dia);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final alto = MediaQuery.of(ctx).size.height * 0.8;
        final bloques = _generarBloquesDia(fechaBase);

        _BloqueHora? bloqueSeleccionado;

        return StatefulBuilder(
          builder: (context, setModalState) {
            void seleccionarBloque(_BloqueHora b) {
              setModalState(() => bloqueSeleccionado = b);
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
                              final seleccionado = bloqueSeleccionado == b;

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

    setState(() => _recalcularResumenDias());
  }

  Widget _buildTareaTile(TareaModel t, BuildContext ctx) {
    final iniLocal = t.fechaInicio.toLocal();
    final finLocal = t.fechaFin.toLocal();

    final horaIni = TimeOfDay.fromDateTime(iniLocal).format(ctx);
    final horaFin = TimeOfDay.fromDateTime(finLocal).format(ctx);

    final durMin = t.duracionMinutos;
    final durH = durMin / 60.0;

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
              '⏱ $durMin min (${durH.toStringAsFixed(1)} h)  •  $horaIni - $horaFin',
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

  void _mostrarDetalleTarea(TareaModel t, BuildContext ctx) {
    final iniLocal = t.fechaInicio.toLocal();
    final finLocal = t.fechaFin.toLocal();

    final fechaIniStr = DateFormat('dd/MM/yyyy HH:mm', 'es').format(iniLocal);
    final fechaFinStr = DateFormat('dd/MM/yyyy HH:mm', 'es').format(finLocal);

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

    final durMin = t.duracionMinutos;
    final durH = durMin / 60.0;

    final maquinariaLista = t.maquinariaPlan ?? const [];
    final maquinariaTxt = maquinariaLista.isEmpty
        ? 'Sin maquinaria planificada'
        : maquinariaLista
              .map((m) {
                String base = 'ID ${m.maquinariaId ?? '-'}';
                if (m.tipo != null && m.tipo!.trim().isNotEmpty) {
                  base += ' – ${m.tipo}';
                }
                if (m.cantidad != null) base += ' (${m.cantidad} h / unidades)';
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
                          _infoRow(
                            'Duración',
                            '$durMin min (${durH.toStringAsFixed(1)} h)',
                          ),
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

  // ✅ mover tarea: trabaja en MINUTOS (no horas)
  Future<void> _moverTareaADia(TareaModel t, int nuevoDia) async {
    final iniLocal = t.fechaInicio.toLocal();
    final finLocal = t.fechaFin.toLocal();

    final durMin =
        ((finLocal.millisecondsSinceEpoch - iniLocal.millisecondsSinceEpoch) /
                60000)
            .round();

    final nuevaFechaInicio = DateTime(
      _anioActual,
      _mesActual,
      nuevoDia,
      iniLocal.hour,
      iniLocal.minute,
    );

    final nuevaFechaFin = nuevaFechaInicio.add(Duration(minutes: durMin));

    setState(() {
      final idx = _tareasMes.indexWhere((x) => x.id == t.id);
      if (idx != -1) {
        _tareasMes[idx] = t.copyWith(
          fechaInicio: nuevaFechaInicio,
          fechaFin: nuevaFechaFin,
          duracionMinutos: durMin,
        );
        _recalcularResumenDias();
      }
    });

    // TODO: endpoint de reprogramación cuando lo tengas
  }

  // ================= UI =================

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
          ? _buildError()
          : _buildContenido(mesNombre),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 40),
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
    );
  }

  Widget _buildContenido(String mesNombre) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _buildTopBar(mesNombre),
          const SizedBox(height: 10),
          Expanded(
            child: _vista == _VistaCronograma.mensual
                ? _buildCalendarioMensualSemanas()
                : _buildAgendaSemanal(),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(String mesNombre) {
    final start = _startOfWeekMonday(_semanaBase);
    final end = _endOfWeekSunday(_semanaBase);
    final rangoSemana =
        "${DateFormat('dd MMM', 'es').format(start)} - ${DateFormat('dd MMM', 'es').format(end)}";

    return Row(
      children: [
        SegmentedButton<_VistaCronograma>(
          segments: const [
            ButtonSegment(
              value: _VistaCronograma.mensual,
              label: Text('Mensual'),
              icon: Icon(Icons.calendar_month),
            ),
            ButtonSegment(
              value: _VistaCronograma.semanal,
              label: Text('Semanal'),
              icon: Icon(Icons.view_week),
            ),
          ],
          selected: {_vista},
          onSelectionChanged: (s) => setState(() => _vista = s.first),
        ),
        const Spacer(),

        // Navegación
        if (_vista == _VistaCronograma.mensual) ...[
          IconButton(
            tooltip: 'Mes anterior',
            onPressed: () => _cambiarMes(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          Text(
            '$mesNombre $_anioActual',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          IconButton(
            tooltip: 'Mes siguiente',
            onPressed: () => _cambiarMes(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ] else ...[
          IconButton(
            tooltip: 'Semana anterior',
            onPressed: () => setState(
              () => _semanaBase = _semanaBase.subtract(const Duration(days: 7)),
            ),
            icon: const Icon(Icons.chevron_left),
          ),
          Text(
            rangoSemana,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          IconButton(
            tooltip: 'Semana siguiente',
            onPressed: () => setState(
              () => _semanaBase = _semanaBase.add(const Duration(days: 7)),
            ),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ],
    );
  }

  // ================== Vista mensual (7 columnas por semana) ==================
  Widget _buildCalendarioMensualSemanas() {
    final now = DateTime.now();
    final esMismoMes = now.year == _anioActual && now.month == _mesActual;

    // 0..6 (lunes..domingo)
    int weekdayIndexMonday(DateTime d) => (d.weekday + 6) % 7;

    final primerDiaMes = DateTime(_anioActual, _mesActual, 1);
    final offset = weekdayIndexMonday(primerDiaMes); // espacios antes del 1

    final totalCeldas = offset + _daysInMonth;
    final totalFilas = (totalCeldas / 7).ceil();
    final totalItems = totalFilas * 7;

    return Column(
      children: [
        // Leyenda
        Row(
          children: [
            _buildLegend(Colors.grey.shade200, 'Sin tareas'),
            const SizedBox(width: 8),
            _buildLegend(AppTheme.primary.withOpacity(0.2), 'Con preventivas'),
            const SizedBox(width: 8),
            _buildLegend(Colors.blue.shade100, 'Hoy'),
          ],
        ),
        const SizedBox(height: 10),

        // Encabezado días semana
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: const [
              Expanded(
                child: Center(
                  child: Text(
                    'Lun',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    'Mar',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    'Mié',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    'Jue',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    'Vie',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    'Sáb',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    'Dom',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: GridView.builder(
            itemCount: totalItems,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.25,
              mainAxisExtent: 78,
            ),
            itemBuilder: (context, index) {
              final dia = index - offset + 1;

              // Celdas vacías (antes del 1 o después del último día)
              if (dia < 1 || dia > _daysInMonth) {
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                );
              }

              final resumen = _getResumenDia(dia);
              final isToday = esMismoMes && now.day == dia;

              return DragTarget<TareaModel>(
                onWillAccept: (t) => t != null,
                onAccept: (t) => _moverTareaADia(t, dia),
                builder: (context, candidateData, rejectedData) {
                  final hasCandidate = candidateData.isNotEmpty;

                  Color baseColor = resumen.preventivas > 0
                      ? AppTheme.primary.withOpacity(0.15)
                      : Colors.grey.shade100;

                  if (isToday) baseColor = Colors.blue.shade100;
                  if (hasCandidate)
                    baseColor = Colors.greenAccent.withOpacity(0.35);

                  return GestureDetector(
                    onTap: () => _abrirDia(dia),
                    child: Container(
                      decoration: BoxDecoration(
                        color: baseColor,
                        borderRadius: BorderRadius.circular(12),
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
                              padding: const EdgeInsets.only(top: 6),
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
    );
  }

  // ================== Vista semanal ==================
  Widget _buildAgendaSemanal() {
    final weekStart = _startOfWeekMonday(_semanaBase);
    final tareas = _tareasSemana(_semanaBase);

    final w = MediaQuery.of(context).size.width;
    final showSidebar = w >= 1100;

    if (!showSidebar) {
      return _WeekScheduleView(
        weekStart: weekStart,
        tareas: tareas,
        onTapTarea: (t) => _mostrarDetalleTarea(t, context),
      );
    }

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: _SidebarSimple(
            title: 'Resumen',
            items: [
              'Tareas semana: ${tareas.length}',
              'Tareas mes: ${_tareasMes.length}',
              'Horario: 08:00 - 16:00 (almuerzo 13-14)',
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 8,
          child: _WeekScheduleView(
            weekStart: weekStart,
            tareas: tareas,
            onTapTarea: (t) => _mostrarDetalleTarea(t, context),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 4,
          child: _SidebarAgendaDia(
            weekStart: weekStart,
            tareasSemana: tareas,
            onTapTarea: (t) => _mostrarDetalleTarea(t, context),
          ),
        ),
      ],
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

// ============================
//   WIDGETS: Semana tipo agenda
//   ✅ Header scrollea igual que body (Fix 2)
// ============================

class _WeekScheduleView extends StatefulWidget {
  final DateTime weekStart; // lunes 00:00
  final List<TareaModel> tareas;
  final void Function(TareaModel t) onTapTarea;

  const _WeekScheduleView({
    required this.weekStart,
    required this.tareas,
    required this.onTapTarea,
  });

  @override
  State<_WeekScheduleView> createState() => _WeekScheduleViewState();
}

class _WeekScheduleViewState extends State<_WeekScheduleView> {
  // Controladores para que header y body usen el MISMO scroll horizontal
  final ScrollController _hCtrl = ScrollController();
  final ScrollController _vCtrl = ScrollController();

  // Horario fijo
  static const int horaInicio = 8;
  static const int horaFin = 16;

  // Look & feel
  static const double pxPorMin = 1.2;
  static const double anchoHora = 56;
  static const double altoHeader = 44;

  int _minutesFromStart(DateTime d) {
    final start = DateTime(d.year, d.month, d.day, horaInicio);
    return d.difference(start).inMinutes;
  }

  int _dayIndex(DateTime d) {
    final diff = DateTime(d.year, d.month, d.day)
        .difference(
          DateTime(
            widget.weekStart.year,
            widget.weekStart.month,
            widget.weekStart.day,
          ),
        )
        .inDays;
    return diff;
  }

  bool _isWithinWeek(DateTime d) {
    final start = DateTime(
      widget.weekStart.year,
      widget.weekStart.month,
      widget.weekStart.day,
    );
    final end = start.add(const Duration(days: 7));
    final dd = DateTime(d.year, d.month, d.day);
    return !dd.isBefore(start) && dd.isBefore(end);
  }

  @override
  void dispose() {
    _hCtrl.dispose();
    _vCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hours = horaFin - horaInicio;
    final heightGrid = (hours * 60) * pxPorMin;

    final bg = const Color(0xFF0F1115);
    final line = Colors.white.withOpacity(0.08);
    final text = Colors.white.withOpacity(0.85);
    final subtext = Colors.white.withOpacity(0.60);

    return LayoutBuilder(
      builder: (context, c) {
        // si la pantalla es angosta, igual dejamos scroll horizontal
        const minDayCol = 120.0;
        final available = c.maxWidth - anchoHora;
        final colWidth = (available / 7).clamp(minDayCol, 9999.0);
        final totalWidth = anchoHora + colWidth * 7;

        return Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            children: [
              // ✅ HEADER (Fix 2): mismo ScrollController horizontal
              SizedBox(
                height: altoHeader,
                child: SingleChildScrollView(
                  controller: _hCtrl,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: totalWidth,
                    child: Row(
                      children: [
                        SizedBox(
                          width: anchoHora,
                          child: Center(
                            child: Text(
                              'Hora',
                              style: TextStyle(color: subtext, fontSize: 12),
                            ),
                          ),
                        ),
                        ...List.generate(7, (i) {
                          final d = widget.weekStart.add(Duration(days: i));
                          final label = [
                            "Lun",
                            "Mar",
                            "Mié",
                            "Jue",
                            "Vie",
                            "Sáb",
                            "Dom",
                          ][i];
                          return SizedBox(
                            width: colWidth,
                            child: Center(
                              child: Text(
                                "$label ${d.day}",
                                style: TextStyle(
                                  color: text,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ),
              Container(height: 1, color: line),

              // BODY: scroll horizontal (mismo controller) + scroll vertical
              Expanded(
                child: SingleChildScrollView(
                  controller: _hCtrl,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: totalWidth,
                    child: SingleChildScrollView(
                      controller: _vCtrl,
                      child: SizedBox(
                        height: heightGrid,
                        child: Stack(
                          children: [
                            // Columnas
                            Positioned.fill(
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: anchoHora,
                                    child: _HoursColumnDark(
                                      pxPorMin: pxPorMin,
                                      textColor: subtext,
                                    ),
                                  ),
                                  ...List.generate(7, (_) {
                                    return Container(
                                      width: colWidth,
                                      decoration: BoxDecoration(
                                        border: Border(
                                          left: BorderSide(color: line),
                                        ),
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),

                            // Líneas por hora
                            ...List.generate(hours + 1, (h) {
                              final top = (h * 60) * pxPorMin;
                              return Positioned(
                                left: 0,
                                right: 0,
                                top: top,
                                child: Container(height: 1, color: line),
                              );
                            }),

                            // Bloques tareas
                            ...widget.tareas
                                .where(
                                  (t) => _isWithinWeek(t.fechaInicio.toLocal()),
                                )
                                .map((t) {
                                  final ini = t.fechaInicio.toLocal();
                                  final fin = t.fechaFin.toLocal();

                                  final day = _dayIndex(ini);
                                  if (day < 0 || day > 6)
                                    return const SizedBox.shrink();

                                  final startMin = _minutesFromStart(ini);
                                  final durMin = fin.difference(ini).inMinutes;

                                  final left = anchoHora + day * colWidth + 6;
                                  final top = startMin * pxPorMin;
                                  final height = (durMin * pxPorMin).clamp(
                                    18.0,
                                    9999.0,
                                  );

                                  final colorBase = AppTheme.primary;
                                  final fill = colorBase.withOpacity(0.22);
                                  final border = colorBase.withOpacity(0.70);

                                  final horaIni = DateFormat(
                                    'HH:mm',
                                  ).format(ini);
                                  final horaFin = DateFormat(
                                    'HH:mm',
                                  ).format(fin);

                                  return Positioned(
                                    left: left,
                                    top: top,
                                    width: colWidth - 12,
                                    height: height,
                                    child: GestureDetector(
                                      onTap: () => widget.onTapTarea(t),
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: fill,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: border,
                                            width: 1,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              t.descripcion,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: text,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              '$horaIni - $horaFin',
                                              style: TextStyle(
                                                color: subtext,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HoursColumnDark extends StatelessWidget {
  final double pxPorMin;
  final Color textColor;

  const _HoursColumnDark({required this.pxPorMin, required this.textColor});

  @override
  Widget build(BuildContext context) {
    const int horaInicio = 8;
    const int horaFin = 16;
    final hours = horaFin - horaInicio;

    return Column(
      children: List.generate(hours, (i) {
        final h = horaInicio + i;
        return SizedBox(
          height: 60 * pxPorMin,
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                "${h.toString().padLeft(2, '0')}:00",
                style: TextStyle(fontSize: 11, color: textColor),
              ),
            ),
          ),
        );
      }),
    );
  }
}

// Sidebar simple (izquierda)
class _SidebarSimple extends StatelessWidget {
  final String title;
  final List<String> items;

  const _SidebarSimple({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 10),
            ...items.map(
              (s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text("• $s", style: const TextStyle(fontSize: 12)),
              ),
            ),
            const Spacer(),
            Text(
              "Tip: aquí metes filtros (supervisor, operario, ubicación) sin tocar la agenda.",
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }
}

// Sidebar agenda del día (derecha)
class _SidebarAgendaDia extends StatefulWidget {
  final DateTime weekStart;
  final List<TareaModel> tareasSemana;
  final void Function(TareaModel t) onTapTarea;

  const _SidebarAgendaDia({
    required this.weekStart,
    required this.tareasSemana,
    required this.onTapTarea,
  });

  @override
  State<_SidebarAgendaDia> createState() => _SidebarAgendaDiaState();
}

class _SidebarAgendaDiaState extends State<_SidebarAgendaDia> {
  int _diaIndex = 0; // 0..6

  @override
  Widget build(BuildContext context) {
    final fecha = widget.weekStart.add(Duration(days: _diaIndex));
    final tareasDia = widget.tareasSemana.where((t) {
      final d = t.fechaInicio.toLocal();
      return d.year == fecha.year &&
          d.month == fecha.month &&
          d.day == fecha.day;
    }).toList()..sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));

    return Card(
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Agenda',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
                DropdownButton<int>(
                  value: _diaIndex,
                  items: List.generate(7, (i) {
                    final d = widget.weekStart.add(Duration(days: i));
                    final label = [
                      "Lun",
                      "Mar",
                      "Mié",
                      "Jue",
                      "Vie",
                      "Sáb",
                      "Dom",
                    ][i];
                    return DropdownMenuItem(
                      value: i,
                      child: Text("$label ${d.day}"),
                    );
                  }),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _diaIndex = v);
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              DateFormat("EEEE dd MMMM", "es").format(fecha),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const Divider(height: 18),
            if (tareasDia.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'Sin tareas este día',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: tareasDia.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final t = tareasDia[i];
                    final ini = t.fechaInicio.toLocal();
                    final fin = t.fechaFin.toLocal();
                    return InkWell(
                      onTap: () => widget.onTapTarea(t),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.primary.withOpacity(0.25),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.descripcion,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "${DateFormat('HH:mm').format(ini)} - ${DateFormat('HH:mm').format(fin)}",
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
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
