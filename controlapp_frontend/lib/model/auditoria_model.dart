/// Un movimiento registrado en la bitácora de auditoría.
class AuditoriaEventoModel {
  final String id;
  final String modulo;
  final String entidad;
  final String entidadId;
  final String accion;
  final String? actorId;
  final String? actorRol;
  final String? actorNombre;
  final String origen;
  final String? descripcion;
  final DateTime creadoEn;

  const AuditoriaEventoModel({
    required this.id,
    required this.modulo,
    required this.entidad,
    required this.entidadId,
    required this.accion,
    required this.origen,
    required this.creadoEn,
    this.actorId,
    this.actorRol,
    this.actorNombre,
    this.descripcion,
  });

  factory AuditoriaEventoModel.fromJson(Map<String, dynamic> json) {
    return AuditoriaEventoModel(
      id: json['id']?.toString() ?? '',
      modulo: json['modulo']?.toString() ?? '',
      entidad: json['entidad']?.toString() ?? '',
      entidadId: json['entidadId']?.toString() ?? '',
      accion: json['accion']?.toString() ?? '',
      actorId: json['actorId']?.toString(),
      actorRol: json['actorRol']?.toString(),
      actorNombre: json['actorNombre']?.toString(),
      origen: json['origen']?.toString() ?? 'USUARIO',
      descripcion: json['descripcion']?.toString(),
      creadoEn:
          DateTime.tryParse(json['creadoEn']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }

  /// Nombre legible del responsable. Los procesos automáticos no tienen actor.
  String get responsable {
    final nombre = actorNombre?.trim();
    if (nombre != null && nombre.isNotEmpty) {
      return actorRol != null && actorRol!.isNotEmpty
          ? '$nombre (${actorRol!.toLowerCase()})'
          : nombre;
    }
    if (actorId != null && actorId!.isNotEmpty) return actorId!;
    return origen == 'SCHEDULER'
        ? 'Generador de cronograma'
        : origen == 'CRON'
        ? 'Proceso automático'
        : 'Sistema';
  }
}

class AuditoriaActor {
  final String? id;
  final String? rol;
  final String? nombre;

  const AuditoriaActor({this.id, this.rol, this.nombre});

  factory AuditoriaActor.fromJson(Map<String, dynamic> json) => AuditoriaActor(
    id: json['id']?.toString(),
    rol: json['rol']?.toString(),
    nombre: json['nombre']?.toString(),
  );

  String get etiqueta {
    final n = nombre?.trim();
    if (n != null && n.isNotEmpty) {
      return rol != null && rol!.isNotEmpty ? '$n (${rol!.toLowerCase()})' : n;
    }
    return id?.trim().isNotEmpty == true ? id! : 'Sistema';
  }
}

/// Resumen "creado por / última modificación" de una entidad.
class TrazabilidadEntidad {
  final String entidadId;
  final AuditoriaActor? creadoPor;
  final DateTime? creadoEn;
  final AuditoriaActor? modificadoPor;
  final String? ultimaAccion;
  final String? ultimaDescripcion;
  final DateTime? modificadoEn;
  final int totalEventos;

  const TrazabilidadEntidad({
    required this.entidadId,
    required this.totalEventos,
    this.creadoPor,
    this.creadoEn,
    this.modificadoPor,
    this.ultimaAccion,
    this.ultimaDescripcion,
    this.modificadoEn,
  });

  factory TrazabilidadEntidad.fromJson(
    String entidadId,
    Map<String, dynamic> json,
  ) {
    final ultima = json['ultimaModificacion'] as Map<String, dynamic>?;
    final creador = json['creadoPor'] as Map<String, dynamic>?;

    return TrazabilidadEntidad(
      entidadId: entidadId,
      totalEventos: (json['totalEventos'] as num?)?.toInt() ?? 0,
      creadoPor: creador == null ? null : AuditoriaActor.fromJson(creador),
      creadoEn: DateTime.tryParse(
        json['creadoEn']?.toString() ?? '',
      )?.toLocal(),
      modificadoPor: ultima?['actor'] == null
          ? null
          : AuditoriaActor.fromJson(
              Map<String, dynamic>.from(ultima!['actor'] as Map),
            ),
      ultimaAccion: ultima?['accion']?.toString(),
      ultimaDescripcion: ultima?['descripcion']?.toString(),
      modificadoEn: DateTime.tryParse(
        ultima?['fecha']?.toString() ?? '',
      )?.toLocal(),
    );
  }

  bool get tieneDatos => creadoPor != null || modificadoPor != null;
}
