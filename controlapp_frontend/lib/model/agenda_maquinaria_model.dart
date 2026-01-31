// agenda_maquinaria_model.dart

class AgendaMaquinaria {
  final int maquinariaId;
  final String nombre;
  final bool esPropiaConjunto;
  final List<ReservaMaquinaria> reservas;

  const AgendaMaquinaria({
    required this.maquinariaId,
    required this.nombre,
    required this.esPropiaConjunto,
    required this.reservas,
  });

  factory AgendaMaquinaria.fromJson(Map<String, dynamic> json) {
    return AgendaMaquinaria(
      maquinariaId: (json['maquinariaId'] as num).toInt(),
      nombre: json['nombre']?.toString() ?? '',
      esPropiaConjunto: json['esPropiaConjunto'] as bool? ?? false,
      reservas: (json['reservas'] as List<dynamic>)
          .map((e) => ReservaMaquinaria.fromJson(e))
          .toList(),
    );
  }
}

class ReservaMaquinaria {
  final int id;
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final int? tareaId;
  final TareaAgenda? tarea;
  final String? observacion;

  const ReservaMaquinaria({
    required this.id,
    required this.fechaInicio,
    required this.fechaFin,
    this.tareaId,
    this.tarea,
    this.observacion,
  });

  factory ReservaMaquinaria.fromJson(Map<String, dynamic> json) {
    return ReservaMaquinaria(
      id: (json['id'] as num).toInt(),
      fechaInicio: DateTime.parse(json['fechaInicio']),
      fechaFin: DateTime.parse(json['fechaFin']),
      tareaId: (json['tareaId'] as num?)?.toInt(),
      tarea: json['tarea'] != null ? TareaAgenda.fromJson(json['tarea']) : null,
      observacion: json['observacion']?.toString(),
    );
  }
}

class TareaAgenda {
  final int id;
  final String descripcion;
  final String estado;
  final String tipo;
  final int prioridad;
  final String? ubicacion;
  final String? elemento;
  final DateTime fechaInicio;
  final DateTime fechaFin;

  const TareaAgenda({
    required this.id,
    required this.descripcion,
    required this.estado,
    required this.tipo,
    required this.prioridad,
    this.ubicacion,
    this.elemento,
    required this.fechaInicio,
    required this.fechaFin,
  });

  factory TareaAgenda.fromJson(Map<String, dynamic> json) {
    return TareaAgenda(
      id: (json['id'] as num).toInt(),
      descripcion: json['descripcion']?.toString() ?? '',
      estado: json['estado']?.toString() ?? '',
      tipo: json['tipo']?.toString() ?? '',
      prioridad: (json['prioridad'] as num?)?.toInt() ?? 0,
      ubicacion: json['ubicacion']?.toString(),
      elemento: json['elemento']?.toString(),
      fechaInicio: DateTime.parse(json['fechaInicio']),
      fechaFin: DateTime.parse(json['fechaFin']),
    );
  }
}
