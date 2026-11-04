import '../../api/api_error.dart';
import '../api_exception.dart';

enum ClaseError {
  /// Nunca llegó al servidor o el servidor falló (red, timeout, 5xx, 429):
  /// se reintenta solo.
  transitorio,

  /// El servidor rechazó el contenido (4xx de negocio): el operario lo
  /// revisa; nunca se reintenta ni se descarta solo.
  negocio,

  /// 401, o 403 por cambio de contraseña pendiente: hay que renovar o volver
  /// a iniciar sesión. Lo guardado se conserva.
  sesionExpirada,

  /// 426 `APP_DESACTUALIZADA`: hay que actualizar la app. La cola se
  /// conserva y se envía con la versión nueva.
  appDesactualizada,
}

/// Clasifica una excepción de red/HTTP para decidir qué hacer con un cierre
/// de tarea o una asistencia guardada sin señal.
///
/// - 401 => sesión expirada (no se pierde el trabajo: se encola igual).
/// - 403 con `requiereCambioContrasena` => sesión (debe cambiar la
///   contraseña); cualquier otro 403 es de negocio (p. ej. fuera del
///   conjunto en la asistencia).
/// - 426 => app desactualizada.
/// - 5xx/429/408 => falla transitoria del servidor.
/// - Otro 4xx => error de negocio (tarea ya cerrada, reasignada, stock
///   insuficiente, QR inválido…): no se reintenta solo.
/// - Cualquier otra excepción (timeout, socket, DNS, "failed to fetch" en
///   web) => nunca llegó al servidor, es transitorio por definición.
ClaseError clasificarError(Object error) {
  final int? status;
  final String? codigo;
  var cambioContrasena = false;
  if (error is ApiError) {
    status = error.statusCode;
    codigo = error.codigo;
    cambioContrasena = error.esCambioDeContrasenaPendiente;
  } else if (error is ApiException) {
    status = error.statusCode;
    codigo = error.reason;
    final d = error.details;
    cambioContrasena =
        d is Map &&
        (d['requiereCambioContrasena'] == true ||
            d['code'] == 'CAMBIO_CONTRASENA_REQUERIDO');
  } else {
    return ClaseError.transitorio;
  }

  if (status == 401) return ClaseError.sesionExpirada;
  if (status == 403 && cambioContrasena) return ClaseError.sesionExpirada;
  if (status == 426) return ClaseError.appDesactualizada;
  if (status >= 500 || status == 429 || status == 408) {
    return ClaseError.transitorio;
  }
  if (status == 409 && codigo == 'RENOVACION_EN_CURSO') {
    return ClaseError.transitorio;
  }
  if (status >= 400) return ClaseError.negocio;
  return ClaseError.transitorio;
}
