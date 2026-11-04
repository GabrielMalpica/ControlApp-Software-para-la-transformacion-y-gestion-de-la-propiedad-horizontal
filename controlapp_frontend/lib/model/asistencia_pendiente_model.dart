import 'cierre_tarea_pendiente_model.dart';

/// Una marca de asistencia por QR que se escaneó sin señal y todavía no
/// llegó al servidor. Vive en el store `asistencias_pendientes` hasta quedar
/// sincronizada. Comparte los estados de los cierres pendientes
/// ([CierreSyncEstado]) para que la cola y la pantalla de pendientes los
/// traten igual.
class AsistenciaPendiente {
  /// UUID v4: deduplica los reintentos en el servidor.
  final String clienteRegistroId;
  final String usuarioId;
  final String rol;
  final String conjuntoId;
  final String qrPayload;
  final double latitud;
  final double longitud;
  final double? precisionMetros;

  /// Reloj del celular al escanear (UTC).
  final DateTime registradaEn;

  /// Hora del escaneo según el reloj monotónico (`RelojConfiable`), o null.
  final DateTime? registradaEnEstimada;

  final CierreSyncEstado estadoSync;
  final int intentos;
  final String? ultimoError;

  /// `code` del rechazo del servidor (p. ej. `QR_INVALIDO`), si lo hubo.
  final String? codigoError;
  final DateTime? nextAttemptAt;
  final DateTime creadoEn;
  final DateTime? sincronizadoEn;

  /// ENTRADA o SALIDA, cuando el servidor ya la registró.
  final String? tipoRegistrado;
  final String? conjuntoNombre;

  const AsistenciaPendiente({
    required this.clienteRegistroId,
    required this.usuarioId,
    required this.rol,
    required this.conjuntoId,
    required this.qrPayload,
    required this.latitud,
    required this.longitud,
    required this.registradaEn,
    required this.creadoEn,
    this.precisionMetros,
    this.registradaEnEstimada,
    this.estadoSync = CierreSyncEstado.pendiente,
    this.intentos = 0,
    this.ultimoError,
    this.codigoError,
    this.nextAttemptAt,
    this.sincronizadoEn,
    this.tipoRegistrado,
    this.conjuntoNombre,
  });

  AsistenciaPendiente copyWith({
    CierreSyncEstado? estadoSync,
    int? intentos,
    String? ultimoError,
    String? codigoError,
    DateTime? nextAttemptAt,
    DateTime? sincronizadoEn,
    String? tipoRegistrado,
    String? conjuntoNombre,
    bool limpiarError = false,
  }) {
    return AsistenciaPendiente(
      clienteRegistroId: clienteRegistroId,
      usuarioId: usuarioId,
      rol: rol,
      conjuntoId: conjuntoId,
      qrPayload: qrPayload,
      latitud: latitud,
      longitud: longitud,
      precisionMetros: precisionMetros,
      registradaEn: registradaEn,
      registradaEnEstimada: registradaEnEstimada,
      creadoEn: creadoEn,
      estadoSync: estadoSync ?? this.estadoSync,
      intentos: intentos ?? this.intentos,
      ultimoError: limpiarError ? null : (ultimoError ?? this.ultimoError),
      codigoError: limpiarError ? null : (codigoError ?? this.codigoError),
      nextAttemptAt: nextAttemptAt,
      sincronizadoEn: sincronizadoEn ?? this.sincronizadoEn,
      tipoRegistrado: tipoRegistrado ?? this.tipoRegistrado,
      conjuntoNombre: conjuntoNombre ?? this.conjuntoNombre,
    );
  }

  Map<String, dynamic> toJson() => {
    'clienteRegistroId': clienteRegistroId,
    'usuarioId': usuarioId,
    'rol': rol,
    'conjuntoId': conjuntoId,
    'qrPayload': qrPayload,
    'latitud': latitud,
    'longitud': longitud,
    'precisionMetros': precisionMetros,
    'registradaEn': registradaEn.toUtc().toIso8601String(),
    'registradaEnEstimada': registradaEnEstimada?.toUtc().toIso8601String(),
    'estadoSync': estadoSync.name,
    'intentos': intentos,
    'ultimoError': ultimoError,
    'codigoError': codigoError,
    'nextAttemptAt': nextAttemptAt?.toIso8601String(),
    'creadoEn': creadoEn.toIso8601String(),
    'sincronizadoEn': sincronizadoEn?.toIso8601String(),
    'tipoRegistrado': tipoRegistrado,
    'conjuntoNombre': conjuntoNombre,
  };

  factory AsistenciaPendiente.fromJson(Map<String, dynamic> json) {
    DateTime? fecha(String k) => DateTime.tryParse(json[k]?.toString() ?? '');
    return AsistenciaPendiente(
      clienteRegistroId: (json['clienteRegistroId'] ?? '').toString(),
      usuarioId: (json['usuarioId'] ?? '').toString(),
      rol: (json['rol'] ?? '').toString(),
      conjuntoId: (json['conjuntoId'] ?? '').toString(),
      qrPayload: (json['qrPayload'] ?? '').toString(),
      latitud: (json['latitud'] as num).toDouble(),
      longitud: (json['longitud'] as num).toDouble(),
      precisionMetros: (json['precisionMetros'] as num?)?.toDouble(),
      registradaEn: fecha('registradaEn')!,
      registradaEnEstimada: fecha('registradaEnEstimada'),
      estadoSync: cierreSyncEstadoFromName(json['estadoSync'] as String?),
      intentos: (json['intentos'] as num?)?.toInt() ?? 0,
      ultimoError: json['ultimoError'] as String?,
      codigoError: json['codigoError'] as String?,
      nextAttemptAt: fecha('nextAttemptAt'),
      creadoEn: fecha('creadoEn')!,
      sincronizadoEn: fecha('sincronizadoEn'),
      tipoRegistrado: json['tipoRegistrado'] as String?,
      conjuntoNombre: json['conjuntoNombre'] as String?,
    );
  }
}
