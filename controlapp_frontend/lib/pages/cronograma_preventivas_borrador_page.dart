// lib/pages/cronograma_preventivas_borrador_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/festivo_api.dart';
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
  final _festivoApi = FestivoApi();

  bool _loading = true;
  bool _publicando = false;
  String? _error;
  Set<String> _festivosYmd = {};
  Map<String, String> _festivoNombrePorYmd = {};

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
  late DateTime _semanaBase;

  bool _mostrarFiltrosMensual = false;

  String _filtroTipo = 'TODAS';
  String _filtroEstado = 'TODOS';
  String _filtroOperario = 'TODOS';
  String _filtroUbicacion = 'TODAS';

  List<String> _operariosDisponibles = [];
  List<String> _ubicacionesDisponibles = [];

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

  String _toYmd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool _esFestivo(DateTime d) {
    final dl = d.toLocal();
    final key = _toYmd(DateTime(dl.year, dl.month, dl.day));
    return _festivosYmd.contains(key);
  }

  String? _nombreFestivo(DateTime d) {
    final dl = d.toLocal();
    final key = _toYmd(DateTime(dl.year, dl.month, dl.day));
    return _festivoNombrePorYmd[key];
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
    return _tareasFiltradas.where((t) {
      final start = _startOfWeekMonday(semanaBase);
      final end = start.add(const Duration(days: 7));
      final dt = t.fechaInicio.toLocal();
      return !dt.isBefore(start) && dt.isBefore(end);
    }).toList();
  }

  List<TareaModel> get _tareasFiltradas =>
      _tareasMes.where(_pasaFiltros).toList();

  bool _pasaFiltros(TareaModel t) {
    // Tipo
    if (_filtroTipo != 'TODAS') {
      final tipo = (t.tipo ?? '').toUpperCase();
      if (tipo != _filtroTipo) return false;
    }

    // Estado
    if (_filtroEstado != 'TODOS') {
      if ((t.estado ?? '') != _filtroEstado) return false;
    }

    // Operario
    if (_filtroOperario != 'TODOS') {
      if (!_tareaTieneOperario(t, _filtroOperario)) return false;
    }

    // Ubicación
    if (_filtroUbicacion != 'TODAS') {
      final u = _nombreUbicacion(t) ?? '';
      if (u != _filtroUbicacion) return false;
    }

    return true;
  }

  String? _nombreUbicacion(TareaModel t) => t.ubicacionNombre;

  List<String> _nombresOperarios(TareaModel t) => t.operariosNombres;

  bool _tareaTieneOperario(TareaModel t, String nombreOperario) {
    return _nombresOperarios(t).contains(nombreOperario);
  }

  void _reconstruirFiltrosDisponibles() {
    final ops = <String>{};
    final ubis = <String>{};

    for (final t in _tareasMes) {
      final u = _nombreUbicacion(t);
      if (u != null && u.trim().isNotEmpty) ubis.add(u.trim());

      for (final op in _nombresOperarios(t)) {
        final n = op.trim();
        if (n.isNotEmpty) ops.add(n);
      }
    }

    _operariosDisponibles = ops.toList()..sort();
    _ubicacionesDisponibles = ubis.toList()..sort();
  }

  void _aplicarFiltrosYRefrescar() {
    _recalcularResumenDias(); // si lo usas
    setState(() {});
  }

  void _limpiarFiltros() {
    setState(() {
      _filtroTipo = 'TODAS';
      _filtroEstado = 'TODOS';
      _filtroOperario = 'TODOS';
      _filtroUbicacion = 'TODAS';
    });
    _aplicarFiltrosYRefrescar();
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
      final desde = DateTime(_anioActual, _mesActual, 1);
      final hasta = DateTime(_anioActual, _mesActual, _daysInMonth);

      final results = await Future.wait([
        _cronogramaApi.cronogramaMensual(
          nit: widget.nit,
          anio: _anioActual,
          mes: _mesActual,
          borrador: true,
          tipo: 'PREVENTIVA',
        ),
        _festivoApi.listarFestivosRango(desde: desde, hasta: hasta, pais: 'CO'),
      ]);

      final lista = results[0] as List<TareaModel>;
      final festivos = results[1] as List<FestivoItem>;

      final filtradas = lista
          .where((t) => _isInThisMonth(t.fechaInicio))
          .toList();

      final setYmd = <String>{};
      final nombrePorYmd = <String, String>{};

      for (final f in festivos) {
        final key = _toYmd(f.fecha);
        setYmd.add(key);
        if (f.nombre != null && f.nombre!.trim().isNotEmpty) {
          nombrePorYmd[key] = f.nombre!.trim();
        }
      }

      setState(() {
        _tareasMes = filtradas;
        _reconstruirFiltrosDisponibles();
        _festivosYmd = setYmd;
        _festivoNombrePorYmd = nombrePorYmd;
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

      final tareasDia = _tareasFiltradas.where((t) {
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

  bool _hayFiltrosActivos() {
    return _filtroTipo != 'TODAS' ||
        _filtroEstado != 'TODOS' ||
        _filtroOperario != 'TODOS' ||
        _filtroUbicacion != 'TODAS';
  }

  _DiaResumen _getResumenDia(int dia) {
    return _diasResumen.firstWhere(
      (d) => d.dia == dia,
      orElse: () => _DiaResumen(dia: dia, total: 0, preventivas: 0),
    );
  }

  // ========= NUEVO: Mensual tipo matriz (como la foto) =========

  String _codigoEstado(String? estado) {
    final e = (estado ?? '').trim().toUpperCase();
    const map = <String, String>{
      'ASIGNADA': 'AS',
      'EN_PROCESO': 'EP',
      'COMPLETADA': 'CO',
      'APROBADA': 'AP',
      'PENDIENTE_APROBACION': 'PA',
      'RECHAZADA': 'RE',
      'NO_COMPLETADA': 'NC',
      'PENDIENTE_REPROGRAMACION': 'PR',
    };

    if (e.isEmpty) return '';
    if (map.containsKey(e)) return map[e]!;

    // fallback: 1-2 letras desde el texto
    final parts = e
        .split(RegExp(r'[_\s]+'))
        .where((x) => x.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1)
      return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1);
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  bool _esDomingo(DateTime d) => d.weekday == DateTime.sunday;

  String _weekdayLetter(DateTime d) {
    // L M M J V S D (lunes..domingo)
    const letters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
    return letters[d.weekday - 1];
  }

  Widget _ddTipo() {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Tipo',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      value: _filtroTipo,
      items: const [
        DropdownMenuItem(value: 'TODAS', child: Text('Todas')),
        DropdownMenuItem(value: 'PREVENTIVA', child: Text('Preventivas')),
        DropdownMenuItem(value: 'CORRECTIVA', child: Text('Correctivas')),
      ],
      onChanged: (v) {
        if (v == null) return;
        setState(() => _filtroTipo = v);
        _aplicarFiltrosYRefrescar();
      },
    );
  }

  Widget _ddEstado() {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Estado',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      value: _filtroEstado,
      items: const [
        DropdownMenuItem(value: 'TODOS', child: Text('Todos')),
        DropdownMenuItem(value: 'ASIGNADA', child: Text('Asignada')),
        DropdownMenuItem(value: 'EN_PROCESO', child: Text('En proceso')),
        DropdownMenuItem(value: 'COMPLETADA', child: Text('Completada')),
        DropdownMenuItem(value: 'APROBADA', child: Text('Aprobada')),
        DropdownMenuItem(
          value: 'PENDIENTE_APROBACION',
          child: Text('Pendiente aprobación'),
        ),
        DropdownMenuItem(value: 'RECHAZADA', child: Text('Rechazada')),
        DropdownMenuItem(value: 'NO_COMPLETADA', child: Text('No completada')),
        DropdownMenuItem(
          value: 'PENDIENTE_REPROGRAMACION',
          child: Text('Pendiente reprogramación'),
        ),
      ],
      onChanged: (v) {
        if (v == null) return;
        setState(() => _filtroEstado = v);
        _aplicarFiltrosYRefrescar();
      },
    );
  }

  Widget _ddOperario() {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Operario',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      value: _filtroOperario,
      items: [
        const DropdownMenuItem(value: 'TODOS', child: Text('Todos')),
        ..._operariosDisponibles.map(
          (o) => DropdownMenuItem(value: o, child: Text(o)),
        ),
      ],
      onChanged: (v) {
        if (v == null) return;
        setState(() => _filtroOperario = v);
        _aplicarFiltrosYRefrescar();
      },
    );
  }

  Widget _ddUbicacion() {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Ubicación',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      value: _filtroUbicacion,
      items: [
        const DropdownMenuItem(value: 'TODAS', child: Text('Todas')),
        ..._ubicacionesDisponibles.map(
          (u) => DropdownMenuItem(value: u, child: Text(u)),
        ),
      ],
      onChanged: (v) {
        if (v == null) return;
        setState(() => _filtroUbicacion = v);
        _aplicarFiltrosYRefrescar();
      },
    );
  }

  Widget _buildFiltrosMensualCompacto() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  'Filtros',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade900,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _limpiarFiltros,
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('Limpiar'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 2 columnas para que no quede “bloque ladrillo”
            Row(
              children: [
                Expanded(child: _ddTipo()),
                const SizedBox(width: 10),
                Expanded(child: _ddEstado()),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _ddOperario()),
                const SizedBox(width: 10),
                Expanded(child: _ddUbicacion()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltrosComoColumna({bool mostrarTitulo = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (mostrarTitulo) ...[
          const Text(
            'Filtros',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 10),
        ],
        _ddTipo(),
        const SizedBox(height: 8),
        _ddEstado(),
        const SizedBox(height: 8),
        _ddOperario(),
        const SizedBox(height: 8),
        _ddUbicacion(),
      ],
    );
  }

  List<_FilaCrono> _buildFilasCronoMensual() {
    // Agrupa por: descripcion + frecuencia + ubicacion + responsable (ajustable)
    final Map<String, _FilaCrono> rows = {};

    for (final t in _tareasFiltradas) {
      final ubic = (t.ubicacionNombre ?? 'ID ${t.ubicacionId}').trim();
      final freq = (t.frecuencia ?? '—').trim();
      final diag = (t.descripcion).trim();

      // responsable: prioriza operarios, si no supervisor
      final resp = t.operariosNombres.isNotEmpty
          ? t.operariosNombres.join(', ')
          : (t.supervisorNombre ??
                (t.supervisorId != null
                    ? 'ID ${t.supervisorId}'
                    : 'Sin asignar'));

      final key = '$freq||$diag||$ubic||$resp';

      rows.putIfAbsent(
        key,
        () => _FilaCrono(
          frecuencia: freq,
          diagnostico: diag,
          ubicacion: ubic,
          responsable: resp,
          porDia: {},
        ),
      );

      final day = t.fechaInicio.toLocal().day;

      // Si hay varias tareas el mismo día para esa fila, mostramos la “más crítica”
      // Orden: X > R > O > vacío (ajusta si quieres)
      final s = _codigoEstado(t.estado);
      final actual = rows[key]!.porDia[day] ?? '';
      rows[key]!.porDia[day] = _mergeSimbolos(actual, s);
    }

    final list = rows.values.toList();

    // Ordena: frecuencia, diagnóstico, ubicación
    list.sort((a, b) {
      final c1 = a.frecuencia.compareTo(b.frecuencia);
      if (c1 != 0) return c1;
      final c2 = a.diagnostico.compareTo(b.diagnostico);
      if (c2 != 0) return c2;
      return a.ubicacion.compareTo(b.ubicacion);
    });

    return list;
  }

  String _mergeSimbolos(String a, String b) {
    int rank(String s) {
      switch (s) {
        case 'NC':
          return 90; // no completada
        case 'RE':
          return 80; // rechazada
        case 'PR':
          return 70; // pendiente reprogramación
        case 'PA':
          return 60; // pendiente aprobación
        case 'EP':
          return 50; // en proceso
        case 'AS':
          return 40; // asignada
        case 'CO':
          return 30; // completada
        case 'AP':
          return 20; // aprobada
        default:
          return s.isEmpty ? 0 : 10;
      }
    }

    return rank(b) > rank(a) ? b : a;
  }

  Color _colorPorCodigo(String code) {
    switch (code) {
      case 'NC':
        return Colors.red.shade700;
      case 'RE':
        return Colors.red.shade900;
      case 'PR':
        return Colors.deepOrange.shade800;
      case 'PA':
        return Colors.orange.shade800;
      case 'EP':
        return Colors.blue.shade800;
      case 'AS':
        return Colors.indigo.shade700;
      case 'CO':
        return Colors.green.shade800;
      case 'AP':
        return Colors.teal.shade800;
      default:
        return Colors.grey.shade900;
    }
  }

  Widget _buildCronogramaMensualTipoFoto() {
    final filas = _buildFilasCronoMensual();

    // tamaños (ajusta si quieres)
    const wFrecuencia = 120.0;
    const wDiagnostico = 260.0;
    const wUbicacion = 120.0;
    const wResponsable = 140.0;
    const wDia = 34.0;

    final headerStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: Colors.grey.shade900,
    );

    final border = BorderSide(color: Colors.grey.shade300);

    Widget cellBox({
      required double w,
      required Widget child,
      Color? color,
      Alignment align = Alignment.center,
    }) {
      return Container(
        width: w,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        alignment: align,
        decoration: BoxDecoration(
          color: color ?? Colors.white,
          border: Border(right: border, bottom: border),
        ),
        child: child,
      );
    }

    // encabezados días
    final dias = List.generate(_daysInMonth, (i) => i + 1);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          color: Colors.white,
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ===== Header 1: títulos fijos + letras de semana =====
              Row(
                children: [
                  cellBox(
                    w: wFrecuencia,
                    color: Colors.green.shade200,
                    align: Alignment.center,
                    child: Text('Frecuencia', style: headerStyle),
                  ),
                  cellBox(
                    w: wDiagnostico,
                    color: Colors.green.shade200,
                    align: Alignment.center,
                    child: Text('Tarea', style: headerStyle),
                  ),
                  cellBox(
                    w: wUbicacion,
                    color: Colors.green.shade200,
                    align: Alignment.center,
                    child: Text('Ubicación', style: headerStyle),
                  ),
                  cellBox(
                    w: wResponsable,
                    color: Colors.green.shade200,
                    align: Alignment.center,
                    child: Text('Responsable', style: headerStyle),
                  ),
                  ...dias.map((dia) {
                    final fecha = DateTime(_anioActual, _mesActual, dia);
                    final dom = _esDomingo(fecha);
                    final fest = _esFestivo(fecha);

                    Color headerColor;
                    if (dom) {
                      headerColor = Colors.yellow.shade300;
                    } else if (fest) {
                      headerColor = Colors.red.shade200;
                    } else {
                      headerColor = Colors.green.shade200;
                    }

                    return cellBox(
                      w: wDia,
                      color: headerColor,
                      child: Tooltip(
                        message: fest
                            ? (_nombreFestivo(fecha) ?? 'Festivo')
                            : '',
                        child: Text(_weekdayLetter(fecha), style: headerStyle),
                      ),
                    );
                  }),
                ],
              ),
              // ===== Header 2: números de día =====
              Row(
                children: [
                  cellBox(
                    w: wFrecuencia,
                    color: Colors.white,
                    child: const SizedBox.shrink(),
                  ),
                  cellBox(
                    w: wDiagnostico,
                    color: Colors.white,
                    child: const SizedBox.shrink(),
                  ),
                  cellBox(
                    w: wUbicacion,
                    color: Colors.white,
                    child: const SizedBox.shrink(),
                  ),
                  cellBox(
                    w: wResponsable,
                    color: Colors.white,
                    child: const SizedBox.shrink(),
                  ),
                  ...dias.map((dia) {
                    final fecha = DateTime(_anioActual, _mesActual, dia);
                    final dom = _esDomingo(fecha);
                    final fest = _esFestivo(fecha);

                    Color header2Color;
                    if (dom) {
                      header2Color = Colors.yellow.shade300;
                    } else if (fest) {
                      header2Color = Colors.red.shade100; // 👈 festivo
                    } else {
                      header2Color = Colors.grey.shade100;
                    }

                    return cellBox(
                      w: wDia,
                      color: header2Color,
                      child: Tooltip(
                        message: fest
                            ? (_nombreFestivo(fecha) ?? 'Festivo')
                            : '',
                        child: Text(
                          '$dia',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade900,
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),

              // ===== Body =====
              ...filas.map((f) {
                return Row(
                  children: [
                    cellBox(
                      w: wFrecuencia,
                      align: Alignment.centerLeft,
                      child: Text(
                        f.frecuencia,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    cellBox(
                      w: wDiagnostico,
                      align: Alignment.centerLeft,
                      child: Text(
                        f.diagnostico,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    cellBox(
                      w: wUbicacion,
                      align: Alignment.centerLeft,
                      child: Text(
                        f.ubicacion,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    cellBox(
                      w: wResponsable,
                      align: Alignment.centerLeft,
                      child: Text(
                        f.responsable,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    ...dias.map((dia) {
                      final fecha = DateTime(_anioActual, _mesActual, dia);
                      final dom = _esDomingo(fecha);
                      final fest = _esFestivo(fecha);
                      final val = f.porDia[dia] ?? '';

                      Color cellColor;
                      if (dom) {
                        cellColor = Colors.yellow.shade200;
                      } else if (fest) {
                        cellColor = Colors.red.shade50;
                      } else {
                        cellColor = Colors.white;
                      }

                      return GestureDetector(
                        onTap: () => _abrirDia(dia),
                        child: cellBox(
                          w: wDia,
                          color: dom
                              ? Colors.yellow.shade200
                              : fest
                              ? Colors.red.shade50
                              : Colors.white,
                          child: Text(
                            val,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: _colorPorCodigo(val), // 👈 AQUÍ SE USA
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
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

      final tareasDelDia = _tareasFiltradas;

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

  static const Map<String, String> _leyendaEstados = {
    'AS': 'Asignada',
    'EP': 'En proceso',
    'CO': 'Completada',
    'AP': 'Aprobada',
    'PA': 'Pendiente aprobación',
    'RE': 'Rechazada',
    'NC': 'No completada',
    'PR': 'Pendiente reprogramación',
  };

  Widget _buildLeyendaMensual() {
    // mostrar solo lo que aparece en el mes
    final usados = <String>{};
    for (final f in _buildFilasCronoMensual()) {
      usados.addAll(f.porDia.values.where((x) => x.trim().isNotEmpty));
    }

    final items = usados.toList()..sort();

    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        children: items.map((code) {
          final label = _leyendaEstados[code] ?? 'Estado: $code';
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppTheme.primary.withOpacity(0.18)),
            ),
            child: Text(
              '$code = $label',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade900,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

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
          if (_vista == _VistaCronograma.mensual)
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 180),
              crossFadeState: _mostrarFiltrosMensual
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _buildFiltrosMensualCompacto(),
              ),
              secondChild: const SizedBox.shrink(),
            ),

          const SizedBox(height: 10),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: _vista == _VistaCronograma.mensual
                      ? _buildCronogramaMensualTipoFoto()
                      : _buildAgendaSemanal(),
                ),
                if (_vista == _VistaCronograma.mensual) _buildLeyendaMensual(),
              ],
            ),
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
          const SizedBox(width: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.filter_alt_outlined, size: 18),
            label: Text(
              _hayFiltrosActivos() ? 'Filtros •' : 'Filtros',
              style: const TextStyle(fontSize: 12),
            ),
            onPressed: () => setState(
              () => _mostrarFiltrosMensual = !_mostrarFiltrosMensual,
            ),
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
              'Tareas mes: ${_tareasFiltradas.length}',
              'Horario: 08:00 - 16:00 (almuerzo 13-14)',
            ],
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _buildFiltrosComoColumna(mostrarTitulo: false),
            ),
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
}

// ============================
//   WIDGETS: Semana tipo agenda
//   ✅ FIX: Banda de almuerzo + pxPorMin + tema claro
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
  final ScrollController _hCtrl = ScrollController();
  final ScrollController _vCtrl = ScrollController();

  static const int horaInicio = 8;
  static const int horaFin = 16;

  // ✅ más “respirable”
  static const double pxPorMin = 1.6; // estaba 1.2
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
    final hours = horaFin - horaInicio; // 8 horas: 08..16
    final heightGrid = (hours * 60) * pxPorMin;

    // ✅ tema claro
    final bg = Colors.white;
    final line = Colors.grey.shade300;
    final text = Colors.grey.shade900;
    final subtext = Colors.grey.shade700;

    // ==== Banda de almuerzo 13:00 - 14:00 ====
    final lunchStartMin = (13 - horaInicio) * 60; // 13:00
    final lunchDurMin = 60;

    return LayoutBuilder(
      builder: (context, c) {
        const minDayCol = 120.0;
        final available = c.maxWidth - anchoHora;
        final colWidth = (available / 7).clamp(minDayCol, 9999.0);
        final totalWidth = anchoHora + colWidth * 7;

        return Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade300), // ✅
          ),
          child: Column(
            children: [
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

                            // líneas horizontales por hora
                            ...List.generate(hours + 1, (h) {
                              final top = (h * 60) * pxPorMin;
                              return Positioned(
                                left: 0,
                                right: 0,
                                top: top,
                                child: Container(height: 1, color: line),
                              );
                            }),

                            // ✅ banda de almuerzo
                            Positioned(
                              left: anchoHora,
                              right: 0,
                              top: lunchStartMin * pxPorMin,
                              height: lunchDurMin * pxPorMin,
                              child: Container(
                                color: Colors.orange.withOpacity(0.12),
                              ),
                            ),

                            // tareas
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
                                  final fill = colorBase.withOpacity(0.12);
                                  final border = colorBase.withOpacity(0.55);

                                  final horaIni = DateFormat(
                                    'HH:mm',
                                  ).format(ini);
                                  final horaFinStr = DateFormat(
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
                                              '$horaIni - $horaFinStr',
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
    final hours = horaFin - horaInicio; // 8

    return LayoutBuilder(
      builder: (context, c) {
        final height = c.maxHeight;

        return Stack(
          children: List.generate(hours + 1, (i) {
            final h = horaInicio + i;

            double top = (i * 60) * pxPorMin;
            top += 6;

            const labelHeight = 16.0;
            if (top > height - labelHeight) top = height - labelHeight;

            return Positioned(
              top: top,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  "${h.toString().padLeft(2, '0')}:00",
                  style: TextStyle(fontSize: 11, color: textColor),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// Sidebar simple (izquierda)
class _SidebarSimple extends StatelessWidget {
  final String title;
  final List<String> items;
  final Widget? child;

  const _SidebarSimple({required this.title, required this.items, this.child});

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
            if (child != null) ...[const Divider(), child!],
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

// ✅ Modelo interno de fila (debe ser top-level en Dart)
class _FilaCrono {
  final String frecuencia;
  final String diagnostico;
  final String ubicacion;
  final String responsable;
  final Map<int, String> porDia;

  _FilaCrono({
    required this.frecuencia,
    required this.diagnostico,
    required this.ubicacion,
    required this.responsable,
    required this.porDia,
  });
}
