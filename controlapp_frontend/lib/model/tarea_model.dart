import 'package:flutter_application_1/model/insumo_usado_model.dart';
import 'package:flutter_application_1/model/preventiva_model.dart';

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
  final int? supervisorId;
  final int ubicacionId;
  final int elementoId;
  final int prioridad;

  final List<int> operariosIds;
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
    // (sí, esto es el “control de tiempos” en Controlito 😄)
  }

  factory TareaModel.fromJson(Map<String, dynamic> json) {
    // --- Fechas en local para evitar desajustes visuales ---
    final fechaInicioRaw = DateTime.parse(json['fechaInicio']);
    final fechaFinRaw = DateTime.parse(json['fechaFin']);
    final fechaInicio = fechaInicioRaw.toLocal();
    final fechaFin = fechaFinRaw.toLocal();

    // --- Operarios: soportar formato plano y anidado ---
    List<int> opIds = [];
    List<String> opNombres = [];

    if (json['operariosIds'] != null) {
      opIds = (json['operariosIds'] as List? ?? [])
          .map((e) => int.parse(e.toString()))
          .toList();
      opNombres = (json['operariosNombres'] as List? ?? [])
          .map((e) => e.toString())
          .toList();
    } else if (json['operarios'] != null) {
      final ops = json['operarios'] as List;
      opIds = ops.map((e) => int.parse(e['id'].toString())).toList();
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
    final ubicacionId = json['ubicacionId'] ?? 0;
    String? ubicacionNombre;
    if (json['ubicacionNombre'] != null) {
      ubicacionNombre = json['ubicacionNombre'] as String?;
    } else if (json['ubicacion'] != null) {
      ubicacionNombre = json['ubicacion']?['nombre']?.toString();
    }

    final elementoId = json['elementoId'] ?? 0;
    String? elementoNombre;
    if (json['elementoNombre'] != null) {
      elementoNombre = json['elementoNombre'] as String?;
    } else if (json['elemento'] != null) {
      elementoNombre = json['elemento']?['nombre']?.toString();
    }

    final prioridad = json['prioridad'] != null
        ? int.tryParse(json['prioridad'].toString()) ?? 2
        : 2;

    final tipo = json['tipo']?.toString();

    // --- Nuevos campos de planificación / insumo principal ---
    String? insumoPrincipalNombre;
    if (json['insumoPrincipalNombre'] != null) {
      insumoPrincipalNombre = json['insumoPrincipalNombre'] as String?;
    } else if (json['insumoPrincipal'] != null) {
      insumoPrincipalNombre = json['insumoPrincipal']?['nombre']?.toString();
    }

    num? tiempoEstimadoHoras;
    if (json['tiempoEstimadoHoras'] != null) {
      tiempoEstimadoHoras = num.tryParse(
        json['tiempoEstimadoHoras'].toString(),
      );
    }

    num? consumoPrincipalPorUnidad;
    if (json['consumoPrincipalPorUnidad'] != null) {
      consumoPrincipalPorUnidad = num.tryParse(
        json['consumoPrincipalPorUnidad'].toString(),
      );
    }

    num? consumoTotalEstimado;
    if (json['consumoTotalEstimado'] != null) {
      consumoTotalEstimado = num.tryParse(
        json['consumoTotalEstimado'].toString(),
      );
    }

    int durMin = 0;
    if (json['duracionMinutos'] != null) {
      durMin = int.tryParse(json['duracionMinutos'].toString()) ?? 0;
    } else if (json['duracionHoras'] != null) {
      final h = int.tryParse(json['duracionHoras'].toString()) ?? 0;
      durMin = h * 60;
    }

    return TareaModel(
      id: json['id'] ?? 0,
      descripcion: json['descripcion'] ?? '',
      fechaInicio: fechaInicio,
      fechaFin: fechaFin,
      duracionMinutos: durMin,
      estado: json['estado'],
      evidencias: json['evidencias'] != null
          ? List<String>.from(json['evidencias'])
          : [],
      insumosUsados: json['insumosUsados'] != null
          ? (json['insumosUsados'] as List)
                .map((i) => InsumoUsadoItem.fromJson(i))
                .toList()
          : [],
      observaciones: json['observaciones'],
      observacionesRechazo: json['observacionesRechazo'],
      tipo: json['tipo'],
      frecuencia: json['frecuencia'],
      conjuntoId: json['conjuntoId']?.toString(),
      conjuntoNombre: json['conjuntoNombre']?.toString(),
      supervisorId: json['supervisorId'] != null
          ? int.tryParse(json['supervisorId'].toString())
          : null,
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
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'descripcion': descripcion,
    'fechaInicio': fechaInicio.toIso8601String(),
    'fechaFin': fechaFin.toIso8601String(),

    /// ✅ NUEVO
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
    'supervisorId': supervisorId,
    'ubicacionId': ubicacionId,
    'elementoId': elementoId,
    'operariosIds': operariosIds,
    'prioridad': prioridad,
    'operariosNombres': operariosNombres,
    'supervisorNombre': supervisorNombre,
    'ubicacionNombre': ubicacionNombre,
    'elementoNombre': elementoNombre,
    'tiempoEstimadoHoras': tiempoEstimadoHoras,
    'insumoPrincipalNombre': insumoPrincipalNombre,
    'consumoPrincipalPorUnidad': consumoPrincipalPorUnidad,
    'consumoTotalEstimado': consumoTotalEstimado,
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
    int? supervisorId,
    int? ubicacionId,
    int? elementoId,
    List<int>? operariosIds,
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
    );
  }
}


