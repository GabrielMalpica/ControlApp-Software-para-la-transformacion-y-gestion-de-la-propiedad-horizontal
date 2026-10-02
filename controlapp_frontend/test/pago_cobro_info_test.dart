import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/model/commerce_lifecycle_models.dart';

void main() {
  group('PagoCobroInfo - cobro de Factus Pay', () {
    test('fromJson parsea un cobro pendiente con QR', () {
      final pago = PagoCobroInfo.fromJson({
        'id': 7,
        'canal': 'CONTROLAPP',
        'referenceCode': 'CA-abc123',
        'estado': 'PENDIENTE',
        'estadoProveedor': 'ready',
        'montoEsperado': 50000,
        'moneda': 'COP',
        'qrBase64': 'data:image/png;base64,${base64Encode([1, 2, 3])}',
        'expiraLocalEn': '2026-09-25T18:00:00.000Z',
        'creadoEn': '2026-09-25T17:30:00.000Z',
        'actualizadoEn': '2026-09-25T17:30:05.000Z',
      });

      expect(pago.id, 7);
      expect(pago.referenceCode, 'CA-abc123');
      expect(pago.montoEsperado, 50000);
      expect(pago.tieneQr, isTrue);
      expect(pago.qrBytes, [1, 2, 3]);
      expect(pago.estaActivo, isTrue);
      expect(pago.estaPagado, isFalse);
      expect(pago.fallo, isFalse);
    });

    test('estaPagado y estaActivo distinguen los estados del cobro', () {
      PagoCobroInfo conEstado(String estado) => PagoCobroInfo.fromJson({
        'id': 1,
        'canal': 'CONTROLAPP',
        'referenceCode': 'CA-x',
        'estado': estado,
        'estadoProveedor': null,
        'montoEsperado': 10000,
        'moneda': 'COP',
        'qrBase64': null,
        'expiraLocalEn': null,
        'creadoEn': null,
        'actualizadoEn': null,
      });

      expect(conEstado('PAGADO').estaPagado, isTrue);
      expect(conEstado('PAGADO').estaActivo, isFalse);
      expect(conEstado('CREADO').estaActivo, isTrue);
      expect(conEstado('PENDIENTE').estaActivo, isTrue);
      expect(conEstado('VENCIDO').estaActivo, isTrue);
      expect(conEstado('VENCIDO').vencidoLocal, isTrue);
      expect(conEstado('FALLIDO').fallo, isTrue);
      expect(conEstado('ERROR').fallo, isTrue);
      expect(conEstado('PAGADO_HUERFANO').estaActivo, isFalse);
      expect(conEstado('PAGADO_HUERFANO').fallo, isFalse);
    });

    test('vencidoLocal tambien se cumple cuando expiraLocalEn ya pasó, sin importar el estado', () {
      final pago = PagoCobroInfo.fromJson({
        'id': 1,
        'canal': 'CONTROLAPP',
        'referenceCode': 'CA-x',
        'estado': 'PENDIENTE',
        'estadoProveedor': 'ready',
        'montoEsperado': 10000,
        'moneda': 'COP',
        'qrBase64': null,
        'expiraLocalEn': '2000-01-01T00:00:00.000Z',
        'creadoEn': null,
        'actualizadoEn': null,
      });

      expect(pago.vencidoLocal, isTrue);
    });

    test('qrBytes decodifica tanto con prefijo data URI como sin él', () {
      final crudo = base64Encode([9, 9, 9]);
      final conPrefijo = PagoCobroInfo.fromJson({
        'id': 1,
        'canal': 'CONTROLAPP',
        'referenceCode': 'CA-x',
        'estado': 'PENDIENTE',
        'estadoProveedor': 'ready',
        'montoEsperado': 10000,
        'moneda': 'COP',
        'qrBase64': 'data:image/png;base64,$crudo',
        'expiraLocalEn': null,
        'creadoEn': null,
        'actualizadoEn': null,
      });
      final sinPrefijo = PagoCobroInfo.fromJson({
        'id': 1,
        'canal': 'CONTROLAPP',
        'referenceCode': 'CA-x',
        'estado': 'PENDIENTE',
        'estadoProveedor': 'ready',
        'montoEsperado': 10000,
        'moneda': 'COP',
        'qrBase64': crudo,
        'expiraLocalEn': null,
        'creadoEn': null,
        'actualizadoEn': null,
      });

      expect(conPrefijo.qrBytes, [9, 9, 9]);
      expect(sinPrefijo.qrBytes, [9, 9, 9]);
    });

    test('sin qrBase64, qrBytes y tieneQr quedan en null/false sin lanzar', () {
      final pago = PagoCobroInfo.fromJson({
        'id': 1,
        'canal': 'CONTROLAPP',
        'referenceCode': 'CA-x',
        'estado': 'CREADO',
        'estadoProveedor': null,
        'montoEsperado': 10000,
        'moneda': 'COP',
        'qrBase64': null,
        'expiraLocalEn': null,
        'creadoEn': null,
        'actualizadoEn': null,
      });

      expect(pago.qrBytes, isNull);
      expect(pago.tieneQr, isFalse);
    });

    test('un base64 invalido no lanza: qrBytes devuelve null', () {
      final pago = PagoCobroInfo.fromJson({
        'id': 1,
        'canal': 'CONTROLAPP',
        'referenceCode': 'CA-x',
        'estado': 'PENDIENTE',
        'estadoProveedor': 'ready',
        'montoEsperado': 10000,
        'moneda': 'COP',
        'qrBase64': 'esto-no-es-base64-valido!!',
        'expiraLocalEn': null,
        'creadoEn': null,
        'actualizadoEn': null,
      });

      expect(pago.qrBytes, isNull);
    });
  });
}
