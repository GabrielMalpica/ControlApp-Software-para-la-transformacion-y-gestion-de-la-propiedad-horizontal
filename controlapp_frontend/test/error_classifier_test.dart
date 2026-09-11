import 'dart:async';
import 'dart:io';

import 'package:flutter_application_1/api/operario_api.dart';
import 'package:flutter_application_1/service/offline/error_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('401 se clasifica como sesión expirada: la cola no debe abandonarla', () {
    expect(clasificarError(ApiError(401, 'no autorizado')), ClaseError.sesionExpirada);
  });

  test('5xx y 429 se clasifican como transitorios: se reintentan solos', () {
    expect(clasificarError(ApiError(500, 'boom')), ClaseError.transitorio);
    expect(clasificarError(ApiError(503, 'boom')), ClaseError.transitorio);
    expect(clasificarError(ApiError(429, 'rate limited')), ClaseError.transitorio);
  });

  test('4xx de negocio (400/404/409) no se reintentan solos', () {
    expect(clasificarError(ApiError(400, 'stock insuficiente')), ClaseError.negocio);
    expect(clasificarError(ApiError(404, 'tarea no encontrada')), ClaseError.negocio);
    expect(clasificarError(ApiError(409, 'tarea ya cerrada')), ClaseError.negocio);
  });

  test('errores de transporte (timeout, socket) nunca llegaron al servidor: son transitorios', () {
    expect(
      clasificarError(TimeoutException('sin respuesta')),
      ClaseError.transitorio,
    );
    expect(
      clasificarError(const SocketException('Failed host lookup')),
      ClaseError.transitorio,
    );
  });
}
