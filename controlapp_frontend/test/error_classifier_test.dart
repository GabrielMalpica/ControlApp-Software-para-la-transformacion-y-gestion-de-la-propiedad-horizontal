import 'dart:async';
import 'dart:io';

import 'package:flutter_application_1/api/operario_api.dart';
import 'package:flutter_application_1/service/api_exception.dart';
import 'package:flutter_application_1/service/offline/error_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    '401 se clasifica como sesión expirada: la cola no debe abandonarla',
    () {
      expect(
        clasificarError(ApiError(401, 'no autorizado')),
        ClaseError.sesionExpirada,
      );
    },
  );

  test('5xx y 429 se clasifican como transitorios: se reintentan solos', () {
    expect(clasificarError(ApiError(500, 'boom')), ClaseError.transitorio);
    expect(clasificarError(ApiError(503, 'boom')), ClaseError.transitorio);
    expect(
      clasificarError(ApiError(429, 'rate limited')),
      ClaseError.transitorio,
    );
  });

  test('4xx de negocio (400/404/409) no se reintentan solos', () {
    expect(
      clasificarError(ApiError(400, 'stock insuficiente')),
      ClaseError.negocio,
    );
    expect(
      clasificarError(ApiError(404, 'tarea no encontrada')),
      ClaseError.negocio,
    );
    expect(
      clasificarError(ApiError(409, 'tarea ya cerrada')),
      ClaseError.negocio,
    );
  });

  test(
    'errores de transporte (timeout, socket) nunca llegaron al servidor: son transitorios',
    () {
      expect(
        clasificarError(TimeoutException('sin respuesta')),
        ClaseError.transitorio,
      );
      expect(
        clasificarError(const SocketException('Failed host lookup')),
        ClaseError.transitorio,
      );
    },
  );

  test('426 APP_DESACTUALIZADA: actualizar la app, la cola se conserva', () {
    expect(
      clasificarError(ApiError(426, '{"code":"APP_DESACTUALIZADA"}')),
      ClaseError.appDesactualizada,
    );
  });

  test('403 por cambio de contraseña es de sesión; otro 403 es de negocio', () {
    expect(
      clasificarError(ApiError(403, '{"code":"CAMBIO_CONTRASENA_REQUERIDO"}')),
      ClaseError.sesionExpirada,
    );
    expect(
      clasificarError(ApiError(403, '{"requiereCambioContrasena":true}')),
      ClaseError.sesionExpirada,
    );
    expect(
      clasificarError(ApiError(403, '{"message":"Estás lejos del conjunto"}')),
      ClaseError.negocio,
    );
  });

  test('códigos de rechazo del contrato son de negocio', () {
    for (final (status, code) in const [
      (404, 'TAREA_ELIMINADA'),
      (409, 'TAREA_REASIGNADA'),
      (409, 'TAREA_YA_CERRADA'),
      (409, 'STOCK_INSUFICIENTE'),
      (400, 'FECHA_CIERRE_INVALIDA'),
      (400, 'QR_INVALIDO'),
      (400, 'ASISTENCIA_FUERA_DE_VENTANA'),
      (409, 'ASISTENCIA_COMPLETA'),
    ]) {
      expect(
        clasificarError(ApiError(status, '{"code":"$code"}')),
        ClaseError.negocio,
        reason: code,
      );
    }
  });

  test('ApiException también se clasifica por su código HTTP', () {
    expect(
      clasificarError(ApiException(statusCode: 401, message: 'x')),
      ClaseError.sesionExpirada,
    );
    expect(
      clasificarError(ApiException(statusCode: 502, message: 'x')),
      ClaseError.transitorio,
    );
    expect(
      clasificarError(
        ApiException(
          statusCode: 409,
          message: 'x',
          reason: 'RENOVACION_EN_CURSO',
        ),
      ),
      ClaseError.transitorio,
    );
  });
}
