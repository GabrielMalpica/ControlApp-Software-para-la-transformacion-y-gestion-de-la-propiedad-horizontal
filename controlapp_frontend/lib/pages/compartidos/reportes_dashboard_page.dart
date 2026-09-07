// ignore_for_file: curly_braces_in_flow_control_structures, prefer_interpolation_to_compose_strings

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../utils/frecuencia_utils.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_application_1/api/reporte_api.dart';
import 'package:flutter_application_1/model/reporte_model.dart';
import 'package:flutter_application_1/pdf/pdf_download.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/chart_capture.dart';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:flutter_application_1/service/chart_style.dart';
import 'package:flutter_application_1/service/session_service.dart';
import 'package:flutter_application_1/service/theme.dart';
import 'package:flutter_application_1/utils/duration_format.dart';
import 'package:flutter_application_1/utils/evidence_utils.dart';
import 'package:flutter_application_1/widgets/evidencia_gallery.dart';
import 'package:flutter_application_1/widgets/skeleton.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import 'package:flutter_application_1/service/app_feedback.dart';

class ReportesDashboardPage extends StatefulWidget {
  final String? conjuntoIdInicial;
  final bool modoGeneral;
  final bool permitirInformesPdf;
  final bool soloResumenTipos;
  const ReportesDashboardPage({
    super.key,
    this.conjuntoIdInicial,
    this.modoGeneral = false,
    this.permitirInformesPdf = true,
    this.soloResumenTipos = false,
  });

  @override
  State<ReportesDashboardPage> createState() => _ReportesDashboardPageState();
}

class _ReportesDashboardPageState extends State<ReportesDashboardPage> {
  final _api = ReporteApi();

  late DateTime _desde;
  late DateTime _hasta;

  late final String? _conjuntoIdFijo;
  bool get _esReporteGeneral => widget.modoGeneral;
  bool get _permitirInformesPdf => widget.permitirInformesPdf;
  bool get _soloResumenTipos => widget.soloResumenTipos;

  bool _loading = false;
  bool _generandoPdf = false;
  String? _error;

  ReporteKpis? _kpis;
  SerieDiariaPorEstado? _serie;
  ReporteCompromisosDashboard? _compromisosReporte;
  List<ResumenConjuntoRow> _porConjunto = [];
  List<ResumenOperarioRow> _porOperario = [];
  List<InsumoUsoRow> _insumos = [];
  List<UsoEquipoRow> _maq = [];
  List<UsoEquipoRow> _herr = [];

  // ✅ Informes usa tareas detalle
  List<TareaDetalleRow> _tareasDetalle = [];

  // Calendario de "Tareas del rango" (tab Informes)
  late DateTime _calMes;
  DateTime? _calDia;
  bool _verTodasLasTareas = false;

  // IDs de operarios con la tarjeta de "Ranking y carga" expandida.
  final Set<String> _operariosExpandidos = {};

  // ✅ Keys para capturar charts (Offstage + RepaintBoundary)
  final GlobalKey _kPieEstados = GlobalKey();
  final GlobalKey _kLineSerie = GlobalKey();
  final GlobalKey _kPieTipos = GlobalKey();
  final GlobalKey _kBarInsumos = GlobalKey();

  /// =========================
  ///  ✅ ANÁLISIS EDITABLES
  /// =========================
  late final _a11Ctrl = TextEditingController();
  late final _p11Ctrl = TextEditingController();

  late final _a12Ctrl = TextEditingController();
  late final _p12Ctrl = TextEditingController();

  late final _a13Ctrl = TextEditingController();
  late final _p13Ctrl = TextEditingController();

  late final _a14Ctrl = TextEditingController();
  late final _p14Ctrl = TextEditingController();

  /// Si luego quieres IA: aquí queda el “hueco” (por ahora genera texto básico).
  bool _analisisInicializado = false;

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();
    _desde = DateTime(now.year, now.month, 1);
    _hasta = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    _calMes = DateTime(_desde.year, _desde.month);

    final ref = widget.conjuntoIdInicial?.trim();
    _conjuntoIdFijo = _esReporteGeneral
        ? null
        : (ref == null || ref.isEmpty)
        ? null
        : ref;
    _cargarTodo();
  }

  @override
  void dispose() {
    _a11Ctrl.dispose();
    _p11Ctrl.dispose();
    _a12Ctrl.dispose();
    _p12Ctrl.dispose();
    _a13Ctrl.dispose();
    _p13Ctrl.dispose();
    _a14Ctrl.dispose();
    _p14Ctrl.dispose();

    super.dispose();
  }

  String? get _conjuntoId => _conjuntoIdFijo;

  Future<void> _cargarTodo() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final conjuntoId = _conjuntoId;
      if (!_esReporteGeneral && conjuntoId == null) {
        throw Exception(
          'No se recibió el conjuntoId/NIT. Esta página solo funciona por conjunto.',
        );
      }

      // Las 8 peticiones de abajo son independientes entre si (ninguna usa el
      // resultado de otra), asi que se disparan en paralelo en vez de en
      // cascada. Solo "insumos" depende de "porConjunto" (para el modo
      // reporte general), por eso se pide despues.
      final resultados = await Future.wait([
        _api.kpis(
          desde: _desde,
          hasta: _hasta,
          conjuntoId: _esReporteGeneral ? null : conjuntoId,
        ),
        _api.serieDiaria(
          desde: _desde,
          hasta: _hasta,
          conjuntoId: _esReporteGeneral ? null : conjuntoId,
        ),
        _api.compromisosDashboard(
          desde: _desde,
          hasta: _hasta,
          conjuntoId: _esReporteGeneral ? null : conjuntoId,
        ),
        _api.resumenPorConjunto(desde: _desde, hasta: _hasta),
        _api.resumenPorOperario(
          desde: _desde,
          hasta: _hasta,
          conjuntoId: _esReporteGeneral ? null : conjuntoId,
        ),
        _api.topMaquinaria(
          desde: _desde,
          hasta: _hasta,
          conjuntoId: _esReporteGeneral ? null : conjuntoId,
        ),
        _api.topHerramientas(
          desde: _desde,
          hasta: _hasta,
          conjuntoId: _esReporteGeneral ? null : conjuntoId,
        ),
        // ✅ NUEVO: tareas detalle (correctivas + preventivas)
        _api.mensualDetalle(
          desde: _desde,
          hasta: _hasta,
          conjuntoId: _esReporteGeneral ? null : conjuntoId,
        ),
      ]);

      final kpis = resultados[0] as ReporteKpis;
      final serie = resultados[1] as SerieDiariaPorEstado;
      final compromisos = resultados[2] as ReporteCompromisosDashboard;
      final porConjunto = resultados[3] as List<ResumenConjuntoRow>;
      final porOperario = resultados[4] as List<ResumenOperarioRow>;
      final maq = resultados[5] as List<UsoEquipoRow>;
      final herr = resultados[6] as List<UsoEquipoRow>;
      final tareasDetalle = resultados[7] as List<TareaDetalleRow>;

      // Sin conjuntoId, el backend agrega el uso de insumos de toda la
      // empresa en una sola consulta (antes se pedia conjunto por conjunto).
      final insumos = await _api.usoInsumos(
        conjuntoId: _esReporteGeneral ? null : conjuntoId,
        desde: _desde,
        hasta: _hasta,
      );

      final porConjuntoFiltrado = _esReporteGeneral
          ? porConjunto
          : porConjunto
                .where((r) => _matchesConjuntoRef(r, conjuntoId!))
                .toList();

      if (!mounted) return;
      setState(() {
        _kpis = kpis;
        _serie = serie;
        _compromisosReporte = compromisos;
        _porConjunto = porConjuntoFiltrado;
        _porOperario = porOperario;
        _insumos = insumos;
        _maq = maq;
        _herr = herr;
        _tareasDetalle = tareasDetalle;
      });

      // ✅ inicializa los análisis solo una vez (editable por usuario)
      if (!_analisisInicializado) {
        _seedAnalisisEditable();
        _analisisInicializado = true;
      } else {
        // si quieres que al cambiar rango se regenere, puedes poner un botón “Regenerar”
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AppError.messageOf(e));
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
      _analisisInicializado = false; // para que regenere en el próximo cargar
      _calMes = DateTime(_desde.year, _desde.month);
      _calDia = null;
      _verTodasLasTareas = false;
    });
    _cargarTodo();
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Expande cada tarea de fechaInicio a fechaFin (recortado al rango) para
  /// que las multidia cuenten en cada dia que abarcan.
  Map<DateTime, List<TareaDetalleRow>> _agruparTareasPorDia() {
    final map = <DateTime, List<TareaDetalleRow>>{};
    final rangoDesde = _dateOnly(_desde);
    final rangoHasta = _dateOnly(_hasta);

    for (final t in _tareasDetalle) {
      var inicio = _dateOnly(t.fechaInicio);
      var fin = _dateOnly(t.fechaFin);
      if (fin.isBefore(inicio))
        fin = inicio; // fecha corrupta -> solo el dia de inicio
      if (inicio.isBefore(rangoDesde)) inicio = rangoDesde;
      if (fin.isAfter(rangoHasta)) fin = rangoHasta;
      if (fin.isBefore(inicio)) continue;

      var cursor = inicio;
      var guard = 0;
      while (!cursor.isAfter(fin) && guard < 400) {
        map.putIfAbsent(cursor, () => []).add(t);
        cursor = cursor.add(const Duration(days: 1));
        guard++;
      }
    }
    return map;
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

  // ===================== ANÁLISIS “BÁSICO” + EDITABLE =====================

  void _seedAnalisisEditable() {
    final k = _kpis;
    if (k == null) return;

    final kd = k.kpi;
    final conteoTipos = _contarTipos();
    final prev = conteoTipos['preventivas'] ?? 0;
    final corr = conteoTipos['correctivas'] ?? 0;

    // 1.1 Tipos
    if (prev + corr == 0) {
      _a11Ctrl.text = 'No se registran tareas en el periodo seleccionado.';
      _p11Ctrl.text = 'Validar programación y confirmar operación del periodo.';
    } else if (corr > prev) {
      _a11Ctrl.text =
          'Se observa mayor proporción de correctivas frente a preventivas. '
          'Esto suele indicar recurrencia de fallas o baja ejecución preventiva.';
      _p11Ctrl.text =
          'Reforzar plan preventivo, revisar causas raíz de correctivas repetidas y priorizar actividades de control.';
    } else {
      _a11Ctrl.text =
          'La ejecución preventiva se mantiene estable frente a las correctivas. '
          'Esto contribuye a reducir incidencias y mejorar continuidad del servicio.';
      _p11Ctrl.text =
          'Mantener programación preventiva y monitorear correctivas para evitar recurrencia.';
    }

    // 1.2 Estados
    if (k.total == 0) {
      _a12Ctrl.text = 'No hay datos de estados porque no se registran tareas.';
      _p12Ctrl.text = 'Confirmar operación/cargue de tareas.';
    } else {
      final tasa = kd.tasaCierrePct;
      final rej = kd.rechazadas;
      final nocomp = kd.noCompletadas;
      final noCompPorReemplazo = _tareasDetalle
          .where((t) => t.noCompletadaPorReemplazo)
          .length;
      final pend = kd.pendientesAprobacion;

      if (tasa < 75) {
        _a12Ctrl.text =
            'La tasa de cierre es baja ($tasa%). Se evidencian tareas pendientes o con cierre tardío.';
      } else if (tasa < 90) {
        _a12Ctrl.text =
            'La tasa de cierre es media ($tasa%). Existe oportunidad de mejorar tiempos y aprobaciones.';
      } else {
        _a12Ctrl.text =
            'La tasa de cierre es alta ($tasa%). El flujo operativo muestra buen control del cierre.';
      }

      final bullets = <String>[];
      if (rej > 0) {
        bullets.add('Rechazadas: $rej (revisar causas y evidencias).');
      }
      if (nocomp > 0) {
        bullets.add(
          'No completadas: $nocomp (validar accesos/insumos/tiempos).',
        );
      }
      if (noCompPorReemplazo > 0) {
        bullets.add(
          'No completadas por reemplazo: $noCompPorReemplazo (confirmar trazabilidad con correctivas que las reemplazaron).',
        );
      }
      if (pend > 0) {
        bullets.add('Pendientes aprobación: $pend (acelerar VoBo).');
      }
      _a12Ctrl.text += bullets.isEmpty
          ? ''
          : '\n' + bullets.map((e) => '• $e').join('\n');

      _p12Ctrl.text =
          'Estandarizar evidencias, validar checklist de cierre y asegurar aprobación oportuna con administración/interventoría.';
    }

    // 1.3 Serie diaria
    final s = _serie;
    if (s == null || s.days.isEmpty) {
      _a13Ctrl.text = 'No hay serie diaria disponible para el periodo.';
      _p13Ctrl.text =
          'Validar que el endpoint de serie diaria esté retornando datos.';
    } else {
      // picos simples
      int maxVal = 0;
      String? maxDay;
      for (final d in s.days) {
        final m = s.series[d] ?? {};
        final total = m.values.fold<int>(0, (a, b) => a + b);
        if (total > maxVal) {
          maxVal = total;
          maxDay = d;
        }
      }
      _a13Ctrl.text =
          'La tendencia diaria muestra variación de carga. '
          '${maxDay != null ? 'Mayor pico el día $maxDay con $maxVal tareas.' : ''}';
      _p13Ctrl.text =
          'Balancear carga en días pico, confirmar disponibilidad de personal y priorizar tareas críticas.';
    }

    // 1.4 Insumos
    if (!_esReporteGeneral && _conjuntoId == null) {
      _a14Ctrl.text = 'No se recibió conjuntoId/NIT para analizar insumos.';
      _p14Ctrl.text =
          'Abrir esta página desde un conjunto válido y regenerar el informe.';
    } else if (_insumos.isEmpty) {
      _a14Ctrl.text = 'No se registran consumos de insumos en el periodo.';
      _p14Ctrl.text =
          'Validar cargue de insumos en cierre de tareas y control de inventarios.';
    } else {
      final top = [..._insumos]
        ..sort((a, b) => b.cantidad.compareTo(a.cantidad));
      final t = top.first;
      _a14Ctrl.text =
          '${_esReporteGeneral ? 'Consolidado de todos los conjuntos del periodo. ' : ''}'
          'Se evidencia consumo de insumos asociado a la operación del periodo. '
          'Insumo principal: ${t.nombre} (${t.cantidad.toStringAsFixed(2)} ${t.unidad}).';
      _p14Ctrl.text =
          '${_esReporteGeneral ? 'Priorizar control de abastecimiento global y estandarizar consumos entre conjuntos. ' : ''}'
          'Revisar reposición, validar rendimientos y evitar sobreconsumo. Mantener control por tarea.';
    }
  }

  Future<void> _regenerarAnalisis() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿Regenerar texto base?'),
        content: const Text(
          'Esto reemplaza los 4 análisis y planes de acción con el texto '
          'sugerido automáticamente. Se perderá lo que hayas escrito a mano.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Regenerar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    setState(() {
      _seedAnalisisEditable();
    });
  }

  int _analisisConTexto() {
    final pares = [_a11Ctrl, _a12Ctrl, _a13Ctrl, _a14Ctrl];
    return pares.where((c) => c.text.trim().isNotEmpty).length;
  }

  // ======================= PDF =======================

  /// Captura charts del host offscreen (robusto)
  Future<Map<String, Uint8List>> _captureChartsForPdf() async {
    // 2 frames + pequeño delay para asegurar paint estable (web)
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    await Future.delayed(const Duration(milliseconds: 120));
    await WidgetsBinding.instance.endOfFrame;

    final pr = kIsWeb ? 3.0 : 2.0;

    final pngEstados = await capturePngFromKey(_kPieEstados, pixelRatio: pr);
    final pngSerie = await capturePngFromKey(_kLineSerie, pixelRatio: pr);
    final pngTipos = await capturePngFromKey(_kPieTipos, pixelRatio: pr);
    final pngInsumos = await capturePngFromKey(_kBarInsumos, pixelRatio: pr);

    return {
      'estados': pngEstados,
      'serie': pngSerie,
      'tipos': pngTipos,
      'insumos': pngInsumos,
    };
  }

  List<String> _evidenceUrlCandidates(String raw) => evidenceUrlCandidates(raw);

  String _normalizeConjuntoRef(String value) {
    return value.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  bool _matchesConjuntoRef(ResumenConjuntoRow row, String ref) {
    if (row.conjuntoId.trim() == ref || row.nit.trim() == ref) return true;
    final normRef = _normalizeConjuntoRef(ref);
    if (normRef.isEmpty) return false;
    return _normalizeConjuntoRef(row.conjuntoId) == normRef ||
        _normalizeConjuntoRef(row.nit) == normRef;
  }

  String _safeFile(String s) {
    final x = s
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return x.isEmpty ? 'sin_nombre' : x;
  }

  String _conjuntoNombreForReport() {
    if (_esReporteGeneral) return 'TODOS';

    final id = _conjuntoId;
    if (id == null) return 'SIN_CONJUNTO';

    final hit = _porConjunto.where((r) => _matchesConjuntoRef(r, id)).toList();
    if (hit.isNotEmpty && hit.first.conjuntoNombre.trim().isNotEmpty) {
      return hit.first.conjuntoNombre.trim();
    }
    return id;
  }

  // ignore: unused_element
  Future<void> _generarInformeGestionPdf() async {
    final k = _kpis;
    final s = _serie;
    if (k == null || s == null) return;

    setState(() => _generandoPdf = true);

    try {
      final charts = await _captureChartsForPdf();

      final fontRegular = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
      );
      final fontBold = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
      );

      final doc = pw.Document();

      final rangoFmt = DateFormat('dd/MM/yyyy', 'es');
      final fechaHoraFmt = DateFormat('dd/MM/yyyy HH:mm', 'es');
      final mesNombre = DateFormat('MMMM', 'es').format(_desde);
      final anio = _desde.year.toString();
      final cliente = _conjuntoNombreForReport();
      final kd = k.kpi;
      final conteoTipos = _contarTipos();
      final totalPrev = conteoTipos['preventivas'] ?? 0;
      final totalCorr = conteoTipos['correctivas'] ?? 0;

      final topConjuntos = [..._porConjunto]
        ..sort((a, b) => b.total.compareTo(a.total));
      final topOperarios = [..._porOperario]
        ..sort((a, b) => b.total.compareTo(a.total));
      final topInsumos = [..._insumos]
        ..sort((a, b) => b.cantidad.compareTo(a.cantidad));

      final imageCache = <String, pw.ImageProvider>{};
      final evidenceImageByRaw = <String, pw.ImageProvider?>{};

      final evidenceAuthToken = await SessionService().getToken();

      Future<pw.ImageProvider?> loadEvidenceImage(String raw) async {
        final candidates = _evidenceUrlCandidates(raw);
        for (final u in candidates) {
          if (imageCache.containsKey(u)) return imageCache[u];
          try {
            final img = await networkImage(
              u,
              headers: u.startsWith(AppConstants.baseUrl)
                  ? {'Authorization': 'Bearer $evidenceAuthToken'}
                  : null,
            );
            imageCache[u] = img;
            return img;
          } catch (_) {
            // sigue con el siguiente candidato
          }
        }
        return null;
      }

      Future<void> preloadEvidence() async {
        final raws = _tareasDetalle
            .expand((t) => t.evidencias.take(4))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet();

        for (final raw in raws) {
          evidenceImageByRaw[raw] = await loadEvidenceImage(raw);
        }
      }

      await preloadEvidence();

      String miniList(List<Map<String, dynamic>> xs, {int max = 4}) {
        if (xs.isEmpty) return 'Sin datos';
        return xs
            .take(max)
            .map((m) {
              final n = (m['nombre'] ?? '-').toString();
              final c = (m['cantidad'] ?? '').toString();
              final u = (m['unidad'] ?? '').toString();
              final extra = [c, u].where((e) => e.trim().isNotEmpty).join(' ');
              return extra.isEmpty ? n : '$n ($extra)';
            })
            .join(' | ');
      }

      pw.Widget sectionTitle(String text) {
        return pw.Container(
          margin: const pw.EdgeInsets.only(top: 8, bottom: 6),
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromHex('#1F3A5F'),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Text(
            text,
            style: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        );
      }

      pw.Widget metricCard(String title, String value) {
        return pw.Container(
          width: 120,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                title,
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey700,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                value,
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromHex('#1F3A5F'),
                ),
              ),
            ],
          ),
        );
      }

      pw.Widget chartSection({
        required String title,
        required Uint8List imageBytes,
        required String analysis,
        required String actionPlan,
      }) {
        return pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 10),
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Container(
                height: 200,
                alignment: pw.Alignment.center,
                child: pw.Image(
                  pw.MemoryImage(imageBytes),
                  fit: pw.BoxFit.contain,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Análisis',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                analysis.trim().isEmpty ? '-' : analysis,
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'Plan de acción',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                actionPlan.trim().isEmpty ? '-' : actionPlan,
                style: const pw.TextStyle(fontSize: 9),
              ),
            ],
          ),
        );
      }

      pw.Widget tableOrEmpty({
        required String title,
        required List<String> headers,
        required List<List<String>> data,
      }) {
        return pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 10),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              if (data.isEmpty)
                pw.Text('Sin datos', style: pw.TextStyle(fontSize: 9))
              else
                pw.TableHelper.fromTextArray(
                  headers: headers,
                  data: data,
                  headerStyle: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                  headerDecoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#2A4A73'),
                  ),
                  cellStyle: const pw.TextStyle(fontSize: 8),
                  cellAlignments: {
                    for (int i = 0; i < headers.length; i++)
                      i: i == 0 ? pw.Alignment.centerLeft : pw.Alignment.center,
                  },
                ),
            ],
          ),
        );
      }

      pw.Widget evidenceTile(pw.ImageProvider? img) {
        return pw.Container(
          width: 120,
          height: 82,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: img == null
              ? pw.Center(
                  child: pw.Text(
                    'Sin imagen',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                )
              : pw.ClipRRect(
                  horizontalRadius: 4,
                  verticalRadius: 4,
                  child: pw.Image(img, fit: pw.BoxFit.cover),
                ),
        );
      }

      pw.Widget tareaBlock(TareaDetalleRow t) {
        final evid = t.evidencias.take(4).toList();
        final evidWidgets = <pw.Widget>[];
        final motivoNoComp = (t.motivoNoCompletada ?? '').trim();
        final motivoReemplazo = _replacementInfoText(t);
        final reemplazoWarn = _replacementWarn(t);
        final refReemplazo = t.reemplazadaPorTareaId != null
            ? '#${t.reemplazadaPorTareaId}${(t.reemplazadaPorDescripcion ?? '').trim().isNotEmpty ? " (${t.reemplazadaPorDescripcion})" : ""}'
            : null;

        for (final raw in evid) {
          final key = raw.trim();
          evidWidgets.add(evidenceTile(evidenceImageByRaw[key]));
        }

        if (evidWidgets.isEmpty) {
          evidWidgets.add(evidenceTile(null));
        }

        return pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 10),
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey500),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      '${t.tipo} | ${t.estado}',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromHex('#1F3A5F'),
                      ),
                    ),
                  ),
                  pw.Text(
                    'ID ${t.id}',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Text(t.descripcion, style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 4),
              pw.Text(
                'Inicio: ${fechaHoraFmt.format(t.fechaInicio)} | Fin: ${fechaHoraFmt.format(t.fechaFin)} | Duración: ${t.duracionMinutos} min',
                style: const pw.TextStyle(fontSize: 8),
              ),
              if ((t.ubicacion ?? '').isNotEmpty)
                pw.Text(
                  'Ubicación: ${t.ubicacion}',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              if ((t.elemento ?? '').isNotEmpty)
                pw.Text(
                  'Elemento: ${t.elemento}',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              if ((t.supervisor ?? '').isNotEmpty)
                pw.Text(
                  'Supervisor: ${t.supervisor}',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              if (t.operarios.isNotEmpty)
                pw.Text(
                  'Operarios: ${t.operarios.join(', ')}',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              if (t.reubicadaPorPlanificacion && t.fechaObjetivoPlan != null)
                pw.Container(
                  margin: const pw.EdgeInsets.only(top: 4),
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#EFF6FF'),
                    border: pw.Border.all(color: PdfColor.fromHex('#93C5FD')),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Text(
                    'Reubicada por planificación: objetivo ${DateFormat('dd/MM/yyyy').format(t.fechaObjetivoPlan!)}; ejecución ${DateFormat('dd/MM/yyyy').format(t.fechaInicio)}. ${(t.motivoPlanificacion ?? '').trim()}',
                    style: pw.TextStyle(
                      fontSize: 8,
                      color: PdfColor.fromHex('#1E3A8A'),
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              if (t.esTareaReemplazo)
                pw.Container(
                  margin: const pw.EdgeInsets.only(top: 4),
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex(
                      reemplazoWarn ? '#FFF7ED' : '#ECFDF5',
                    ),
                    border: pw.Border.all(
                      color: PdfColor.fromHex(
                        reemplazoWarn ? '#FDBA74' : '#86EFAC',
                      ),
                    ),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Text(
                    motivoReemplazo,
                    style: pw.TextStyle(
                      fontSize: 8,
                      color: PdfColor.fromHex(
                        reemplazoWarn ? '#9A3412' : '#166534',
                      ),
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              if (t.noCompletadaPorReemplazo || motivoNoComp.isNotEmpty)
                pw.Container(
                  margin: const pw.EdgeInsets.only(top: 4),
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#FEF2F2'),
                    border: pw.Border.all(color: PdfColor.fromHex('#FCA5A5')),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Text(
                    motivoNoComp.isNotEmpty
                        ? motivoNoComp
                        : (refReemplazo != null
                              ? 'No fue completada porque fue reemplazada por la correctiva $refReemplazo.'
                              : 'No fue completada por reemplazo.'),
                    style: pw.TextStyle(
                      fontSize: 8,
                      color: PdfColor.fromHex('#991B1B'),
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Insumos: ${miniList(t.insumos)}',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Text(
                'Maquinaria: ${miniList(t.maquinaria)}',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Text(
                'Herramientas: ${miniList(t.herramientas)}',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.SizedBox(height: 8),
              pw.Wrap(spacing: 8, runSpacing: 8, children: evidWidgets),
            ],
          ),
        );
      }

      final conjuntosTable = topConjuntos.take(10).map((r) {
        return [
          r.conjuntoNombre.trim().isEmpty ? r.conjuntoId : r.conjuntoNombre,
          r.total.toString(),
          r.aprobadas.toString(),
          r.rechazadas.toString(),
          r.noCompletadas.toString(),
        ];
      }).toList();

      final operariosTable = topOperarios.take(10).map((r) {
        return [
          r.nombre,
          r.total.toString(),
          r.aprobadas.toString(),
          r.rechazadas.toString(),
          r.minutosPromedio.toString(),
        ];
      }).toList();

      final insumosTable = topInsumos.take(10).map((r) {
        return [
          r.nombre,
          r.cantidad.toStringAsFixed(2),
          r.unidad,
          r.usos.toString(),
        ];
      }).toList();

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 24),
          theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
          header: (ctx) {
            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 10),
              child: pw.Row(
                children: [
                  pw.Text(
                    'INFORME DE GESTIÓN',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromHex('#1F3A5F'),
                    ),
                  ),
                  pw.Spacer(),
                  pw.Text(
                    '${rangoFmt.format(_desde)} - ${rangoFmt.format(_hasta)}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            );
          },
          footer: (ctx) {
            return pw.Container(
              margin: const pw.EdgeInsets.only(top: 10),
              child: pw.Row(
                children: [
                  pw.Text(
                    'Conjunto: $cliente',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                  pw.Spacer(),
                  pw.Text(
                    'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
              ),
            );
          },
          build: (_) {
            return [
              pw.Text(
                'Periodo: ${mesNombre.toUpperCase()} $anio',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Cliente/Conjunto: $cliente',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.SizedBox(height: 10),

              sectionTitle('1. Resumen Ejecutivo'),
              pw.Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  metricCard('Total tareas', k.total.toString()),
                  metricCard('Aprobadas', kd.aprobadas.toString()),
                  metricCard('Rechazadas', kd.rechazadas.toString()),
                  metricCard('No completadas', kd.noCompletadas.toString()),
                  metricCard(
                    'Pend. aprobación',
                    kd.pendientesAprobacion.toString(),
                  ),
                  metricCard('% cierre', '${kd.tasaCierrePct}%'),
                  metricCard('Preventivas', totalPrev.toString()),
                  metricCard('Correctivas', totalCorr.toString()),
                ],
              ),

              pw.SizedBox(height: 10),
              sectionTitle('2. Distribución y Tendencias'),
              chartSection(
                title: '2.1 Preventivas vs Correctivas',
                imageBytes: charts['tipos']!,
                analysis: _a11Ctrl.text,
                actionPlan: _p11Ctrl.text,
              ),
              chartSection(
                title: '2.2 Distribución por estado',
                imageBytes: charts['estados']!,
                analysis: _a12Ctrl.text,
                actionPlan: _p12Ctrl.text,
              ),
              chartSection(
                title: '2.3 Tareas por día (tendencia)',
                imageBytes: charts['serie']!,
                analysis: _a13Ctrl.text,
                actionPlan: _p13Ctrl.text,
              ),
              chartSection(
                title: '2.4 Uso de insumos',
                imageBytes: charts['insumos']!,
                analysis: _a14Ctrl.text,
                actionPlan: _p14Ctrl.text,
              ),

              sectionTitle('3. Rankings Operativos'),
              tableOrEmpty(
                title: 'Top conjuntos (10)',
                headers: ['Conjunto', 'Total', 'Aprob', 'Rech', 'NoComp'],
                data: conjuntosTable,
              ),
              tableOrEmpty(
                title: 'Top operarios (10)',
                headers: ['Operario', 'Total', 'Aprob', 'Rech', 'Min Prom'],
                data: operariosTable,
              ),
              tableOrEmpty(
                title: 'Top insumos (10)',
                headers: ['Insumo', 'Cantidad', 'Unidad', 'Usos'],
                data: insumosTable,
              ),

              sectionTitle('4. Registro Fotográfico y Tareas'),
              if (_tareasDetalle.isEmpty)
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Text(
                    'Sin tareas en el rango seleccionado.',
                    style: pw.TextStyle(fontSize: 9),
                  ),
                )
              else
                ..._tareasDetalle.map(tareaBlock),
            ];
          },
        ),
      );

      final bytes = await doc.save();
      final filename =
          'Informe_de_gestion_${_safeFile(cliente)}_${_safeFile(mesNombre)}_$anio.pdf';

      if (kIsWeb) {
        await downloadPdfWeb(bytes, filename);
      } else {
        await Printing.layoutPdf(name: filename, onLayout: (_) async => bytes);
      }
    } catch (e, st) {
      debugPrint('Error PDF Gestión: $e\n$st');
      if (mounted) {
        AppFeedback.showFromSnackBar(
          context,
          SnackBar(content: Text('Error generando PDF: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _generandoPdf = false;
        });
      }
    }
  }

  // ======================= PDF DETALLADO (tu versión) =======================

  // ignore: unused_element
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
              final motivoNoComp = (t.motivoNoCompletada ?? '').trim();
              final refReemplazo = t.reemplazadaPorTareaId != null
                  ? '#${t.reemplazadaPorTareaId}${(t.reemplazadaPorDescripcion ?? '').trim().isNotEmpty ? " (${t.reemplazadaPorDescripcion})" : ""}'
                  : null;
              final motivoReemplazo = _replacementInfoText(t);
              final reemplazoWarn = _replacementWarn(t);

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
                    if (t.esTareaReemplazo)
                      pw.Container(
                        margin: const pw.EdgeInsets.only(top: 4),
                        padding: const pw.EdgeInsets.all(6),
                        decoration: pw.BoxDecoration(
                          color: PdfColor.fromHex(
                            reemplazoWarn ? '#FFF7ED' : '#ECFDF5',
                          ),
                          border: pw.Border.all(
                            color: PdfColor.fromHex(
                              reemplazoWarn ? '#FDBA74' : '#86EFAC',
                            ),
                          ),
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: pw.Text(
                          motivoReemplazo,
                          style: pw.TextStyle(
                            fontSize: 9,
                            color: PdfColor.fromHex(
                              reemplazoWarn ? '#9A3412' : '#166534',
                            ),
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                    if (t.noCompletadaPorReemplazo || motivoNoComp.isNotEmpty)
                      pw.Container(
                        margin: const pw.EdgeInsets.only(top: 4),
                        padding: const pw.EdgeInsets.all(6),
                        decoration: pw.BoxDecoration(
                          color: PdfColor.fromHex('#FEF2F2'),
                          border: pw.Border.all(
                            color: PdfColor.fromHex('#FCA5A5'),
                          ),
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: pw.Text(
                          motivoNoComp.isNotEmpty
                              ? motivoNoComp
                              : (refReemplazo != null
                                    ? 'No fue completada porque fue reemplazada por la correctiva $refReemplazo.'
                                    : 'No fue completada por reemplazo.'),
                          style: pw.TextStyle(
                            fontSize: 9,
                            color: PdfColor.fromHex('#991B1B'),
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
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
                        children: evid.take(8).map((u) {
                          return pw.Text(
                            '- $u',
                            style: const pw.TextStyle(fontSize: 9),
                          );
                        }).toList(),
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
    final mes = DateFormat('MMMM', 'es').format(_desde);
    final anio = DateFormat('yyyy', 'es').format(_desde);
    final conjunto = _safeFile(_conjuntoNombreForReport());

    final filename =
        'Informe_detallado_${conjunto}_${_safeFile(mes)}_$anio.pdf';

    if (kIsWeb) {
      await downloadPdfWeb(bytes, filename);
    } else {
      await Printing.layoutPdf(name: filename, onLayout: (_) async => bytes);
    }
  }

  Future<void> _generarInformeGestionPdfV2() async {
    if (_kpis == null) return;

    setState(() => _generandoPdf = true);

    try {
      final charts = await _captureChartsForPdf();

      final fontRegular = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
      );
      final fontBold = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
      );

      final doc = pw.Document();
      final rangoFmt = DateFormat('dd/MM/yyyy', 'es');
      final mesNombre = DateFormat('MMMM', 'es').format(_desde);
      final anio = _desde.year.toString();
      final cliente = _conjuntoNombreForReport();

      pw.Widget chartSection({
        required String title,
        required Uint8List imageBytes,
        required String analysis,
        required String actionPlan,
      }) {
        return pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 10),
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Container(
                height: 200,
                alignment: pw.Alignment.center,
                child: pw.Image(
                  pw.MemoryImage(imageBytes),
                  fit: pw.BoxFit.contain,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Analisis',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                analysis.trim().isEmpty ? '-' : analysis,
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'Plan de accion',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                actionPlan.trim().isEmpty ? '-' : actionPlan,
                style: const pw.TextStyle(fontSize: 9),
              ),
            ],
          ),
        );
      }

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 24),
          theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
          header: (ctx) {
            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 10),
              child: pw.Row(
                children: [
                  pw.Text(
                    'INFORME DE GESTION',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromHex('#1F3A5F'),
                    ),
                  ),
                  pw.Spacer(),
                  pw.Text(
                    '${rangoFmt.format(_desde)} - ${rangoFmt.format(_hasta)}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            );
          },
          footer: (ctx) {
            return pw.Container(
              margin: const pw.EdgeInsets.only(top: 10),
              child: pw.Row(
                children: [
                  pw.Text(
                    'Conjunto: $cliente',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                  pw.Spacer(),
                  pw.Text(
                    'Pagina ${ctx.pageNumber} de ${ctx.pagesCount}',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
              ),
            );
          },
          build: (_) {
            return [
              pw.Text(
                'Periodo: ${mesNombre.toUpperCase()} $anio',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Cliente/Conjunto: $cliente',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.SizedBox(height: 6),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#EFF6FF'),
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: PdfColor.fromHex('#93C5FD')),
                ),
                child: pw.Text(
                  'Este informe contiene unicamente graficas de gestion y sus analisis predefinidos.',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ),
              pw.SizedBox(height: 10),
              chartSection(
                title: '1. Preventivas vs Correctivas',
                imageBytes: charts['tipos']!,
                analysis: _a11Ctrl.text,
                actionPlan: _p11Ctrl.text,
              ),
              chartSection(
                title: '2. Distribucion por estado',
                imageBytes: charts['estados']!,
                analysis: _a12Ctrl.text,
                actionPlan: _p12Ctrl.text,
              ),
              chartSection(
                title: '3. Tareas por día (tendencia)',
                imageBytes: charts['serie']!,
                analysis: _a13Ctrl.text,
                actionPlan: _p13Ctrl.text,
              ),
              chartSection(
                title: '4. Uso de insumos',
                imageBytes: charts['insumos']!,
                analysis: _a14Ctrl.text,
                actionPlan: _p14Ctrl.text,
              ),
            ];
          },
        ),
      );

      final bytes = await doc.save();
      final filename =
          'Informe_de_gestion_${_safeFile(cliente)}_${_safeFile(mesNombre)}_$anio.pdf';

      if (kIsWeb) {
        await downloadPdfWeb(bytes, filename);
      } else {
        await Printing.layoutPdf(name: filename, onLayout: (_) async => bytes);
      }
    } catch (e, st) {
      debugPrint('Error PDF Gestion V2: $e\n$st');
      if (mounted) {
        AppFeedback.showFromSnackBar(
          context,
          SnackBar(content: Text('Error generando PDF: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _generandoPdf = false;
        });
      }
    }
  }

  String _frequencyKeyV2(String? raw) {
    return (raw ?? '')
        .trim()
        .toUpperCase()
        .replaceAll('Á', 'A')
        .replaceAll('É', 'E')
        .replaceAll('Í', 'I')
        .replaceAll('Ó', 'O')
        .replaceAll('Ú', 'U')
        .replaceAll('Ñ', 'N')
        .replaceAll(RegExp(r'[\s\-]+'), '_');
  }

  bool _isDailyFrequencyV2(String? raw) {
    final key = _frequencyKeyV2(raw);
    return key == 'DIARIA' ||
        key == 'DIARIO' ||
        key.startsWith('DIARIA_') ||
        key.startsWith('DIARIO_');
  }

  String _normalizeTaskGroupValueV2(String value) {
    return value
        .trim()
        .toUpperCase()
        .replaceAll('Á', 'A')
        .replaceAll('É', 'E')
        .replaceAll('Í', 'I')
        .replaceAll('Ó', 'O')
        .replaceAll('Ú', 'U')
        .replaceAll('Ñ', 'N')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[^A-Z0-9 ]'), '');
  }

  List<Map<String, dynamic>> _buildDetallePdfItemsV2() {
    final ordered = [..._tareasDetalle]
      ..sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));

    final dailyBuckets = <String, List<TareaDetalleRow>>{};
    final items = <Map<String, dynamic>>[];

    for (final t in ordered) {
      if (!_isDailyFrequencyV2(t.frecuencia)) {
        items.add({
          'esResumenDiario': false,
          'principal': t,
          'tareas': <TareaDetalleRow>[t],
          'inicio': t.fechaInicio,
        });
        continue;
      }

      final key = [
        _normalizeTaskGroupValueV2(t.tipo),
        _normalizeTaskGroupValueV2(t.descripcion),
        _normalizeTaskGroupValueV2(t.ubicacion ?? ''),
        _normalizeTaskGroupValueV2(t.elemento ?? ''),
      ].join('|');

      dailyBuckets.putIfAbsent(key, () => <TareaDetalleRow>[]).add(t);
    }

    for (final bucket in dailyBuckets.values) {
      bucket.sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));
      if (bucket.length == 1) {
        final only = bucket.first;
        items.add({
          'esResumenDiario': false,
          'principal': only,
          'tareas': <TareaDetalleRow>[only],
          'inicio': only.fechaInicio,
        });
        continue;
      }

      final principal = bucket.first;
      items.add({
        'esResumenDiario': true,
        'principal': principal,
        'tareas': bucket,
        'inicio': principal.fechaInicio,
      });
    }

    items.sort(
      (a, b) => (a['inicio'] as DateTime).compareTo(b['inicio'] as DateTime),
    );
    return items;
  }

  Future<void> _generarInformeDetalladoPdfV2() async {
    if (_tareasDetalle.isEmpty) return;

    setState(() => _generandoPdf = true);

    try {
      final fontRegular = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
      );
      final fontBold = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
      );

      final doc = pw.Document();
      final df = DateFormat('dd/MM/yyyy HH:mm', 'es');
      final dfShort = DateFormat('dd/MM/yyyy', 'es');
      final mes = DateFormat('MMMM', 'es').format(_desde);
      final anio = DateFormat('yyyy', 'es').format(_desde);
      final cliente = _conjuntoNombreForReport();

      final items = _buildDetallePdfItemsV2();
      if (items.isEmpty) return;

      final totalDiasRango =
          DateTime(
            _hasta.year,
            _hasta.month,
            _hasta.day,
          ).difference(DateTime(_desde.year, _desde.month, _desde.day)).inDays +
          1;

      final imageCache = <String, pw.ImageProvider>{};
      final evidenceImageByRaw = <String, pw.ImageProvider?>{};

      final evidenceAuthToken = await SessionService().getToken();

      Future<pw.ImageProvider?> loadEvidenceImage(String raw) async {
        final candidates = _evidenceUrlCandidates(raw);
        for (final u in candidates) {
          if (imageCache.containsKey(u)) return imageCache[u];
          try {
            final img = await networkImage(
              u,
              headers: u.startsWith(AppConstants.baseUrl)
                  ? {'Authorization': 'Bearer $evidenceAuthToken'}
                  : null,
            );
            imageCache[u] = img;
            return img;
          } catch (_) {
            // intenta siguiente candidato
          }
        }
        return null;
      }

      final raws = items
          .expand((item) => (item['tareas'] as List<TareaDetalleRow>))
          .expand((t) => t.evidencias.take(4))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet();
      for (final raw in raws) {
        evidenceImageByRaw[raw] = await loadEvidenceImage(raw);
      }

      String clipText(String value, {int max = 180}) {
        final v = value.trim();
        if (v.length <= max) return v;
        return '${v.substring(0, max).trim()}...';
      }

      // Etiqueta unificada con el resto de la app (incluye el dia programado
      // cuando la frecuencia depende de el).
      String frequencyLabel(String? raw) {
        final label = etiquetaFrecuencia(raw);
        return label == '—' ? '-' : label.toUpperCase();
      }

      double toDouble(dynamic v) {
        if (v == null) return 0;
        if (v is num) return v.toDouble();
        return double.tryParse('$v') ?? 0;
      }

      String miniList(List<Map<String, dynamic>> rows, {int max = 4}) {
        if (rows.isEmpty) return 'Sin datos';
        return rows
            .take(max)
            .map((m) {
              final nombre = (m['nombre'] ?? '-').toString().trim();
              final cantidad = toDouble(m['cantidad']);
              final unidad = (m['unidad'] ?? '').toString().trim();
              final qty = cantidad > 0
                  ? (cantidad % 1 == 0
                        ? cantidad.toStringAsFixed(0)
                        : cantidad.toStringAsFixed(2))
                  : '';
              final extra = [
                qty,
                unidad,
              ].where((x) => x.trim().isNotEmpty).join(' ');
              return extra.isEmpty ? nombre : '$nombre ($extra)';
            })
            .join(' | ');
      }

      String mergedResourceList(
        List<TareaDetalleRow> tasks,
        List<Map<String, dynamic>> Function(TareaDetalleRow) selector, {
        int max = 4,
      }) {
        final agg = <String, Map<String, dynamic>>{};
        for (final t in tasks) {
          for (final r in selector(t)) {
            final nombre = (r['nombre'] ?? '-').toString().trim();
            final unidad = (r['unidad'] ?? '').toString().trim();
            final key = '${nombre.toUpperCase()}|${unidad.toUpperCase()}';
            final slot = agg.putIfAbsent(
              key,
              () => <String, dynamic>{
                'nombre': nombre,
                'unidad': unidad,
                'cantidad': 0.0,
              },
            );
            slot['cantidad'] =
                (slot['cantidad'] as double) + toDouble(r['cantidad']);
          }
        }
        return miniList(agg.values.toList(), max: max);
      }

      pw.Widget evidenceTile(pw.ImageProvider? img) {
        return pw.Container(
          width: 88,
          height: 62,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400),
            borderRadius: pw.BorderRadius.circular(5),
          ),
          child: img == null
              ? pw.Center(
                  child: pw.Text(
                    'Sin imagen',
                    style: const pw.TextStyle(fontSize: 7),
                  ),
                )
              : pw.ClipRRect(
                  horizontalRadius: 5,
                  verticalRadius: 5,
                  child: pw.Image(img, fit: pw.BoxFit.cover),
                ),
        );
      }

      pw.Widget tareaCard(Map<String, dynamic> item) {
        final resumenDiario = item['esResumenDiario'] == true;
        final principal = item['principal'] as TareaDetalleRow;
        final tasks = (item['tareas'] as List<TareaDetalleRow>)
          ..sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));

        final first = tasks.first;
        final last = tasks.last;
        final uniqueDays = tasks
            .map(
              (t) => DateTime(
                t.fechaInicio.year,
                t.fechaInicio.month,
                t.fechaInicio.day,
              ).millisecondsSinceEpoch,
            )
            .toSet()
            .length;
        final supervisors = tasks
            .map((t) => (t.supervisor ?? '').trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList();
        final operarios = tasks
            .expand((t) => t.operarios)
            .map((o) => o.trim())
            .where((o) => o.isNotEmpty)
            .toSet()
            .toList();
        final estados = tasks
            .map((t) => t.estado.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList();
        final evidenciaRaw = tasks
            .expand((t) => t.evidencias)
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList();

        String? reemplazadaPorRef(TareaDetalleRow t) {
          if (t.reemplazadaPorTareaId == null) return null;
          final desc = (t.reemplazadaPorDescripcion ?? '').trim();
          return desc.isNotEmpty
              ? '#${t.reemplazadaPorTareaId} ($desc)'
              : '#${t.reemplazadaPorTareaId}';
        }

        final reemplazaRefs = tasks
            .expand(_replacementRefs)
            .map((r) => r.trim())
            .where((r) => r.isNotEmpty)
            .toSet()
            .toList();
        final reemplazadaPorRefs = tasks
            .map(reemplazadaPorRef)
            .whereType<String>()
            .map((r) => r.trim())
            .where((r) => r.isNotEmpty)
            .toSet()
            .toList();
        final tieneReemplazo = tasks.any((t) => t.esTareaReemplazo);
        final motivoNoComp = (principal.motivoNoCompletada ?? '').trim();
        final refReemplazo = reemplazadaPorRef(principal);
        final motivoReemplazo = _replacementInfoText(principal);

        final resumenTexto = uniqueDays >= totalDiasRango
            ? 'Esta tarea se hizo todos los días del mes.'
            : 'Esta tarea se hizo de forma diaria durante el mes ($uniqueDays de $totalDiasRango días con registro).';

        final insumosTxt = resumenDiario
            ? mergedResourceList(tasks, (t) => t.insumos)
            : miniList(principal.insumos);
        final maquinariaTxt = resumenDiario
            ? mergedResourceList(tasks, (t) => t.maquinaria)
            : miniList(principal.maquinaria);
        final herramientasTxt = resumenDiario
            ? mergedResourceList(tasks, (t) => t.herramientas)
            : miniList(principal.herramientas);

        String safe(String? v) {
          final txt = (v ?? '').trim();
          return txt.isEmpty ? '-' : txt;
        }

        pw.Widget cell(String txt, {bool bold = false}) {
          return pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: pw.Text(
              clipText(txt, max: 120),
              style: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          );
        }

        pw.TableRow kvRow({
          required String k1,
          required String v1,
          required String k2,
          required String v2,
        }) {
          return pw.TableRow(
            children: [
              cell(k1, bold: true),
              cell(v1),
              cell(k2, bold: true),
              cell(v2),
            ],
          );
        }

        final reemplazaTxt = reemplazaRefs.isNotEmpty
            ? reemplazaRefs.join(', ')
            : (tieneReemplazo ? clipText(motivoReemplazo, max: 110) : '-');
        final reemplazadaTxt = reemplazadaPorRefs.isNotEmpty
            ? reemplazadaPorRefs.join(', ')
            : (refReemplazo ?? '-');

        return pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: PdfColors.white,
            border: pw.Border.all(color: PdfColor.fromHex('#D1D5DB')),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#F3F4F6'),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Text(
                  resumenDiario
                      ? 'TAREA (RESUMEN DIARIO) - ${principal.tipo}'
                      : 'TAREA - ${principal.tipo}',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#111827'),
                  ),
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColor.fromHex('#D1D5DB')),
                columnWidths: const {
                  0: pw.FlexColumnWidth(1.1),
                  1: pw.FlexColumnWidth(1.9),
                  2: pw.FlexColumnWidth(1.1),
                  3: pw.FlexColumnWidth(1.9),
                },
                children: [
                  kvRow(
                    k1: 'ID',
                    v1: resumenDiario
                        ? 'Multiple (${tasks.length})'
                        : '${principal.id}',
                    k2: 'Estado',
                    v2: resumenDiario ? estados.join(', ') : principal.estado,
                  ),
                  kvRow(
                    k1: 'Frecuencia',
                    v1: frequencyLabel(principal.frecuencia),
                    k2: 'Tipo',
                    v2: principal.tipo,
                  ),
                  kvRow(
                    k1: resumenDiario ? 'Periodo' : 'Inicio',
                    v1: resumenDiario
                        ? '${dfShort.format(first.fechaInicio)} - ${dfShort.format(last.fechaFin)}'
                        : df.format(principal.fechaInicio),
                    k2: resumenDiario ? 'Registros' : 'Fin',
                    v2: resumenDiario
                        ? '${tasks.length}'
                        : '${df.format(principal.fechaFin)} (${principal.duracionMinutos} min)',
                  ),
                  kvRow(
                    k1: 'Ubicación',
                    v1: safe(principal.ubicacion),
                    k2: 'Elemento',
                    v2: safe(principal.elemento),
                  ),
                  kvRow(
                    k1: 'Supervisor',
                    v1: supervisors.isEmpty ? '-' : supervisors.join(', '),
                    k2: 'Operarios',
                    v2: operarios.isEmpty ? '-' : operarios.join(', '),
                  ),
                  kvRow(
                    k1: 'Insumos',
                    v1: insumosTxt,
                    k2: 'Maquinaria',
                    v2: maquinariaTxt,
                  ),
                  kvRow(
                    k1: 'Herramientas',
                    v1: herramientasTxt,
                    k2: 'Reemplaza',
                    v2: reemplazaTxt,
                  ),
                  kvRow(
                    k1: 'Reemplazada por',
                    v1: reemplazadaTxt,
                    k2: 'Evidencias',
                    v2: '${evidenciaRaw.length}',
                  ),
                ],
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                'Descripcion: ${clipText(principal.descripcion, max: 220)}',
                style: const pw.TextStyle(fontSize: 7.5),
              ),
              if (resumenDiario)
                pw.Text(
                  resumenTexto,
                  style: pw.TextStyle(
                    fontSize: 7.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              if (motivoNoComp.isNotEmpty)
                pw.Text(
                  'Motivo no completada: ${clipText(motivoNoComp, max: 220)}',
                  style: const pw.TextStyle(fontSize: 7.5),
                ),
              pw.SizedBox(height: 5),
              pw.Wrap(
                spacing: 6,
                runSpacing: 6,
                children: evidenciaRaw.isEmpty
                    ? [evidenceTile(null)]
                    : evidenciaRaw
                          .take(3)
                          .map(
                            (raw) =>
                                evidenceTile(evidenceImageByRaw[raw.trim()]),
                          )
                          .toList(),
              ),
            ],
          ),
        );
      }

      List<List<Map<String, dynamic>>> chunkedItems(
        List<Map<String, dynamic>> source,
      ) {
        final out = <List<Map<String, dynamic>>>[];
        for (var i = 0; i < source.length; i += 2) {
          out.add(source.sublist(i, math.min(i + 2, source.length)));
        }
        return out;
      }

      final pages = chunkedItems(items);
      final pageTheme = pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(18),
        theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
      );

      int countEstado(String estado) =>
          _tareasDetalle.where((t) => _estadoKey(t.estado) == estado).length;

      final resumenConteos = <List<String>>[
        ['Total tareas (registros)', '${_tareasDetalle.length}'],
        ['Tareas visibles en PDF', '${items.length}'],
        ['Asignadas', '${countEstado('ASIGNADA')}'],
        ['En proceso', '${countEstado('EN_PROCESO')}'],
        ['Completadas', '${countEstado('COMPLETADA')}'],
        ['Aprobadas', '${countEstado('APROBADA')}'],
        ['Pendientes aprobación', '${countEstado('PENDIENTE_APROBACION')}'],
        ['No completadas', '${countEstado('NO_COMPLETADA')}'],
        [
          'Pendientes reprogramación',
          '${countEstado('PENDIENTE_REPROGRAMACION')}',
        ],
        ['Rechazadas', '${countEstado('RECHAZADA')}'],
        [
          'Tareas que reemplazan',
          '${_tareasDetalle.where((t) => t.esTareaReemplazo).length}',
        ],
        [
          'Tareas reemplazadas',
          '${_tareasDetalle.where((t) => t.noCompletadaPorReemplazo || t.reemplazadaPorTareaId != null).length}',
        ],
      ];

      pw.TableRow resumenRow(String k, String v) {
        return pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 5,
              ),
              child: pw.Text(
                k,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 5,
              ),
              child: pw.Text(v, style: const pw.TextStyle(fontSize: 9)),
            ),
          ],
        );
      }

      doc.addPage(
        pw.Page(
          pageTheme: pageTheme,
          build: (_) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    borderRadius: pw.BorderRadius.circular(8),
                    border: pw.Border.all(color: PdfColor.fromHex('#D1D5DB')),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'INFORME DETALLADO DE TAREAS',
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('#111827'),
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'Conjunto: $cliente | Rango: ${dfShort.format(_desde)} - ${dfShort.format(_hasta)}',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                      pw.Text(
                        'Resumen general del periodo',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Table(
                  border: pw.TableBorder.all(
                    color: PdfColor.fromHex('#D1D5DB'),
                  ),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(2.4),
                    1: pw.FlexColumnWidth(1),
                  },
                  children: resumenConteos
                      .map((r) => resumenRow(r[0], r[1]))
                      .toList(),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  'Las siguientes hojas muestran 2 tablitas por página (1 tablita = 1 tarea visible del informe detallado).',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ],
            );
          },
        ),
      );

      for (var i = 0; i < pages.length; i++) {
        final pageItems = pages[i];
        doc.addPage(
          pw.Page(
            pageTheme: pageTheme,
            build: (_) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      borderRadius: pw.BorderRadius.circular(8),
                      border: pw.Border.all(color: PdfColor.fromHex('#D1D5DB')),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          children: [
                            pw.Expanded(
                              child: pw.Text(
                                'INFORME DETALLADO DE TAREAS',
                                style: pw.TextStyle(
                                  fontSize: 13,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColor.fromHex('#111827'),
                                ),
                              ),
                            ),
                            pw.Text(
                              'Hoja tareas ${i + 1}/${pages.length}',
                              style: const pw.TextStyle(fontSize: 9),
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'Conjunto: $cliente | Rango: ${dfShort.format(_desde)} - ${dfShort.format(_hasta)}',
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                        pw.Text(
                          'Tareas visibles: ${items.length} (diarias repetitivas consolidadas)',
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Expanded(child: tareaCard(pageItems[0])),
                  pw.SizedBox(height: 10),
                  pw.Expanded(
                    child: pageItems.length > 1
                        ? tareaCard(pageItems[1])
                        : pw.Container(
                            decoration: pw.BoxDecoration(
                              border: pw.Border.all(
                                color: PdfColor.fromHex('#E5E7EB'),
                              ),
                              borderRadius: pw.BorderRadius.circular(10),
                            ),
                            child: pw.Center(
                              child: pw.Text(
                                'Fin de pagina',
                                style: const pw.TextStyle(
                                  fontSize: 10,
                                  color: PdfColors.grey600,
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
        );
      }

      final bytes = await doc.save();
      final filename =
          'Informe_detallado_${_safeFile(cliente)}_${_safeFile(mes)}_$anio.pdf';

      if (kIsWeb) {
        await downloadPdfWeb(bytes, filename);
      } else {
        await Printing.layoutPdf(name: filename, onLayout: (_) async => bytes);
      }
    } catch (e, st) {
      debugPrint('Error PDF Detallado V2: $e\n$st');
      if (mounted) {
        AppFeedback.showFromSnackBar(
          context,
          SnackBar(content: Text('Error generando PDF: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _generandoPdf = false);
      }
    }
  }

  // ======================= BUILD =======================

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.primary;
    final df = DateFormat('dd/MM/yyyy', 'es');
    final tabs = _soloResumenTipos
        ? <Tab>[const Tab(text: 'Resumen'), const Tab(text: 'Tipos')]
        : <Tab>[
            const Tab(text: 'Resumen'),
            const Tab(text: 'Compromisos'),
            const Tab(text: 'Operarios'),
            const Tab(text: 'Insumos'),
            const Tab(text: 'Maq/Herr'),
            const Tab(text: 'Tipos'),
            if (_permitirInformesPdf) const Tab(text: 'Informes'),
          ];
    final tabViews = _soloResumenTipos
        ? <Widget>[_tabResumen(), _tabTipos()]
        : <Widget>[
            _tabResumen(),
            _tabCompromisos(),
            _tabOperarios(),
            _tabInsumos(),
            _tabMaqHerr(),
            _tabTipos(),
            if (_permitirInformesPdf) _tabInformes(),
          ];

    final conteoTipos = _contarTipos();
    final prev = conteoTipos['preventivas'] ?? 0;
    final corr = conteoTipos['correctivas'] ?? 0;

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F7FB),
        appBar: AppBar(
          backgroundColor: primary,
          title: Text(
            _esReporteGeneral
                ? 'Reportes Generales'
                : 'Reportes - ${_conjuntoNombreForReport()}',
            style: const TextStyle(color: Colors.white),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              onPressed: _cargarTodo,
              icon: const Icon(Icons.refresh, color: Colors.white),
              tooltip: 'Actualizar',
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: tabs,
          ),
        ),
        body: Stack(
          children: [
            Column(
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
                            child: _filterChip(
                              icon: Icons.business,
                              title: _esReporteGeneral
                                  ? 'Cobertura'
                                  : 'Conjunto',
                              subtitle: _esReporteGeneral
                                  ? 'Todos los conjuntos'
                                  : (_conjuntoId ?? 'No definido'),
                              onTap: () {},
                            ),
                          ),
                        ],
                      ),
                      if (!_esReporteGeneral && _conjuntoId == null)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Esta página requiere conjuntoId/NIT desde la navegación.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                Expanded(
                  child: _loading
                      ? const SingleChildScrollView(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            children: [
                              SkeletonDashboardGrid(
                                tiles: 4,
                                crossAxisCount: 2,
                                padding: EdgeInsets.zero,
                              ),
                              SizedBox(height: 16),
                              SkeletonCard(height: 260, lines: 1),
                              SizedBox(height: 16),
                              SkeletonCard(lines: 4),
                            ],
                          ),
                        )
                      : _error != null
                      ? _buildError()
                      : TabBarView(children: tabViews),
                ),
              ],
            ),

            // Las 4 graficas offscreen solo se necesitan para capturarlas al
            // generar el PDF de gestion (_captureChartsForPdf). Antes se
            // montaban siempre que la pestaña de informes estaba habilitada,
            // lo que las mantenia layouteadas y pintadas en cada frame sin
            // usarlas. _captureChartsForPdf ya espera varios frames + un
            // delay antes de capturar, tiempo suficiente para que esta
            // rama recien montada tambien termine de layoutear/pintar.
            if (_permitirInformesPdf && _generandoPdf)
              Positioned(
                left: -5000,
                top: 0,
                child: IgnorePointer(
                  child: Material(
                    color: Colors.white,
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
                        RepaintBoundary(
                          key: _kBarInsumos,
                          child: SizedBox(
                            width: 900,
                            height: 420,
                            child: _barInsumosForPdf(),
                          ),
                        ),
                      ],
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

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _kpiGrid([
          _kpiTile('Total', k.total.toString(), Icons.assignment),
          _kpiTile(
            'Aprobadas',
            kd.aprobadas.toString(),
            Icons.verified,
            accentColor: _estadoColor('APROBADA'),
          ),
          _kpiTile(
            'No completadas',
            kd.noCompletadas.toString(),
            Icons.warning_amber,
            accentColor: _estadoColor('NO_COMPLETADA'),
          ),
        ]),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('Distribución por estado'),
                  const SizedBox(height: 8),
                  _card(
                    child: SizedBox(
                      height: 260,
                      child: Row(
                        children: [
                          Expanded(child: _pieEstados(k.byEstado)),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 150,
                            child: _legendEstados(k.byEstado),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('Top Operarios (por volumen)'),
                  const SizedBox(height: 8),
                  _card(
                    child: SizedBox(height: 260, child: _barTopOperarios()),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _sectionTitle('Tareas por ubicación'),
        const SizedBox(height: 8),
        _card(child: _barPorUbicacion()),
      ],
    );
  }

  /// Estados con conteo > 0 en algún día de la serie diaria, en el orden fijo
  /// de ChartStyle (y cualquier estado fuera del catálogo al final).
  List<String> _estadosEnSerieDiaria(SerieDiariaPorEstado? s) {
    if (s == null) return const [];
    final presentes = <String>{};
    for (final day in s.days) {
      final raw = s.series[day] ?? {};
      raw.forEach((k, v) {
        if (v > 0) presentes.add(_estadoKey(k));
      });
    }
    final ordenados = ChartStyle.estadoOrder
        .where(presentes.contains)
        .toList();
    for (final k in presentes) {
      if (!ordenados.contains(k)) ordenados.add(k);
    }
    return ordenados;
  }

  String _estadoKey(String estado) {
    return estado
        .trim()
        .toUpperCase()
        .replaceAll('Á', 'A')
        .replaceAll('É', 'E')
        .replaceAll('Í', 'I')
        .replaceAll('Ó', 'O')
        .replaceAll('Ú', 'U')
        .replaceAll('Ñ', 'N')
        .replaceAll(RegExp(r'[\s\-]+'), '_');
  }

  Color _estadoColor(String estado) =>
      ChartStyle.estadoColor(_estadoKey(estado));

  String _estadoLabel(String estado) =>
      ChartStyle.estadoLabel(_estadoKey(estado));

  Color _compromisoAnsColor(String estado) {
    switch (estado.trim().toLowerCase()) {
      case 'verde':
        return const Color(0xFF2E7D32);
      case 'naranja':
        return const Color(0xFFEF6C00);
      case 'rojo':
        return const Color(0xFFC62828);
      case 'cerrado':
        return const Color(0xFF1B8F5A);
      default:
        return AppTheme.primary;
    }
  }

  String _formatOneDecimal(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }

  Widget _tabCompromisos() {
    final data = _compromisosReporte;
    if (data == null) return const Center(child: Text('Sin datos'));

    final r = data.resumen;
    final totalAns = data.porAns.values.fold<int>(0, (a, b) => a + b);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _kpiGrid([
          _kpiTile('Gestionados', r.total.toString(), Icons.dashboard_outlined),
          _kpiTile(
            'Creados periodo',
            r.creadosPeriodo.toString(),
            Icons.assignment_outlined,
          ),
          _kpiTile(
            'Abiertos',
            r.abiertos.toString(),
            Icons.timelapse_rounded,
            accentColor: ChartStyle.warning,
          ),
          _kpiTile(
            'Cerrados',
            r.cerrados.toString(),
            Icons.task_alt_outlined,
            accentColor: ChartStyle.good,
          ),
          _kpiTile(
            'Cerrados periodo',
            r.cerradosPeriodo.toString(),
            Icons.event_available_outlined,
            accentColor: ChartStyle.good,
          ),
          _kpiTile(
            'Verdes',
            r.verdes.toString(),
            Icons.flag_outlined,
            accentColor: _compromisoAnsColor('verde'),
          ),
          _kpiTile(
            'Naranjas',
            r.naranjas.toString(),
            Icons.flag_outlined,
            accentColor: _compromisoAnsColor('naranja'),
          ),
          _kpiTile(
            'Rojos',
            r.rojos.toString(),
            Icons.flag_outlined,
            accentColor: _compromisoAnsColor('rojo'),
          ),
          _kpiTile(
            '% Cumplimiento',
            '${r.porcentajeCumplimiento}%',
            Icons.verified_outlined,
            accentColor: ChartStyle.good,
          ),
          _kpiTile(
            'Prom. cierre',
            '${_formatOneDecimal(r.promedioDiasCierre)} días',
            Icons.av_timer_outlined,
            accentColor: AppTheme.primary,
          ),
        ]),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('Salud ANS de compromisos'),
                  const SizedBox(height: 8),
                  _card(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 760;
                        final stats = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _miniTextPill(
                              'ANS sano',
                              '${r.porcentajeAnsSaludable}%',
                            ),
                            const SizedBox(height: 10),
                            _miniTextPill(
                              'Prom. días abiertos',
                              _formatOneDecimal(r.promedioDiasAbiertos),
                            ),
                            const SizedBox(height: 10),
                            _miniTextPill(
                              'Items evaluados',
                              totalAns.toString(),
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _legendChip(
                                  'Verdes ${r.verdes}',
                                  _compromisoAnsColor('verde'),
                                ),
                                _legendChip(
                                  'Naranjas ${r.naranjas}',
                                  _compromisoAnsColor('naranja'),
                                ),
                                _legendChip(
                                  'Rojos ${r.rojos}',
                                  _compromisoAnsColor('rojo'),
                                ),
                              ],
                            ),
                          ],
                        );

                        if (compact) {
                          return Column(
                            children: [
                              SizedBox(
                                height: 240,
                                child: _compromisosAnsChart(data),
                              ),
                              const SizedBox(height: 12),
                              stats,
                            ],
                          );
                        }

                        return SizedBox(
                          height: 260,
                          child: Row(
                            children: [
                              Expanded(child: _compromisosAnsChart(data)),
                              const SizedBox(width: 12),
                              SizedBox(width: 180, child: stats),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _sectionTitle('Tendencia de compromisos'),
        const SizedBox(height: 8),
        _compromisosSerieChart(data),
        if (_esReporteGeneral) ...[
          const SizedBox(height: 14),
          _sectionTitle('Conjuntos con mayor carga de compromisos'),
          const SizedBox(height: 8),
          _compromisosTopConjuntosChart(data),
        ],
        const SizedBox(height: 14),
        _sectionTitle('Compromisos criticos abiertos'),
        const SizedBox(height: 8),
        _compromisosCriticosCard(data),
      ],
    );
  }

  Widget _compromisosAnsChart(ReporteCompromisosDashboard data) {
    final rows = <_ChartSliceDatum>[
      _ChartSliceDatum(
        label: 'Verdes',
        value: data.resumen.verdes.toDouble(),
        color: _compromisoAnsColor('verde'),
      ),
      _ChartSliceDatum(
        label: 'Naranjas',
        value: data.resumen.naranjas.toDouble(),
        color: _compromisoAnsColor('naranja'),
      ),
      _ChartSliceDatum(
        label: 'Rojos',
        value: data.resumen.rojos.toDouble(),
        color: _compromisoAnsColor('rojo'),
      ),
      _ChartSliceDatum(
        label: 'Cerrados',
        value: data.resumen.cerrados.toDouble(),
        color: _compromisoAnsColor('cerrado'),
      ),
    ].where((e) => e.value > 0).toList();

    final total = rows.fold<double>(0, (a, b) => a + b.value);
    if (total <= 0)
      return const Center(child: Text('Sin compromisos en el rango'));

    return SfCircularChart(
      margin: EdgeInsets.zero,
      tooltipBehavior: ChartStyle.sfTooltip(),
      series: <CircularSeries<_ChartSliceDatum, String>>[
        DoughnutSeries<_ChartSliceDatum, String>(
          dataSource: rows,
          animationDuration: 0,
          xValueMapper: (d, _) => d.label,
          yValueMapper: (d, _) => d.value,
          pointColorMapper: (d, _) => d.color,
          innerRadius: '60%',
          radius: '88%',
          dataLabelSettings: ChartStyle.sfDonutLabels,
          dataLabelMapper: (d, _) {
            final pct = total <= 0 ? 0 : (d.value / total) * 100;
            return pct >= 8 ? '${pct.toStringAsFixed(0)}%' : '';
          },
        ),
      ],
      annotations: <CircularChartAnnotation>[
        CircularChartAnnotation(
          widget: ChartStyle.donutCenter(
            data.resumen.total.toString(),
            'creados',
          ),
        ),
      ],
    );
  }

  /// Evolución diaria de compromisos creados vs. cerrados: permite ver si el
  /// ritmo de cierre acompaña al de creación o si se está acumulando rezago.
  Widget _compromisosSerieChart(ReporteCompromisosDashboard data) {
    final s = data.serie;
    if (s.days.isEmpty) {
      return const _EmptyCard(
        text: 'Sin serie de compromisos para el rango seleccionado.',
      );
    }

    final dayLabels = s.days.map((d) {
      final parts = d.split('-');
      return parts.length == 3 ? '${parts[2]}/${parts[1]}' : d;
    }).toList();

    final rows = <_CompromisoTrendDatum>[
      for (int i = 0; i < s.days.length; i++)
        _CompromisoTrendDatum(
          label: dayLabels[i],
          creados: (s.created[s.days[i]] ?? 0).toDouble(),
          cerrados: (s.closed[s.days[i]] ?? 0).toDouble(),
        ),
    ];

    final maxY = rows.fold<double>(
      0,
      (a, b) => math.max(a, math.max(b.creados, b.cerrados)),
    );
    final yTop = maxY <= 0 ? 5.0 : maxY * 1.25;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Compromisos creados vs. cerrados por día en el rango seleccionado.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 260,
            child: SfCartesianChart(
              margin: EdgeInsets.zero,
              plotAreaBorderWidth: 0,
              tooltipBehavior: ChartStyle.sfTooltip(shared: true),
              primaryXAxis: ChartStyle.sfCategoryAxis(
                interval: math.max(1, (rows.length / 6).floor()).toDouble(),
              ),
              primaryYAxis: ChartStyle.sfNumericAxis(minimum: 0, maximum: yTop),
              series: <CartesianSeries<_CompromisoTrendDatum, String>>[
                SplineSeries<_CompromisoTrendDatum, String>(
                  dataSource: rows,
                  animationDuration: 0,
                  xValueMapper: (d, _) => d.label,
                  yValueMapper: (d, _) => d.creados,
                  color: ChartStyle.slot2,
                  width: 3,
                  splineType: SplineType.monotonic,
                  markerSettings: const MarkerSettings(isVisible: false),
                  name: 'Creados',
                ),
                SplineSeries<_CompromisoTrendDatum, String>(
                  dataSource: rows,
                  animationDuration: 0,
                  xValueMapper: (d, _) => d.label,
                  yValueMapper: (d, _) => d.cerrados,
                  color: ChartStyle.good,
                  width: 3,
                  splineType: SplineType.monotonic,
                  markerSettings: const MarkerSettings(isVisible: false),
                  name: 'Cerrados',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _legendChip('Creados', ChartStyle.slot2),
              _legendChip('Cerrados', ChartStyle.good),
            ],
          ),
        ],
      ),
    );
  }

  Widget _compromisosTopConjuntosChart(ReporteCompromisosDashboard data) {
    if (data.topConjuntos.isEmpty) {
      return const _EmptyCard(
        text: 'Sin datos por conjunto para el rango seleccionado.',
      );
    }

    final items = [...data.topConjuntos]
      ..sort((a, b) {
        final abiertosDiff = b.abiertos.compareTo(a.abiertos);
        if (abiertosDiff != 0) return abiertosDiff;
        return b.total.compareTo(a.total);
      });
    final maxY = items
        .map((e) => e.total)
        .fold<int>(0, (a, b) => math.max(a, b))
        .toDouble();

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Comparativo por conjunto segun el total de compromisos gestionados en el rango.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 320,
            child: SfCartesianChart(
              margin: EdgeInsets.zero,
              plotAreaBorderWidth: 0,
              tooltipBehavior: ChartStyle.sfTooltip(shared: true),
              primaryXAxis: ChartStyle.sfCategoryAxis(
                labelRotation: items.length > 4 ? -28 : 0,
              ),
              primaryYAxis: ChartStyle.sfNumericAxis(
                minimum: 0,
                maximum: maxY <= 0 ? 5 : (maxY * 1.25),
              ),
              series: <CartesianSeries<ReporteCompromisoConjuntoRow, String>>[
                ColumnSeries<ReporteCompromisoConjuntoRow, String>(
                  dataSource: items,
                  animationDuration: 0,
                  xValueMapper: (d, _) =>
                      d.conjuntoNombre.isEmpty ? d.nit : d.conjuntoNombre,
                  yValueMapper: (d, _) => d.total.toDouble(),
                  color: ChartStyle.slot1,
                  width: 0.6,
                  spacing: 0.22,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                  name: 'Gestionados',
                ),
                ColumnSeries<ReporteCompromisoConjuntoRow, String>(
                  dataSource: items,
                  animationDuration: 0,
                  xValueMapper: (d, _) =>
                      d.conjuntoNombre.isEmpty ? d.nit : d.conjuntoNombre,
                  yValueMapper: (d, _) => d.abiertos.toDouble(),
                  color: ChartStyle.slot3,
                  width: 0.6,
                  spacing: 0.22,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                  name: 'Abiertos',
                ),
                ColumnSeries<ReporteCompromisoConjuntoRow, String>(
                  dataSource: items,
                  animationDuration: 0,
                  xValueMapper: (d, _) =>
                      d.conjuntoNombre.isEmpty ? d.nit : d.conjuntoNombre,
                  yValueMapper: (d, _) => d.rojos.toDouble(),
                  color: ChartStyle.slot8,
                  width: 0.6,
                  spacing: 0.22,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                  name: 'Rojos',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _legendChip('Gestionados', ChartStyle.slot1),
              _legendChip('Abiertos', ChartStyle.slot3),
              _legendChip('Rojos', ChartStyle.slot8),
            ],
          ),
        ],
      ),
    );
  }

  Widget _compromisosCriticosCard(ReporteCompromisosDashboard data) {
    if (data.criticos.isEmpty) {
      return const _EmptyCard(
        text: 'No hay compromisos criticos abiertos en este rango.',
      );
    }

    final df = DateFormat('dd/MM/yyyy', 'es');
    return _card(
      child: Column(
        children: data.criticos.map((item) {
          final conjuntoTxt = _esReporteGeneral
              ? (item.conjuntoNombre.isEmpty
                    ? item.conjuntoNit
                    : item.conjuntoNombre)
              : 'Compromiso del conjunto';
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7F7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFF2B8B5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: _compromisoAnsColor(
                            item.ansEstado,
                          ).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.priority_high_rounded,
                          color: _compromisoAnsColor(item.ansEstado),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.titulo,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              conjuntoTxt,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _miniTextPill('ANS', item.ansLabel),
                      _miniTextPill(
                        'Días abiertos',
                        item.diasAbierto.toString(),
                      ),
                      _miniTextPill('Creado', df.format(item.creadaEn)),
                    ],
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Envuelve tarjetas KPI en un grid responsivo (2/3/4 columnas segun el
  /// ancho disponible) en vez de un ancho fijo que deja huecos irregulares.
  Widget _kpiGrid(List<Widget> tiles) {
    const spacing = 10.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 860 ? 4 : (width >= 620 ? 3 : 2);
        final tileWidth = (width - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final t in tiles) SizedBox(width: tileWidth, child: t),
          ],
        );
      },
    );
  }

  Widget _kpiTile(
    String title,
    String value,
    IconData icon, {
    Color? accentColor,
  }) {
    final accent = accentColor ?? AppTheme.primary;
    return _card(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------- Pie estados --------

  Widget _pieEstados(Map<String, int> byEstado) {
    final entries = byEstado.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) {
        final ia = ChartStyle.estadoOrder.indexOf(_estadoKey(a.key));
        final ib = ChartStyle.estadoOrder.indexOf(_estadoKey(b.key));
        if (ia == -1 && ib == -1) return b.value.compareTo(a.value);
        if (ia == -1) return 1;
        if (ib == -1) return -1;
        return ia.compareTo(ib);
      });
    final total = entries.fold<int>(0, (a, b) => a + b.value);
    if (total <= 0) return const Center(child: Text('Sin datos'));

    final data = entries
        .map(
          (e) => _ChartSliceDatum(
            label: _estadoLabel(e.key),
            value: e.value.toDouble(),
            color: _estadoColor(e.key),
          ),
        )
        .toList();

    return SfCircularChart(
      margin: EdgeInsets.zero,
      tooltipBehavior: ChartStyle.sfTooltip(),
      series: <CircularSeries<_ChartSliceDatum, String>>[
        DoughnutSeries<_ChartSliceDatum, String>(
          dataSource: data,
          animationDuration: 0,
          xValueMapper: (d, _) => d.label,
          yValueMapper: (d, _) => d.value,
          pointColorMapper: (d, _) => d.color,
          innerRadius: '58%',
          radius: '88%',
          dataLabelSettings: ChartStyle.sfDonutLabels,
          dataLabelMapper: (d, _) {
            final pct = (d.value / total) * 100;
            return pct >= 7 ? '${pct.toStringAsFixed(0)}%' : '';
          },
        ),
      ],
      annotations: <CircularChartAnnotation>[
        CircularChartAnnotation(
          widget: ChartStyle.donutCenter('$total', 'tareas'),
        ),
      ],
    );
  }

  Widget _legendEstados(Map<String, int> byEstado) {
    final entries = byEstado.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) {
        final ia = ChartStyle.estadoOrder.indexOf(_estadoKey(a.key));
        final ib = ChartStyle.estadoOrder.indexOf(_estadoKey(b.key));
        if (ia == -1 && ib == -1) return b.value.compareTo(a.value);
        if (ia == -1) return 1;
        if (ib == -1) return -1;
        return ia.compareTo(ib);
      });
    final total = entries.fold<int>(0, (a, b) => a + b.value);
    if (total <= 0) return const SizedBox.shrink();

    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final e = entries[i];
        final pct = (e.value / total) * 100;
        final c = _estadoColor(e.key);
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
                _estadoLabel(e.key),
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

  Widget _legendChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  /// Tendencia diaria de tareas, apilada por estado (stacked area) para ver
  /// no solo el volumen sino su composición (p. ej. si un pico de carga
  /// coincide con más rechazadas/no completadas).
  Widget _lineSerieDiaria() {
    final s = _serie;
    if (s == null || s.days.isEmpty) {
      return const Center(child: Text('Sin serie'));
    }

    final days = s.days.length <= 30
        ? s.days
        : s.days.sublist(s.days.length - 30);
    final dayLabels = days.map((d) {
      final parts = d.split('-');
      return parts.length == 3 ? '${parts[2]}/${parts[1]}' : d;
    }).toList();

    final data = <_DiaEstadoDatum>[];
    for (int i = 0; i < days.length; i++) {
      final raw = s.series[days[i]] ?? {};
      final normalizado = <String, int>{};
      raw.forEach((k, v) {
        final key = _estadoKey(k);
        normalizado[key] = (normalizado[key] ?? 0) + v;
      });
      data.add(_DiaEstadoDatum(label: dayLabels[i], porEstado: normalizado));
    }

    final estadosOrdenados = _estadosEnSerieDiaria(s);
    if (estadosOrdenados.isEmpty) {
      return const Center(child: Text('Sin serie'));
    }

    final maxDiario = data
        .map((d) => d.porEstado.values.fold<int>(0, (a, b) => a + b))
        .fold<int>(0, (a, b) => math.max(a, b));
    final yTop = maxDiario <= 0 ? 5.0 : maxDiario * 1.2;

    return SfCartesianChart(
      margin: EdgeInsets.zero,
      plotAreaBorderWidth: 0,
      tooltipBehavior: ChartStyle.sfTooltip(shared: true),
      primaryXAxis: ChartStyle.sfCategoryAxis(
        interval: math.max(1, (days.length / 6).floor()).toDouble(),
      ),
      primaryYAxis: ChartStyle.sfNumericAxis(minimum: 0, maximum: yTop),
      series: <CartesianSeries<_DiaEstadoDatum, String>>[
        for (final estado in estadosOrdenados)
          StackedAreaSeries<_DiaEstadoDatum, String>(
            dataSource: data,
            animationDuration: 0,
            xValueMapper: (d, _) => d.label,
            yValueMapper: (d, _) => (d.porEstado[estado] ?? 0).toDouble(),
            color: _estadoColor(estado).withValues(alpha: 0.85),
            borderColor: _estadoColor(estado),
            borderWidth: 1.5,
            name: _estadoLabel(estado),
          ),
      ],
    );
  }

  // -------- Bar top operarios / conjuntos --------

  Widget _barTopOperarios() {
    if (_porOperario.isEmpty) return const Center(child: Text('Sin datos'));

    final top = [..._porOperario]..sort((a, b) => b.total.compareTo(a.total));
    final items = top.take(6).toList();
    final labels = items.map((e) => e.nombre).toList();
    final maxY = items.first.total.toDouble();

    return BarChart(
      BarChartData(
        maxY: maxY <= 0 ? 5 : maxY * 1.5,
        alignment: BarChartAlignment.spaceAround,
        groupsSpace: 28,
        barTouchData: ChartStyle.flBarTooltip(labels: labels),
        gridData: ChartStyle.flGrid(),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: ChartStyle.flValueTitles(),
          bottomTitles: ChartStyle.flCategoryTitles(
            labels,
            rotate: true,
            width: 88,
          ),
        ),
        barGroups: [
          for (int i = 0; i < items.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                ChartStyle.flRod(
                  value: items[i].total.toDouble(),
                  color: ChartStyle.slot1,
                  width: 34,
                  maxWidth: 46,
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Pareto de incidencias por operario: rechazadas + no completadas,
  /// ordenadas de mayor a menor con el % acumulado, para identificar quién
  /// concentra la mayor parte de los problemas (regla 80/20).
  Widget _paretoOperarios() {
    final conIncidencias =
        _porOperario
            .map((r) => MapEntry(r, r.rechazadas + r.noCompletadas))
            .where((e) => e.value > 0)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    if (conIncidencias.isEmpty) {
      return const _EmptyCard(
        text: 'Sin rechazos ni tareas no completadas en el rango.',
      );
    }

    final top = conIncidencias.take(10).toList();
    final totalIncidencias = conIncidencias.fold<int>(
      0,
      (a, e) => a + e.value,
    );

    var acumulado = 0;
    final data = <_ParetoDatum>[];
    for (final e in top) {
      acumulado += e.value;
      data.add(
        _ParetoDatum(
          label: e.key.nombre,
          value: e.value.toDouble(),
          cumulativePct: totalIncidencias <= 0
              ? 0
              : (acumulado / totalIncidencias) * 100,
        ),
      );
    }

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Operarios que concentran rechazos + tareas no completadas.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 300,
            child: SfCartesianChart(
              margin: EdgeInsets.zero,
              plotAreaBorderWidth: 0,
              tooltipBehavior: ChartStyle.sfTooltip(shared: true),
              primaryXAxis: ChartStyle.sfCategoryAxis(
                labelRotation: data.length > 5 ? -28 : 0,
              ),
              primaryYAxis: ChartStyle.sfNumericAxis(minimum: 0),
              axes: <ChartAxis>[
                NumericAxis(
                  name: 'pct',
                  minimum: 0,
                  maximum: 100,
                  interval: 20,
                  opposedPosition: true,
                  axisLine: const AxisLine(width: 0),
                  majorTickLines: const MajorTickLines(size: 0),
                  majorGridLines: const MajorGridLines(width: 0),
                  labelFormat: '{value}%',
                  labelStyle: ChartStyle.axisLabelStyle,
                ),
              ],
              series: <CartesianSeries<_ParetoDatum, String>>[
                ColumnSeries<_ParetoDatum, String>(
                  dataSource: data,
                  animationDuration: 0,
                  xValueMapper: (d, _) => d.label,
                  yValueMapper: (d, _) => d.value,
                  color: ChartStyle.slot8,
                  width: 0.6,
                  name: 'Incidencias',
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                ),
                LineSeries<_ParetoDatum, String>(
                  dataSource: data,
                  animationDuration: 0,
                  xValueMapper: (d, _) => d.label,
                  yValueMapper: (d, _) => d.cumulativePct,
                  yAxisName: 'pct',
                  color: ChartStyle.slot7,
                  width: 2.5,
                  markerSettings: const MarkerSettings(
                    isVisible: true,
                    height: 6,
                    width: 6,
                  ),
                  name: '% acumulado',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _legendChip('Incidencias (rech. + no compl.)', ChartStyle.slot8),
              _legendChip('% acumulado', ChartStyle.slot7),
            ],
          ),
        ],
      ),
    );
  }

  // -------- Tareas por ubicación --------

  Map<String, int> _tareasPorUbicacion() {
    final map = <String, int>{};
    for (final t in _tareasDetalle) {
      final raw = (t.ubicacion ?? '').trim();
      final key = raw.isEmpty ? 'Sin ubicación' : raw;
      map[key] = (map[key] ?? 0) + 1;
    }
    return map;
  }

  /// Barras horizontales rankeadas: para "cuantas tareas por ubicacion" el
  /// dato es comparar magnitud entre categorias con nombres largos, asi que
  /// una barra horizontal ordenada es la forma correcta (evita el pisado de
  /// etiquetas de una columna vertical y no necesita mas de un eje).
  Widget _barPorUbicacion() {
    final porUbicacion = _tareasPorUbicacion();
    if (porUbicacion.isEmpty) {
      return const _EmptyCard(text: 'Sin ubicaciones registradas en el rango.');
    }

    final entries = porUbicacion.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(8).toList();
    final maxVal = top.first.value.toDouble();
    final data = top.reversed.toList();

    return SizedBox(
      height: (top.length * 36 + 24).clamp(200, 320).toDouble(),
      child: SfCartesianChart(
        margin: EdgeInsets.zero,
        plotAreaBorderWidth: 0,
        tooltipBehavior: ChartStyle.sfTooltip(),
        primaryXAxis: CategoryAxis(
          axisLine: const AxisLine(width: 0),
          majorTickLines: const MajorTickLines(size: 0),
          majorGridLines: const MajorGridLines(width: 0),
          labelStyle: ChartStyle.axisLabelStyle,
        ),
        primaryYAxis: ChartStyle.sfNumericAxis(
          minimum: 0,
          maximum: maxVal * 1.35,
        ),
        series: <CartesianSeries<MapEntry<String, int>, String>>[
          BarSeries<MapEntry<String, int>, String>(
            dataSource: data,
            animationDuration: 0,
            xValueMapper: (d, _) => d.key,
            yValueMapper: (d, _) => d.value,
            color: ChartStyle.slot2,
            width: 0.64,
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(4),
              bottomRight: Radius.circular(4),
            ),
            dataLabelSettings: DataLabelSettings(
              isVisible: true,
              labelAlignment: ChartDataLabelAlignment.outer,
              textStyle: ChartStyle.axisLabelStyle.copyWith(
                fontWeight: FontWeight.w800,
                color: AppTheme.text,
              ),
            ),
            dataLabelMapper: (d, _) => '${d.value}',
          ),
        ],
      ),
    );
  }

  Widget _miniRatioBar(String label, double ratio, {Color? color}) {
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
              backgroundColor: ChartStyle.grid,
              color: color ?? AppTheme.primary,
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

  String _horasFromMin(int minutos) {
    return formatHoursMinutes(minutos);
  }

  Color _usoColor(double pctRaw) {
    final pct = pctRaw.isFinite ? pctRaw : 0.0;
    if (pct < 70) return ChartStyle.critical;
    if (pct < 90) return ChartStyle.warning;
    return ChartStyle.good;
  }

  Widget _usoCargaBar({
    required String label,
    required double pctRaw,
    required String detalle,
  }) {
    final pct = pctRaw.isFinite ? pctRaw : 0.0;
    final progress = (pct / 100).clamp(0.0, 1.0).toDouble();
    final color = _usoColor(pct);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
            const Spacer(),
            Text(
              '${pct.toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 10,
            backgroundColor: ChartStyle.grid,
            color: color,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          detalle,
          style: const TextStyle(fontSize: 11, color: Colors.black54),
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
        _card(
          child: Text(
            'Uso de horas asignadas: <70% rojo, 70%-90% naranja, 90%-100% verde.',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black87,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 14),
        _sectionTitle('Concentración de incidencias (Pareto)'),
        const SizedBox(height: 8),
        _paretoOperarios(),
        const SizedBox(height: 14),
        _sectionTitle('Ranking y carga (12)'),
        const SizedBox(height: 8),
        _rankingOperariosGrid(top),
      ],
    );
  }

  /// Dos columnas de tarjetas compactas (en vez de una lista larga de una
  /// sola columna): cada tarjeta muestra lo esencial y una flechita para
  /// expandir el detalle completo (horas, pills, barras) solo si se pide.
  Widget _rankingOperariosGrid(List<ResumenOperarioRow> top) {
    final col1 = <ResumenOperarioRow>[];
    final col2 = <ResumenOperarioRow>[];
    for (int i = 0; i < top.length; i++) {
      (i.isEven ? col1 : col2).add(top[i]);
    }

    Widget columna(List<ResumenOperarioRow> items) => Column(
      children: [
        for (final r in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _operarioCargaCard(r),
          ),
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: columna(col1)),
        const SizedBox(width: 10),
        Expanded(child: columna(col2)),
      ],
    );
  }

  Widget _operarioCargaCard(ResumenOperarioRow r) {
    final expandido = _operariosExpandidos.contains(r.operarioId);
    final total = r.total <= 0 ? 1 : r.total;
    final aprob = r.aprobadas / total;
    final rech = r.rechazadas / total;
    final promHoras = (r.minutosPromedio / 60).toStringAsFixed(2);
    final asigSem = _horasFromMin(r.minutosAsignadosSemana);
    final asigMes = _horasFromMin(r.minutosAsignadosMes);
    final dispSem = _horasFromMin(r.minutosDisponiblesSemana);
    final dispMes = _horasFromMin(r.minutosDisponiblesMes);

    return _card(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() {
              if (expandido) {
                _operariosExpandidos.remove(r.operarioId);
              } else {
                _operariosExpandidos.add(r.operarioId);
              }
            }),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Total ${r.total} • Uso sem. ${r.usoSemanalPct.toStringAsFixed(0)}%',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  expandido
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: AppTheme.textMuted,
                ),
              ],
            ),
          ),
          if (expandido) ...[
            const SizedBox(height: 10),
            Text(
              'ID: ${r.operarioId} • Prom: $promHoras h',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            if ((r.conjuntoCapacidadId ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'Capacidad base: ${r.conjuntoCapacidadId}',
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ],
            const SizedBox(height: 10),
            _miniRatioBar('Aprobadas', aprob, color: ChartStyle.good),
            const SizedBox(height: 6),
            _miniRatioBar('Rechazadas', rech, color: ChartStyle.critical),
            const SizedBox(height: 10),
            _usoCargaBar(
              label: 'Uso semanal',
              pctRaw: r.usoSemanalPct,
              detalle: 'Asignadas $asigSem de $dispSem disponibles.',
            ),
            const SizedBox(height: 8),
            _usoCargaBar(
              label: 'Uso mensual',
              pctRaw: r.usoMensualPct,
              detalle: 'Asignadas $asigMes de $dispMes disponibles.',
            ),
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
                _miniTextPill('Sem', '$asigSem / $dispSem'),
                _miniTextPill('Mes', '$asigMes / $dispMes'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ======================= TAB: INSUMOS =======================

  Widget _tabInsumos() {
    if (!_esReporteGeneral && _conjuntoId == null) {
      return const Center(
        child: Text('No se recibió el conjuntoId/NIT para cargar insumos.'),
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
        _sectionTitle(
          _esReporteGeneral
              ? 'Top Insumos globales (12) por cantidad'
              : 'Top Insumos (12) por cantidad',
        ),
        const SizedBox(height: 8),
        _card(
          child: SizedBox(
            height: (top.length * 34 + 24).clamp(200, 460).toDouble(),
            child: _barInsumos(top, maxQty),
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

  /// Barras horizontales: el nombre completo del insumo va a la izquierda,
  /// asi que nunca se pisa aunque haya 12 elementos en una tarjeta angosta.
  Widget _barInsumos(List<InsumoUsoRow> top, double maxQty) {
    final data = top.reversed.toList();
    return SfCartesianChart(
      margin: EdgeInsets.zero,
      plotAreaBorderWidth: 0,
      tooltipBehavior: ChartStyle.sfTooltip(),
      primaryXAxis: CategoryAxis(
        axisLine: const AxisLine(width: 0),
        majorTickLines: const MajorTickLines(size: 0),
        majorGridLines: const MajorGridLines(width: 0),
        labelStyle: ChartStyle.axisLabelStyle,
      ),
      primaryYAxis: ChartStyle.sfNumericAxis(minimum: 0, maximum: maxQty * 1.3),
      series: <CartesianSeries<InsumoUsoRow, String>>[
        BarSeries<InsumoUsoRow, String>(
          dataSource: data,
          animationDuration: 0,
          xValueMapper: (d, _) => d.nombre,
          yValueMapper: (d, _) => d.cantidad,
          color: ChartStyle.slot1,
          width: 0.62,
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(4),
            bottomRight: Radius.circular(4),
          ),
          dataLabelSettings: DataLabelSettings(
            isVisible: true,
            labelAlignment: ChartDataLabelAlignment.outer,
            textStyle: ChartStyle.axisLabelStyle.copyWith(
              fontWeight: FontWeight.w800,
              color: AppTheme.text,
            ),
          ),
          dataLabelMapper: (d, _) => d.cantidad.toStringAsFixed(2),
        ),
      ],
    );
  }

  /// versión “simple” para imprimir insumos en el PDF incluso si no hay conjuntoId
  Widget _barInsumosForPdf() {
    if (_insumos.isEmpty) {
      return const Center(child: Text('Sin insumos en este rango.'));
    }
    final sorted = [..._insumos]
      ..sort((a, b) => b.cantidad.compareTo(a.cantidad));
    final top = sorted.take(8).toList();
    final maxQty = top.first.cantidad <= 0 ? 1.0 : top.first.cantidad;
    return _barInsumos(top, maxQty);
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

  /// Lista rankeada; ya no dibuja tambien una grafica de barras redundante
  /// con exactamente el mismo dato (10 barras con etiquetas de 64px se
  /// pisaban entre si).
  Widget _topListChart(List<UsoEquipoRow> rows, {required String valueLabel}) {
    final sorted = [...rows]..sort((a, b) => b.usos.compareTo(a.usos));
    final top = sorted.take(10).toList();
    final maxUsos = top.first.usos <= 0 ? 1 : top.first.usos;

    return Column(
      children: [
        for (int i = 0; i < top.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == top.length - 1 ? 0 : 10),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    top[i].nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: (top[i].usos / maxUsos).clamp(0.0, 1.0),
                      minHeight: 10,
                      backgroundColor: ChartStyle.grid,
                      color: ChartStyle.slot1,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 78,
                  child: Text(
                    '${top[i].usos} $valueLabel',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ======================= TAB: TIPOS =======================

  Widget _tabTipos() {
    if (_tareasDetalle.isEmpty) {
      return const Center(child: Text('Sin datos en el rango.'));
    }

    final conteo = _contarTipos();
    final prev = conteo['preventivas'] ?? 0;
    final corr = conteo['correctivas'] ?? 0;
    final total = math.max(1, prev + corr);
    final preventivas = _cumplimientoPreventivasPorDefinicion();
    final correctivas = _cumplimientoCorrectivas();

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
                        ChartStyle.slot1,
                      ),
                      const SizedBox(height: 10),
                      _legendItem(
                        'Correctivas',
                        corr,
                        corr / total,
                        ChartStyle.slot3,
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
        _sectionTitle('Cumplimiento de correctivas'),
        const SizedBox(height: 8),
        _cumplimientoCard(correctivas, mostrarFrecuencia: false),
        const SizedBox(height: 14),
        _sectionTitle('Cumplimiento por definición preventiva'),
        const SizedBox(height: 8),
        if (preventivas.isEmpty)
          const _EmptyCard(text: 'No hay tareas preventivas en el rango.')
        else
          ...preventivas.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _cumplimientoCard(item),
            ),
          ),
      ],
    );
  }

  List<_CumplimientoSerieDatum> _cumplimientoPreventivasPorDefinicion() {
    final grupos = <String, List<TareaDetalleRow>>{};

    for (final tarea in _tareasDetalle) {
      if (tarea.tipo.toUpperCase().trim() != 'PREVENTIVA') continue;
      final base = tarea.descripcion.trim().isEmpty
          ? 'Preventiva sin nombre'
          : tarea.descripcion.trim();
      final frecuencia = (tarea.frecuencia ?? '').trim();
      final key = frecuencia.isEmpty ? base : '$base||$frecuencia';
      grupos.putIfAbsent(key, () => <TareaDetalleRow>[]).add(tarea);
    }

    final out = grupos.entries.map((entry) {
      final partes = entry.key.split('||');
      final lista = [...entry.value]
        ..sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));
      return _buildCumplimientoSerie(
        titulo: partes.first,
        frecuencia: partes.length > 1 ? partes.last : null,
        tareas: lista,
      );
    }).toList();

    out.sort((a, b) => b.total.compareTo(a.total));
    return out;
  }

  _CumplimientoSerieDatum _cumplimientoCorrectivas() {
    final lista =
        _tareasDetalle
            .where((t) => t.tipo.toUpperCase().trim() == 'CORRECTIVA')
            .toList()
          ..sort((a, b) => a.fechaInicio.compareTo(b.fechaInicio));
    return _buildCumplimientoSerie(
      titulo: 'Correctivas del rango',
      frecuencia: null,
      tareas: lista,
    );
  }

  _CumplimientoSerieDatum _buildCumplimientoSerie({
    required String titulo,
    required String? frecuencia,
    required List<TareaDetalleRow> tareas,
  }) {
    var cumplidas = 0;
    var noCumplidas = 0;
    var pendientes = 0;

    for (int i = 0; i < tareas.length; i++) {
      final estado = tareas[i].estado.toUpperCase().trim();
      if (_estadoCumplido(estado)) {
        cumplidas++;
      } else if (_estadoNoCumplido(estado)) {
        noCumplidas++;
      } else {
        pendientes++;
      }
    }

    return _CumplimientoSerieDatum(
      titulo: titulo,
      frecuencia: frecuencia,
      total: tareas.length,
      cumplidas: cumplidas,
      noCumplidas: noCumplidas,
      pendientes: pendientes,
    );
  }

  bool _estadoCumplido(String estado) {
    return estado == 'APROBADA' || estado == 'COMPLETADA';
  }

  bool _estadoNoCumplido(String estado) {
    return estado == 'NO_COMPLETADA' || estado == 'RECHAZADA';
  }

  Widget _cumplimientoCard(
    _CumplimientoSerieDatum data, {
    bool mostrarFrecuencia = true,
  }) {
    final totalCerradas = data.cumplidas + data.noCumplidas;
    final ratio = totalCerradas == 0 ? 0.0 : data.cumplidas / totalCerradas;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.titulo,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (mostrarFrecuencia &&
                        (data.frecuencia ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _miniTextPill('Frecuencia', data.frecuencia!.trim()),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 132,
                height: 132,
                child: _donutCumplimiento(
                  cumplidas: data.cumplidas,
                  noCumplidas: data.noCumplidas,
                  pendientes: data.pendientes,
                  center: '${(ratio * 100).toStringAsFixed(0)}%',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _legendChip('Cumplidas', ChartStyle.good),
              _legendChip('No cumplidas', ChartStyle.critical),
              _legendChip('Pendientes', ChartStyle.warning),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _miniPill('Total', data.total),
              _miniPill('Cumplidas', data.cumplidas),
              _miniPill('No cumplidas', data.noCumplidas),
              _miniPill('Pendientes', data.pendientes),
            ],
          ),
        ],
      ),
    );
  }

  Widget _donutCumplimiento({
    required int cumplidas,
    required int noCumplidas,
    required int pendientes,
    required String center,
  }) {
    final total = cumplidas + noCumplidas + pendientes;
    if (total <= 0) {
      return const Center(child: Text('Sin datos'));
    }

    final data = <_ChartSliceDatum>[
      _ChartSliceDatum(
        label: 'Cumplidas',
        value: cumplidas.toDouble(),
        color: ChartStyle.good,
      ),
      _ChartSliceDatum(
        label: 'No cumplidas',
        value: noCumplidas.toDouble(),
        color: ChartStyle.critical,
      ),
      _ChartSliceDatum(
        label: 'Pendientes',
        value: pendientes.toDouble(),
        color: ChartStyle.warning,
      ),
    ];

    return SfCircularChart(
      margin: EdgeInsets.zero,
      tooltipBehavior: ChartStyle.sfTooltip(),
      series: <CircularSeries<_ChartSliceDatum, String>>[
        DoughnutSeries<_ChartSliceDatum, String>(
          dataSource: data,
          animationDuration: 0,
          xValueMapper: (_ChartSliceDatum d, _) => d.label,
          yValueMapper: (_ChartSliceDatum d, _) => d.value,
          pointColorMapper: (_ChartSliceDatum d, _) => d.color,
          innerRadius: '62%',
          radius: '88%',
        ),
      ],
      annotations: <CircularChartAnnotation>[
        CircularChartAnnotation(
          widget: ChartStyle.donutCenter(center, 'cumpl.'),
        ),
      ],
    );
  }

  Widget _pieTipos({required int prev, required int corr}) {
    final total = prev + corr;
    if (total <= 0) return const Center(child: Text('Sin datos'));

    final data = <_ChartSliceDatum>[
      _ChartSliceDatum(
        label: 'Preventivas',
        value: prev.toDouble(),
        color: ChartStyle.slot1,
      ),
      _ChartSliceDatum(
        label: 'Correctivas',
        value: corr.toDouble(),
        color: ChartStyle.slot3,
      ),
    ];

    return SfCircularChart(
      margin: EdgeInsets.zero,
      tooltipBehavior: ChartStyle.sfTooltip(),
      series: <CircularSeries<_ChartSliceDatum, String>>[
        DoughnutSeries<_ChartSliceDatum, String>(
          dataSource: data,
          animationDuration: 0,
          xValueMapper: (d, _) => d.label,
          yValueMapper: (d, _) => d.value,
          pointColorMapper: (d, _) => d.color,
          innerRadius: '60%',
          radius: '88%',
          dataLabelMapper: (d, _) =>
              '${(d.value / total * 100).toStringAsFixed(0)}%',
          dataLabelSettings: ChartStyle.sfDonutLabels,
        ),
      ],
      annotations: <CircularChartAnnotation>[
        CircularChartAnnotation(
          widget: ChartStyle.donutCenter('$total', 'tareas'),
        ),
      ],
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
        _analisisEditableCard(),
        const SizedBox(height: 14),

        _sectionTitle('Informes automáticos'),
        const SizedBox(height: 8),
        _card(
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (_kpis == null || _generandoPdf)
                      ? null
                      : _generarInformeGestionPdfV2,
                  icon: _generandoPdf
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.insights),
                  label: Text(
                    _generandoPdf ? 'Generando...' : 'Gestión (solo gráficas)',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _tareasDetalle.isEmpty
                      ? null
                      : _generarInformeDetalladoPdfV2,
                  icon: const Icon(Icons.list_alt),
                  label: const Text('Detallado (PDF)'),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),
        _sectionTitle('Tareas del rango'),
        const SizedBox(height: 8),
        _tareasCalendarSection(),
      ],
    );
  }

  /// Analisis editable colapsado por defecto: son 8 campos de texto que
  /// antes ocupaban toda la parte superior de la pestaña Informes.
  Widget _analisisEditableCard() {
    final total = 4;
    final conTexto = _analisisConTexto();
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.black12),
      ),
      child: ExpansionTile(
        initiallyExpanded: false,
        title: const Text(
          'Análisis del informe',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
        ),
        subtitle: Text(
          'Se imprime en el PDF · $conTexto de $total con texto',
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: [
          _analisisBlock(
            1,
            'Tareas preventivas y correctivas',
            _a11Ctrl,
            _p11Ctrl,
          ),
          const Divider(height: 24),
          _analisisBlock(2, 'Distribución por estado', _a12Ctrl, _p12Ctrl),
          const Divider(height: 24),
          _analisisBlock(3, 'Tareas por día (tendencia)', _a13Ctrl, _p13Ctrl),
          const Divider(height: 24),
          _analisisBlock(4, 'Insumos usados', _a14Ctrl, _p14Ctrl),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _regenerarAnalisis,
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('Regenerar texto base'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _analisisBlock(
    int numero,
    String title,
    TextEditingController analisis,
    TextEditingController plan,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Text(
                '$numero',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: analisis,
          maxLines: 4,
          maxLength: 600,
          decoration: const InputDecoration(
            labelText: 'Análisis del mes',
            hintText: 'Ej: la tasa de cierre fue de 92%, con recurrencia en...',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: plan,
          maxLines: 2,
          maxLength: 300,
          decoration: const InputDecoration(
            labelText: 'Plan de acción',
            hintText: 'Ej: reforzar el plan preventivo del conjunto...',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }

  // ======================= CALENDARIO "TAREAS DEL RANGO" =======================

  Widget _tareasCalendarSection() {
    if (_tareasDetalle.isEmpty) {
      return const _EmptyCard(text: 'Sin tareas en este rango.');
    }

    final porDia = _agruparTareasPorDia();
    final maxCount = porDia.values.fold<int>(
      0,
      (a, b) => math.max(a, b.length),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _calendarMonthHeader(),
              const SizedBox(height: 2),
              Text(
                '${_tareasDetalle.length} tarea(s) en el rango seleccionado',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 6),
              const Text(
                'Toca un día para ver el detalle de sus tareas. El número '
                'que aparece en la casilla es la cantidad de tareas de ese día.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 14),
              _calendarGrid(porDia, maxCount),
              const SizedBox(height: 14),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 8,
                children: [
                  const Text(
                    'Menos tareas',
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                  for (var i = 1; i <= 4; i++)
                    Container(
                      width: 18,
                      height: 12,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: ChartStyle.heat(i, 4),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: Colors.black12),
                      ),
                    ),
                  const Text(
                    'Más tareas',
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(
                    () => _verTodasLasTareas = !_verTodasLasTareas,
                  ),
                  child: Text(
                    _verTodasLasTareas
                        ? 'Ocultar lista completa'
                        : 'Ver todas las tareas del rango',
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_verTodasLasTareas) ...[
          const SizedBox(height: 14),
          ..._tareasDetalle.map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _tareaDetalleCard(t),
            ),
          ),
        ],
      ],
    );
  }

  Widget _calendarMonthHeader() {
    final mesFmt = DateFormat('MMMM yyyy', 'es');
    final mesInicio = DateTime(_desde.year, _desde.month);
    final mesFin = DateTime(_hasta.year, _hasta.month);
    final label = mesFmt.format(_calMes);
    final labelCap = label.isEmpty
        ? label
        : '${label[0].toUpperCase()}${label.substring(1)}';

    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: _calMes.isAfter(mesInicio)
              ? () => setState(() {
                  _calMes = DateTime(_calMes.year, _calMes.month - 1);
                  _calDia = null;
                })
              : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(
            labelCap,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: _calMes.isBefore(mesFin)
              ? () => setState(() {
                  _calMes = DateTime(_calMes.year, _calMes.month + 1);
                  _calDia = null;
                })
              : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  Widget _calendarGrid(
    Map<DateTime, List<TareaDetalleRow>> porDia,
    int maxCount,
  ) {
    const weekDays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    final diasEnMes = DateTime(_calMes.year, _calMes.month + 1, 0).day;
    final primerDiaSemana = DateTime(_calMes.year, _calMes.month, 1).weekday;
    final rangoDesde = _dateOnly(_desde);
    final rangoHasta = _dateOnly(_hasta);
    final hoy = _dateOnly(DateTime.now());

    final celdas = <Widget>[];
    for (var i = 1; i < primerDiaSemana; i++) {
      celdas.add(const SizedBox.shrink());
    }
    for (var dia = 1; dia <= diasEnMes; dia++) {
      final fecha = DateTime(_calMes.year, _calMes.month, dia);
      final enRango = !fecha.isBefore(rangoDesde) && !fecha.isAfter(rangoHasta);
      if (!enRango) {
        celdas.add(
          Padding(
            padding: const EdgeInsets.all(6),
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                '$dia',
                style: const TextStyle(fontSize: 12, color: Colors.black26),
              ),
            ),
          ),
        );
        continue;
      }
      final tareas = porDia[fecha] ?? const <TareaDetalleRow>[];
      celdas.add(
        _calendarDayCell(
          fecha: fecha,
          dia: dia,
          count: tareas.length,
          maxCount: maxCount,
          seleccionado: _calDia != null && _calDia == fecha,
          esHoy: fecha == hoy,
          onTap: tareas.isEmpty
              ? null
              : () {
                  setState(() => _calDia = fecha);
                  _openDiaModal(fecha, tareas);
                },
        ),
      );
    }

    return Column(
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: weekDays.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 2.6,
          ),
          itemBuilder: (_, i) => Center(
            child: Text(
              weekDays[i],
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.black54,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: celdas.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
            childAspectRatio: 1.55,
          ),
          itemBuilder: (_, i) => celdas[i],
        ),
      ],
    );
  }

  /// Blanco o negro según qué tanto contraste da sobre [background], para que
  /// el número del día se siga viendo incluso en las casillas más "calientes"
  /// (verde oscuro) del mapa de calor.
  Color _contrastTextColor(Color background) {
    final opaco = Color.alphaBlend(background, Colors.white);
    return opaco.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;
  }

  Widget _calendarDayCell({
    required DateTime fecha,
    required int dia,
    required int count,
    required int maxCount,
    required bool seleccionado,
    required bool esHoy,
    required VoidCallback? onTap,
  }) {
    final tieneTareas = count > 0;
    final bg = seleccionado
        ? AppTheme.primary
        : ChartStyle.heat(count, maxCount);
    final fg = _contrastTextColor(bg);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: seleccionado
                ? AppTheme.primaryDark
                : (esHoy ? AppTheme.primary : Colors.black12),
            width: !seleccionado && esHoy ? 1.6 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '$dia',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: fg,
              ),
            ),
            const Spacer(),
            if (tieneTareas)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: seleccionado ? Colors.white : AppTheme.primaryDark,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: seleccionado ? AppTheme.primaryDark : Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Modal "vista del día": muestra la lista de tareas de un día puntual del
  /// calendario. Tocar una tarea abre su detalle completo (_openTareaModal)
  /// encima de este modal.
  /// Vista de un día tipo Google Calendar: franja horaria a la izquierda con
  /// las tareas ubicadas por hora, filtros (operario/tipo, igual que en el
  /// cronograma) y a la derecha la lista de tareas del día. Tocar una tarea
  /// (en la línea de tiempo o en la lista) abre su detalle completo.
  void _openDiaModal(DateTime fecha, List<TareaDetalleRow> todasLasTareas) {
    final dfTitulo = DateFormat("EEEE d 'de' MMMM", 'es');
    final titulo = dfTitulo.format(fecha);
    final tituloCap = titulo.isEmpty
        ? titulo
        : '${titulo[0].toUpperCase()}${titulo.substring(1)}';

    final operariosDisponibles =
        todasLasTareas.expand((t) => t.operarios).toSet().toList()..sort();

    var operarioFiltro = 'TODOS';
    var tipoFiltro = 'TODAS';
    var escalaMinutos = 30;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogCtx, setModalState) {
          final tareas = todasLasTareas.where((t) {
            if (operarioFiltro != 'TODOS' &&
                !t.operarios.contains(operarioFiltro)) {
              return false;
            }
            if (tipoFiltro != 'TODAS' &&
                t.tipo.toUpperCase().trim() != tipoFiltro) {
              return false;
            }
            return true;
          }).toList();

          final pantalla = MediaQuery.of(dialogCtx).size;
          final anchoDialogo = math.min(1100.0, pantalla.width - 32);
          final altoDialogo = math.min(780.0, pantalla.height - 32);

          return Dialog(
            insetPadding: const EdgeInsets.all(14),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: anchoDialogo),
              child: SizedBox(
                height: altoDialogo,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tituloCap,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${tareas.length} de ${todasLasTareas.length} tarea(s)',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: _diaFiltroDropdown(
                              label: 'Operario',
                              value: operarioFiltro,
                              items: [
                                const DropdownMenuItem(
                                  value: 'TODOS',
                                  child: Text('Todos'),
                                ),
                                for (final op in operariosDisponibles)
                                  DropdownMenuItem(
                                    value: op,
                                    child: Text(
                                      op,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (v) =>
                                  setModalState(() => operarioFiltro = v),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _diaFiltroDropdown(
                              label: 'Tipo',
                              value: tipoFiltro,
                              items: const [
                                DropdownMenuItem(
                                  value: 'TODAS',
                                  child: Text('Todas'),
                                ),
                                DropdownMenuItem(
                                  value: 'PREVENTIVA',
                                  child: Text('Preventivas'),
                                ),
                                DropdownMenuItem(
                                  value: 'CORRECTIVA',
                                  child: Text('Correctivas'),
                                ),
                              ],
                              onChanged: (v) =>
                                  setModalState(() => tipoFiltro = v),
                            ),
                          ),
                          const SizedBox(width: 10),
                          PopupMenuButton<int>(
                            tooltip: 'Cambiar escala',
                            initialValue: escalaMinutos,
                            onSelected: (value) =>
                                setModalState(() => escalaMinutos = value),
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 1,
                                child: Text('Escala 1 minuto'),
                              ),
                              PopupMenuItem(
                                value: 15,
                                child: Text('Escala 15 minutos'),
                              ),
                              PopupMenuItem(
                                value: 30,
                                child: Text('Escala 30 minutos'),
                              ),
                              PopupMenuItem(
                                value: 60,
                                child: Text('Escala 1 hora'),
                              ),
                            ],
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade400),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.zoom_in, size: 18),
                                  const SizedBox(width: 6),
                                  Text('Escala ${escalaMinutos}m'),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: tareas.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(20),
                              child: Text(
                                'Sin tareas para este filtro.',
                                style: TextStyle(color: Colors.black54),
                              ),
                            )
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                final estrecho = constraints.maxWidth < 720;
                                final timeline = Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: _diaTimeline(
                                    tareas,
                                    fecha,
                                    pxPorMin: _pxPorMinParaEscala(
                                      escalaMinutos,
                                    ),
                                  ),
                                );
                                final lista = ListView.builder(
                                  padding: const EdgeInsets.all(14),
                                  itemCount: tareas.length,
                                  itemBuilder: (_, i) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _tareaDetalleCard(tareas[i]),
                                  ),
                                );

                                if (estrecho) {
                                  return Column(
                                    children: [
                                      SizedBox(height: 320, child: timeline),
                                      const Divider(height: 1),
                                      Expanded(child: lista),
                                    ],
                                  );
                                }

                                return Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(flex: 3, child: timeline),
                                    const VerticalDivider(width: 1),
                                    Expanded(flex: 2, child: lista),
                                  ],
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _diaFiltroDropdown({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 8,
        ),
      ),
      items: items,
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  /// Igual mapeo escala->px/min que la vista semanal del cronograma, para que
  /// "más grande"/"más chico" se comporte igual en los dos lugares.
  double _pxPorMinParaEscala(int escalaMinutos) {
    switch (escalaMinutos) {
      case 1:
        return 15.6;
      case 15:
        return 2.4;
      case 30:
        return 1.7;
      default:
        return 1.1;
    }
  }

  /// Altura mínima de un bloque para que siempre quepan sus 3 líneas (hora,
  /// descripción, ubicación) sin overflow, aunque la tarea dure muy poco.
  static const double _alturaMinimaBloque = 54;

  /// Línea de tiempo de un día (estilo agenda de Google Calendar): eje de
  /// horas a la izquierda y bloques de tareas ubicados/dimensionados según su
  /// hora de inicio y duración; las que se solapan se acomodan en columnas.
  Widget _diaTimeline(
    List<TareaDetalleRow> tareas,
    DateTime fecha, {
    required double pxPorMin,
  }) {
    final bloques = _layoutBloquesDia(tareas, fecha);
    if (bloques.isEmpty) {
      return const Center(child: Text('Sin tareas para este filtro.'));
    }

    var horaInicio = (bloques
                .map((b) => b.inicioMin)
                .reduce(math.min) /
            60)
        .floor();
    var horaFin = (bloques.map((b) => b.finMin).reduce(math.max) / 60).ceil();
    horaInicio = (horaInicio - 1).clamp(0, 22);
    horaFin = (horaFin + 1).clamp(horaInicio + 1, 24);

    final offsetMin = horaInicio * 60;
    final alturaTotal = (horaFin - horaInicio) * 60 * pxPorMin;
    const anchoHoras = 46.0;

    // Un bloque corto se agranda hasta _alturaMinimaBloque para que se
    // alcance a leer, pero esa altura NUNCA debe invadir el bloque
    // siguiente. Como la posición vertical se calcula solo con la hora real
    // (no hay "empuje" entre hermanos en un Stack), hay que topar la altura
    // de cada bloque con el inicio del próximo que comparte su misma
    // columna visual (agrupando por índice de columna cruzando clusters,
    // que por construcción nunca se solapan en el tiempo entre sí).
    final porColumna = <int, List<_TimelineBlock>>{};
    for (final b in bloques) {
      porColumna.putIfAbsent(b.columna, () => []).add(b);
    }
    for (final lista in porColumna.values) {
      lista.sort((a, c) => a.inicioMin.compareTo(c.inicioMin));
    }
    final topeMinPorBloque = <_TimelineBlock, int>{};
    for (final lista in porColumna.values) {
      for (var i = 0; i < lista.length - 1; i++) {
        topeMinPorBloque[lista[i]] = lista[i + 1].inicioMin;
      }
    }

    return SingleChildScrollView(
      child: SizedBox(
        height: alturaTotal,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final anchoDisponible = math.max(
              0.0,
              constraints.maxWidth - anchoHoras,
            );
            return Stack(
              children: [
                for (var h = horaInicio; h <= horaFin; h++)
                  Positioned(
                    top: (h * 60 - offsetMin) * pxPorMin,
                    left: 0,
                    right: 0,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: anchoHoras,
                          child: Text(
                            '${h.toString().padLeft(2, '0')}:00',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.black45,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Container(height: 1, color: Colors.black12),
                        ),
                      ],
                    ),
                  ),
                for (final b in bloques)
                  Positioned(
                    top: (b.inicioMin - offsetMin) * pxPorMin,
                    left:
                        anchoHoras +
                        4 +
                        b.columna * (anchoDisponible / b.totalColumnas),
                    width: (anchoDisponible / b.totalColumnas) - 4,
                    height: math.min(
                      math.max(
                        (b.finMin - b.inicioMin) * pxPorMin,
                        _alturaMinimaBloque,
                      ),
                      topeMinPorBloque.containsKey(b)
                          ? math.max(
                              4.0,
                              (topeMinPorBloque[b]! - b.inicioMin) * pxPorMin,
                            )
                          : double.infinity,
                    ),
                    child: _bloqueTareaTimeline(b.tarea),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Cuántas líneas de texto (hora, descripción, ubicación) mostrar dado
  /// [alturaDisponible] (ya sin el padding/borde del Container, porque
  /// LayoutBuilder recibe las constraints DESPUÉS de que Container los
  /// descuenta). Es solo una heurística de CALIDAD -para que, ante muy poco
  /// espacio, se oculten líneas en vez de mostrar texto ilegible- y no algo
  /// de lo que dependa evitar el overflow: eso lo garantiza el `Flexible`
  /// en cada línea (ver [_bloqueTareaTimeline]), así que no importa qué tan
  /// preciso sea este número ni a qué escala de zoom esté el calendario.
  int _lineasQueCaben(double alturaDisponible) {
    const altoLinea = 15.0;
    return (alturaDisponible / altoLinea).floor().clamp(0, 3);
  }

  Widget _bloqueTareaTimeline(TareaDetalleRow t) {
    final color = _estadoColor(t.estado);
    final onColor = _contrastTextColor(color);
    final df = DateFormat('HH:mm', 'es');
    final ubicacion = (t.ubicacion ?? '').trim();

    return InkWell(
      onTap: () => _openTareaModal(t),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final lineas = _lineasQueCaben(constraints.maxHeight);

            // Cada línea va en un Flexible: el Column reparte el alto que
            // de verdad tiene entre las líneas visibles en vez de exigir la
            // altura natural de cada Text. Así, sin importar la duración de
            // la tarea, la escala de zoom elegida o cuántas tareas cortas
            // haya seguidas, el Column jamás pide más espacio del que el
            // bloque realmente tiene -nunca más "RenderFlex overflowed"-,
            // en cualquier conjunto.
            Widget linea(String texto, TextStyle style) => Flexible(
              child: Text(
                texto,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (lineas >= 3)
                  linea(
                    '${df.format(t.fechaInicio)}–${df.format(t.fechaFin)}',
                    TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: onColor.withValues(alpha: 0.85),
                    ),
                  ),
                if (lineas >= 1)
                  linea(
                    t.descripcion,
                    TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: onColor,
                    ),
                  ),
                if (lineas >= 2 && ubicacion.isNotEmpty)
                  linea(
                    ubicacion,
                    TextStyle(fontSize: 9, color: onColor.withValues(alpha: 0.85)),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Agrupa tareas que se solapan en el tiempo y les asigna columna dentro de
  /// su grupo (packing tipo "google calendar"), sin castigar con más columnas
  /// de las necesarias a tareas de otro momento del día que no se solapan.
  List<_TimelineBlock> _layoutBloquesDia(
    List<TareaDetalleRow> tareas,
    DateTime fecha,
  ) {
    final diaInicio = DateTime(fecha.year, fecha.month, fecha.day);
    final diaFin = diaInicio.add(const Duration(days: 1));

    final items = <_TimelineItem>[];
    for (final t in tareas) {
      var ini = t.fechaInicio.isBefore(diaInicio) ? diaInicio : t.fechaInicio;
      var fin = t.fechaFin.isAfter(diaFin) ? diaFin : t.fechaFin;
      if (!fin.isAfter(ini)) fin = ini.add(const Duration(minutes: 20));
      items.add(_TimelineItem(tarea: t, inicio: ini, fin: fin));
    }
    items.sort((a, b) => a.inicio.compareTo(b.inicio));

    final clusters = <List<_TimelineItem>>[];
    var current = <_TimelineItem>[];
    DateTime? clusterFin;
    for (final item in items) {
      if (clusterFin == null || item.inicio.isBefore(clusterFin)) {
        current.add(item);
        clusterFin = clusterFin == null || item.fin.isAfter(clusterFin)
            ? item.fin
            : clusterFin;
      } else {
        clusters.add(current);
        current = [item];
        clusterFin = item.fin;
      }
    }
    if (current.isNotEmpty) clusters.add(current);

    final placements = <_TimelineBlock>[];
    for (final cluster in clusters) {
      final columnasFin = <DateTime>[];
      final colDeItem = <_TimelineItem, int>{};
      for (final item in cluster) {
        var col = -1;
        for (var i = 0; i < columnasFin.length; i++) {
          if (!item.inicio.isBefore(columnasFin[i])) {
            col = i;
            break;
          }
        }
        if (col == -1) {
          col = columnasFin.length;
          columnasFin.add(item.fin);
        } else {
          columnasFin[col] = item.fin;
        }
        colDeItem[item] = col;
      }
      final totalCols = columnasFin.length;
      for (final item in cluster) {
        placements.add(
          _TimelineBlock(
            tarea: item.tarea,
            inicioMin: item.inicio.difference(diaInicio).inMinutes,
            finMin: item.fin.difference(diaInicio).inMinutes,
            columna: colDeItem[item]!,
            totalColumnas: totalCols,
          ),
        );
      }
    }
    return placements;
  }

  Widget _tareaDetalleCard(TareaDetalleRow t) {
    final df = DateFormat('dd/MM HH:mm', 'es');
    return InkWell(
      onTap: () => _openTareaModal(t),
      child: _card(
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: .10),
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
                  if ((t.ubicacion ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(
                          Icons.place_outlined,
                          size: 13,
                          color: Colors.black54,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            t.ubicacion!.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _chipState(t.estado),
                      if (t.esTareaReemplazo)
                        _replacementInfoChip(t, compact: true),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${df.format(t.fechaInicio)} → ${df.format(t.fechaFin)} • ${t.duracionMinutos} min',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  if (t.noCompletadaPorReemplazo ||
                      (t.motivoNoCompletada ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      (t.motivoNoCompletada ?? '').trim().isNotEmpty
                          ? t.motivoNoCompletada!.trim()
                          : (t.reemplazadaPorTareaId != null
                                ? 'No fue completada porque fue reemplazada por la correctiva #${t.reemplazadaPorTareaId}.'
                                : 'No fue completada por reemplazo.'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    'Evidencias: ${t.evidencias.length}',
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  // ======================= MODAL (tu versión) =======================

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
                Row(
                  children: [
                    _chipBadge(t.tipo),
                    const SizedBox(width: 8),
                    _chipState(t.estado),
                    if (t.esTareaReemplazo) ...[
                      const SizedBox(width: 8),
                      _replacementInfoChip(t),
                    ],
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
                      if (t.esTareaReemplazo)
                        _kv('Aviso reemplazo', _replacementInfoText(t)),
                      if (t.noCompletadaPorReemplazo ||
                          (t.motivoNoCompletada ?? '').trim().isNotEmpty)
                        _kv(
                          'Motivo no completada',
                          (t.motivoNoCompletada ?? '').trim().isNotEmpty
                              ? t.motivoNoCompletada!.trim()
                              : (t.reemplazadaPorTareaId != null
                                    ? 'Fue reemplazada por la correctiva #${t.reemplazadaPorTareaId}.'
                                    : 'No completada por reemplazo.'),
                        ),
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
                    children: [
                      for (
                        var i = 0;
                        i < t.evidencias.length && i < 12;
                        i++
                      )
                        InkWell(
                          onTap: () =>
                              _openEvidenciasCarousel(t.evidencias, i),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: 150,
                              height: 110,
                              color: Colors.black12,
                              child: EvidenceImage(
                                urls: _evidenceUrlCandidates(t.evidencias[i]),
                                fit: BoxFit.cover,
                                fallback: const Center(
                                  child: Icon(Icons.image_not_supported),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Carrusel de evidencias a pantalla completa: si la tarea tiene varias,
  /// se puede deslizar/usar las flechas para pasar entre todas partiendo de
  /// la que se tocó.
  void _openEvidenciasCarousel(List<String> evidencias, int initialIndex) {
    final total = evidencias.length;
    final controller = PageController(initialPage: initialIndex);
    var current = initialIndex;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Dialog(
          insetPadding: const EdgeInsets.all(12),
          backgroundColor: Colors.black,
          child: SizedBox(
            width: double.infinity,
            height: MediaQuery.of(ctx).size.height * 0.85,
            child: Stack(
              children: [
                PageView.builder(
                  controller: controller,
                  itemCount: total,
                  onPageChanged: (i) => setModalState(() => current = i),
                  itemBuilder: (_, i) => InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4,
                    child: Center(
                      child: EvidenceImage(
                        urls: _evidenceUrlCandidates(evidencias[i]),
                        fit: BoxFit.contain,
                        fallback: const Center(
                          child: Icon(
                            Icons.image_not_supported,
                            color: Colors.white70,
                            size: 48,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ),
                if (total > 1) ...[
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: IconButton(
                        onPressed: current > 0
                            ? () => controller.previousPage(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOut,
                              )
                            : null,
                        icon: const Icon(
                          Icons.chevron_left,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: IconButton(
                        onPressed: current < total - 1
                            ? () => controller.nextPage(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOut,
                              )
                            : null,
                        icon: const Icon(
                          Icons.chevron_right,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 14,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${current + 1} / $total',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
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
        color: AppTheme.primary.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.primary.withValues(alpha: .25)),
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
    final bg = _estadoColor(txt);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: bg.withValues(alpha: .38)),
      ),
      child: Text(
        _estadoLabel(txt),
        style: TextStyle(color: bg, fontWeight: FontWeight.w900, fontSize: 12),
      ),
    );
  }

  bool _replacementWarn(TareaDetalleRow t) {
    final estado = _estadoKey(t.estado);
    return estado != 'APROBADA' && estado != 'COMPLETADA';
  }

  List<String> _replacementRefs(TareaDetalleRow t) {
    return t.reemplazaPreventivas
        .map((m) {
          final raw = m['tareaId'];
          final descripcion = (m['descripcion'] ?? '').toString().trim();
          final descCorta = descripcion.length > 52
              ? '${descripcion.substring(0, 52).trim()}...'
              : descripcion;
          if (raw is num) {
            return descCorta.isNotEmpty
                ? '#${raw.toInt()} ($descCorta)'
                : '#${raw.toInt()}';
          }
          final asInt = int.tryParse('${raw ?? ''}');
          if (asInt == null) return null;
          return descCorta.isNotEmpty ? '#$asInt ($descCorta)' : '#$asInt';
        })
        .whereType<String>()
        .toList();
  }

  String _replacementInfoText(TareaDetalleRow t) {
    final explicit = (t.motivoTareaReemplazo ?? '').trim();
    if (explicit.isNotEmpty) return explicit;

    final refs = _replacementRefs(t);

    if (refs.isNotEmpty) {
      final cut = refs.take(3).toList();
      final extra = refs.length > cut.length
          ? ' y ${refs.length - cut.length} más'
          : '';
      return 'Esta fue el reemplazo de ${cut.join(', ')}$extra.';
    }

    return 'Esta fue el reemplazo de una preventiva.';
  }

  Widget _replacementInfoChip(TareaDetalleRow t, {bool compact = false}) {
    final warn = _replacementWarn(t);
    final base = warn ? ChartStyle.warning : ChartStyle.good;
    final refs = _replacementRefs(t);
    final maxRefs = compact ? 1 : 2;
    final slice = refs.take(maxRefs).toList();
    final suffix = refs.length > slice.length ? ' +' : '';
    final label = slice.isNotEmpty
        ? 'Reemplazo de ${slice.join(', ')}$suffix'
        : (compact ? 'Reemplazo' : 'Reemplazo de preventiva');

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 10,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: base.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: base.withValues(alpha: .36)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: base,
          fontWeight: FontWeight.w900,
          fontSize: compact ? 11 : 12,
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .04),
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

  Widget _miniTextPill(String label, String value) {
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

class _CumplimientoSerieDatum {
  final String titulo;
  final String? frecuencia;
  final int total;
  final int cumplidas;
  final int noCumplidas;
  final int pendientes;

  const _CumplimientoSerieDatum({
    required this.titulo,
    required this.frecuencia,
    required this.total,
    required this.cumplidas,
    required this.noCumplidas,
    required this.pendientes,
  });
}

class _ChartSliceDatum {
  final String label;
  final double value;
  final Color color;

  const _ChartSliceDatum({
    required this.label,
    required this.value,
    required this.color,
  });
}

class _DiaEstadoDatum {
  final String label;
  final Map<String, int> porEstado;

  const _DiaEstadoDatum({required this.label, required this.porEstado});
}

class _CompromisoTrendDatum {
  final String label;
  final double creados;
  final double cerrados;

  const _CompromisoTrendDatum({
    required this.label,
    required this.creados,
    required this.cerrados,
  });
}

class _ParetoDatum {
  final String label;
  final double value;
  final double cumulativePct;

  const _ParetoDatum({
    required this.label,
    required this.value,
    required this.cumulativePct,
  });
}

class _TimelineItem {
  final TareaDetalleRow tarea;
  final DateTime inicio;
  final DateTime fin;

  const _TimelineItem({
    required this.tarea,
    required this.inicio,
    required this.fin,
  });
}

class _TimelineBlock {
  final TareaDetalleRow tarea;
  final int inicioMin;
  final int finMin;
  final int columna;
  final int totalColumnas;

  const _TimelineBlock({
    required this.tarea,
    required this.inicioMin,
    required this.finMin,
    required this.columna,
    required this.totalColumnas,
  });
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
        boxShadow: const [
          BoxShadow(
            blurRadius: 12,
            color: Color(0x0A000000),
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54),
        ),
      ),
    );
  }
}
