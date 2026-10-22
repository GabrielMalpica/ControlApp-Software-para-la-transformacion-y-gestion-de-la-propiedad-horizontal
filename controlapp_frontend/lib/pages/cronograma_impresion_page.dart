import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/conjunto_api.dart';
import 'package:flutter_application_1/api/cronograma_api.dart';
import 'package:flutter_application_1/api/festivo_api.dart';
import 'package:flutter_application_1/api/gerente_api.dart';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/model/necesidad_operario_model.dart';
import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/pdf/cronograma_pdf.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/app_feedback.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/utils/cronograma/agrupar_actividades.dart';
import 'package:flutter_application_1/utils/cronograma/hoja_impresion.dart';
import 'package:flutter_application_1/widgets/cronograma/hoja_impresion_vista.dart';
import 'package:flutter_application_1/widgets/skeleton.dart';

/// Imprimir el cronograma: la semana (o el mes) de un operario o de todo
/// el equipo, con la cuadrícula por horas del administrador. La vista previa
/// dibuja las mismas hojas del PDF.
class CronogramaImpresionPage extends StatefulWidget {
  final String nit;

  const CronogramaImpresionPage({super.key, required this.nit});

  @override
  State<CronogramaImpresionPage> createState() =>
      _CronogramaImpresionPageState();
}

class _CronogramaImpresionPageState extends State<CronogramaImpresionPage> {
  static const _todos = '__todos__';

  final _cronogramaApi = CronogramaApi();
  final _festivoApi = FestivoApi();
  final _gerenteApi = GerenteApi();
  final _conjuntoApi = ConjuntoApi();

  bool _loading = true;
  bool _descargando = false;
  String? _error;

  int _mes = DateTime.now().month;
  int _anio = DateTime.now().year;
  int _semana = 1;
  String _operario = _todos;
  String _alcance = 'SEMANA';

  List<TareaModel> _tareasMes = [];
  List<HorarioConjunto> _horariosConjunto = const [];
  List<NecesidadOperario> _necesidades = const [];
  List<TrabajadorRef> _equipo = const [];
  String _conjuntoNombre = '';
  Map<String, String> _festivos = const {};

  @override
  void initState() {
    super.initState();
    _semana = _semanaDeHoy();
    _cargarMes();
  }

  int _semanaDeHoy() {
    final hoy = DateTime.now();
    if (hoy.year != _anio || hoy.month != _mes) return 1;
    final semanas = semanasDelMes(_anio, _mes);
    final i = semanas.lastIndexWhere((lunes) => !lunes.isAfter(hoy));
    return i < 0 ? 1 : i + 1;
  }

  String _toYmd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  List<int> get _aniosDisponibles {
    final actual = DateTime.now().year;
    final years = <int>{actual - 1, actual, actual + 1, _anio};
    for (final t in _tareasMes) {
      years.add(t.fechaInicio.toLocal().year);
    }
    return years.toList()..sort();
  }

  Future<void> _cargarMes() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final desde = DateTime(_anio, _mes, 1);
      final hasta = DateTime(_anio, _mes + 1, 0);
      final results = await Future.wait([
        _cronogramaApi.listarPorConjuntoYMes(
          nit: widget.nit,
          anio: _anio,
          mes: _mes,
        ),
        _festivoApi.listarFestivosRango(desde: desde, hasta: hasta, pais: 'CO'),
      ]);
      final tareas = results[0] as List<TareaModel>;
      final festivos = results[1] as List<FestivoItem>;

      var horarios = _horariosConjunto;
      var nombre = _conjuntoNombre;
      try {
        final detalle = await _gerenteApi.obtenerConjunto(widget.nit);
        horarios = detalle.horarios;
        nombre = detalle.nombre.trim();
      } catch (_) {
        try {
          final conjuntos = await _gerenteApi.listarConjuntos();
          for (final conjunto in conjuntos) {
            if (conjunto.nit == widget.nit) {
              horarios = conjunto.horarios;
              nombre = conjunto.nombre.trim();
              break;
            }
          }
        } catch (_) {}
      }

      // Plazas (puesto, horario especial, festivos). Si el rol no puede
      // verlas, la hoja usa el cargo del operario y el horario del conjunto.
      var necesidades = _necesidades;
      try {
        necesidades = await _conjuntoApi.listarNecesidades(widget.nit);
      } catch (_) {}

      if (!mounted) return;
      final equipo = trabajadoresDe(tareas);
      final totalSemanas = semanasDelMes(_anio, _mes).length;
      setState(() {
        _tareasMes = tareas;
        _horariosConjunto = horarios;
        _necesidades = necesidades;
        _conjuntoNombre = nombre;
        _equipo = equipo;
        _festivos = {
          for (final f in festivos) _toYmd(f.fecha): f.nombre?.trim() ?? '',
        };
        if (_operario != _todos && !equipo.any((e) => e.id == _operario)) {
          _operario = _todos;
        }
        if (_semana > totalSemanas) _semana = totalSemanas;
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

  String get _nombreConjunto {
    if (_conjuntoNombre.isNotEmpty) return _conjuntoNombre;
    for (final t in _tareasMes) {
      final n = (t.conjuntoNombre ?? '').trim();
      if (n.isNotEmpty) return n;
    }
    return widget.nit;
  }

  List<TrabajadorRef> get _operariosElegidos => _operario == _todos
      ? _equipo
      : _equipo.where((e) => e.id == _operario).toList();

  PlanImpresion _plan({required bool completo}) {
    final semanas = completo && _alcance == 'MES'
        ? [for (var i = 1; i <= semanasDelMes(_anio, _mes).length; i++) i]
        : [_semana];
    return construirPlanImpresion(
      conjuntoNombre: _nombreConjunto,
      anio: _anio,
      mes: _mes,
      tareasMes: _tareasMes,
      equipo: _equipo,
      operarios: _operariosElegidos,
      semanas: semanas,
      horariosConjunto: _horariosConjunto,
      necesidades: _necesidades,
      festivos: _festivos,
      conPortada: _operario == _todos,
    );
  }

  Future<void> _descargarPdf() async {
    final plan = _plan(completo: true);
    if (plan.vacio) {
      AppFeedback.showInfo(
        context,
        title: 'Sin actividades',
        message: _equipo.isEmpty
            ? 'Este mes no tiene actividades asignadas para imprimir.'
            : 'No hay actividades en la semana elegida.',
      );
      return;
    }
    setState(() => _descargando = true);
    try {
      await imprimirCronograma(plan);
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showError(
        context,
        title: 'No se pudo generar el PDF',
        message: AppError.messageOf(e),
      );
    } finally {
      if (mounted) setState(() => _descargando = false);
    }
  }

  Widget _buildFiltros() {
    final semanas = semanasDelMes(_anio, _mes);
    InputDecoration deco(String label) => InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
    );

    final mes = DropdownButtonFormField<int>(
      initialValue: _mes,
      isExpanded: true,
      decoration: deco('Mes'),
      items: [
        for (var m = 1; m <= 12; m++)
          DropdownMenuItem(
            value: m,
            child: Text(
              '${nombreMes(m)[0].toUpperCase()}${nombreMes(m).substring(1)}',
            ),
          ),
      ],
      onChanged: (v) async {
        if (v == null) return;
        setState(() {
          _mes = v;
          _semana = _semanaDeHoy();
        });
        await _cargarMes();
      },
    );
    final anio = DropdownButtonFormField<int>(
      initialValue: _anio,
      isExpanded: true,
      decoration: deco('Año'),
      items: [
        for (final y in _aniosDisponibles)
          DropdownMenuItem(value: y, child: Text('$y')),
      ],
      onChanged: (v) async {
        if (v == null) return;
        setState(() {
          _anio = v;
          _semana = _semanaDeHoy();
        });
        await _cargarMes();
      },
    );
    final operario = DropdownButtonFormField<String>(
      key: ValueKey('operario-$_anio-$_mes'),
      initialValue: _operario,
      isExpanded: true,
      decoration: deco('Operario'),
      items: [
        const DropdownMenuItem(
          value: _todos,
          child: Text('Todos los operarios'),
        ),
        for (final o in _equipo)
          DropdownMenuItem(
            value: o.id,
            child: Text(o.nombre, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) => setState(() => _operario = v ?? _todos),
    );
    final semana = DropdownButtonFormField<int>(
      key: ValueKey('semana-$_anio-$_mes'),
      initialValue: _semana,
      isExpanded: true,
      decoration: deco(_alcance == 'MES' ? 'Semana a revisar' : 'Semana'),
      items: [
        for (var i = 0; i < semanas.length; i++)
          DropdownMenuItem(
            value: i + 1,
            child: Text('Semana ${i + 1} · ${_rangoSemana(semanas[i])}'),
          ),
      ],
      onChanged: (v) => setState(() => _semana = v ?? 1),
    );
    final alcance = DropdownButtonFormField<String>(
      initialValue: _alcance,
      isExpanded: true,
      decoration: deco('Imprimir'),
      items: const [
        DropdownMenuItem(
          value: 'SEMANA',
          child: Text('Solo la semana elegida'),
        ),
        DropdownMenuItem(value: 'MES', child: Text('Todo el mes en un PDF')),
      ],
      onChanged: (v) => setState(() => _alcance = v ?? 'SEMANA'),
    );

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final ancho = constraints.maxWidth;
            final columnas = ancho >= 900 ? 5 : (ancho >= 560 ? 2 : 1);
            final campos = [mes, anio, operario, semana, alcance];
            const sep = 10.0;
            final anchoCampo = (ancho - sep * (columnas - 1)) / columnas;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Elige qué cronograma imprimir',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: sep,
                  runSpacing: sep,
                  children: [
                    for (final c in campos)
                      SizedBox(width: anchoCampo, child: c),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _rangoSemana(DateTime lunes) {
    final dias = [
      for (var i = 0; i < 7; i++) lunes.add(Duration(days: i)),
    ].where((d) => d.year == _anio && d.month == _mes).toList();
    if (dias.isEmpty) return '';
    return dias.first.day == dias.last.day
        ? '${dias.first.day}'
        : '${dias.first.day} al ${dias.last.day}';
  }

  Widget _buildPreview() {
    final plan = _plan(completo: false);
    final hojas = <(String, Widget)>[];
    final ahora = DateTime.now();
    final portada = plan.portada;
    final total = plan.hojas.length + (portada == null ? 0 : 1);
    if (portada != null) {
      hojas.add((
        'Portada · todo el equipo',
        PortadaImpresionVista(portada: portada),
      ));
    }
    for (var i = 0; i < plan.hojas.length; i++) {
      final h = plan.hojas[i];
      final pagina = i + 1 + (portada == null ? 0 : 1);
      final parte = h.totalPartes > 1
          ? ' · parte ${h.parte} de ${h.totalPartes}'
          : '';
      hojas.add((
        '${h.operario.ref.nombre}$parte',
        HojaImpresionVista(
          hoja: h,
          pagina: pagina,
          paginas: total,
          generado: ahora,
        ),
      ));
    }

    final semanasMes = semanasDelMes(_anio, _mes).length;
    final descripcion = _alcance == 'MES'
        ? 'El PDF trae las $semanasMes semanas de ${nombreMes(_mes)}. Aquí ves la semana $_semana; cambia «Semana a revisar» para ver otra.'
        : 'Así sale impresa la semana $_semana de ${nombreMes(_mes)} de $_anio. Toca una hoja para verla en grande.';

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Vista previa del PDF',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        descripcion,
                        style: const TextStyle(color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  style: AppTheme.saveButtonStyle,
                  onPressed: _loading || _descargando || _equipo.isEmpty
                      ? null
                      : _descargarPdf,
                  icon: _descargando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.download),
                  label: Text(
                    _descargando
                        ? 'Generando PDF…'
                        : (_alcance == 'MES'
                              ? 'Descargar PDF del mes'
                              : 'Descargar PDF de la semana'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (hojas.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  _equipo.isEmpty
                      ? 'Este mes no tiene actividades asignadas.'
                      : 'No hay actividades en la semana elegida.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textMuted),
                ),
              )
            else
              for (final (etiqueta, hoja) in hojas)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: PapelImpresion(etiqueta: etiqueta, hoja: hoja),
                    ),
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
          ? const SkeletonList()
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _cargarMes,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
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
