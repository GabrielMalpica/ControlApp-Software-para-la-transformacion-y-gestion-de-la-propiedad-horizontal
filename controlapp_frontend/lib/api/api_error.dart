import 'dart:convert';

import 'package:flutter_application_1/service/app_error.dart';

/// Error con el código HTTP real, para poder distinguir en el motor de
/// sincronización offline entre fallas transitorias (red, 5xx) y fallas de
/// negocio (4xx) que no deben reintentarse indefinidamente.
class ApiError implements Exception {
  final int statusCode;
  final String body;
  ApiError(this.statusCode, this.body);

  Map<String, dynamic>? get _json {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  /// `code` que manda el backend (p. ej. `TAREA_YA_CERRADA`), o null.
  String? get codigo {
    final c = _json?['code']?.toString().trim();
    return (c == null || c.isEmpty) ? null : c;
  }

  /// Mensaje del servidor listo para mostrar.
  String get mensaje => AppError.fromResponseBody(
    body,
    fallback: 'El servidor rechazó la solicitud ($statusCode).',
  );

  /// true si el cuerpo trae `requiereCambioContrasena` o el código de cambio
  /// de contraseña pendiente (403 de sesión, no de negocio).
  bool get esCambioDeContrasenaPendiente {
    final json = _json;
    if (json == null) return false;
    return json['requiereCambioContrasena'] == true ||
        json['code'] == 'CAMBIO_CONTRASENA_REQUERIDO';
  }

  @override
  String toString() => 'ApiError($statusCode): $body';
}
