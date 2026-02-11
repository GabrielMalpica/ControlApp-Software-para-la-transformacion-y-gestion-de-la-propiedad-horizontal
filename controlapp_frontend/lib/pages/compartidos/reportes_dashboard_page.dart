import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_application_1/api/reporte_api.dart';
import 'package:flutter_application_1/model/reporte_model.dart';
import 'package:flutter_application_1/pdf/pdf_download.dart';
import 'package:flutter_application_1/service/chart_capture.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ReportesDashboardPage extends StatefulWidget {
  final String? conjuntoIdInicial;
  const ReportesDashboardPage({super.key, this.conjuntoIdInicial});

  @override
  State<ReportesDashboardPage> createState() => _ReportesDashboardPageState();
}

class _ReportesDashboardPageState extends State<ReportesDashboardPage> {
  final _api = ReporteApi();

  late DateTime _desde;
  late DateTime _hasta;

  late TextEditingController _conjuntoCtrl;

  bool _loading = false;
  bool _generandoPdf = false;
  String? _error;

  ReporteKpis? _kpis;
  SerieDiariaPorEstado? _serie;
  List<ResumenConjuntoRow> _porConjunto = [];
  List<ResumenOperarioRow> _porOperario = [];
  List<InsumoUsoRow> _insumos = [];
  List<UsoEquipoRow> _maq = [];
  List<UsoEquipoRow> _herr = [];

  // ✅ Informes usa tareas detalle
  List<TareaDetalleRow> _tareasDetalle = [];

  // ✅ Keys para capturar charts (Offstage + RepaintBoundary)
  final GlobalKey _kPieEstados = GlobalKey();
  final GlobalKey _kLineSerie = GlobalKey();
  final GlobalKey _kPieTipos = GlobalKey();

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();
    _desde = DateTime(now.year, now.month, 1);
    _hasta = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    _conjuntoCtrl = TextEditingController(text: widget.conjuntoIdInicial ?? '');
    _cargarTodo();
  }

  @override
  void dispose() {
    _conjuntoCtrl.dispose();
    super.dispose();
  }

  String? get _conjuntoId =>
      _conjuntoCtrl.text.trim().isEmpty ? null : _conjuntoCtrl.text.trim();

  Future<void> _cargarTodo() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final conjuntoId = _conjuntoId;

      final kpis = await _api.kpis(
        desde: _desde,
        hasta: _hasta,
        conjuntoId: conjuntoId,
      );
      final serie = await _api.serieDiaria(
        desde: _desde,
        hasta: _hasta,
        conjuntoId: conjuntoId,
      );

      final porConjunto = await _api.resumenPorConjunto(
        desde: _desde,
        hasta: _hasta,
      );
      final porOperario = await _api.resumenPorOperario(
        desde: _desde,
        hasta: _hasta,
        conjuntoId: conjuntoId,
      );

      final maq = await _api.topMaquinaria(
        desde: _desde,
        hasta: _hasta,
        conjuntoId: conjuntoId,
      );
      final herr = await _api.topHerramientas(
        desde: _desde,
        hasta: _hasta,
        conjuntoId: conjuntoId,
      );

      List<InsumoUsoRow> insumos = [];
      if (conjuntoId != null) {
        insumos = await _api.usoInsumos(
          conjuntoId: conjuntoId,
          desde: _desde,
          hasta: _hasta,
        );
      }

      // ✅ NUEVO: tareas detalle (correctivas + preventivas)
      final tareasDetalle = await _api.mensualDetalle(
        desde: _desde,
        hasta: _hasta,
        conjuntoId: conjuntoId,
      );

      setState(() {
        _kpis = kpis;
        _serie = serie;
        _porConjunto = porConjunto;
        _porOperario = porOperario;
        _insumos = insumos;
        _maq = maq;
        _herr = herr;
        _tareasDetalle = tareasDetalle;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickRango() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(DateTime.now().year - 3, 1, 1),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
      initialDateRange: DateTimeRange(start: _desde, end: _hasta),
    );

    if (range == null) return;

    setState(() {
      _desde = DateTime(range.start.year, range.start.month, range.start.day);
      _hasta = DateTime(
        range.end.year,
        range.end.month,
        range.end.day,
        23,
        59,
        59,
      );
    });
    _cargarTodo();
  }

  // ======================= TIPOS =======================

  Map<String, int> _contarTipos() {
    int prev = 0;
    int corr = 0;

    for (final t in _tareasDetalle) {
      final tipo = t.tipo.toUpperCase().trim();
      if (tipo == 'PREVENTIVA') prev++;
      if (tipo == 'CORRECTIVA') corr++;
    }
    return {'preventivas': prev, 'correctivas': corr};
  }

  // ======================= PDF =======================

  Future<void> _generarInformeGestionPdf() async {
    final k = _kpis;
    final s = _serie;
    if (k == null || s == null) return;

    setState(() => _generandoPdf = true);

    try {
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;

      final fontRegular = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
      );
      final fontBold = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
      );

      final pngEstados = await capturePngFromKey(_kPieEstados, pixelRatio: 2);
      final pngSerie = await capturePngFromKey(_kLineSerie, pixelRatio: 2);
      final pngTipos = await capturePngFromKey(_kPieTipos, pixelRatio: 2);

      final tipos = _contarTipos();
      final doc = pw.Document();
      final df = DateFormat('dd/MM/yyyy', 'es');

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(18),
          theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
          build: (_) => [
            pw.Text(
              'INFORME DE GESTIÓN',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            // ✅ sin flecha unicode
            pw.Text(
              'Rango: ${df.format(_desde)} a ${df.format(_hasta)}',
              style: const pw.TextStyle(fontSize: 11),
            ),

            pw.SizedBox(height: 12),
            pw.Text(
              'KPIs',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Bullet(text: 'Total tareas: ${k.total}'),
            pw.Bullet(text: 'Aprobadas: ${k.kpi.aprobadas}'),
            pw.Bullet(text: 'Rechazadas: ${k.kpi.rechazadas}'),
            pw.Bullet(text: 'No completadas: ${k.kpi.noCompletadas}'),
            pw.Bullet(
              text: 'Pendientes aprobación: ${k.kpi.pendientesAprobacion}',
            ),
            pw.Bullet(text: 'Tasa cierre: ${k.kpi.tasaCierrePct}%'),
            pw.Bullet(
              text:
                  'Preventivas: ${tipos['preventivas'] ?? 0} • Correctivas: ${tipos['correctivas'] ?? 0}',
            ),

            pw.SizedBox(height: 14),
            pw.Text(
              'Gráficas',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),

            pw.Text('Tipos (Preventiva/Correctiva)'),
            pw.SizedBox(height: 6),
            pw.Image(pw.MemoryImage(pngTipos), height: 220),

            pw.SizedBox(height: 10),
            pw.Text('Distribución por estado'),
            pw.SizedBox(height: 6),
            pw.Image(pw.MemoryImage(pngEstados), height: 220),

            pw.SizedBox(height: 10),
            pw.Text('Tareas por día (tendencia)'),
            pw.SizedBox(height: 6),
            pw.Image(pw.MemoryImage(pngSerie), height: 220),
          ],
        ),
      );

      final bytes = await doc.save();
      final filename =
          'Informe_Gestion_${df.format(_desde)}_${df.format(_hasta)}.pdf';

      if (kIsWeb) {
        await downloadPdfWeb(bytes, filename);
      } else {
        await Printing.layoutPdf(name: filename, onLayout: (_) async => bytes);
      }
    } catch (e, st) {
      debugPrint('❌ Error PDF Gestión: $e\n$st');
      // opcional: mostrar snackbar
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error generando PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _generandoPdf = false);
    }
  }

  Future<void> _generarInformeDetalladoPdf() async {
    if (_tareasDetalle.isEmpty) return;

    final fontRegular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
    );
    final fontBold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
    );

    final doc = pw.Document();
    final df = DateFormat('dd/MM/yyyy HH:mm', 'es');
    final dfRango = DateFormat('dd/MM/yyyy', 'es');

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(18),
        theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
        build: (_) {
          return [
            pw.Text(
              'INFORME DETALLADO DE TAREAS',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'Tareas: ${_tareasDetalle.length} • Rango: ${dfRango.format(_desde)} → ${dfRango.format(_hasta)}',
              style: const pw.TextStyle(fontSize: 11),
            ),
            pw.SizedBox(height: 12),

            ..._tareasDetalle.map((t) {
              final evid = t.evidencias;

              String miniList(List<Map<String, dynamic>> xs) {
                if (xs.isEmpty) return 'Sin datos';
                return xs
                    .take(4)
                    .map((m) {
                      final n = (m['nombre'] ?? '-').toString();
                      final c = (m['cantidad'] ?? '').toString();
                      final u = (m['unidad'] ?? '').toString();
                      final extra = [
                        c,
                        u,
                      ].where((e) => e.trim().isNotEmpty).join(' ');
                      return extra.isEmpty ? n : '$n ($extra)';
                    })
                    .join(' • ');
              }

              return pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 10),
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      '${t.tipo} • ${t.estado}',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      'ID ${t.id} • ${t.descripcion}',
                      style: const pw.TextStyle(fontSize: 11),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      'Inicio: ${df.format(t.fechaInicio)}',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                    pw.Text(
                      'Fin: ${df.format(t.fechaFin)}',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                    pw.Text(
                      'Duración: ${t.duracionMinutos} min',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                    pw.SizedBox(height: 6),

                    if ((t.ubicacion ?? '').isNotEmpty)
                      pw.Text(
                        'Ubicación: ${t.ubicacion}',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    if ((t.elemento ?? '').isNotEmpty)
                      pw.Text(
                        'Elemento: ${t.elemento}',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    if ((t.supervisor ?? '').isNotEmpty)
                      pw.Text(
                        'Supervisor: ${t.supervisor}',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    if (t.operarios.isNotEmpty)
                      pw.Text(
                        'Operarios: ${t.operarios.join(', ')}',
                        style: const pw.TextStyle(fontSize: 10),
                      ),

                    pw.SizedBox(height: 6),
                    pw.Text(
                      'Insumos: ${miniList(t.insumos)}',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                    pw.Text(
                      'Maquinaria: ${miniList(t.maquinaria)}',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                    pw.Text(
                      'Herramientas: ${miniList(t.herramientas)}',
                      style: const pw.TextStyle(fontSize: 10),
                    ),

                    pw.SizedBox(height: 6),
                    pw.Text(
                      'Evidencias (${evid.length}):',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    if (evid.isEmpty)
                      pw.Text(
                        'Sin evidencias',
                        style: const pw.TextStyle(fontSize: 10),
                      )
                    else
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: evid
                            .take(8)
                            .map(
                              (u) => pw.Text(
                                '- $u',
                                style: const pw.TextStyle(fontSize: 9),
                              ),
                            )
                            .toList(),
                      ),
                  ],
                ),
              );
            }),
          ];
        },
      ),
    );

    final bytes = await doc.save();
    final filename =
        'Informe_Detallado_${DateFormat('ddMMyyyy', 'es').format(_desde)}_${DateFormat('ddMMyyyy', 'es').format(_hasta)}.pdf';

    if (kIsWeb) {
      await downloadPdfWeb(bytes, filename);
    } else {
      await Printing.layoutPdf(name: filename, onLayout: (_) async => bytes);
    }
  }

  // ======================= BUILD =======================

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.primary;
    final df = DateFormat('dd/MM/yyyy', 'es');

    final tipos = _contarTipos();
    final prev = tipos['preventivas'] ?? 0;
    final corr = tipos['correctivas'] ?? 0;

    return DefaultTabController(
      length: 7,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F7FB),
        appBar: AppBar(
          backgroundColor: primary,
          title: const Text('Reportes', style: TextStyle(color: Colors.white)),
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              onPressed: _cargarTodo,
              icon: const Icon(Icons.refresh, color: Colors.white),
              tooltip: 'Actualizar',
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Resumen'),
              Tab(text: 'Conjuntos'),
              Tab(text: 'Operarios'),
              Tab(text: 'Insumos'),
              Tab(text: 'Maq/Herr'),
              Tab(text: 'Tipos'),
              Tab(text: 'Informes'),
            ],
          ),
        ),
        body: Column(
          children: [
            // filtros
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _filterChip(
                          icon: Icons.date_range,
                          title: 'Rango',
                          subtitle:
                              '${df.format(_desde)} → ${df.format(_hasta)}',
                          onTap: _pickRango,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _conjuntoCtrl,
                          style: const TextStyle(color: Colors.black87),
                          decoration: InputDecoration(
                            labelText: 'Filtro conjuntoId (opcional)',
                            labelStyle: const TextStyle(color: Colors.black54),
                            floatingLabelStyle: const TextStyle(
                              color: Colors.black87,
                            ),
                            isDense: true,
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              tooltip: 'Aplicar',
                              icon: const Icon(Icons.search),
                              onPressed: _cargarTodo,
                            ),
                          ),
                          onSubmitted: (_) => _cargarTodo(),
                        ),
                      ),
                    ],
                  ),
                  if (_conjuntoId == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Tip: para Insumos necesitas conjuntoId.',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? _buildError()
                  : TabBarView(
                      children: [
                        _tabResumen(),
                        _tabConjuntos(),
                        _tabOperarios(),
                        _tabInsumos(),
                        _tabMaqHerr(),
                        _tabTipos(),
                        _tabInformes(),
                      ],
                    ),
            ),

            // ✅ Charts invisibles para captura PNG (SÍ PINTA en web)
            IgnorePointer(
              ignoring: true,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Opacity(
                  opacity: 0.01, // invisible pero se pinta
                  child: SizedBox(
                    width: 1,
                    height: 1,
                    child: OverflowBox(
                      minWidth: 0,
                      minHeight: 0,
                      maxWidth: 9999,
                      maxHeight: 9999,
                      alignment: Alignment.topLeft,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RepaintBoundary(
                            key: _kPieEstados,
                            child: SizedBox(
                              width: 900,
                              height: 420,
                              child: _pieEstados(_kpis?.byEstado ?? {}),
                            ),
                          ),
                          RepaintBoundary(
                            key: _kLineSerie,
                            child: SizedBox(
                              width: 900,
                              height: 420,
                              child: _lineSerieDiaria(),
                            ),
                          ),
                          RepaintBoundary(
                            key: _kPieTipos,
                            child: SizedBox(
                              width: 900,
                              height: 420,
                              child: _pieTipos(prev: prev, corr: corr),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===================== UI atoms =====================

  Widget _filterChip({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black12),
          color: Colors.white,
          boxShadow: const [
            BoxShadow(
              blurRadius: 10,
              color: Color(0x0F000000),
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(14),
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
        boxShadow: const [
          BoxShadow(
            blurRadius: 12,
            color: Color(0x0A000000),
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }

  Widget _sectionTitle(String t) => Text(
    t,
    style: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w900,
      color: Colors.black87,
    ),
  );

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 40),
            const SizedBox(height: 10),
            Text(_error ?? 'Error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _cargarTodo,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  // ======================= TAB: RESUMEN =======================

  Widget _tabResumen() {
    final k = _kpis;
    if (k == null) return const Center(child: Text('Sin datos'));

    final kd = k.kpi;
    final tipos = _contarTipos();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _kpiTile('Total', k.total.toString(), Icons.assignment),
            _kpiTile('Aprobadas', kd.aprobadas.toString(), Icons.verified),
            _kpiTile('Rechazadas', kd.rechazadas.toString(), Icons.block),
            _kpiTile(
              'No completadas',
              kd.noCompletadas.toString(),
              Icons.warning_amber,
            ),
            _kpiTile(
              'Pend. aprobación',
              kd.pendientesAprobacion.toString(),
              Icons.hourglass_bottom,
            ),
            _kpiTile('% Cierre', '${kd.tasaCierrePct}%', Icons.trending_up),
            _kpiTile(
              'Preventivas',
              '${tipos['preventivas'] ?? 0}',
              Icons.build_circle,
            ),
            _kpiTile(
              'Correctivas',
              '${tipos['correctivas'] ?? 0}',
              Icons.report_problem,
            ),
          ],
        ),
        const SizedBox(height: 14),

        _sectionTitle('Distribución por estado'),
        const SizedBox(height: 8),
        _card(
          child: SizedBox(
            height: 240,
            child: Row(
              children: [
                Expanded(child: _pieEstados(k.byEstado)),
                const SizedBox(width: 10),
                SizedBox(width: 170, child: _legendEstados(k.byEstado)),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        _sectionTitle('Tareas por día (tendencia)'),
        const SizedBox(height: 8),
        _card(child: SizedBox(height: 260, child: _lineSerieDiaria())),

        const SizedBox(height: 14),

        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('Top Operarios (por volumen)'),
                  const SizedBox(height: 8),
                  _card(
                    child: SizedBox(height: 240, child: _barTopOperarios()),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('Top Conjuntos (por volumen)'),
                  const SizedBox(height: 8),
                  _card(
                    child: SizedBox(height: 240, child: _barTopConjuntos()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _kpiTile(String title, String value, IconData icon) {
    return _card(
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        width: 185,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppTheme.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------- Pie estados --------

  Widget _pieEstados(Map<String, int> byEstado) {
    final entries = byEstado.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (a, b) => a + b.value);
    if (total <= 0) return const Center(child: Text('Sin datos'));

    final sections = <PieChartSectionData>[];
    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      final pct = (e.value / total) * 100;
      final c = i.isEven ? AppTheme.primary : AppTheme.primary.withOpacity(.55);

      sections.add(
        PieChartSectionData(
          value: e.value.toDouble(),
          title: pct >= 8 ? '${pct.toStringAsFixed(0)}%' : '',
          radius: 70,
          titleStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
          color: c,
        ),
      );
    }

    return PieChart(
      PieChartData(sectionsSpace: 2, centerSpaceRadius: 44, sections: sections),
    );
  }

  Widget _legendEstados(Map<String, int> byEstado) {
    final entries = byEstado.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (a, b) => a + b.value);
    if (total <= 0) return const SizedBox.shrink();

    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final e = entries[i];
        final pct = (e.value / total) * 100;
        final c = i.isEven
            ? AppTheme.primary
            : AppTheme.primary.withOpacity(.55);
        return Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                e.key,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${e.value} (${pct.toStringAsFixed(0)}%)',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        );
      },
    );
  }

  // -------- Line serie diaria --------

  Widget _lineSerieDiaria() {
    final s = _serie;
    if (s == null || s.days.isEmpty)
      return const Center(child: Text('Sin serie'));

    final days = s.days.length <= 30
        ? s.days
        : s.days.sublist(s.days.length - 30);
    final spots = <FlSpot>[];

    for (int i = 0; i < days.length; i++) {
      final d = days[i];
      final m = s.series[d] ?? {};
      final total = m.values.fold<int>(0, (a, b) => a + b);
      spots.add(FlSpot(i.toDouble(), total.toDouble()));
    }

    final maxY = spots
        .map((e) => e.y)
        .fold<double>(0, (a, b) => math.max(a, b));
    final yTop = (maxY <= 0) ? 5 : (maxY * 1.2);

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: yTop.toDouble(),
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (v, meta) => Text(
                v.toInt().toString(),
                style: const TextStyle(fontSize: 10, color: Colors.black87),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: math.max(1, (days.length / 6).floor()).toDouble(),
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= days.length)
                  return const SizedBox.shrink();
                final label = days[idx].split('-');
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${label[2]}/${label[1]}',
                    style: const TextStyle(fontSize: 10, color: Colors.black87),
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: AppTheme.primary.withOpacity(.12),
            ),
            color: AppTheme.primary,
          ),
        ],
      ),
    );
  }

  // -------- Bar top operarios / conjuntos --------

  Widget _barTopOperarios() {
    if (_porOperario.isEmpty) return const Center(child: Text('Sin datos'));

    final top = [..._porOperario]..sort((a, b) => b.total.compareTo(a.total));
    final items = top.take(6).toList();
    final maxY = items.first.total.toDouble();

    return BarChart(
      BarChartData(
        maxY: maxY <= 0 ? 5 : maxY * 1.25,
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (v, meta) => Text(
                v.toInt().toString(),
                style: const TextStyle(fontSize: 10, color: Colors.black87),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= items.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SizedBox(
                    width: 56,
                    child: Text(
                      items[i].nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (int i = 0; i < items.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: items[i].total.toDouble(),
                  width: 16,
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(6),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _barTopConjuntos() {
    if (_porConjunto.isEmpty) return const Center(child: Text('Sin datos'));

    final top = [..._porConjunto]..sort((a, b) => b.total.compareTo(a.total));
    final items = top.take(6).toList();
    final maxY = items.first.total.toDouble();

    return BarChart(
      BarChartData(
        maxY: maxY <= 0 ? 5 : maxY * 1.25,
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (v, meta) => Text(
                v.toInt().toString(),
                style: const TextStyle(fontSize: 10, color: Colors.black87),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= items.length) return const SizedBox.shrink();
                final name = items[i].conjuntoNombre.isNotEmpty
                    ? items[i].conjuntoNombre
                    : items[i].conjuntoId;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SizedBox(
                    width: 56,
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (int i = 0; i < items.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: items[i].total.toDouble(),
                  width: 16,
                  color: AppTheme.primary.withOpacity(.8),
                  borderRadius: BorderRadius.circular(6),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ======================= TAB: CONJUNTOS =======================

  Widget _tabConjuntos() {
    if (_porConjunto.isEmpty) return const Center(child: Text('Sin datos'));

    final sorted = [..._porConjunto]
      ..sort((a, b) => b.total.compareTo(a.total));
    final top = sorted.take(10).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionTitle('Top Conjuntos (10)'),
        const SizedBox(height: 8),
        _card(child: SizedBox(height: 280, child: _barTopConjuntos())),
        const SizedBox(height: 14),
        _sectionTitle('Detalle'),
        const SizedBox(height: 8),
        ...top.map((r) {
          final total = r.total <= 0 ? 1 : r.total;
          final aprob = r.aprobadas / total;
          final rech = r.rechazadas / total;
          final noComp = r.noCompletadas / total;

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.conjuntoNombre.isNotEmpty
                        ? r.conjuntoNombre
                        : r.conjuntoId,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'NIT: ${r.nit}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 10),
                  _miniRatioBar('Aprobadas', aprob),
                  const SizedBox(height: 6),
                  _miniRatioBar('Rechazadas', rech),
                  const SizedBox(height: 6),
                  _miniRatioBar('No completadas', noComp),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    children: [
                      _miniPill('Total', r.total),
                      _miniPill('Aprob', r.aprobadas),
                      _miniPill('Rech', r.rechazadas),
                      _miniPill('NoComp', r.noCompletadas),
                      _miniPill('Pend', r.pendientesAprobacion),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _miniRatioBar(String label, double ratio) {
    final p = ratio.clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: p,
              minHeight: 10,
              backgroundColor: Colors.black12,
              color: AppTheme.primary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 44,
          child: Text(
            '${(p * 100).toStringAsFixed(0)}%',
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  // ======================= TAB: OPERARIOS =======================

  Widget _tabOperarios() {
    if (_porOperario.isEmpty) return const Center(child: Text('Sin datos'));

    final sorted = [..._porOperario]
      ..sort((a, b) => b.total.compareTo(a.total));
    final top = sorted.take(12).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionTitle('Top Operarios (6)'),
        const SizedBox(height: 8),
        _card(child: SizedBox(height: 280, child: _barTopOperarios())),
        const SizedBox(height: 14),
        _sectionTitle('Ranking (12)'),
        const SizedBox(height: 8),
        ...top.map((r) {
          final total = r.total <= 0 ? 1 : r.total;
          final aprob = r.aprobadas / total;
          final rech = r.rechazadas / total;

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.nombre,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ID: ${r.operarioId} • Prom: ${r.minutosPromedio} min',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 10),
                  _miniRatioBar('Aprobadas', aprob),
                  const SizedBox(height: 6),
                  _miniRatioBar('Rechazadas', rech),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    children: [
                      _miniPill('Total', r.total),
                      _miniPill('Aprob', r.aprobadas),
                      _miniPill('Rech', r.rechazadas),
                      _miniPill('NoComp', r.noCompletadas),
                      _miniPill('Pend', r.pendientesAprobacion),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ======================= TAB: INSUMOS =======================

  Widget _tabInsumos() {
    if (_conjuntoId == null) {
      return const Center(
        child: Text('Para ver Insumos, escribe un conjuntoId arriba.'),
      );
    }
    if (_insumos.isEmpty) {
      return const Center(child: Text('Sin consumos en este rango.'));
    }

    final sorted = [..._insumos]
      ..sort((a, b) => b.cantidad.compareTo(a.cantidad));
    final top = sorted.take(12).toList();
    final maxQty = top.first.cantidad <= 0 ? 1.0 : top.first.cantidad;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionTitle('Top Insumos (12) por cantidad'),
        const SizedBox(height: 8),
        _card(
          child: SizedBox(
            height: 320,
            child: BarChart(
              BarChartData(
                maxY: maxQty * 1.25,
                gridData: const FlGridData(show: true),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 38,
                      getTitlesWidget: (v, meta) => Text(
                        v.toInt().toString(),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, meta) {
                        final i = v.toInt();
                        if (i < 0 || i >= top.length)
                          return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: SizedBox(
                            width: 70,
                            child: Text(
                              top[i].nombre,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (int i = 0; i < top.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: top[i].cantidad,
                          width: 12,
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _sectionTitle('Detalle'),
        const SizedBox(height: 8),
        ...top.map((r) {
          final p = (r.cantidad / maxQty).clamp(0.0, 1.0);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.nombre,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: p,
                      minHeight: 10,
                      backgroundColor: Colors.black12,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Cantidad: ${r.cantidad.toStringAsFixed(2)} ${r.unidad} • Usos: ${r.usos}',
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ======================= TAB: MAQ/HERR =======================

  Widget _tabMaqHerr() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionTitle('Top Maquinaria (por usos)'),
        const SizedBox(height: 8),
        _maq.isEmpty
            ? const _EmptyCard(text: 'Sin datos')
            : _card(child: _topListChart(_maq, valueLabel: 'Usos')),
        const SizedBox(height: 14),
        _sectionTitle('Top Herramientas (por usos)'),
        const SizedBox(height: 8),
        _herr.isEmpty
            ? const _EmptyCard(text: 'Sin datos')
            : _card(child: _topListChart(_herr, valueLabel: 'Usos')),
      ],
    );
  }

  Widget _topListChart(List<UsoEquipoRow> rows, {required String valueLabel}) {
    final sorted = [...rows]..sort((a, b) => b.usos.compareTo(a.usos));
    final top = sorted.take(10).toList();
    final maxUsos = top.first.usos <= 0 ? 1 : top.first.usos;

    return Column(
      children: [
        SizedBox(
          height: 240,
          child: BarChart(
            BarChartData(
              maxY: maxUsos.toDouble() * 1.25,
              gridData: const FlGridData(show: true),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 34,
                    getTitlesWidget: (v, meta) => Text(
                      v.toInt().toString(),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, meta) {
                      final i = v.toInt();
                      if (i < 0 || i >= top.length)
                        return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: SizedBox(
                          width: 64,
                          child: Text(
                            top[i].nombre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (int i = 0; i < top.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: top[i].usos.toDouble(),
                        width: 12,
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        ...top.map((r) {
          final p = (r.usos / maxUsos).clamp(0.0, 1.0);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    r.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 120,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: p,
                      minHeight: 10,
                      backgroundColor: Colors.black12,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 70,
                  child: Text(
                    '$valueLabel: ${r.usos}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ======================= TAB: TIPOS =======================

  Widget _tabTipos() {
    if (_tareasDetalle.isEmpty)
      return const Center(child: Text('Sin datos en el rango.'));

    final tipos = _contarTipos();
    final prev = tipos['preventivas'] ?? 0;
    final corr = tipos['correctivas'] ?? 0;
    final total = math.max(1, prev + corr);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionTitle('Preventivas vs Correctivas'),
        const SizedBox(height: 8),
        _card(
          child: SizedBox(
            height: 260,
            child: Row(
              children: [
                Expanded(
                  child: _pieTipos(prev: prev, corr: corr),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 190,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _legendItem(
                        'Preventivas',
                        prev,
                        prev / total,
                        AppTheme.primary,
                      ),
                      const SizedBox(height: 10),
                      _legendItem(
                        'Correctivas',
                        corr,
                        corr / total,
                        AppTheme.primary.withOpacity(.55),
                      ),
                      const Spacer(),
                      Text(
                        'Total: ${prev + corr}',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        _sectionTitle('Distribución por estado'),
        const SizedBox(height: 8),
        _card(
          child: SizedBox(
            height: 260,
            child: _pieEstados(_kpis?.byEstado ?? {}),
          ),
        ),
      ],
    );
  }

  Widget _pieTipos({required int prev, required int corr}) {
    final total = prev + corr;
    if (total <= 0) return const Center(child: Text('Sin datos'));

    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 44,
        sections: [
          PieChartSectionData(
            value: prev.toDouble(),
            title: (prev / total) >= 0.08
                ? '${(prev / total * 100).toStringAsFixed(0)}%'
                : '',
            radius: 70,
            titleStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
            color: AppTheme.primary,
          ),
          PieChartSectionData(
            value: corr.toDouble(),
            title: (corr / total) >= 0.08
                ? '${(corr / total * 100).toStringAsFixed(0)}%'
                : '',
            radius: 70,
            titleStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
            color: AppTheme.primary.withOpacity(.55),
          ),
        ],
      ),
    );
  }

  Widget _legendItem(String label, int value, double ratio, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.black87,
            ),
          ),
        ),
        Text(
          '$value (${(ratio * 100).toStringAsFixed(0)}%)',
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }

  // ======================= TAB: INFORMES =======================

  Widget _tabInformes() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionTitle('Informes automáticos'),
        const SizedBox(height: 8),
        _card(
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (_kpis == null || _generandoPdf)
                      ? null
                      : _generarInformeGestionPdf,
                  icon: _generandoPdf
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.insights),
                  label: Text(_generandoPdf ? 'Generando...' : 'Gestión (PDF)'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _tareasDetalle.isEmpty
                      ? null
                      : _generarInformeDetalladoPdf,
                  icon: const Icon(Icons.list_alt),
                  label: const Text('Detallado (PDF)'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _sectionTitle('Tareas del rango (tap para ver detalle)'),
        const SizedBox(height: 8),

        if (_tareasDetalle.isEmpty)
          const _EmptyCard(text: 'Sin tareas en este rango.')
        else
          ListView.builder(
            itemCount: _tareasDetalle.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemBuilder: (_, i) {
              final t = _tareasDetalle[i];
              final df = DateFormat('dd/MM HH:mm', 'es');

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  onTap: () => _openTareaModal(t),
                  child: _card(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withOpacity(.10),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            t.tipo,
                            style: TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.descripcion,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${t.estado} • ${df.format(t.fechaInicio)} → ${df.format(t.fechaFin)} • ${t.duracionMinutos} min',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Evidencias: ${t.evidencias.length}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  // ======================= MODAL PRO =======================

  void _openTareaModal(TareaDetalleRow t) {
    final df = DateFormat('dd/MM/yyyy HH:mm', 'es');

    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    _chipBadge(t.tipo),
                    const SizedBox(width: 8),
                    _chipState(t.estado),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      label: const Text('Cerrar'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                Text(
                  t.descripcion,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'ID ${t.id}',
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 12),

                // Info principal
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _kv('Inicio', df.format(t.fechaInicio)),
                      _kv('Fin', df.format(t.fechaFin)),
                      _kv('Duración', '${t.duracionMinutos} min'),
                      if ((t.ubicacion ?? '').isNotEmpty)
                        _kv('Ubicación', t.ubicacion!),
                      if ((t.elemento ?? '').isNotEmpty)
                        _kv('Elemento', t.elemento!),
                      if ((t.supervisor ?? '').isNotEmpty)
                        _kv('Supervisor', t.supervisor!),
                      if (t.operarios.isNotEmpty)
                        _kv('Operarios', t.operarios.join(', ')),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                _resourceTable(
                  title: 'Insumos',
                  rows: t.insumos,
                  columns: const ['nombre', 'cantidad', 'unidad'],
                ),
                const SizedBox(height: 10),
                _resourceTable(
                  title: 'Maquinaria',
                  rows: t.maquinaria,
                  columns: const ['nombre', 'cantidad'],
                ),
                const SizedBox(height: 10),
                _resourceTable(
                  title: 'Herramientas',
                  rows: t.herramientas,
                  columns: const ['nombre', 'cantidad'],
                ),

                const SizedBox(height: 14),
                _sectionTitle('Evidencias'),
                const SizedBox(height: 8),

                if (t.evidencias.isEmpty)
                  const Text(
                    'Sin evidencias',
                    style: TextStyle(color: Colors.black54),
                  )
                else
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: t.evidencias.take(12).map((e) {
                      final viewUrl = _driveViewUrl(e);
                      return InkWell(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (_) => Dialog(
                              child: InteractiveViewer(
                                child: Image.network(
                                  viewUrl,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          );
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 150,
                            height: 110,
                            color: Colors.black12,
                            child: Image.network(
                              viewUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Center(
                                child: Icon(Icons.image_not_supported),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chipBadge(String txt) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.primary.withOpacity(.25)),
      ),
      child: Text(
        txt,
        style: TextStyle(
          color: AppTheme.primary,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _chipState(String txt) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.04),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
      ),
      child: Text(
        txt,
        style: const TextStyle(
          color: Colors.black87,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        '$k: $v',
        style: const TextStyle(fontSize: 12, color: Colors.black87),
      ),
    );
  }

  String _driveViewUrl(String url) {
    try {
      if (url.contains('uc?export=view') || url.contains('uc?id=')) return url;

      final reg = RegExp(r'/d/([^/]+)');
      final m = reg.firstMatch(url);
      if (m != null) {
        final id = m.group(1);
        return 'https://drive.google.com/uc?export=view&id=$id';
      }
    } catch (_) {}
    return url;
  }

  /// Tabla “bonita” (sin DataTable para que no se rompa en web)
  Widget _resourceTable({
    required String title,
    required List<Map<String, dynamic>> rows,
    required List<String> columns,
  }) {
    if (rows.isEmpty) {
      return _card(
        child: Text(
          '$title: Sin datos',
          style: const TextStyle(color: Colors.black87),
        ),
      );
    }

    String cell(Map<String, dynamic> r, String k) =>
        (r[k] ?? '').toString().trim();

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),

          // header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black12),
            ),
            child: Row(
              children: [
                for (final c in columns)
                  Expanded(
                    flex: (c == 'nombre') ? 3 : 2,
                    child: Text(
                      c.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: Colors.black54,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          ...rows.take(12).map((r) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.black12),
                ),
                child: Row(
                  children: [
                    for (final c in columns)
                      Expanded(
                        flex: (c == 'nombre') ? 3 : 2,
                        child: Text(
                          cell(r, c).isEmpty ? '-' : cell(r, c),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ======================= helpers =======================

  Widget _miniPill(String label, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
        color: Colors.white,
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Colors.black87,
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String text;
  const _EmptyCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Center(
        child: Text(text, style: const TextStyle(color: Colors.black87)),
      ),
    );
  }
}
