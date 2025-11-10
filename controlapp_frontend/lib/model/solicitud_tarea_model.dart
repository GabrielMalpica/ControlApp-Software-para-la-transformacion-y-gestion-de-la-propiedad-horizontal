// lib/models/solicitud_tarea_model.dart

enum EstadoSolicitud {
  pendiente,
  aprobada,
  rechazada;

  static EstadoSolicitud fromString(String value) {
    switch (value.toLowerCase()) {
      case 'aprobada':
        return EstadoSolicitud.aprobada;
      case 'rechazada':
        return EstadoSolicitud.rechazada;
      default:
        return EstadoSolicitud.pendiente;
    }
  }

  String toJson() {
    return name.toUpperCase();
  }
}

class SolicitudTareaModel {
  final int? id;
  final String descripcion;
  final int duracionHoras;
  final String conjuntoId;
  final int ubicacionId;
  final int elementoId;
  final String? empresaId;
  final String? observaciones;
  final EstadoSolicitud? estado;
  final DateTime? fechaCreacion;

  SolicitudTareaModel({
    this.id,
    required this.descripcion,
    required this.duracionHoras,
    required this.conjuntoId,
    required this.ubicacionId,
    required this.elementoId,
    this.empresaId,
    this.observaciones,
    this.estado,
    this.fechaCreacion,
  });

  factory SolicitudTareaModel.fromJson(Map<String, dynamic> json) {
    return SolicitudTareaModel(
      id: json['id'],
      descripcion: json['descripcion'] ?? '',
      duracionHoras: json['duracionHoras'] ?? 0,
      conjuntoId: json['conjuntoId'] ?? '',
      ubicacionId: json['ubicacionId'] ?? 0,
      elementoId: json['elementoId'] ?? 0,
      empresaId: json['empresaId'],
      observaciones: json['observaciones'],
      estado: json['estado'] != null
          ? EstadoSolicitud.fromString(json['estado'])
          : null,
      fechaCreacion: json['fechaCreacion'] != null
          ? DateTime.parse(json['fechaCreacion'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'descripcion': descripcion,
      'duracionHoras': duracionHoras,
      'conjuntoId': conjuntoId,
      'ubicacionId': ubicacionId,
      'elementoId': elementoId,
      if (empresaId != null) 'empresaId': empresaId,
      if (observaciones != null) 'observaciones': observaciones,
      if (estado != null) 'estado': estado!.toJson(),
    };
  }
}
