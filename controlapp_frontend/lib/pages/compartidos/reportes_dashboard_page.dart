import 'dart:math' as math;
import 'dart:typed_data';

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
  final bool modoGeneral;
  const ReportesDashboardPage({
    super.key,
    this.conjuntoIdInicial,
    this.modoGeneral = false,
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

  bool _loading = false;
  bool _generandoPdf = false;
  String? _error;

  /// Ã¢Å“â€¦ cuando estÃƒÂ¡ true:
  /// - desactiva animaciones de charts
  /// - asegura que el host offscreen pinte estable antes de capturar
  bool _captureMode = false;

  ReporteKpis? _kpis;
  SerieDiariaPorEstado? _serie;
  List<ResumenConjuntoRow> _porConjunto = [];
  List<ResumenOperarioRow> _porOperario = [];
  List<InsumoUsoRow> _insumos = [];
  List<UsoEquipoRow> _maq = [];
  List<UsoEquipoRow> _herr = [];

  // Ã¢Å“â€¦ Informes usa tareas detalle
  List<TareaDetalleRow> _tareasDetalle = [];

  // Ã¢Å“â€¦ Keys para capturar charts (Offstage + RepaintBoundary)
  final GlobalKey _kPieEstados = GlobalKey();
  final GlobalKey _kLineSerie = GlobalKey();
  final GlobalKey _kPieTipos = GlobalKey();
  final GlobalKey _kBarInsumos = GlobalKey();

  /// =========================
  ///  Ã¢Å“â€¦ ANÃƒÂLISIS EDITABLES
  /// =========================
  late final _a11Ctrl = TextEditingController();
  late final _p11Ctrl = TextEditingController();

  late final _a12Ctrl = TextEditingController();
  late final _p12Ctrl = TextEditingController();

  late final _a13Ctrl = TextEditingController();
  late final _p13Ctrl = TextEditingController();

  late final _a14Ctrl = TextEditingController();
  late final _p14Ctrl = TextEditingController();

  /// Si luego quieres IA: aquÃƒÂ­ queda el Ã¢â‚¬Å“huecoÃ¢â‚¬Â (por ahora genera texto bÃƒÂ¡sico).
  bool _analisisInicializado = false;

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();
    _desde = DateTime(now.year, now.month, 1);
    _hasta = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

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

  Future<List<InsumoUsoRow>> _cargarInsumosGlobal(
    List<ResumenConjuntoRow> porConjunto,
  ) async {
    if (porConjunto.isEmpty) return <InsumoUsoRow>[];

    Future<List<InsumoUsoRow>> fetchByRefs(List<String> refs) async {
      for (final ref in refs) {
        if (ref.trim().isEmpty) continue;
        try {
          return await _api.usoInsumos(
            conjuntoId: ref.trim(),
            desde: _desde,
            hasta: _hasta,
          );
        } catch (_) {
          // intenta con la siguiente referencia (id/nit)
        }
      }
      return <InsumoUsoRow>[];
    }

    final futures = porConjunto.map((r) {
      final refs = <String>{
        r.conjuntoId.trim(),
        r.nit.trim(),
      }.where((e) => e.isNotEmpty).toList();
      return fetchByRefs(refs);
    }).toList();

    final lotes = await Future.wait(futures);

    final agg = <String, Map<String, dynamic>>{};
    for (final lote in lotes) {
      for (final item in lote) {
        final key = item.insumoId > 0
            ? 'id:${item.insumoId}'
            : 'name:${item.nombre.trim().toUpperCase()}|${item.unidad.trim().toUpperCase()}';

        final m = agg.putIfAbsent(
          key,
          () => <String, dynamic>{
            'insumoId': item.insumoId,
            'nombre': item.nombre,
            'unidad': item.unidad,
            'cantidad': 0.0,
            'usos': 0,
          },
        );

        m['cantidad'] = (m['cantidad'] as double) + item.cantidad;
        m['usos'] = (m['usos'] as int) + item.usos;
      }
    }

    return agg.values.map((m) {
      return InsumoUsoRow(
        insumoId: (m['insumoId'] as int?) ?? 0,
        nombre: (m['nombre'] ?? '').toString(),
        unidad: (m['unidad'] ?? '').toString(),
        cantidad: (m['cantidad'] as double?) ?? 0.0,
        usos: (m['usos'] as int?) ?? 0,
      );
    }).toList();
  }

  Future<void> _cargarTodo() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final conjuntoId = _conjuntoId;
      if (!_esReporteGeneral && conjuntoId == null) {
        throw Exception(
          'No se recibio el conjuntoId/NIT. Esta pagina solo funciona por conjunto.',
        );
      }

      final kpis = await _api.kpis(
        desde: _desde,
        hasta: _hasta,
        conjuntoId: _esReporteGeneral ? null : conjuntoId,
      );
      final serie = await _api.serieDiaria(
        desde: _desde,
        hasta: _hasta,
        conjuntoId: _esReporteGeneral ? null : conjuntoId,
      );

      final porConjunto = await _api.resumenPorConjunto(
        desde: _desde,
        hasta: _hasta,
      );
      final porOperario = await _api.resumenPorOperario(
        desde: _desde,
        hasta: _hasta,
        conjuntoId: _esReporteGeneral ? null : conjuntoId,
      );

      final maq = await _api.topMaquinaria(
        desde: _desde,
        hasta: _hasta,
        conjuntoId: _esReporteGeneral ? null : conjuntoId,
      );
      final herr = await _api.topHerramientas(
        desde: _desde,
        hasta: _hasta,
        conjuntoId: _esReporteGeneral ? null : conjuntoId,
      );

      final insumos = _esReporteGeneral
          ? await _cargarInsumosGlobal(porConjunto)
          : await _api.usoInsumos(
              conjuntoId: conjuntoId!,
              desde: _desde,
              hasta: _hasta,
            );

      final porConjuntoFiltrado = _esReporteGeneral
          ? porConjunto
          : porConjunto
                .where((r) => _matchesConjuntoRef(r, conjuntoId!))
                .toList();

      // Ã¢Å“â€¦ NUEVO: tareas detalle (correctivas + preventivas)
      final tareasDetalle = await _api.mensualDetalle(
        desde: _desde,
        hasta: _hasta,
        conjuntoId: _esReporteGeneral ? null : conjuntoId,
      );

      setState(() {
        _kpis = kpis;
        _serie = serie;
        _porConjunto = porConjuntoFiltrado;
        _porOperario = porOperario;
        _insumos = insumos;
        _maq = maq;
        _herr = herr;
        _tareasDetalle = tareasDetalle;
      });

      // Ã¢Å“â€¦ inicializa los anÃƒÂ¡lisis solo una vez (editable por usuario)
      if (!_analisisInicializado) {
        _seedAnalisisEditable();
        _analisisInicializado = true;
      } else {
        // si quieres que al cambiar rango se regenere, puedes poner un botÃƒÂ³n Ã¢â‚¬Å“RegenerarÃ¢â‚¬Â
      }
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
      _analisisInicializado =
          false; // para que regenere en el prÃƒÂ³ximo cargar
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

  // ===================== ANÃƒÂLISIS Ã¢â‚¬Å“BÃƒÂSICOÃ¢â‚¬Â + EDITABLE =====================

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
      _p11Ctrl.text =
          'Validar programaciÃƒÂ³n y confirmar operaciÃƒÂ³n del periodo.';
    } else if (corr > prev) {
      _a11Ctrl.text =
          'Se observa mayor proporciÃƒÂ³n de correctivas frente a preventivas. '
          'Esto suele indicar recurrencia de fallas o baja ejecuciÃƒÂ³n preventiva.';
      _p11Ctrl.text =
          'Reforzar plan preventivo, revisar causas raÃƒÂ­z de correctivas repetidas y priorizar actividades de control.';
    } else {
      _a11Ctrl.text =
          'La ejecuciÃƒÂ³n preventiva se mantiene estable frente a las correctivas. '
          'Esto contribuye a reducir incidencias y mejorar continuidad del servicio.';
      _p11Ctrl.text =
          'Mantener programaciÃƒÂ³n preventiva y monitorear correctivas para evitar recurrencia.';
    }

    // 1.2 Estados
    if (k.total == 0) {
      _a12Ctrl.text = 'No hay datos de estados porque no se registran tareas.';
      _p12Ctrl.text = 'Confirmar operaciÃƒÂ³n/cargue de tareas.';
    } else {
      final tasa = kd.tasaCierrePct;
      final rej = kd.rechazadas;
      final nocomp = kd.noCompletadas;
      final pend = kd.pendientesAprobacion;

      if (tasa < 75) {
        _a12Ctrl.text =
            'La tasa de cierre es baja ($tasa%). Se evidencian tareas pendientes o con cierre tardÃƒÂ­o.';
      } else if (tasa < 90) {
        _a12Ctrl.text =
            'La tasa de cierre es media ($tasa%). Existe oportunidad de mejorar tiempos y aprobaciones.';
      } else {
        _a12Ctrl.text =
            'La tasa de cierre es alta ($tasa%). El flujo operativo muestra buen control del cierre.';
      }

      final bullets = <String>[];
      if (rej > 0)
        bullets.add('Rechazadas: $rej (revisar causas y evidencias).');
      if (nocomp > 0)
        bullets.add(
          'No completadas: $nocomp (validar accesos/insumos/tiempos).',
        );
      if (pend > 0)
        bullets.add('Pendientes aprobaciÃƒÂ³n: $pend (acelerar VoBo).');

      _a12Ctrl.text += bullets.isEmpty
          ? ''
          : '\n' + bullets.map((e) => 'Ã¢â‚¬Â¢ $e').join('\n');

      _p12Ctrl.text =
          'Estandarizar evidencias, validar checklist de cierre y asegurar aprobaciÃƒÂ³n oportuna con administraciÃƒÂ³n/interventorÃƒÂ­a.';
    }

    // 1.3 Serie diaria
    final s = _serie;
    if (s == null || s.days.isEmpty) {
      _a13Ctrl.text = 'No hay serie diaria disponible para el periodo.';
      _p13Ctrl.text =
          'Validar que el endpoint de serie diaria estÃƒÂ© retornando datos.';
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
          'La tendencia diaria muestra variaciÃƒÂ³n de carga. '
          '${maxDay != null ? 'Mayor pico el dÃƒÂ­a $maxDay con $maxVal tareas.' : ''}';
      _p13Ctrl.text =
          'Balancear carga en dÃƒÂ­as pico, confirmar disponibilidad de personal y priorizar tareas crÃƒÂ­ticas.';
    }

    // 1.4 Insumos
    if (!_esReporteGeneral && _conjuntoId == null) {
      _a14Ctrl.text = 'No se recibio conjuntoId/NIT para analizar insumos.';
      _p14Ctrl.text =
          'Abrir esta pagina desde un conjunto valido y regenerar el informe.';
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
          'Se evidencia consumo de insumos asociado a la operacion del periodo. '
          'Insumo principal: ${t.nombre} (${t.cantidad.toStringAsFixed(2)} ${t.unidad}).';
      _p14Ctrl.text =
          '${_esReporteGeneral ? 'Priorizar control de abastecimiento global y estandarizar consumos entre conjuntos. ' : ''}'
          'Revisar reposicion, validar rendimientos y evitar sobreconsumo. Mantener control por tarea.';
    }
  }

  void _regenerarAnalisis() {
    setState(() {
      _seedAnalisisEditable();
    });
  }

  // ======================= PDF =======================

  /// Captura charts del host offscreen (robusto)
  Future<Map<String, Uint8List>> _captureChartsForPdf() async {
    setState(() => _captureMode = true);

    // 2 frames + pequeÃƒÂ±o delay para asegurar paint estable (web)
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

  String _normalizeEvidenceRaw(String raw) {
    var s = raw.trim();
    if ((s.startsWith('"') && s.endsWith('"')) ||
        (s.startsWith("'") && s.endsWith("'"))) {
      s = s.substring(1, s.length - 1).trim();
    }
    return s
        .replaceAll(r'\u003d', '=')
        .replaceAll(r'\u0026', '&')
        .replaceAll('&amp;', '&')
        .replaceAll('\\/', '/')
        .replaceAll(RegExp(r'[,.;]+$'), '');
  }

  List<String> _extractHttpUrls(String text) {
    final matches = RegExp(
      r'https?:\/\/[^\s<>"\]\[)]+',
      caseSensitive: false,
    ).allMatches(text);
    return matches.map((m) => text.substring(m.start, m.end)).toList();
  }

  String? _extractDriveId(String input) {
    final s = _normalizeEvidenceRaw(input);
    final directId = RegExp(r'^[a-zA-Z0-9_-]{20,}$').firstMatch(s);
    if (directId != null) return directId.group(0);

    final uri = Uri.tryParse(s);
    final qpId = uri?.queryParameters['id'];
    if (qpId != null && qpId.trim().isNotEmpty) return qpId.trim();

    final patterns = [
      RegExp(r'/d/([a-zA-Z0-9_-]{20,})'),
      RegExp(r'id=([a-zA-Z0-9_-]{20,})'),
      RegExp(r'file/d/([a-zA-Z0-9_-]{20,})'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(s);
      if (m != null && m.groupCount >= 1) return m.group(1);
    }
    return null;
  }

  List<String> _evidenceUrlCandidates(String raw) {
    final clean = _normalizeEvidenceRaw(raw);
    final out = <String>[];
    final seen = <String>{};

    void add(String? u) {
      if (u == null) return;
      final v = _normalizeEvidenceRaw(u);
      if (v.isEmpty || seen.contains(v)) return;
      seen.add(v);
      out.add(v);
    }

    final urls = _extractHttpUrls(clean);
    if (urls.isNotEmpty) {
      for (final u in urls) {
        add(u);
      }
    } else if (clean.startsWith('http://') || clean.startsWith('https://')) {
      add(clean);
    }

    final driveId = _extractDriveId(clean);
    if (driveId != null) {
      add('https://drive.google.com/thumbnail?id=$driveId&sz=w2000');
      add('https://drive.google.com/uc?export=view&id=$driveId');
      add('https://drive.google.com/uc?export=download&id=$driveId');
      add('https://lh3.googleusercontent.com/d/$driveId=w2000');
    }

    return out;
  }

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
        .replaceAll('ÃƒÂ¡', 'a')
        .replaceAll('ÃƒÂ©', 'e')
        .replaceAll('ÃƒÂ­', 'i')
        .replaceAll('ÃƒÂ³', 'o')
        .replaceAll('ÃƒÂº', 'u')
        .replaceAll('ÃƒÂ±', 'n')
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

      Future<pw.ImageProvider?> loadEvidenceImage(String raw) async {
        final candidates = _evidenceUrlCandidates(raw);
        for (final u in candidates) {
          if (imageCache.containsKey(u)) return imageCache[u];
          try {
            final img = await networkImage(u);
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
                pw.Table.fromTextArray(
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
                'Inicio: ${fechaHoraFmt.format(t.fechaInicio)} | Fin: ${fechaHoraFmt.format(t.fechaFin)} | Duracion: ${t.duracionMinutos} min',
                style: const pw.TextStyle(fontSize: 8),
              ),
              if ((t.ubicacion ?? '').isNotEmpty)
                pw.Text(
                  'Ubicacion: ${t.ubicacion}',
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
                    'Pend. aprobacion',
                    kd.pendientesAprobacion.toString(),
                  ),
                  metricCard('% cierre', '${kd.tasaCierrePct}%'),
                  metricCard('Preventivas', totalPrev.toString()),
                  metricCard('Correctivas', totalCorr.toString()),
                ],
              ),

              pw.SizedBox(height: 10),
              sectionTitle('2. Distribucion y Tendencias'),
              chartSection(
                title: '2.1 Preventivas vs Correctivas',
                imageBytes: charts['tipos']!,
                analysis: _a11Ctrl.text,
                actionPlan: _p11Ctrl.text,
              ),
              chartSection(
                title: '2.2 Distribucion por estado',
                imageBytes: charts['estados']!,
                analysis: _a12Ctrl.text,
                actionPlan: _p12Ctrl.text,
              ),
              chartSection(
                title: '2.3 Tareas por dia (tendencia)',
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

              sectionTitle('4. Registro Fotografico y Tareas'),
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
      debugPrint('Error PDF Gestion: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error generando PDF: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _generandoPdf = false;
          _captureMode = false;
        });
      }
    }
  }

  // ======================= PDF DETALLADO (tu versiÃƒÂ³n) =======================

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
              'Tareas: ${_tareasDetalle.length} Ã¢â‚¬Â¢ Rango: ${dfRango.format(_desde)} Ã¢â€ â€™ ${dfRango.format(_hasta)}',
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
                    .join(' Ã¢â‚¬Â¢ ');
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
                      '${t.tipo} Ã¢â‚¬Â¢ ${t.estado}',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      'ID ${t.id} Ã¢â‚¬Â¢ ${t.descripcion}',
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
                      'DuraciÃƒÂ³n: ${t.duracionMinutos} min',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                    pw.SizedBox(height: 6),
                    if ((t.ubicacion ?? '').isNotEmpty)
                      pw.Text(
                        'UbicaciÃƒÂ³n: ${t.ubicacion}',
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

  // ======================= BUILD =======================

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.primary;
    final df = DateFormat('dd/MM/yyyy', 'es');

    final conteoTipos = _contarTipos();
    final prev = conteoTipos['preventivas'] ?? 0;
    final corr = conteoTipos['correctivas'] ?? 0;

    return DefaultTabController(
      length: 6,
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
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Resumen'),
              Tab(text: 'Operarios'),
              Tab(text: 'Insumos'),
              Tab(text: 'Maq/Herr'),
              Tab(text: 'Tipos'),
              Tab(text: 'Informes'),
            ],
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
                                  '${df.format(_desde)} Ã¢â€ â€™ ${df.format(_hasta)}',
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
                              'Esta pagina requiere conjuntoId/NIT desde la navegacion.',
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
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                      ? _buildError()
                      : TabBarView(
                          children: [
                            _tabResumen(),
                            _tabOperarios(),
                            _tabInsumos(),
                            _tabMaqHerr(),
                            _tabTipos(),
                            _tabInformes(),
                          ],
                        ),
                ),
              ],
            ),

            // Ã¢Å“â€¦ Host real fuera de pantalla (para captura)
            Positioned(
              left: -5000,
              top: 0,
              child: IgnorePointer(
                child: Material(
                  color: Colors
                      .white, // Ã¢Å“â€¦ importante para que capture no quede transparente
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
    final conteoTipos = _contarTipos();

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
              'Pend. aprobaciÃƒÂ³n',
              kd.pendientesAprobacion.toString(),
              Icons.hourglass_bottom,
            ),
            _kpiTile('% Cierre', '${kd.tasaCierrePct}%', Icons.trending_up),
            _kpiTile(
              'Preventivas',
              '${conteoTipos['preventivas'] ?? 0}',
              Icons.build_circle,
            ),
            _kpiTile(
              'Correctivas',
              '${conteoTipos['correctivas'] ?? 0}',
              Icons.report_problem,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _sectionTitle('DistribuciÃƒÂ³n por estado'),
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
        _sectionTitle('Tareas por dÃƒÂ­a (tendencia)'),
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
                  _sectionTitle('Conjunto actual (volumen)'),
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

  TextStyle get _tooltipTextStyle => const TextStyle(
    color: Colors.white,
    fontSize: 11,
    fontWeight: FontWeight.w700,
  );

  BarTouchData _whiteBarTouchData({
    required List<String> labels,
    int decimals = 0,
    String? suffix,
  }) {
    return BarTouchData(
      enabled: true,
      touchTooltipData: BarTouchTooltipData(
        getTooltipColor: (_) => AppTheme.primary,
        getTooltipItem: (group, groupIndex, rod, rodIndex) {
          final idx = group.x;
          final label = (idx >= 0 && idx < labels.length) ? labels[idx] : '';
          final value = rod.toY.toStringAsFixed(decimals);
          final extra = (suffix == null || suffix.isEmpty) ? '' : ' $suffix';
          return BarTooltipItem('$label\n$value$extra', _tooltipTextStyle);
        },
      ),
    );
  }

  LineTouchData _whiteLineTouchData(List<String> labels) {
    return LineTouchData(
      enabled: true,
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (_) => AppTheme.primary,
        getTooltipItems: (touchedSpots) {
          return touchedSpots.map((s) {
            final idx = s.x.toInt();
            final label = (idx >= 0 && idx < labels.length) ? labels[idx] : '';
            return LineTooltipItem(
              '$label\n${s.y.toStringAsFixed(0)}',
              _tooltipTextStyle,
            );
          }).toList();
        },
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
      swapAnimationDuration: _captureMode
          ? Duration.zero
          : const Duration(milliseconds: 250),
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
    final dayLabels = days.map((d) {
      final parts = d.split('-');
      return parts.length == 3 ? '${parts[2]}/${parts[1]}' : d;
    }).toList();
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
        lineTouchData: _whiteLineTouchData(dayLabels),
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
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    dayLabels[idx],
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
    final labels = items.map((e) => e.nombre).toList();
    final maxY = items.first.total.toDouble();

    return BarChart(
      BarChartData(
        maxY: maxY <= 0 ? 5 : maxY * 1.25,
        barTouchData: _whiteBarTouchData(labels: labels),
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
    final labels = items
        .map(
          (e) => e.conjuntoNombre.isNotEmpty ? e.conjuntoNombre : e.conjuntoId,
        )
        .toList();
    final maxY = items.first.total.toDouble();

    return BarChart(
      BarChartData(
        maxY: maxY <= 0 ? 5 : maxY * 1.25,
        barTouchData: _whiteBarTouchData(labels: labels),
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
          final promHoras = (r.minutosPromedio / 60).toStringAsFixed(2);

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
                    'ID: ${r.operarioId} Ã¢â‚¬Â¢ Prom: $promHoras h',
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
    if (!_esReporteGeneral && _conjuntoId == null) {
      return const Center(
        child: Text('No se recibio el conjuntoId/NIT para cargar insumos.'),
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
        _card(child: SizedBox(height: 320, child: _barInsumos(top, maxQty))),
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
                    'Cantidad: ${r.cantidad.toStringAsFixed(2)} ${r.unidad} Ã¢â‚¬Â¢ Usos: ${r.usos}',
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

  Widget _barInsumos(List<InsumoUsoRow> top, double maxQty) {
    final labels = top.map((e) => e.nombre).toList();
    return BarChart(
      BarChartData(
        maxY: maxQty * 1.25,
        barTouchData: _whiteBarTouchData(labels: labels, decimals: 2),
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
                style: const TextStyle(fontSize: 10, color: Colors.black87),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= top.length) return const SizedBox.shrink();
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
    );
  }

  /// versiÃƒÂ³n Ã¢â‚¬Å“simpleÃ¢â‚¬Â para imprimir insumos en el PDF incluso si no hay conjuntoId
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

  Widget _topListChart(List<UsoEquipoRow> rows, {required String valueLabel}) {
    final sorted = [...rows]..sort((a, b) => b.usos.compareTo(a.usos));
    final top = sorted.take(10).toList();
    final labels = top.map((e) => e.nombre).toList();
    final maxUsos = top.first.usos <= 0 ? 1 : top.first.usos;

    return Column(
      children: [
        SizedBox(
          height: 240,
          child: BarChart(
            BarChartData(
              maxY: maxUsos.toDouble() * 1.25,
              barTouchData: _whiteBarTouchData(
                labels: labels,
                suffix: valueLabel,
              ),
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

    final conteo = _contarTipos();
    final prev = conteo['preventivas'] ?? 0;
    final corr = conteo['correctivas'] ?? 0;
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
      swapAnimationDuration: _captureMode
          ? Duration.zero
          : const Duration(milliseconds: 250),
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
        _sectionTitle('AnÃƒÂ¡lisis editable (se imprimen en el PDF)'),
        const SizedBox(height: 8),
        _card(
          child: Column(
            children: [
              _analisisBlock(
                '1.1 Tareas preventivas y correctivas',
                _a11Ctrl,
                _p11Ctrl,
              ),
              const Divider(),
              _analisisBlock(
                '1.2 DistribuciÃƒÂ³n por estado',
                _a12Ctrl,
                _p12Ctrl,
              ),
              const Divider(),
              _analisisBlock(
                '1.3 Tareas por dÃƒÂ­a (tendencia)',
                _a13Ctrl,
                _p13Ctrl,
              ),
              const Divider(),
              _analisisBlock('1.4 Insumos usados', _a14Ctrl, _p14Ctrl),
              const SizedBox(height: 10),
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
        ),
        const SizedBox(height: 14),

        _sectionTitle('Informes automÃƒÂ¡ticos'),
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
                  label: Text(
                    _generandoPdf ? 'Generando...' : 'GestiÃ³n(PDF plantilla)',
                  ),
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
                                '${t.estado} Ã¢â‚¬Â¢ ${df.format(t.fechaInicio)} Ã¢â€ â€™ ${df.format(t.fechaFin)} Ã¢â‚¬Â¢ ${t.duracionMinutos} min',
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

  Widget _analisisBlock(
    String title,
    TextEditingController analisis,
    TextEditingController plan,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        TextField(
          controller: analisis,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'ANÃƒÂLISIS MES',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: plan,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'PLAN DE ACCIÃƒâ€œN',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }

  // ======================= MODAL (tu versiÃƒÂ³n) =======================

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
                      _kv('DuraciÃƒÂ³n', '${t.duracionMinutos} min'),
                      if ((t.ubicacion ?? '').isNotEmpty)
                        _kv('UbicaciÃƒÂ³n', t.ubicacion!),
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
                      final candidates = _evidenceUrlCandidates(e);
                      return InkWell(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (_) => Dialog(
                              child: InteractiveViewer(
                                child: _EvidenceImage(
                                  urls: candidates,
                                  fit: BoxFit.contain,
                                  fallback: const Center(
                                    child: Icon(Icons.image_not_supported),
                                  ),
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
                            child: _EvidenceImage(
                              urls: candidates,
                              fit: BoxFit.cover,
                              fallback: const Center(
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

  /// Tabla Ã¢â‚¬Å“bonitaÃ¢â‚¬Â (sin DataTable para que no se rompa en web)
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

class _EvidenceImage extends StatefulWidget {
  final List<String> urls;
  final BoxFit fit;
  final Widget fallback;

  const _EvidenceImage({
    required this.urls,
    required this.fit,
    required this.fallback,
  });

  @override
  State<_EvidenceImage> createState() => _EvidenceImageState();
}

class _EvidenceImageState extends State<_EvidenceImage> {
  int _index = 0;
  bool _advanceScheduled = false;

  void _tryNext() {
    if (_advanceScheduled) return;
    _advanceScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _index++;
        _advanceScheduled = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final cleanUrls = widget.urls
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .toList();

    if (cleanUrls.isEmpty || _index >= cleanUrls.length) {
      return widget.fallback;
    }

    final url = cleanUrls[_index];
    return Image.network(
      url,
      fit: widget.fit,
      errorBuilder: (_, __, ___) {
        _tryNext();
        return const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
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
