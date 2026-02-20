import 'package:flutter_application_1/model/insumo_usado_model.dart';
import 'package:flutter_application_1/model/preventiva_model.dart';

class InsumoProgramado {
  final int insumoId;
  final String nombre;
  final String unidad;
  final num cantidad;

  InsumoProgramado({
    required this.insumoId,
    required this.nombre,
    required this.unidad,
    required this.cantidad,
  });

  factory InsumoProgramado.fromJson(Map<String, dynamic> json) {
    return InsumoProgramado(
      insumoId: int.tryParse(json['insumoId']?.toString() ?? '') ?? 0,
      nombre: (json['nombre'] ?? '').toString(),
      unidad: (json['unidad'] ?? '').toString(),
      cantidad: num.tryParse(json['cantidad']?.toString() ?? '') ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'insumoId': insumoId,
    'nombre': nombre,
    'unidad': unidad,
    'cantidad': cantidad,
  };
}

class HerramientaAsignada {
  final int herramientaId;
  final String nombre;
  final num cantidad;
  final String? estado;

  HerramientaAsignada({
    required this.herramientaId,
    required this.nombre,
    required this.cantidad,
    this.estado,
  });

  factory HerramientaAsignada.fromJson(Map<String, dynamic> json) {
    return HerramientaAsignada(
      herramientaId: int.tryParse(json['herramientaId']?.toString() ?? '') ?? 0,
      nombre: (json['nombre'] ?? '').toString(),
      cantidad: num.tryParse(json['cantidad']?.toString() ?? '') ?? 1,
      estado: json['estado']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'herramientaId': herramientaId,
    'nombre': nombre,
    'cantidad': cantidad,
    if (estado != null) 'estado': estado,
  };
}

class MaquinariaAsignada {
  final int maquinariaId;
  final String nombre;

  MaquinariaAsignada({required this.maquinariaId, required this.nombre});

  factory MaquinariaAsignada.fromJson(Map<String, dynamic> json) {
    return MaquinariaAsignada(
      maquinariaId: int.tryParse(json['maquinariaId']?.toString() ?? '') ?? 0,
      nombre: (json['nombre'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'maquinariaId': maquinariaId,
    'nombre': nombre,
  };
}

class TareaModel {
  final int id;
  final String descripcion;
  final DateTime fechaInicio;
  final DateTime fechaFin;

  final int duracionMinutos;
  final bool borrador;

  final String? estado;
  final List<String>? evidencias;
  final List<InsumoUsadoItem>? insumosUsados;
  final String? observaciones;
  final String? observacionesRechazo;
  final String? tipo;
  final String? frecuencia;
  final String? conjuntoId;
  final String? conjuntoNombre;

  // ✅ IDs como STRING (cédula)
  final String? supervisorId;
  final List<String> operariosIds;

  final int ubicacionId;
  final int elementoId;
  final int prioridad;

  final List<String> operariosNombres;
  final String? supervisorNombre;
  final String? ubicacionNombre;
  final String? elementoNombre;

  // Planificación de maquinaria (si la necesitas más adelante)
  final List<MaquinariaPlanItem>? maquinariaPlan;

  // 🔹 Nuevos campos para detalle de planificación:
  final num? tiempoEstimadoHoras;
  final String? insumoPrincipalNombre;
  final num? consumoPrincipalPorUnidad;
  final num? consumoTotalEstimado;
  final List<HerramientaAsignada> herramientasAsignadas;
  final List<MaquinariaAsignada> maquinariasAsignadas;

  final List<InsumoProgramado> insumosProgramados;

  final String? insumoPrincipalUnidad;
  final bool reprogramada;
  final DateTime? reprogramadaEn;
  final String? reprogramadaMotivo;
  final int? reprogramadaPorTareaId;

  TareaModel({
    required this.id,
    required this.descripcion,
    required this.fechaInicio,
    required this.fechaFin,
    required this.duracionMinutos,
    required this.borrador,
    this.estado,
    this.evidencias,
    this.insumosUsados,
    this.observaciones,
    this.observacionesRechazo,
    this.tipo,
    this.prioridad = 2,
    this.frecuencia,
    this.conjuntoId,
    this.conjuntoNombre,
    this.supervisorId,
    required this.ubicacionId,
    required this.elementoId,
    this.operariosIds = const [],
    this.operariosNombres = const [],
    this.supervisorNombre,
    this.ubicacionNombre,
    this.elementoNombre,
    this.maquinariaPlan,
    this.tiempoEstimadoHoras,
    this.insumoPrincipalNombre,
    this.consumoPrincipalPorUnidad,
    this.consumoTotalEstimado,
    this.herramientasAsignadas = const [],
    this.maquinariasAsignadas = const [],
    this.insumosProgramados = const [],
    this.insumoPrincipalUnidad,
    this.reprogramada = false,
    this.reprogramadaEn,
    this.reprogramadaMotivo,
    this.reprogramadaPorTareaId,
  });

  /// ✅ Helpers para UI (si quieres mostrar horas)
  double get duracionHorasDecimal => duracionMinutos / 60.0;
  int get duracionHorasEnteras => (duracionMinutos / 60).floor();
  int get duracionMinRestantes => duracionMinutos % 60;

  String get duracionBonita {
    final h = duracionHorasEnteras;
    final m = duracionMinRestantes;
    if (h <= 0) return '$m min';
    if (m == 0) return '$h h';
    return '$h h $m min';
  }

  factory TareaModel.fromJson(Map<String, dynamic> json) {
    // --- Fechas en local para evitar desajustes visuales ---
    final fechaInicioRaw = DateTime.parse(json['fechaInicio']);
    final fechaFinRaw = DateTime.parse(json['fechaFin']);
    final fechaInicio = fechaInicioRaw.toLocal();
    final fechaFin = fechaFinRaw.toLocal();

    // --- Operarios: soportar formato plano y anidado ---
    List<String> opIds = [];
    List<String> opNombres = [];

    if (json['operariosIds'] != null) {
      opIds = (json['operariosIds'] as List? ?? [])
          .map((e) => e.toString())
          .toList();

      opNombres = (json['operariosNombres'] as List? ?? [])
          .map((e) => e.toString())
          .toList();
    } else if (json['operarios'] != null) {
      final ops = (json['operarios'] as List? ?? []);
      opIds = ops.map((e) => e['id'].toString()).toList();
      opNombres = ops
          .map((e) => (e['usuario']?['nombre'] ?? '').toString())
          .toList();
    }

    // --- Supervisor nombre: plano o anidado ---
    String? supervisorNombre;
    if (json['supervisorNombre'] != null) {
      supervisorNombre = json['supervisorNombre'] as String?;
    } else if (json['supervisor'] != null) {
      final sup = json['supervisor'];
      supervisorNombre = sup['usuario']?['nombre']?.toString();
    }

    // --- Ubicación / elemento: nombre plano o anidado ---
    final ubicacionId =
        int.tryParse(json['ubicacionId']?.toString() ?? '') ?? 0;
    String? ubicacionNombre;
    if (json['ubicacionNombre'] != null) {
      ubicacionNombre = json['ubicacionNombre'] as String?;
    } else if (json['ubicacion'] != null) {
      ubicacionNombre = json['ubicacion']?['nombre']?.toString();
    }

    final elementoId = int.tryParse(json['elementoId']?.toString() ?? '') ?? 0;
    String? elementoNombre;
    if (json['elementoNombre'] != null) {
      elementoNombre = json['elementoNombre'] as String?;
    } else if (json['elemento'] != null) {
      elementoNombre = json['elemento']?['nombre']?.toString();
    }

    final prioridad = int.tryParse(json['prioridad']?.toString() ?? '') ?? 2;

    // --- Nuevos campos de planificación / insumo principal ---
    String? insumoPrincipalNombre;
    if (json['insumoPrincipalNombre'] != null) {
      insumoPrincipalNombre = json['insumoPrincipalNombre'] as String?;
    } else if (json['insumoPrincipal'] != null) {
      insumoPrincipalNombre = json['insumoPrincipal']?['nombre']?.toString();
    }

    final tiempoEstimadoHoras = json['tiempoEstimadoHoras'] != null
        ? num.tryParse(json['tiempoEstimadoHoras'].toString())
        : null;

    final consumoPrincipalPorUnidad = json['consumoPrincipalPorUnidad'] != null
        ? num.tryParse(json['consumoPrincipalPorUnidad'].toString())
        : null;

    final consumoTotalEstimado = json['consumoTotalEstimado'] != null
        ? num.tryParse(json['consumoTotalEstimado'].toString())
        : null;

    int durMin = 0;
    if (json['duracionMinutos'] != null) {
      durMin = int.tryParse(json['duracionMinutos'].toString()) ?? 0;
    } else if (json['duracionHoras'] != null) {
      final h = int.tryParse(json['duracionHoras'].toString()) ?? 0;
      durMin = h * 60;
    }

    // ✅ supervisorId como STRING (cédula)
    final supervisorId = json['supervisorId'] != null
        ? json['supervisorId'].toString()
        : null;

    final herramientasAsignadas = (json['herramientasAsignadas'] as List? ?? [])
        .map((e) => HerramientaAsignada.fromJson(e as Map<String, dynamic>))
        .toList();

    final maquinariasAsignadas = (json['maquinariasAsignadas'] as List? ?? [])
        .map((e) => MaquinariaAsignada.fromJson(e as Map<String, dynamic>))
        .toList();

    final insumosProg = (json['insumosProgramados'] as List? ?? const [])
        .map(
          (e) => InsumoProgramado.fromJson((e as Map).cast<String, dynamic>()),
        )
        .toList();

    final insumoPrincipalUnidad = json['insumoPrincipalUnidad']?.toString();
    final reprogramada = json['reprogramada'] == true;
    final reprogramadaEn = json['reprogramadaEn'] != null
        ? DateTime.tryParse(json['reprogramadaEn'].toString())?.toLocal()
        : null;
    final reprogramadaMotivo = json['reprogramadaMotivo']?.toString();
    final reprogramadaPorTareaId = json['reprogramadaPorTareaId'] != null
        ? int.tryParse(json['reprogramadaPorTareaId'].toString())
        : null;

    return TareaModel(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      descripcion: (json['descripcion'] ?? '').toString(),
      fechaInicio: fechaInicio,
      fechaFin: fechaFin,
      duracionMinutos: durMin,
      estado: json['estado']?.toString(),
      evidencias: json['evidencias'] != null
          ? List<String>.from(
              (json['evidencias'] as List).map((e) => e.toString()),
            )
          : const [],
      insumosUsados: json['insumosUsados'] != null
          ? (json['insumosUsados'] as List)
                .map((i) => InsumoUsadoItem.fromJson(i))
                .toList()
          : const [],
      observaciones: json['observaciones']?.toString(),
      observacionesRechazo: json['observacionesRechazo']?.toString(),
      tipo: json['tipo']?.toString(),
      frecuencia: json['frecuencia']?.toString(),
      conjuntoId: json['conjuntoId']?.toString(),
      conjuntoNombre: json['conjuntoNombre']?.toString(),
      supervisorId: supervisorId,
      ubicacionId: ubicacionId,
      elementoId: elementoId,
      operariosIds: opIds,
      operariosNombres: opNombres,
      prioridad: prioridad,
      supervisorNombre: supervisorNombre,
      ubicacionNombre: ubicacionNombre,
      elementoNombre: elementoNombre,
      maquinariaPlan: null,
      tiempoEstimadoHoras: tiempoEstimadoHoras,
      insumoPrincipalNombre: insumoPrincipalNombre,
      consumoPrincipalPorUnidad: consumoPrincipalPorUnidad,
      consumoTotalEstimado: consumoTotalEstimado,
      borrador:
          (json['borrador'] as bool?) ?? (json['esBorrador'] as bool?) ?? false,
      herramientasAsignadas: herramientasAsignadas,
      maquinariasAsignadas: maquinariasAsignadas,
      insumosProgramados: insumosProg,
      insumoPrincipalUnidad: insumoPrincipalUnidad,
      reprogramada: reprogramada,
      reprogramadaEn: reprogramadaEn,
      reprogramadaMotivo: reprogramadaMotivo,
      reprogramadaPorTareaId: reprogramadaPorTareaId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'descripcion': descripcion,
    'fechaInicio': fechaInicio.toIso8601String(),
    'fechaFin': fechaFin.toIso8601String(),
    'duracionMinutos': duracionMinutos,
    'estado': estado,
    'evidencias': evidencias,
    'insumosUsados': (insumosUsados ?? []).map((e) => e.toJson()).toList(),
    'observaciones': observaciones,
    'observacionesRechazo': observacionesRechazo,
    'tipo': tipo,
    'frecuencia': frecuencia,
    'conjuntoId': conjuntoId,
    'conjuntoNombre': conjuntoNombre,
    'supervisorId': supervisorId, // ✅ string
    'ubicacionId': ubicacionId,
    'elementoId': elementoId,
    'operariosIds': operariosIds, // ✅ List<String>
    'prioridad': prioridad,
    'operariosNombres': operariosNombres,
    'supervisorNombre': supervisorNombre,
    'ubicacionNombre': ubicacionNombre,
    'elementoNombre': elementoNombre,
    'tiempoEstimadoHoras': tiempoEstimadoHoras,
    'insumoPrincipalNombre': insumoPrincipalNombre,
    'consumoPrincipalPorUnidad': consumoPrincipalPorUnidad,
    'consumoTotalEstimado': consumoTotalEstimado,
    'herramientasAsignadas': herramientasAsignadas
        .map((e) => e.toJson())
        .toList(),
    'maquinariasAsignadas': maquinariasAsignadas
        .map((e) => e.toJson())
        .toList(),
    'insumosProgramados': insumosProgramados.map((e) => e.toJson()).toList(),
    'insumoPrincipalUnidad': insumoPrincipalUnidad,
    'reprogramada': reprogramada,
    'reprogramadaEn': reprogramadaEn?.toIso8601String(),
    'reprogramadaMotivo': reprogramadaMotivo,
    'reprogramadaPorTareaId': reprogramadaPorTareaId,
  };

  TareaModel copyWith({
    int? id,
    String? descripcion,
    DateTime? fechaInicio,
    DateTime? fechaFin,
    int? duracionMinutos,
    String? estado,
    bool? borrador,
    int? prioridad,
    String? tipo,
    String? frecuencia,
    String? conjuntoId,
    String? conjuntoNombre,

    // ✅ supervisorId string
    String? supervisorId,

    int? ubicacionId,
    int? elementoId,

    // ✅ operariosIds strings
    List<String>? operariosIds,

    List<String>? operariosNombres,
    String? supervisorNombre,
    String? ubicacionNombre,
    String? elementoNombre,
    List<MaquinariaPlanItem>? maquinariaPlan,
    num? tiempoEstimadoHoras,
    String? insumoPrincipalNombre,
    num? consumoPrincipalPorUnidad,
    num? consumoTotalEstimado,
    List<String>? evidencias,
    List<InsumoUsadoItem>? insumosUsados,
    String? observaciones,
    String? observacionesRechazo,
    List<HerramientaAsignada>? herramientasAsignadas,
    List<MaquinariaAsignada>? maquinariasAsignadas,
    List<InsumoProgramado>? insumosProgramados,
    String? insumoPrincipalUnidad,
    bool? reprogramada,
    DateTime? reprogramadaEn,
    String? reprogramadaMotivo,
    int? reprogramadaPorTareaId,
  }) {
    return TareaModel(
      id: id ?? this.id,
      descripcion: descripcion ?? this.descripcion,
      fechaInicio: fechaInicio ?? this.fechaInicio,
      fechaFin: fechaFin ?? this.fechaFin,
      duracionMinutos: duracionMinutos ?? this.duracionMinutos,
      estado: estado ?? this.estado,
      borrador: borrador ?? this.borrador,
      prioridad: prioridad ?? this.prioridad,
      tipo: tipo ?? this.tipo,
      frecuencia: frecuencia ?? this.frecuencia,
      conjuntoId: conjuntoId ?? this.conjuntoId,
      conjuntoNombre: conjuntoNombre ?? this.conjuntoNombre,
      supervisorId: supervisorId ?? this.supervisorId,
      ubicacionId: ubicacionId ?? this.ubicacionId,
      elementoId: elementoId ?? this.elementoId,
      operariosIds: operariosIds ?? this.operariosIds,
      operariosNombres: operariosNombres ?? this.operariosNombres,
      supervisorNombre: supervisorNombre ?? this.supervisorNombre,
      ubicacionNombre: ubicacionNombre ?? this.ubicacionNombre,
      elementoNombre: elementoNombre ?? this.elementoNombre,
      maquinariaPlan: maquinariaPlan ?? this.maquinariaPlan,
      tiempoEstimadoHoras: tiempoEstimadoHoras ?? this.tiempoEstimadoHoras,
      insumoPrincipalNombre:
          insumoPrincipalNombre ?? this.insumoPrincipalNombre,
      consumoPrincipalPorUnidad:
          consumoPrincipalPorUnidad ?? this.consumoPrincipalPorUnidad,
      consumoTotalEstimado: consumoTotalEstimado ?? this.consumoTotalEstimado,
      evidencias: evidencias ?? this.evidencias,
      insumosUsados: insumosUsados ?? this.insumosUsados,
      observaciones: observaciones ?? this.observaciones,
      observacionesRechazo: observacionesRechazo ?? this.observacionesRechazo,
      herramientasAsignadas:
          herramientasAsignadas ?? this.herramientasAsignadas,
      maquinariasAsignadas: maquinariasAsignadas ?? this.maquinariasAsignadas,
      insumosProgramados: insumosProgramados ?? this.insumosProgramados,
      insumoPrincipalUnidad:
          insumoPrincipalUnidad ?? this.insumoPrincipalUnidad,
      reprogramada: reprogramada ?? this.reprogramada,
      reprogramadaEn: reprogramadaEn ?? this.reprogramadaEn,
      reprogramadaMotivo: reprogramadaMotivo ?? this.reprogramadaMotivo,
      reprogramadaPorTareaId:
          reprogramadaPorTareaId ?? this.reprogramadaPorTareaId,
    );
  }
}
