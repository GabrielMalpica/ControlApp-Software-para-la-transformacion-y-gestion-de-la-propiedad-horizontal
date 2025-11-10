// lib/models/tarea_model.dart

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
  final int? supervisorId;
  final int ubicacionId;
  final int elementoId;

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
    this.supervisorId,
    required this.ubicacionId,
    required this.elementoId,
  });

  factory TareaModel.fromJson(Map<String, dynamic> json) {
    return TareaModel(
      id: json['id'] ?? 0,
      descripcion: json['descripcion'] ?? '',
      fechaInicio: DateTime.parse(json['fechaInicio']),
      fechaFin: DateTime.parse(json['fechaFin']),
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
      conjuntoId: json['conjuntoId'],
      supervisorId: json['supervisorId'],
      ubicacionId: json['ubicacionId'] ?? 0,
      elementoId: json['elementoId'] ?? 0,
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
        'insumosUsados':
            insumosUsados?.map((e) => e.toJson()).toList() ?? [],
        'observaciones': observaciones,
        'observacionesRechazo': observacionesRechazo,
        'tipo': tipo,
        'frecuencia': frecuencia,
        'conjuntoId': conjuntoId,
        'supervisorId': supervisorId,
        'ubicacionId': ubicacionId,
        'elementoId': elementoId,
      };
}

/// DTO para insumo usado
class InsumoUsadoItem {
  final int insumoId;
  final int cantidad;

  InsumoUsadoItem({required this.insumoId, required this.cantidad});

  factory InsumoUsadoItem.fromJson(Map<String, dynamic> json) =>
      InsumoUsadoItem(
        insumoId: json['insumoId'],
        cantidad: json['cantidad'],
      );

  Map<String, dynamic> toJson() => {
        'insumoId': insumoId,
        'cantidad': cantidad,
      };
}

/// DTO para crear tarea
class CrearTareaDTO {
  final String descripcion;
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final int duracionHoras;
  final int ubicacionId;
  final int elementoId;
  final String? conjuntoId;
  final int? supervisorId;
  final List<int>? operariosIds;

  CrearTareaDTO({
    required this.descripcion,
    required this.fechaInicio,
    required this.fechaFin,
    required this.duracionHoras,
    required this.ubicacionId,
    required this.elementoId,
    this.conjuntoId,
    this.supervisorId,
    this.operariosIds,
  });

  Map<String, dynamic> toJson() => {
        'descripcion': descripcion,
        'fechaInicio': fechaInicio.toIso8601String(),
        'fechaFin': fechaFin.toIso8601String(),
        'duracionHoras': duracionHoras,
        'ubicacionId': ubicacionId,
        'elementoId': elementoId,
        if (conjuntoId != null) 'conjuntoId': conjuntoId,
        if (supervisorId != null) 'supervisorId': supervisorId,
        if (operariosIds != null) 'operariosIds': operariosIds,
      };
}
