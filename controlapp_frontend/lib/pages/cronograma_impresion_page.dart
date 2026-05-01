import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/cronograma_api.dart';
import 'package:flutter_application_1/api/gerente_api.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/pdf/cronograma_pdf.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:intl/intl.dart';

class CronogramaImpresionPage extends StatefulWidget {
  final String nit;

  const CronogramaImpresionPage({super.key, required this.nit});

  @override
  State<CronogramaImpresionPage> createState() => _CronogramaImpresionPageState();
}

class _CronogramaImpresionPageState extends State<CronogramaImpresionPage> {
  final _cronogramaApi = CronogramaApi();
  final _gerenteApi = GerenteApi();

  bool _loading = true;
  String? _error;

  int _mes = DateTime.now().month;
  int _anio = DateTime.now().year;
  int _semana = 1;
  String _operario = 'TODOS';

  List<TareaModel> _tareasMes = [];
  List<HorarioConjunto> _horariosConjunto = const [];
  List<String> _operariosDisponibles = [];
  String _conjuntoNombre = '';

  @override
  void initState() {
    super.initState();
    _cargarMes();
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _startOfWeekMonday(DateTime d) {
    final dd = _dayOnly(d);
    final diff = dd.weekday - DateTime.monday;
    return dd.subtract(Duration(days: diff));
  }

  DateTime _weekStartOfMonthByIndex(int year, int month, int weekIndex) {
    final firstDay = DateTime(year, month, 1);
    final firstWeekStart = _startOfWeekMonday(firstDay);
    return firstWeekStart.add(Duration(days: 7 * (weekIndex - 1)));
  }

  String _nombreMes(int month) {
    return DateFormat('MMMM', 'es').format(DateTime(2000, month, 1));
  }

  List<int> get _aniosDisponibles {
    final years = <int>{DateTime.now().year};
    for (final t in _tareasMes) {
      years.add(t.fechaInicio.toLocal().year);
    }
    final current = DateTime.now().year;
    years.add(current - 1);
    years.add(current + 1);
    final out = years.toList()..sort();
    return out;
  }

  Future<void> _cargarMes() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final tareas = await _cronogramaApi.listarPorConjuntoYMes(
        nit: widget.nit,
        anio: _anio,
        mes: _mes,
      );
      List<HorarioConjunto> horarios = const [];
      try {
        final detalle = await _gerenteApi.obtenerConjunto(widget.nit);
        horarios = detalle.horarios;
        _conjuntoNombre = detalle.nombre.trim();
      } catch (_) {
        try {
          final conjuntos = await _gerenteApi.listarConjuntos();
          for (final conjunto in conjuntos) {
            if (conjunto.nit == widget.nit) {
              horarios = conjunto.horarios;
              _conjuntoNombre = conjunto.nombre.trim();
              break;
            }
          }
        } catch (_) {}
      }

      final operarios = <String>{};
      for (final t in tareas) {
        for (final name in t.operariosNombres) {
          final clean = name.trim();
          if (clean.isNotEmpty) operarios.add(clean);
        }
      }

      if (!mounted) return;
      setState(() {
        _tareasMes = tareas;
        _horariosConjunto = horarios;
        _operariosDisponibles = operarios.toList()..sort();
        if (!_operariosDisponibles.contains(_operario)) {
          _operario = 'TODOS';
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppError.messageOf(e);
        _loading = false;
      });
    }
  }

  List<TareaModel> get _tareasOperarioMes {
    return _tareasMes.where((t) {
      if (_operario == 'TODOS') return false;
      return t.operariosNombres.map((e) => e.trim()).contains(_operario);
    }).toList();
  }

  List<TareaModel> get _tareasPreviewSemana {
    if (_operario == 'TODOS') return const [];
    final weekStart = _weekStartOfMonthByIndex(_anio, _mes, _semana);
    final weekEnd = weekStart.add(const Duration(days: 6));
    return _tareasOperarioMes.where((t) {
      final d = _dayOnly(t.fechaInicio.toLocal());
      return !d.isBefore(_dayOnly(weekStart)) && !d.isAfter(_dayOnly(weekEnd));
    }).toList()..sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));
  }

  Future<void> _descargarPdf() async {
    if (_operario == 'TODOS') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un operario para imprimir.')),
      );
      return;
    }

    final tareasSemana = _tareasPreviewSemana;
    if (tareasSemana.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ese operario no tiene tareas en la semana seleccionada.')),
      );
      return;
    }

    final weekStart = _weekStartOfMonthByIndex(_anio, _mes, _semana);
    final weekEnd = weekStart.add(const Duration(days: 6));
    final conjuntoNombre = tareasSemana.isNotEmpty
        ? ((tareasSemana.first.conjuntoNombre ?? '').trim().isNotEmpty
              ? tareasSemana.first.conjuntoNombre!.trim()
              : _conjuntoNombre)
        : _conjuntoNombre;

    final payload = <String, dynamic>{
      'operarioNombre': _operario,
      'operarioId': '',
      'conjuntoNombre': conjuntoNombre.isEmpty ? widget.nit : conjuntoNombre,
      'anio': _anio,
      'mes': _mes,
      'semanaDelMes': _semana,
      'weekStart': DateFormat('yyyy-MM-dd').format(weekStart),
      'weekEnd': DateFormat('yyyy-MM-dd').format(weekEnd),
      'horariosConjunto': _horariosConjunto
          .map(
            (h) => {
              'dia': h.dia,
              'horaApertura': h.horaApertura,
              'horaCierre': h.horaCierre,
              'descansoInicio': h.descansoInicio,
              'descansoFin': h.descansoFin,
            },
          )
          .toList(),
      'tareas': tareasSemana
          .map(
            (t) => {
              'fechaInicio': t.fechaInicio.toIso8601String(),
              'fechaFin': t.fechaFin.toIso8601String(),
              'descripcion': t.descripcion,
              'ubicacionNombre': t.ubicacionNombre ?? '',
              'elementoNombre': t.elementoNombre ?? '',
            },
          )
          .toList(),
    };

    await imprimirCronogramaOperario(payload);
  }

  Widget _buildFiltros() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selecciona el cronograma a imprimir',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _mes,
                    decoration: const InputDecoration(
                      labelText: 'Mes',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: List.generate(12, (i) => i + 1)
                        .map(
                          (m) => DropdownMenuItem(
                            value: m,
                            child: Text(_nombreMes(m)),
                          ),
                        )
                        .toList(),
                    onChanged: (v) async {
                      setState(() => _mes = v ?? _mes);
                      await _cargarMes();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _anio,
                    decoration: const InputDecoration(
                      labelText: 'Año',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _aniosDisponibles
                        .map(
                          (year) => DropdownMenuItem(
                            value: year,
                            child: Text('$year'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) async {
                      setState(() => _anio = v ?? _anio);
                      await _cargarMes();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _operario,
                    decoration: const InputDecoration(
                      labelText: 'Operario',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'TODOS',
                        child: Text('Selecciona uno'),
                      ),
                      ..._operariosDisponibles.map(
                        (o) => DropdownMenuItem(value: o, child: Text(o)),
                      ),
                    ],
                    onChanged: (v) => setState(() => _operario = v ?? 'TODOS'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _semana,
                    decoration: const InputDecoration(
                      labelText: 'Semana',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: List.generate(6, (i) => i + 1)
                        .map(
                          (w) => DropdownMenuItem(
                            value: w,
                            child: Text('Semana $w'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _semana = v ?? 1),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final tareas = _tareasPreviewSemana;
    final weekStart = _weekStartOfMonthByIndex(_anio, _mes, _semana);
    final dias = List.generate(6, (i) => weekStart.add(Duration(days: i)));

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Previsualización del PDF',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _operario == 'TODOS'
                  ? 'Selecciona un operario para ver el cronograma.'
                  : 'Semana $_semana de ${_nombreMes(_mes)} de $_anio',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            if (_operario == 'TODOS')
              const Text('Sin operario seleccionado.')
            else if (tareas.isEmpty)
              const Text('No hay tareas para ese operario en la semana seleccionada.')
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final totalWidth = constraints.maxWidth;
                  final spacing = 10.0;
                  final cardWidth = (totalWidth - (spacing * 5)) / 6;

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: dias.asMap().entries.map((entry) {
                      final dia = entry.value;
                      final tareasDia = tareas.where((t) {
                        final d = t.fechaInicio.toLocal();
                        return d.year == dia.year &&
                            d.month == dia.month &&
                            d.day == dia.day;
                      }).toList()
                        ..sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));

                      return Container(
                        width: cardWidth,
                        margin: EdgeInsets.only(
                          right: entry.key == dias.length - 1 ? 0 : spacing,
                        ),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateFormat('EEEE dd/MM', 'es').format(dia),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (tareasDia.isEmpty)
                              Text(
                                'Sin tareas',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              )
                            else
                              ...tareasDia.map(
                                (t) => Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: AppTheme.primary.withValues(alpha: 0.20),
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
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${DateFormat('HH:mm').format(t.fechaInicio.toLocal())} - ${DateFormat('HH:mm').format(t.fechaFin.toLocal())}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                      if ((t.ubicacionNombre ?? '').trim().isNotEmpty)
                                        Text(
                                          t.ubicacionNombre!.trim(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _descargarPdf,
                icon: const Icon(Icons.download),
                label: const Text('Descargar PDF'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: const Text(
          'Imprimir cronograma',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Error: $_error'),
            ))
          : RefreshIndicator(
              onRefresh: _cargarMes,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _buildFiltros(),
                  const SizedBox(height: 12),
                  _buildPreview(),
                ],
              ),
            ),
    );
  }
}
