import 'package:flutter_application_1/model/insumo_usado_model.dart';
import 'package:flutter_application_1/model/preventiva_model.dart';

class TareaModel {
  final int id;
  final String descripcion;
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final int duracionHoras;
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

  // 👇 Aquí dejamos los IDs como int, nombres como String
  final List<int> operariosIds;
  final List<String> operariosNombres;
  final String? supervisorNombre;

  final String? ubicacionNombre;
  final String? elementoNombre;

  final List<MaquinariaPlanItem>? maquinariaPlan;

  TareaModel({
    required this.id,
    required this.descripcion,
    required this.fechaInicio,
    required this.fechaFin,
    required this.duracionHoras,
    this.estado,
    this.evidencias,
    this.insumosUsados,
    this.observaciones,
    this.observacionesRechazo,
    this.tipo,
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
  });

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
    int ubicacionId = json['ubicacionId'] ?? 0;
    String? ubicacionNombre;
    if (json['ubicacionNombre'] != null) {
      ubicacionNombre = json['ubicacionNombre'] as String?;
    } else if (json['ubicacion'] != null) {
      ubicacionNombre = json['ubicacion']?['nombre']?.toString();
    }

    int elementoId = json['elementoId'] ?? 0;
    String? elementoNombre;
    if (json['elementoNombre'] != null) {
      elementoNombre = json['elementoNombre'] as String?;
    } else if (json['elemento'] != null) {
      elementoNombre = json['elemento']?['nombre']?.toString();
    }

    return TareaModel(
      id: json['id'] ?? 0,
      descripcion: json['descripcion'] ?? '',
      fechaInicio: fechaInicio,
      fechaFin: fechaFin,
      duracionHoras: json['duracionHoras'] ?? 0,
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
      supervisorNombre: supervisorNombre,
      ubicacionNombre: ubicacionNombre,
      elementoNombre: elementoNombre,
      // Si más adelante necesitas maquinariaPlan:
      // maquinariaPlan: json['maquinariaPlan'] != null
      //     ? (json['maquinariaPlan'] as List)
      //         .map((m) => MaquinariaPlanItem.fromJson(m))
      //         .toList()
      //     : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'descripcion': descripcion,
    'fechaInicio': fechaInicio.toIso8601String(),
    'fechaFin': fechaFin.toIso8601String(),
    'duracionHoras': duracionHoras,
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
    'operariosNombres': operariosNombres,
    'supervisorNombre': supervisorNombre,
    'ubicacionNombre': ubicacionNombre,
    'elementoNombre': elementoNombre,
    // 'maquinariaPlan': maquinariaPlan?.map((m) => m.toJson()).toList(),
  };

  TareaModel copyWith({
    int? id,
    String? descripcion,
    DateTime? fechaInicio,
    DateTime? fechaFin,
    int? duracionHoras,
    String? estado,
    List<String>? evidencias,
    List<InsumoUsadoItem>? insumosUsados,
    String? observaciones,
    String? observacionesRechazo,
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
  }) {
    return TareaModel(
      id: id ?? this.id,
      descripcion: descripcion ?? this.descripcion,
      fechaInicio: fechaInicio ?? this.fechaInicio,
      fechaFin: fechaFin ?? this.fechaFin,
      duracionHoras: duracionHoras ?? this.duracionHoras,
      estado: estado ?? this.estado,
      evidencias: evidencias ?? this.evidencias,
      insumosUsados: insumosUsados ?? this.insumosUsados,
      observaciones: observaciones ?? this.observaciones,
      observacionesRechazo: observacionesRechazo ?? this.observacionesRechazo,
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
    );
  }
}
