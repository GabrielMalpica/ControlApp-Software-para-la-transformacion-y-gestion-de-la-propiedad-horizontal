import 'dart:convert';

import 'package:flutter_application_1/model/auth_models.dart';
import 'package:flutter_application_1/service/api_client.dart';
import 'package:flutter_application_1/service/session_service.dart';

class AuthApi {
  final ApiClient _client = ApiClient();
  final SessionService _session = SessionService();

  String _serverMessage(String body, {required String fallback}) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final message = decoded['message'] ?? decoded['error'];
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
        if (message is List && message.isNotEmpty) {
          return message.first.toString();
        }
      }
    } catch (_) {}

    final trimmed = body.trim();
    if (trimmed.isEmpty) return fallback;
    return trimmed;
  }

  Future<LoginResponse> login({
    required String correo,
    required String contrasena,
  }) async {
    final resp = await _client.post(
      '/auth/login',
      body: {'correo': correo.trim().toLowerCase(), 'contrasena': contrasena},
    );

    if (resp.statusCode != 200) {
      throw Exception(
        _serverMessage(resp.body, fallback: 'No se pudo iniciar sesion.'),
      );
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final result = LoginResponse.fromJson(data);

    if (result.token.isEmpty) {
      throw Exception('Login correcto pero no llego token.');
    }

    await _session.saveSession(
      token: result.token,
      rol: result.user.rol,
      correo: result.user.correo,
      nombre: result.user.nombre,
      userId: result.user.id,
    );

    return result;
  }

  Future<AuthUser> me() async {
    final resp = await _client.get('/auth/me');

    if (resp.statusCode != 200) {
      throw Exception(_serverMessage(resp.body, fallback: 'Sesion invalida.'));
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return AuthUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<void> cambiarContrasena({
    required String contrasenaActual,
    required String nuevaContrasena,
  }) async {
    final resp = await _client.post(
      '/auth/cambiar-contrasena',
      body: {
        'contrasenaActual': contrasenaActual,
        'nuevaContrasena': nuevaContrasena,
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
  }

  Future<void> recuperarContrasena({
    required String correo,
    required String cedula,
    required String nuevaContrasena,
  }) async {
    final resp = await _client.post(
      '/auth/recuperar-contrasena',
      body: {
        'correo': correo.trim().toLowerCase(),
        'id': cedula.trim(),
        'nuevaContrasena': nuevaContrasena,
      },
    );

    if (resp.statusCode != 200) {
      throw Exception(
        _serverMessage(
          resp.body,
          fallback: 'No se pudo recuperar la contrasena.',
        ),
      );
    }
  }

  Future<void> logout() async {
    await _session.clear();
  }
}
