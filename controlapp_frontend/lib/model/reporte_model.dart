// lib/model/reporte_models.dart
import 'dart:convert';

DateTime _dt(dynamic v) {
  if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
  if (v is DateTime) return v;
  return DateTime.tryParse(v.toString()) ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

final RegExp _httpUrlRx = RegExp(r'https?:\/\/[^\s<>"\]\[)]+');

String _cleanEvidence(String s) {
  var x = s.trim();
  if ((x.startsWith('"') && x.endsWith('"')) ||
      (x.startsWith("'") && x.endsWith("'"))) {
    x = x.substring(1, x.length - 1).trim();
  }
  return x
      .replaceAll(r'\u003d', '=')
      .replaceAll(r'\u0026', '&')
      .replaceAll('&amp;', '&')
      .replaceAll('\\/', '/')
      .replaceAll(RegExp(r'[,.;]+$'), '');
}

String? _urlFromEvidenceMap(Map<dynamic, dynamic> m) {
  const keys = [
    'url',
    'downloadUrl',
    'secureUrl',
    'fileUrl',
    'evidenciaUrl',
    'archivoUrl',
    'src',
    'href',
    'path',
  ];
  for (final k in keys) {
    final v = m[k];
    if (v == null) continue;
    final s = _cleanEvidence(v.toString());
    if (s.isNotEmpty) return s;
  }
  return null;
}

void _collectEvidence(dynamic value, Set<String> out) {
  if (value == null) return;

  if (value is List) {
    for (final item in value) {
      _collectEvidence(item, out);
    }
    return;
  }

  if (value is Map) {
    final direct = _urlFromEvidenceMap(value);
    if (direct != null) {
      _collectEvidence(direct, out);
    }
    if (value['urls'] is List) _collectEvidence(value['urls'], out);
    if (value['evidencias'] is List) _collectEvidence(value['evidencias'], out);
    return;
  }

  final s = _cleanEvidence(value.toString());
  if (s.isEmpty) return;

  if ((s.startsWith('{') && s.endsWith('}')) ||
      (s.startsWith('[') && s.endsWith(']'))) {
    try {
      final decoded = jsonDecode(s);
      _collectEvidence(decoded, out);
      return;
    } catch (_) {
      // si no es JSON valido, seguimos con parseo de string plano
    }
  }

  final hits = _httpUrlRx.allMatches(s).map((m) => s.substring(m.start, m.end));
  if (hits.isNotEmpty) {
    for (final h in hits) {
      final u = _cleanEvidence(h);
      if (u.isNotEmpty) out.add(u);
    }
    return;
  }

  // algunos backends devuelven solo el ID de Drive.
  if (RegExp(r'^[a-zA-Z0-9_-]{20,}$').hasMatch(s)) {
    out.add(s);
  }
}

List<String> _toEvidenceUrls(dynamic raw) {
  final out = <String>{};
  _collectEvidence(raw, out);
  return out.toList();
}

class ReporteKpis {
  final bool ok;
  final int total;
  final Map<String, int> byEstado;
  final ReporteKpiDetalle kpi;

  ReporteKpis({
    required this.ok,
    required this.total,
    required this.byEstado,
    required this.kpi,
  });

  factory ReporteKpis.fromJson(Map<String, dynamic> json) {
    final by = <String, int>{};
    final rawBy = json['byEstado'];
    if (rawBy is Map) {
      rawBy.forEach(
        (k, v) =>
            by[k.toString()] = (v is num) ? v.toInt() : int.tryParse('$v') ?? 0,
      );
    }

    return ReporteKpis(
      ok: json['ok'] == true,
      total: (json['total'] is num)
          ? (json['total'] as num).toInt()
          : int.tryParse('${json['total']}') ?? 0,
      byEstado: by,
      kpi: ReporteKpiDetalle.fromJson(
        (json['kpi'] as Map?)?.cast<String, dynamic>() ?? {},
      ),
    );
  }
}

class ReporteKpiDetalle {
  final int asignadas;
  final int enProceso;
  final int completadas;
  final int aprobadas;
  final int pendientesAprobacion;
  final int rechazadas;
  final int noCompletadas;
  final int cerradasOperativas;
  final int tasaCierrePct;

  ReporteKpiDetalle({
    required this.asignadas,
    required this.enProceso,
    required this.completadas,
    required this.aprobadas,
    required this.pendientesAprobacion,
    required this.rechazadas,
    required this.noCompletadas,
    required this.cerradasOperativas,
    required this.tasaCierrePct,
  });

  factory ReporteKpiDetalle.fromJson(Map<String, dynamic> json) =>
      ReporteKpiDetalle(
        asignadas: _toInt(json['asignadas']),
        enProceso: _toInt(json['enProceso']),
        completadas: _toInt(json['completadas']),
        aprobadas: _toInt(json['aprobadas']),
        pendientesAprobacion: _toInt(json['pendientesAprobacion']),
        rechazadas: _toInt(json['rechazadas']),
        noCompletadas: _toInt(json['noCompletadas']),
        cerradasOperativas: _toInt(json['cerradasOperativas']),
        tasaCierrePct: _toInt(json['tasaCierrePct']),
      );

  static int _toInt(dynamic v) =>
      (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;
}

class SerieDiariaPorEstado {
  final bool ok;
  final List<String> days; // yyyy-mm-dd
  final Map<String, Map<String, int>> series; // day -> estado -> count

  SerieDiariaPorEstado({
    required this.ok,
    required this.days,
    required this.series,
  });

  factory SerieDiariaPorEstado.fromJson(Map<String, dynamic> json) {
    final days = (json['days'] is List)
        ? (json['days'] as List).map((e) => e.toString()).toList()
        : <String>[];

    final out = <String, Map<String, int>>{};
    final raw = json['series'];
    if (raw is Map) {
      raw.forEach((day, m) {
        final mm = <String, int>{};
        if (m is Map) {
          m.forEach((estado, count) {
            mm[estado.toString()] = (count is num)
                ? count.toInt()
                : int.tryParse('$count') ?? 0;
          });
        }
        out[day.toString()] = mm;
      });
    }

    return SerieDiariaPorEstado(
      ok: json['ok'] == true,
      days: days,
      series: out,
    );
  }
}

class ResumenConjuntoRow {
  final String conjuntoId;
  final String conjuntoNombre;
  final String nit;
  final int total;
  final int aprobadas;
  final int rechazadas;
  final int noCompletadas;
  final int pendientesAprobacion;

  ResumenConjuntoRow({
    required this.conjuntoId,
    required this.conjuntoNombre,
    required this.nit,
    required this.total,
    required this.aprobadas,
    required this.rechazadas,
    required this.noCompletadas,
    required this.pendientesAprobacion,
  });

  factory ResumenConjuntoRow.fromJson(Map<String, dynamic> json) =>
      ResumenConjuntoRow(
        conjuntoId: (json['conjuntoId'] ?? '').toString(),
        conjuntoNombre: (json['conjuntoNombre'] ?? '').toString(),
        nit: (json['nit'] ?? '').toString(),
        total: _toInt(json['total']),
        aprobadas: _toInt(json['aprobadas']),
        rechazadas: _toInt(json['rechazadas']),
        noCompletadas: _toInt(json['noCompletadas']),
        pendientesAprobacion: _toInt(json['pendientesAprobacion']),
      );

  static int _toInt(dynamic v) =>
      (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;
}

class ResumenOperarioRow {
  final String operarioId;
  final String nombre;
  final int total;
  final int aprobadas;
  final int rechazadas;
  final int noCompletadas;
  final int pendientesAprobacion;
  final int minutosPromedio;
  final int minutosAsignadosSemana;
  final int minutosAsignadosMes;
  final int minutosDisponiblesSemana;
  final int minutosDisponiblesMes;
  final double usoSemanalPct;
  final double usoMensualPct;
  final String? conjuntoCapacidadId;

  ResumenOperarioRow({
    required this.operarioId,
    required this.nombre,
    required this.total,
    required this.aprobadas,
    required this.rechazadas,
    required this.noCompletadas,
    required this.pendientesAprobacion,
    required this.minutosPromedio,
    required this.minutosAsignadosSemana,
    required this.minutosAsignadosMes,
    required this.minutosDisponiblesSemana,
    required this.minutosDisponiblesMes,
    required this.usoSemanalPct,
    required this.usoMensualPct,
    required this.conjuntoCapacidadId,
  });

  factory ResumenOperarioRow.fromJson(Map<String, dynamic> json) =>
      ResumenOperarioRow(
        operarioId: (json['operarioId'] ?? '').toString(),
        nombre: (json['nombre'] ?? '').toString(),
        total: _toInt(json['total']),
        aprobadas: _toInt(json['aprobadas']),
        rechazadas: _toInt(json['rechazadas']),
        noCompletadas: _toInt(json['noCompletadas']),
        pendientesAprobacion: _toInt(json['pendientesAprobacion']),
        minutosPromedio: _toInt(json['minutosPromedio']),
        minutosAsignadosSemana: _toInt(json['minutosAsignadosSemana']),
        minutosAsignadosMes: _toInt(json['minutosAsignadosMes']),
        minutosDisponiblesSemana: _toInt(json['minutosDisponiblesSemana']),
        minutosDisponiblesMes: _toInt(json['minutosDisponiblesMes']),
        usoSemanalPct: _toDouble(json['usoSemanalPct']),
        usoMensualPct: _toDouble(json['usoMensualPct']),
        conjuntoCapacidadId: json['conjuntoCapacidadId']?.toString(),
      );

  static int _toInt(dynamic v) =>
      (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;
  static double _toDouble(dynamic v) =>
      (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;
}

class InsumoUsoRow {
  final int insumoId;
  final String nombre;
  final String unidad;
  final double cantidad;
  final int usos;

  InsumoUsoRow({
    required this.insumoId,
    required this.nombre,
    required this.unidad,
    required this.cantidad,
    required this.usos,
  });

  factory InsumoUsoRow.fromJson(Map<String, dynamic> json) => InsumoUsoRow(
    insumoId: (json['insumoId'] is num)
        ? (json['insumoId'] as num).toInt()
        : int.tryParse('${json['insumoId']}') ?? 0,
    nombre: (json['nombre'] ?? '').toString(),
    unidad: (json['unidad'] ?? '').toString(),
    cantidad: (json['cantidad'] is num)
        ? (json['cantidad'] as num).toDouble()
        : double.tryParse('${json['cantidad']}') ?? 0.0,
    usos: (json['usos'] is num)
        ? (json['usos'] as num).toInt()
        : int.tryParse('${json['usos']}') ?? 0,
  );
}

class UsoEquipoRow {
  final int id;
  final String nombre;
  final int usos;
  final double cantidad;

  UsoEquipoRow({
    required this.id,
    required this.nombre,
    required this.usos,
    required this.cantidad,
  });

  factory UsoEquipoRow.fromJson(
    Map<String, dynamic> json, {
    required String idKey,
  }) => UsoEquipoRow(
    id: (json[idKey] is num)
        ? (json[idKey] as num).toInt()
        : int.tryParse('${json[idKey]}') ?? 0,
    nombre: (json['nombre'] ?? '').toString(),
    usos: (json['usos'] is num)
        ? (json['usos'] as num).toInt()
        : int.tryParse('${json['usos']}') ?? 0,
    cantidad: (json['cantidad'] is num)
        ? (json['cantidad'] as num).toDouble()
        : double.tryParse('${json['cantidad']}') ?? 0.0,
  );
}

class RecursoUsoRow {
  final int? recursoId; // insumoId / maquinariaId / herramientaId (según lista)
  final String? nombre;
  final String? unidad; // aplica para insumos/herramienta
  final double cantidad;
  final String? operario;
  final String? observacion;
  final DateTime? fecha;

  RecursoUsoRow({
    this.recursoId,
    this.nombre,
    this.unidad,
    required this.cantidad,
    this.operario,
    this.observacion,
    this.fecha,
  });

  factory RecursoUsoRow.fromJson(
    Map<String, dynamic> json, {
    required String idKey,
  }) {
    double toDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    return RecursoUsoRow(
      recursoId: (json[idKey] is num)
          ? (json[idKey] as num).toInt()
          : int.tryParse('${json[idKey]}'),
      nombre: json['nombre']?.toString(),
      unidad: json['unidad']?.toString(),
      cantidad: toDouble(json['cantidad']),
      operario: json['operario']?.toString(),
      observacion: json['observacion']?.toString(),
      fecha: json['fecha'] == null ? null : _dt(json['fecha']),
    );
  }
}

class PdfDatasetRow {
  final int id;
  final String descripcion;
  final String estado;
  final String tipo; // PREVENTIVA / CORRECTIVA
  final String? frecuencia;

  final DateTime fechaInicio;
  final DateTime fechaFin;
  final int? duracionMinutos;

  final String? ubicacionNombre;
  final String? elementoNombre;

  final String? supervisor;
  final List<String> operarios;

  final String? conjuntoId;
  final String? conjuntoNombre;
  final String? conjuntoNit;

  final String? observaciones;
  final String? observacionesRechazo;

  final List<String> evidencias;

  // detalle real
  final List<RecursoUsoRow> insumos;
  final List<RecursoUsoRow> maquinaria;
  final List<RecursoUsoRow> herramientas;

  final bool noCompletadaPorReemplazo;
  final String? motivoNoCompletada;
  final int? reemplazadaPorTareaId;
  final String? reemplazadaPorDescripcion;
  final bool esTareaReemplazo;
  final String? motivoTareaReemplazo;
  final List<Map<String, dynamic>> reemplazaPreventivas;

  PdfDatasetRow({
    required this.id,
    required this.descripcion,
    required this.estado,
    required this.tipo,
    this.frecuencia,
    required this.fechaInicio,
    required this.fechaFin,
    required this.duracionMinutos,
    required this.ubicacionNombre,
    required this.elementoNombre,
    required this.supervisor,
    required this.operarios,
    required this.conjuntoId,
    required this.conjuntoNombre,
    required this.conjuntoNit,
    required this.observaciones,
    required this.observacionesRechazo,
    required this.evidencias,
    required this.insumos,
    required this.maquinaria,
    required this.herramientas,
    this.noCompletadaPorReemplazo = false,
    this.motivoNoCompletada,
    this.reemplazadaPorTareaId,
    this.reemplazadaPorDescripcion,
    this.esTareaReemplazo = false,
    this.motivoTareaReemplazo,
    this.reemplazaPreventivas = const [],
  });

  factory PdfDatasetRow.fromJson(Map<String, dynamic> json) {
    List<RecursoUsoRow> mapRecursos(dynamic v, {required String idKey}) {
      if (v is! List) return <RecursoUsoRow>[];
      return v
          .whereType<Map>()
          .map(
            (m) =>
                RecursoUsoRow.fromJson(m.cast<String, dynamic>(), idKey: idKey),
          )
          .toList();
    }

    final conjunto = (json['conjunto'] is Map)
        ? (json['conjunto'] as Map)
        : null;
    final ubic = (json['ubicacion'] is Map) ? (json['ubicacion'] as Map) : null;
    final elem = (json['elemento'] is Map) ? (json['elemento'] as Map) : null;
    final reemplazadaPor = (json['reemplazadaPor'] is Map)
        ? (json['reemplazadaPor'] as Map).cast<String, dynamic>()
        : null;

    return PdfDatasetRow(
      id: (json['id'] is num)
          ? (json['id'] as num).toInt()
          : int.tryParse('${json['id']}') ?? 0,
      descripcion: (json['descripcion'] ?? '').toString(),
      estado: (json['estado'] ?? '').toString(),
      tipo: (json['tipo'] ?? 'CORRECTIVA').toString(),
      frecuencia: json['frecuencia']?.toString(),

      fechaInicio: _dt(json['fechaInicio']),
      fechaFin: _dt(json['fechaFin']),
      duracionMinutos: (json['duracionMinutos'] is num)
          ? (json['duracionMinutos'] as num).toInt()
          : int.tryParse('${json['duracionMinutos']}'),

      ubicacionNombre:
          json['ubicacionNombre']?.toString() ?? ubic?['nombre']?.toString(),
      elementoNombre:
          json['elementoNombre']?.toString() ?? elem?['nombre']?.toString(),

      supervisor: json['supervisor']?.toString(),
      operarios: (json['operarios'] is List)
          ? (json['operarios'] as List).map((e) => e.toString()).toList()
          : <String>[],

      conjuntoId: json['conjuntoId']?.toString() ?? conjunto?['id']?.toString(),
      conjuntoNombre: conjunto?['nombre']?.toString(),
      conjuntoNit: conjunto?['nit']?.toString(),

      observaciones: json['observaciones']?.toString(),
      observacionesRechazo: json['observacionesRechazo']?.toString(),

      evidencias: _toEvidenceUrls(json['evidencias']),

      insumos: mapRecursos(json['insumos'], idKey: 'insumoId'),
      maquinaria: mapRecursos(json['maquinaria'], idKey: 'maquinariaId'),
      herramientas: mapRecursos(json['herramientas'], idKey: 'herramientaId'),
      noCompletadaPorReemplazo: json['noCompletadaPorReemplazo'] == true,
      motivoNoCompletada: json['motivoNoCompletada']?.toString(),
      reemplazadaPorTareaId: (reemplazadaPor?['tareaId'] is num)
          ? (reemplazadaPor!['tareaId'] as num).toInt()
          : int.tryParse('${reemplazadaPor?['tareaId'] ?? ''}'),
      reemplazadaPorDescripcion: reemplazadaPor?['descripcion']?.toString(),
      esTareaReemplazo: json['esTareaReemplazo'] == true,
      motivoTareaReemplazo: json['motivoTareaReemplazo']?.toString(),
      reemplazaPreventivas: (json['reemplazaPreventivas'] is List)
          ? (json['reemplazaPreventivas'] as List)
                .whereType<Map>()
                .map((m) => m.cast<String, dynamic>())
                .toList()
          : const <Map<String, dynamic>>[],
    );
  }

  static List<PdfDatasetRow> parseFromAny(dynamic payload) {
    if (payload is Map && payload['data'] is List) {
      return (payload['data'] as List)
          .map(
            (e) => PdfDatasetRow.fromJson((e as Map).cast<String, dynamic>()),
          )
          .toList();
    }
    if (payload is String) {
      final d = jsonDecode(payload);
      return parseFromAny(d);
    }
    return [];
  }
}

class TareaDetalleRow {
  final int id;
  final String tipo;
  final String? frecuencia;
  final String estado;
  final String descripcion;
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final int duracionMinutos;

  final String? ubicacion;
  final String? elemento;
  final String? supervisor;
  final List<String> operarios;

  final List<Map<String, dynamic>> insumos;
  final List<Map<String, dynamic>> maquinaria;
  final List<Map<String, dynamic>> herramientas;

  final List<String> evidencias;
  final bool noCompletadaPorReemplazo;
  final String? motivoNoCompletada;
  final int? reemplazadaPorTareaId;
  final String? reemplazadaPorDescripcion;
  final bool esTareaReemplazo;
  final String? motivoTareaReemplazo;
  final List<Map<String, dynamic>> reemplazaPreventivas;

  TareaDetalleRow({
    required this.id,
    required this.tipo,
    this.frecuencia,
    required this.estado,
    required this.descripcion,
    required this.fechaInicio,
    required this.fechaFin,
    required this.duracionMinutos,
    required this.ubicacion,
    required this.elemento,
    required this.supervisor,
    required this.operarios,
    required this.insumos,
    required this.maquinaria,
    required this.herramientas,
    required this.evidencias,
    this.noCompletadaPorReemplazo = false,
    this.motivoNoCompletada,
    this.reemplazadaPorTareaId,
    this.reemplazadaPorDescripcion,
    this.esTareaReemplazo = false,
    this.motivoTareaReemplazo,
    this.reemplazaPreventivas = const [],
  });

  static DateTime _dt(dynamic v) =>
      DateTime.tryParse('$v')?.toLocal() ??
      DateTime.fromMillisecondsSinceEpoch(0);

  factory TareaDetalleRow.fromJson(Map<String, dynamic> json) =>
      TareaDetalleRow(
        id: (json['id'] as num).toInt(),
        tipo: (json['tipo'] ?? '').toString(),
        frecuencia: json['frecuencia']?.toString(),
        estado: (json['estado'] ?? '').toString(),
        descripcion: (json['descripcion'] ?? '').toString(),
        fechaInicio: _dt(json['fechaInicio']),
        fechaFin: _dt(json['fechaFin']),
        duracionMinutos: (json['duracionMinutos'] is num)
            ? (json['duracionMinutos'] as num).toInt()
            : int.tryParse('${json['duracionMinutos']}') ?? 0,
        ubicacion: (json['ubicacion'] is Map)
            ? ((json['ubicacion'] as Map)['nombre']?.toString())
            : json['ubicacionNombre']?.toString(),
        elemento: (json['elemento'] is Map)
            ? ((json['elemento'] as Map)['nombre']?.toString())
            : json['elementoNombre']?.toString(),
        supervisor: (json['supervisor'] ?? '').toString().isEmpty
            ? null
            : (json['supervisor']).toString(),
        operarios: (json['operarios'] is List)
            ? (json['operarios'] as List).map((e) => e.toString()).toList()
            : <String>[],
        insumos: (json['insumos'] is List)
            ? (json['insumos'] as List)
                  .map((e) => (e as Map).cast<String, dynamic>())
                  .toList()
            : <Map<String, dynamic>>[],
        maquinaria: (json['maquinaria'] is List)
            ? (json['maquinaria'] as List)
                  .map((e) => (e as Map).cast<String, dynamic>())
                  .toList()
            : <Map<String, dynamic>>[],
        herramientas: (json['herramientas'] is List)
            ? (json['herramientas'] as List)
                  .map((e) => (e as Map).cast<String, dynamic>())
                  .toList()
            : <Map<String, dynamic>>[],
        evidencias: _toEvidenceUrls(json['evidencias']),
        noCompletadaPorReemplazo: json['noCompletadaPorReemplazo'] == true,
        motivoNoCompletada: json['motivoNoCompletada']?.toString(),
        reemplazadaPorTareaId: (() {
          final rep = (json['reemplazadaPor'] is Map)
              ? (json['reemplazadaPor'] as Map).cast<String, dynamic>()
              : null;
          if (rep?['tareaId'] is num) return (rep!['tareaId'] as num).toInt();
          final raw = rep?['tareaId'] ?? json['reprogramadaPorTareaId'];
          return int.tryParse('${raw ?? ''}');
        })(),
        reemplazadaPorDescripcion: (() {
          final rep = (json['reemplazadaPor'] is Map)
              ? (json['reemplazadaPor'] as Map).cast<String, dynamic>()
              : null;
          return rep?['descripcion']?.toString();
        })(),
        esTareaReemplazo: json['esTareaReemplazo'] == true,
        motivoTareaReemplazo: json['motivoTareaReemplazo']?.toString(),
        reemplazaPreventivas: (json['reemplazaPreventivas'] is List)
            ? (json['reemplazaPreventivas'] as List)
                  .whereType<Map>()
                  .map((m) => m.cast<String, dynamic>())
                  .toList()
            : const <Map<String, dynamic>>[],
      );
}

class ZonificacionInsumoRow {
  final int insumoId;
  final String nombre;
  final String unidad;
  final double consumoEstimado;
  final int usos;
  final double consumoPorUnidadPromedio;
  final double? rendimientoPromedio;
  final String? formulaRendimiento;

  const ZonificacionInsumoRow({
    required this.insumoId,
    required this.nombre,
    required this.unidad,
    required this.consumoEstimado,
    required this.usos,
    required this.consumoPorUnidadPromedio,
    required this.rendimientoPromedio,
    required this.formulaRendimiento,
  });

  factory ZonificacionInsumoRow.fromJson(Map<String, dynamic> json) {
    double d(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0;
    }

    int i(dynamic v) => (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;

    final rendRaw = json['rendimientoPromedio'];
    final rendimiento = rendRaw == null ? null : d(rendRaw);

    return ZonificacionInsumoRow(
      insumoId: i(json['insumoId']),
      nombre: (json['nombre'] ?? '').toString(),
      unidad: (json['unidad'] ?? '').toString(),
      consumoEstimado: d(json['consumoEstimado']),
      usos: i(json['usos']),
      consumoPorUnidadPromedio: d(json['consumoPorUnidadPromedio']),
      rendimientoPromedio: rendimiento,
      formulaRendimiento: json['formulaRendimiento']?.toString(),
    );
  }
}

class ZonificacionUbicacionRow {
  final int ubicacionId;
  final String ubicacionNombre;
  final String? unidadCalculo;
  final int preventivas;
  final double areaTotal;
  final List<ZonificacionInsumoRow> topInsumos;

  const ZonificacionUbicacionRow({
    required this.ubicacionId,
    required this.ubicacionNombre,
    required this.unidadCalculo,
    required this.preventivas,
    required this.areaTotal,
    required this.topInsumos,
  });

  factory ZonificacionUbicacionRow.fromJson(Map<String, dynamic> json) {
    int i(dynamic v) => (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;
    double d(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse('${v ?? 0}'.replaceAll(',', '.')) ?? 0;
    }

    final topRaw = (json['topInsumos'] is List)
        ? (json['topInsumos'] as List)
        : const <dynamic>[];

    return ZonificacionUbicacionRow(
      ubicacionId: i(json['ubicacionId']),
      ubicacionNombre: (json['ubicacionNombre'] ?? '').toString(),
      unidadCalculo: json['unidadCalculo']?.toString(),
      preventivas: i(json['preventivas']),
      areaTotal: d(json['areaTotal']),
      topInsumos: topRaw
          .whereType<Map>()
          .map((e) => ZonificacionInsumoRow.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }
}

class ZonificacionConjuntoRow {
  final String conjuntoId;
  final String conjuntoNombre;
  final int preventivas;
  final int ubicaciones;
  final double areaTotal;
  final List<ZonificacionUbicacionRow> ubicacionesDetalle;
  final List<ZonificacionInsumoRow> topInsumos;

  const ZonificacionConjuntoRow({
    required this.conjuntoId,
    required this.conjuntoNombre,
    required this.preventivas,
    required this.ubicaciones,
    required this.areaTotal,
    required this.ubicacionesDetalle,
    required this.topInsumos,
  });

  factory ZonificacionConjuntoRow.fromJson(Map<String, dynamic> json) {
    int i(dynamic v) => (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;
    double d(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse('${v ?? 0}'.replaceAll(',', '.')) ?? 0;
    }

    final ubRaw = (json['ubicacionesDetalle'] is List)
        ? (json['ubicacionesDetalle'] as List)
        : const <dynamic>[];
    final topRaw = (json['topInsumos'] is List)
        ? (json['topInsumos'] as List)
        : const <dynamic>[];

    return ZonificacionConjuntoRow(
      conjuntoId: (json['conjuntoId'] ?? '').toString(),
      conjuntoNombre: (json['conjuntoNombre'] ?? '').toString(),
      preventivas: i(json['preventivas']),
      ubicaciones: i(json['ubicaciones']),
      areaTotal: d(json['areaTotal']),
      ubicacionesDetalle: ubRaw
          .whereType<Map>()
          .map(
            (e) => ZonificacionUbicacionRow.fromJson(e.cast<String, dynamic>()),
          )
          .toList(),
      topInsumos: topRaw
          .whereType<Map>()
          .map((e) => ZonificacionInsumoRow.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }
}

class ZonificacionResumen {
  final int conjuntos;
  final int ubicaciones;
  final int preventivas;
  final double areaTotal;
  final bool soloActivas;

  const ZonificacionResumen({
    required this.conjuntos,
    required this.ubicaciones,
    required this.preventivas,
    required this.areaTotal,
    required this.soloActivas,
  });

  factory ZonificacionResumen.fromJson(Map<String, dynamic> json) {
    int i(dynamic v) => (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;
    double d(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse('${v ?? 0}'.replaceAll(',', '.')) ?? 0;
    }

    return ZonificacionResumen(
      conjuntos: i(json['conjuntos']),
      ubicaciones: i(json['ubicaciones']),
      preventivas: i(json['preventivas']),
      areaTotal: d(json['areaTotal']),
      soloActivas: json['soloActivas'] == true,
    );
  }
}

class ZonificacionPreventivasResponse {
  final bool ok;
  final ZonificacionResumen resumen;
  final List<ZonificacionInsumoRow> topInsumosGlobal;
  final List<ZonificacionConjuntoRow> data;

  const ZonificacionPreventivasResponse({
    required this.ok,
    required this.resumen,
    required this.topInsumosGlobal,
    required this.data,
  });

  factory ZonificacionPreventivasResponse.fromJson(Map<String, dynamic> json) {
    final resumenMap = (json['resumen'] is Map)
        ? (json['resumen'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};

    final topRaw = (json['topInsumosGlobal'] is List)
        ? (json['topInsumosGlobal'] as List)
        : const <dynamic>[];
    final dataRaw = (json['data'] is List)
        ? (json['data'] as List)
        : const <dynamic>[];

    return ZonificacionPreventivasResponse(
      ok: json['ok'] == true,
      resumen: ZonificacionResumen.fromJson(resumenMap),
      topInsumosGlobal: topRaw
          .whereType<Map>()
          .map((e) => ZonificacionInsumoRow.fromJson(e.cast<String, dynamic>()))
          .toList(),
      data: dataRaw
          .whereType<Map>()
          .map(
            (e) => ZonificacionConjuntoRow.fromJson(e.cast<String, dynamic>()),
          )
          .toList(),
    );
  }
}
