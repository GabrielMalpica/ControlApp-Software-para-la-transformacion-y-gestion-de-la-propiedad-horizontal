import 'dart:convert';
import 'package:flutter_application_1/service/api_client.dart';
import 'package:flutter_application_1/service/session_service.dart';
import 'package:flutter_application_1/model/auth_models.dart';

class AuthApi {
  final ApiClient _client = ApiClient();
  final SessionService _session = SessionService();

  Future<LoginResponse> login({
    required String correo,
    required String contrasena,
  }) async {
    final resp = await _client.post(
      '/auth/login',
      body: {'correo': correo, 'contrasena': contrasena},
    );

    if (resp.statusCode != 200) {
      throw Exception('Login falló: ${resp.body}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final result = LoginResponse.fromJson(data);

    if (result.token.isEmpty) {
      throw Exception('Login OK pero NO llegó token.');
    }

    // ✅ Guardar sesión COMPLETA (token + user)
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
      throw Exception('Sesión inválida: ${resp.body}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return AuthUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<void> logout() async {
    await _session.clear();
  }
}
