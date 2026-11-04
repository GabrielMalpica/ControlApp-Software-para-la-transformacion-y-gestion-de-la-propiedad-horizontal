import 'package:flutter_application_1/api/api_error.dart';
import 'package:flutter_application_1/model/auth_models.dart';
import 'package:flutter_application_1/service/api_exception.dart';

enum DestinoArranque {
  /// Pantalla de inicio de sesión.
  login,

  /// Inicio según el rol de [DecisionArranque.usuario].
  inicio,

  /// El servidor exige una versión más nueva (426): se queda en la pantalla
  /// de actualizar.
  actualizarApp,
}

class DecisionArranque {
  final DestinoArranque destino;
  final AuthUser? usuario;

  /// Se entró con el perfil guardado porque no hubo respuesta del servidor.
  final bool sinSenal;

  /// Hay que borrar la sesión de este dispositivo (el servidor la rechazó).
  final bool borrarSesion;

  const DecisionArranque(
    this.destino, {
    this.usuario,
    this.sinSenal = false,
    this.borrarSesion = false,
  });
}

int? _status(Object e) {
  if (e is ApiException) return e.statusCode;
  if (e is ApiError) return e.statusCode;
  return null;
}

/// Decide a dónde entra la app al abrirse (probada en
/// test/arranque_sin_red_test.dart).
///
/// - Sin sesión guardada → login.
/// - `/auth/me` responde → inicio con el perfil del servidor.
/// - 401 (ya después de intentar renovar) → borrar sesión y login.
/// - 426 → pantalla de actualizar.
/// - App nativa sin respuesta (red, tiempo límite, 5xx) → inicio con el
///   perfil, rol, permisos y conjunto guardados; si no hay, login.
/// - Web: cualquier otro error → login, como siempre (la web sin señal no
///   abre de todos modos).
Future<DecisionArranque> decidirArranque({
  required Future<bool> Function() tieneSesion,
  required Future<AuthUser> Function() consultarPerfil,
  required Future<AuthUser?> Function() perfilGuardado,
  required bool esWeb,
}) async {
  if (!await tieneSesion()) {
    return const DecisionArranque(DestinoArranque.login);
  }

  try {
    final u = await consultarPerfil();
    return DecisionArranque(DestinoArranque.inicio, usuario: u);
  } catch (e) {
    final status = _status(e);
    if (status == 401) {
      return const DecisionArranque(DestinoArranque.login, borrarSesion: true);
    }
    if (status == 426) {
      return DecisionArranque(
        DestinoArranque.actualizarApp,
        usuario: esWeb ? null : await perfilGuardado(),
      );
    }
    if (esWeb) {
      return const DecisionArranque(DestinoArranque.login, borrarSesion: true);
    }
    // Un 4xx distinto (403 de cuenta inactiva, 404…) es una respuesta del
    // servidor: no se entra con datos guardados.
    if (status != null && status >= 400 && status < 500) {
      return const DecisionArranque(DestinoArranque.login, borrarSesion: true);
    }
    final guardado = await perfilGuardado();
    if (guardado == null) return const DecisionArranque(DestinoArranque.login);
    return DecisionArranque(
      DestinoArranque.inicio,
      usuario: guardado,
      sinSenal: true,
    );
  }
}
