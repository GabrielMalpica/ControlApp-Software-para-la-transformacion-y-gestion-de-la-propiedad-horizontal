/// Estado de sincronización de un cierre de tarea guardado localmente
/// mientras el operario no tenía conexión.
enum CierreSyncEstado { pendiente, sincronizando, sincronizado, error }

CierreSyncEstado cierreSyncEstadoFromName(String? name) {
  return CierreSyncEstado.values.firstWhere(
    (e) => e.name == name,
    orElse: () => CierreSyncEstado.pendiente,
  );
}

/// Evidencia de un cierre pendiente. En mobile/desktop se persiste como
/// archivo en el almacenamiento propio de la app ([path]); en web no hay
/// filesystem persistente accesible, así que los bytes se guardan
/// directamente en el store ([bytesBase64]).
class EvidenciaPendiente {
  final String nombre;
  final String? path;
  final String? bytesBase64;

  const EvidenciaPendiente({required this.nombre, this.path, this.bytesBase64});

  Map<String, dynamic> toJson() => {
    'nombre': nombre,
    'path': path,
    'bytesBase64': bytesBase64,
  };

  factory EvidenciaPendiente.fromJson(Map<String, dynamic> json) {
    return EvidenciaPendiente(
      nombre: (json['nombre'] ?? '').toString(),
      path: json['path'] as String?,
      bytesBase64: json['bytesBase64'] as String?,
    );
  }
}

/// Un cierre de tarea capturado por el operario que todavía no se ha
/// confirmado con el backend. Vive en el store offline hasta quedar
/// [CierreSyncEstado.sincronizado].
class CierreTareaPendiente {
  final String clienteCierreId;
  final int tareaId;
  final String rol;
  final String usuarioId;
  final String accion;
  final String? observaciones;
  final List<Map<String, num>> insumosUsados;
  final DateTime fechaCierreLocal;
  final List<EvidenciaPendiente> evidencias;

  final CierreSyncEstado estadoSync;
  final int intentos;
  final String? ultimoError;
  final DateTime? nextAttemptAt;
  final DateTime creadoEn;
  final DateTime? sincronizadoEn;

  const CierreTareaPendiente({
    required this.clienteCierreId,
    required this.tareaId,
    required this.rol,
    required this.usuarioId,
    required this.accion,
    required this.insumosUsados,
    required this.fechaCierreLocal,
    required this.evidencias,
    required this.creadoEn,
    this.observaciones,
    this.estadoSync = CierreSyncEstado.pendiente,
    this.intentos = 0,
    this.ultimoError,
    this.nextAttemptAt,
    this.sincronizadoEn,
  });

  CierreTareaPendiente copyWith({
    CierreSyncEstado? estadoSync,
    int? intentos,
    String? ultimoError,
    DateTime? nextAttemptAt,
    DateTime? sincronizadoEn,
    bool limpiarError = false,
  }) {
    return CierreTareaPendiente(
      clienteCierreId: clienteCierreId,
      tareaId: tareaId,
      rol: rol,
      usuarioId: usuarioId,
      accion: accion,
      observaciones: observaciones,
      insumosUsados: insumosUsados,
      fechaCierreLocal: fechaCierreLocal,
      evidencias: evidencias,
      creadoEn: creadoEn,
      estadoSync: estadoSync ?? this.estadoSync,
      intentos: intentos ?? this.intentos,
      ultimoError: limpiarError ? null : (ultimoError ?? this.ultimoError),
      nextAttemptAt: nextAttemptAt,
      sincronizadoEn: sincronizadoEn ?? this.sincronizadoEn,
    );
  }

  Map<String, dynamic> toJson() => {
    'clienteCierreId': clienteCierreId,
    'tareaId': tareaId,
    'rol': rol,
    'usuarioId': usuarioId,
    'accion': accion,
    'observaciones': observaciones,
    'insumosUsados': insumosUsados
        .map((e) => e.map((k, v) => MapEntry(k, v)))
        .toList(),
    'fechaCierreLocal': fechaCierreLocal.toIso8601String(),
    'evidencias': evidencias.map((e) => e.toJson()).toList(),
    'estadoSync': estadoSync.name,
    'intentos': intentos,
    'ultimoError': ultimoError,
    'nextAttemptAt': nextAttemptAt?.toIso8601String(),
    'creadoEn': creadoEn.toIso8601String(),
    'sincronizadoEn': sincronizadoEn?.toIso8601String(),
  };

  factory CierreTareaPendiente.fromJson(Map<String, dynamic> json) {
    return CierreTareaPendiente(
      clienteCierreId: (json['clienteCierreId'] ?? '').toString(),
      tareaId: (json['tareaId'] as num).toInt(),
      rol: (json['rol'] ?? '').toString(),
      usuarioId: (json['usuarioId'] ?? '').toString(),
      accion: (json['accion'] ?? 'COMPLETADA').toString(),
      observaciones: json['observaciones'] as String?,
      insumosUsados: ((json['insumosUsados'] as List?) ?? const [])
          .map((e) => (e as Map).map((k, v) => MapEntry(k.toString(), v as num)))
          .toList(),
      fechaCierreLocal: DateTime.parse(json['fechaCierreLocal']),
      evidencias: ((json['evidencias'] as List?) ?? const [])
          .map((e) => EvidenciaPendiente.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      estadoSync: cierreSyncEstadoFromName(json['estadoSync'] as String?),
      intentos: (json['intentos'] as num?)?.toInt() ?? 0,
      ultimoError: json['ultimoError'] as String?,
      nextAttemptAt: json['nextAttemptAt'] == null
          ? null
          : DateTime.parse(json['nextAttemptAt']),
      creadoEn: DateTime.parse(json['creadoEn']),
      sincronizadoEn: json['sincronizadoEn'] == null
          ? null
          : DateTime.parse(json['sincronizadoEn']),
    );
  }
}
