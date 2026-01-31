// agenda_asignacion_model.dart

enum EstadoAsignacionMaquinaria { RESERVADA, ACTIVA, DEVUELTA, INACTIVA }

extension EstadoAsignacionMaquinariaExt on EstadoAsignacionMaquinaria {
  String get backendValue => name;

  String get label {
    switch (this) {
      case EstadoAsignacionMaquinaria.RESERVADA:
        return 'Reservada';
      case EstadoAsignacionMaquinaria.ACTIVA:
        return 'Activa';
      case EstadoAsignacionMaquinaria.DEVUELTA:
        return 'Devuelta';
      case EstadoAsignacionMaquinaria.INACTIVA:
        return 'Inactiva';
    }
  }
}

EstadoAsignacionMaquinaria estadoAsignacionFromString(String? v) {
  final x = (v ?? '').toUpperCase();
  return EstadoAsignacionMaquinaria.values.firstWhere(
    (e) => e.name == x,
    orElse: () => EstadoAsignacionMaquinaria.RESERVADA,
  );
}

DateTime _parseDate(dynamic v) {
  if (v == null)
    throw ArgumentError('Fecha null en AgendaAsignacionMaquinaria');
  if (v is DateTime) return v;
  return DateTime.parse(v.toString());
}

class AgendaAsignacionMaquinaria {
  final int id;
  final String conjuntoId;
  final int maquinariaId;

  final DateTime inicio;
  final DateTime fin;

  final EstadoAsignacionMaquinaria estado;

  final int? tareaId;
  final String? observacion;

  final String? maquinariaNombre;
  final String? maquinariaMarca;
  final String? maquinariaTipo;
  final String? operarioNombre;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const AgendaAsignacionMaquinaria({
    required this.id,
    required this.conjuntoId,
    required this.maquinariaId,
    required this.inicio,
    required this.fin,
    required this.estado,
    this.tareaId,
    this.observacion,
    this.maquinariaNombre,
    this.maquinariaMarca,
    this.maquinariaTipo,
    this.operarioNombre,
    this.createdAt,
    this.updatedAt,
  });

  factory AgendaAsignacionMaquinaria.fromJson(Map<String, dynamic> json) {
    DateTime? parseOptional(dynamic v) => v == null ? null : _parseDate(v);

    return AgendaAsignacionMaquinaria(
      id: (json['id'] as num).toInt(),
      conjuntoId: (json['conjuntoId'] ?? json['conjuntoNit'] ?? '').toString(),
      maquinariaId: (json['maquinariaId'] as num).toInt(),
      inicio: _parseDate(json['inicio']),
      fin: _parseDate(json['fin']),
      estado: estadoAsignacionFromString(json['estado']?.toString()),
      tareaId: (json['tareaId'] as num?)?.toInt(),
      observacion: json['observacion']?.toString(),
      maquinariaNombre: json['maquinariaNombre']?.toString(),
      maquinariaMarca: json['maquinariaMarca']?.toString(),
      maquinariaTipo: json['maquinariaTipo']?.toString(),
      operarioNombre: json['operarioNombre']?.toString(),
      createdAt: parseOptional(json['createdAt']),
      updatedAt: parseOptional(json['updatedAt']),
    );
  }
}
