import '../../api/operario_api.dart';

enum ClaseError { transitorio, negocio, sesionExpirada }

/// Clasifica una excepción de red/HTTP para decidir si un cierre de tarea
/// se puede encolar para reintento automático ([transitorio]/[sesionExpirada])
/// o si es una falla de negocio que el operario debe revisar ([negocio]).
///
/// - [ApiError] con 401 => sesión expirada (no es culpa de la conectividad,
///   pero tampoco se debe perder el trabajo: se encola igual).
/// - [ApiError] con 5xx/429 => falla transitoria del servidor.
/// - [ApiError] con otro 4xx => error de negocio (datos inválidos, tarea ya
///   cerrada, stock insuficiente, etc.), no se reintenta solo.
/// - Cualquier otra excepción (timeout, socket, DNS, "failed to fetch" en
///   web) => nunca llegó al servidor, es transitorio por definición.
ClaseError clasificarError(Object error) {
  if (error is ApiError) {
    if (error.statusCode == 401) return ClaseError.sesionExpirada;
    if (error.statusCode >= 500 || error.statusCode == 429) {
      return ClaseError.transitorio;
    }
    return ClaseError.negocio;
  }
  return ClaseError.transitorio;
}
