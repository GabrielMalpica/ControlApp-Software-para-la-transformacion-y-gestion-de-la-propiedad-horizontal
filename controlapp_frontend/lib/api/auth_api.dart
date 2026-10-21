import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/model/auth_models.dart';
import 'package:flutter_application_1/model/profile_models.dart';
import 'package:flutter_application_1/service/api_client.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/session_service.dart';

class AuthApi {
  final ApiClient _client = ApiClient();
  final SessionService _session = SessionService();

  String _serverMessage(String body, {required String fallback}) {
    return AppError.fromResponseBody(body, fallback: fallback);
  }

  Future<LoginResponse> login({
    required String correo,
    required String contrasena,
  }) async {
    // En web se pide sesion con cookie HttpOnly de renovacion: el token
    // queda solo en memoria (ver SessionService).
    final resp = await _client.postConCredenciales(
      '/auth/login',
      body: {
        'correo': correo.trim().toLowerCase(),
        'contrasena': contrasena,
        'sesionWeb': kIsWeb,
      },
    );

    if (resp.statusCode != 200) {
      throw Exception(
        _serverMessage(resp.body, fallback: 'No se pudo iniciar sesión.'),
      );
    }

    final result = await _guardarSesion(resp.body);
    if (result.token.isEmpty) {
      throw Exception('Login correcto pero no llego token.');
    }
    return result;
  }

  /// Guarda la sesion que devuelve el backend (login o cambio de contrasena,
  /// que cierra las demas sesiones y entrega una nueva a este dispositivo).
  Future<LoginResponse> _guardarSesion(String body) async {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final result = LoginResponse.fromJson(data);
    if (result.token.isEmpty) return result;

    await _session.saveSession(
      token: result.token,
      rol: result.user.rol,
      correo: result.user.correo,
      nombre: result.user.nombre,
      userId: result.user.id,
      empresaId: result.user.empresaId,
      conjuntoId: result.user.conjuntoId,
      permissions: result.user.permissions,
      requiereCambioContrasena: result.user.requiereCambioContrasena,
    );
    return result;
  }

  Future<AuthUser> me() async {
    final resp = await _client.get('/auth/me');

    if (resp.statusCode != 200) {
      throw Exception(_serverMessage(resp.body, fallback: 'Sesión inválida.'));
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
    await _session.saveProfile(
      rol: user.rol,
      correo: user.correo,
      nombre: user.nombre,
      userId: user.id,
      empresaId: user.empresaId,
      conjuntoId: user.conjuntoId,
      permissions: user.permissions,
      requiereCambioContrasena: user.requiereCambioContrasena,
    );
    return user;
  }

  Future<ProfileSummary> perfilResumen() async {
    final resp = await _client.get('/auth/perfil-resumen');

    if (resp.statusCode != 200) {
      throw Exception(
        _serverMessage(resp.body, fallback: 'No se pudo cargar el perfil.'),
      );
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return ProfileSummary.fromJson(data);
  }

  Future<void> cambiarContrasena({
    required String contrasenaActual,
    required String nuevaContrasena,
  }) async {
    final resp = await _client.postConCredenciales(
      '/auth/cambiar-contrasena',
      body: {
        'contrasenaActual': contrasenaActual,
        'nuevaContrasena': nuevaContrasena,
        'sesionWeb': kIsWeb,
      },
    );

    if (resp.statusCode != 200) {
      throw Exception(
        _serverMessage(
          resp.body,
          fallback: 'No se pudo cambiar la contrasena.',
        ),
      );
    }

    // El backend cerro las demas sesiones y entrego una nueva para este equipo.
    await _guardarSesion(resp.body);
  }

  Future<void> cambiarContrasenaInicial({
    required String nuevaContrasena,
  }) async {
    final resp = await _client.postConCredenciales(
      '/auth/cambiar-contrasena-inicial',
      body: {'nuevaContrasena': nuevaContrasena, 'sesionWeb': kIsWeb},
    );

    if (resp.statusCode != 200) {
      throw Exception(
        _serverMessage(
          resp.body,
          fallback: 'No se pudo actualizar la contrasena inicial.',
        ),
      );
    }

    // La sesion anterior queda cerrada: se guarda la nueva que entrega el
    // backend (ya sin cambio de contrasena pendiente).
    await _guardarSesion(resp.body);
    await _session.setRequirePasswordChange(false);
  }

  Future<void> cambiarContrasenaUsuario({
    required String userId,
    required String nuevaContrasena,
  }) async {
    final resp = await _client.post(
      '/auth/usuarios/$userId/cambiar-contrasena',
      body: {'nuevaContrasena': nuevaContrasena},
    );

    if (resp.statusCode != 200) {
      throw Exception(
        _serverMessage(
          resp.body,
          fallback: 'No se pudo cambiar la contrasena del usuario.',
        ),
      );
    }
  }

  /// Cierra la sesion en el servidor (revoca el token y la cookie web) y
  /// luego en este dispositivo. Si el servidor no responde, igual se limpia.
  Future<void> logout() async {
    try {
      await _client.postConCredenciales('/auth/logout');
    } catch (_) {
      // Mejor esfuerzo: sin red el token vence solo.
    }
    await _session.clear();
  }
}
