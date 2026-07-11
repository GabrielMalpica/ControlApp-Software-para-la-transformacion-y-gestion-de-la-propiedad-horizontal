class ChecklistItem {
  final String texto;
  final bool completado;

  const ChecklistItem({required this.texto, required this.completado});

  factory ChecklistItem.fromJson(Map<String, dynamic> json) {
    return ChecklistItem(
      texto: json['texto']?.toString() ?? '',
      completado: json['completado'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {'texto': texto, 'completado': completado};
  }

  ChecklistItem copyWith({String? texto, bool? completado}) {
    return ChecklistItem(
      texto: texto ?? this.texto,
      completado: completado ?? this.completado,
    );
  }
}

class PlanEsperanzaConfig {
  final int id;
  final String conjuntoId;
  final int intervaloMeses;

  const PlanEsperanzaConfig({
    required this.id,
    required this.conjuntoId,
    required this.intervaloMeses,
  });

  factory PlanEsperanzaConfig.fromJson(Map<String, dynamic> json) {
    return PlanEsperanzaConfig(
      id: json['id'] as int? ?? 0,
      conjuntoId: json['conjuntoId']?.toString() ?? '',
      intervaloMeses: json['intervaloMeses'] as int? ?? 3,
    );
  }
}

class DiagnosticoAreaModel {
  final int id;
  final int elementoId;
  final String elementoNombre;
  final int ubicacionId;
  final String ubicacionNombre;
  final String? subzonaNombre;
  final String? urlFoto;
  final double? valoracion;
  final String? observaciones;
  final List<ChecklistItem> checklist;
  final DateTime? creadoEn;

  const DiagnosticoAreaModel({
    required this.id,
    required this.elementoId,
    required this.elementoNombre,
    required this.ubicacionId,
    required this.ubicacionNombre,
    this.subzonaNombre,
    this.urlFoto,
    this.valoracion,
    this.observaciones,
    this.checklist = const [],
    this.creadoEn,
  });

  factory DiagnosticoAreaModel.fromJson(Map<String, dynamic> json) {
    return DiagnosticoAreaModel(
      id: json['id'] as int? ?? 0,
      elementoId: json['elementoId'] as int? ?? 0,
      elementoNombre: json['elementoNombre']?.toString() ?? '',
      ubicacionId: json['ubicacionId'] as int? ?? 0,
      ubicacionNombre: json['ubicacionNombre']?.toString() ?? '',
      subzonaNombre: json['subzonaNombre']?.toString(),
      urlFoto: json['urlFoto']?.toString(),
      valoracion: (json['valoracion'] as num?)?.toDouble(),
      observaciones: json['observaciones']?.toString(),
      checklist: (json['checklist'] as List<dynamic>? ?? [])
          .map((item) => ChecklistItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      creadoEn: json['creadoEn'] != null
          ? DateTime.tryParse(json['creadoEn'].toString())
          : null,
    );
  }
}

class PlanEsperanzaActivo {
  final int id;
  final String conjuntoId;
  final DateTime fechaInicio;
  final DateTime? fechaFin;
  final bool completado;
  final List<DiagnosticoAreaModel> diagnosticos;

  const PlanEsperanzaActivo({
    required this.id,
    required this.conjuntoId,
    required this.fechaInicio,
    this.fechaFin,
    required this.completado,
    required this.diagnosticos,
  });

  factory PlanEsperanzaActivo.fromJson(Map<String, dynamic> json) {
    return PlanEsperanzaActivo(
      id: json['id'] as int? ?? 0,
      conjuntoId: json['conjuntoId']?.toString() ?? '',
      fechaInicio: DateTime.parse(json['fechaInicio']?.toString() ?? ''),
      fechaFin: json['fechaFin'] != null
          ? DateTime.tryParse(json['fechaFin'].toString())
          : null,
      completado: json['completado'] as bool? ?? false,
      diagnosticos: (json['diagnosticos'] as List<dynamic>? ?? [])
          .map((d) =>
              DiagnosticoAreaModel.fromJson(d as Map<String, dynamic>))
          .toList(),
    );
  }
}

class PlanResumen {
  final int id;
  final DateTime fechaInicio;
  final DateTime? fechaFin;
  final bool completado;
  final int totalAreas;

  const PlanResumen({
    required this.id,
    required this.fechaInicio,
    this.fechaFin,
    required this.completado,
    required this.totalAreas,
  });

  factory PlanResumen.fromJson(Map<String, dynamic> json) {
    return PlanResumen(
      id: json['id'] as int? ?? 0,
      fechaInicio: DateTime.parse(json['fechaInicio']?.toString() ?? ''),
      fechaFin: json['fechaFin'] != null
          ? DateTime.tryParse(json['fechaFin'].toString())
          : null,
      completado: json['completado'] as bool? ?? false,
      totalAreas: json['totalAreas'] as int? ?? 0,
    );
  }
}

class TimelineEntry {
  final int planId;
  final DateTime fecha;
  final String? urlFoto;
  final double? valoracion;
  final String? observaciones;
  final List<ChecklistItem> checklist;

  const TimelineEntry({
    required this.planId,
    required this.fecha,
    this.urlFoto,
    this.valoracion,
    this.observaciones,
    this.checklist = const [],
  });

  factory TimelineEntry.fromJson(Map<String, dynamic> json) {
    return TimelineEntry(
      planId: json['planId'] as int? ?? 0,
      fecha: DateTime.parse(json['fecha']?.toString() ?? ''),
      urlFoto: json['urlFoto']?.toString(),
      valoracion: (json['valoracion'] as num?)?.toDouble(),
      observaciones: json['observaciones']?.toString(),
      checklist: (json['checklist'] as List<dynamic>? ?? [])
          .map((item) => ChecklistItem.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class AreaHistorico {
  final int elementoId;
  final String elementoNombre;
  final List<TimelineEntry> entradas;

  const AreaHistorico({
    required this.elementoId,
    required this.elementoNombre,
    required this.entradas,
  });

  factory AreaHistorico.fromJson(Map<String, dynamic> json) {
    return AreaHistorico(
      elementoId: json['elementoId'] as int? ?? 0,
      elementoNombre: json['elementoNombre']?.toString() ?? '',
      entradas: (json['entradas'] as List<dynamic>? ?? [])
          .map((e) => TimelineEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class SubzonaHistorico {
  final String subzonaNombre;
  final List<AreaHistorico> areas;

  const SubzonaHistorico({
    required this.subzonaNombre,
    required this.areas,
  });

  factory SubzonaHistorico.fromJson(Map<String, dynamic> json) {
    return SubzonaHistorico(
      subzonaNombre: json['subzonaNombre']?.toString() ?? '',
      areas: (json['areas'] as List<dynamic>? ?? [])
          .map((a) => AreaHistorico.fromJson(a as Map<String, dynamic>))
          .toList(),
    );
  }
}

class UbicacionHistorico {
  final String ubicacionNombre;
  final List<SubzonaHistorico> subzonas;

  const UbicacionHistorico({
    required this.ubicacionNombre,
    required this.subzonas,
  });

  factory UbicacionHistorico.fromJson(Map<String, dynamic> json) {
    return UbicacionHistorico(
      ubicacionNombre: json['ubicacionNombre']?.toString() ?? '',
      subzonas: (json['subzonas'] as List<dynamic>? ?? [])
          .map((s) => SubzonaHistorico.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }
}

class HistoricoResponse {
  final List<PlanResumen> planes;
  final List<UbicacionHistorico> ubicaciones;

  const HistoricoResponse({
    required this.planes,
    required this.ubicaciones,
  });

  factory HistoricoResponse.fromJson(Map<String, dynamic> json) {
    return HistoricoResponse(
      planes: (json['planes'] as List<dynamic>? ?? [])
          .map((p) => PlanResumen.fromJson(p as Map<String, dynamic>))
          .toList(),
      ubicaciones: (json['ubicaciones'] as List<dynamic>? ?? [])
          .map((u) => UbicacionHistorico.fromJson(u as Map<String, dynamic>))
          .toList(),
    );
  }
}

class AreaInforme {
  final int elementoId;
  final String elementoNombre;
  final String? urlFoto;
  final double? valoracion;
  final String? observaciones;
  final List<ChecklistItem> checklist;

  const AreaInforme({
    required this.elementoId,
    required this.elementoNombre,
    this.urlFoto,
    this.valoracion,
    this.observaciones,
    this.checklist = const [],
  });

  factory AreaInforme.fromJson(Map<String, dynamic> json) {
    return AreaInforme(
      elementoId: json['elementoId'] as int? ?? 0,
      elementoNombre: json['elementoNombre']?.toString() ?? '',
      urlFoto: json['urlFoto']?.toString(),
      valoracion: (json['valoracion'] as num?)?.toDouble(),
      observaciones: json['observaciones']?.toString(),
      checklist: (json['checklist'] as List<dynamic>? ?? [])
          .map((item) => ChecklistItem.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class SubzonaInforme {
  final String subzonaNombre;
  final List<AreaInforme> areas;

  const SubzonaInforme({
    required this.subzonaNombre,
    required this.areas,
  });

  factory SubzonaInforme.fromJson(Map<String, dynamic> json) {
    return SubzonaInforme(
      subzonaNombre: json['subzonaNombre']?.toString() ?? '',
      areas: (json['areas'] as List<dynamic>? ?? [])
          .map((a) => AreaInforme.fromJson(a as Map<String, dynamic>))
          .toList(),
    );
  }
}

class UbicacionInforme {
  final String ubicacionNombre;
  final List<SubzonaInforme> subzonas;

  const UbicacionInforme({
    required this.ubicacionNombre,
    required this.subzonas,
  });

  factory UbicacionInforme.fromJson(Map<String, dynamic> json) {
    return UbicacionInforme(
      ubicacionNombre: json['ubicacionNombre']?.toString() ?? '',
      subzonas: (json['subzonas'] as List<dynamic>? ?? [])
          .map((s) => SubzonaInforme.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }
}

class InformeResponse {
  final int planId;
  final String conjuntoNombre;
  final String conjuntoNit;
  final DateTime fechaInicio;
  final DateTime? fechaFin;
  final bool completado;
  final List<UbicacionInforme> ubicaciones;

  const InformeResponse({
    required this.planId,
    required this.conjuntoNombre,
    required this.conjuntoNit,
    required this.fechaInicio,
    this.fechaFin,
    required this.completado,
    required this.ubicaciones,
  });

  factory InformeResponse.fromJson(Map<String, dynamic> json) {
    return InformeResponse(
      planId: json['planId'] as int? ?? 0,
      conjuntoNombre: json['conjuntoNombre']?.toString() ?? '',
      conjuntoNit: json['conjuntoNit']?.toString() ?? '',
      fechaInicio: DateTime.parse(json['fechaInicio']?.toString() ?? ''),
      fechaFin: json['fechaFin'] != null
          ? DateTime.tryParse(json['fechaFin'].toString())
          : null,
      completado: json['completado'] as bool? ?? false,
      ubicaciones: (json['ubicaciones'] as List<dynamic>? ?? [])
          .map((u) => UbicacionInforme.fromJson(u as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ZonasNuevasCheck {
  final bool hayZonasNuevas;
  final int zonasExistentes;
  final int zonasActuales;

  const ZonasNuevasCheck({
    required this.hayZonasNuevas,
    required this.zonasExistentes,
    required this.zonasActuales,
  });

  factory ZonasNuevasCheck.fromJson(Map<String, dynamic> json) {
    return ZonasNuevasCheck(
      hayZonasNuevas: json['hayZonasNuevas'] as bool? ?? false,
      zonasExistentes: json['zonasExistentes'] as int? ?? 0,
      zonasActuales: json['zonasActuales'] as int? ?? 0,
    );
  }
}
