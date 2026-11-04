import 'dart:convert';

import 'package:flutter_application_1/service/app_constants.dart';
import 'package:flutter_application_1/service/cliente_credenciales_bridge.dart';
import 'package:flutter_application_1/service/session_service.dart';
import 'package:http/http.dart' as http;

/// Cliente de las APIs que hablan JSON con el backend.
///
/// En la app nativa todas estas peticiones pasan además por `ClienteHttpApp`
/// (cabeceras de versión, renovación de sesión ante un 401 y reintento).
class ApiClient {
  final SessionService _session = SessionService();

  /// Tiempo límite por defecto: con "señal" pero sin datos una petición
  /// quedaría esperando minutos y la pantalla no avisaría nada.
  static const Duration tiempoLimite = Duration(seconds: 60);

  Uri _uri(String urlOrPath) {
    if (urlOrPath.startsWith('http://') || urlOrPath.startsWith('https://')) {
      return Uri.parse(urlOrPath);
    }
    final base = AppConstants.baseUrl;
    return Uri.parse('$base$urlOrPath');
  }

  Future<Map<String, String>> _headers({Map<String, String>? extra}) async {
    final token = await _session.getToken();
    final h = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (token != null && token.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    }
    if (extra != null) h.addAll(extra);

    return h;
  }

  Future<http.Response> get(
    String urlOrPath, {
    Map<String, String>? headers,
    Duration timeout = tiempoLimite,
  }) async {
    final uri = _uri(urlOrPath);
    return http
        .get(uri, headers: await _headers(extra: headers))
        .timeout(timeout);
  }

  Future<http.Response> post(
    String urlOrPath, {
    Object? body,
    Duration timeout = tiempoLimite,
  }) async {
    final uri = _uri(urlOrPath);
    return http
        .post(
          uri,
          headers: await _headers(),
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(timeout);
  }

  /// POST que en web viaja con credenciales: lo usan las rutas de /auth que
  /// ponen o borran la cookie HttpOnly de la sesion (login, cambio de
  /// contrasena, logout). En movil es un POST normal.
  Future<http.Response> postConCredenciales(
    String urlOrPath, {
    Object? body,
    Duration timeout = tiempoLimite,
  }) async {
    final uri = _uri(urlOrPath);
    final client = crearClienteConCredenciales();
    try {
      return await client
          .post(
            uri,
            headers: await _headers(),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(timeout);
    } finally {
      client.close();
    }
  }

  Future<http.Response> put(
    String urlOrPath, {
    Object? body,
    Duration timeout = tiempoLimite,
  }) async {
    final uri = _uri(urlOrPath);
    return http
        .put(
          uri,
          headers: await _headers(),
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(timeout);
  }

  Future<http.Response> patch(
    String urlOrPath, {
    Object? body,
    Duration timeout = tiempoLimite,
  }) async {
    final uri = _uri(urlOrPath);
    return http
        .patch(
          uri,
          headers: await _headers(),
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(timeout);
  }

  Future<http.Response> delete(
    String urlOrPath, {
    Object? body,
    Duration timeout = tiempoLimite,
  }) async {
    final uri = _uri(urlOrPath);
    return http
        .delete(
          uri,
          headers: await _headers(),
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(timeout);
  }
}
