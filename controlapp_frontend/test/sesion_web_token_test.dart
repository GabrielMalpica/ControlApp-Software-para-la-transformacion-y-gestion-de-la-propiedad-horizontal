import 'dart:convert';

import 'package:flutter_application_1/service/session_service.dart';
import 'package:flutter_test/flutter_test.dart';

String _jwtCon(Map<String, dynamic> payload) {
  String parte(Map<String, dynamic> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${parte({'alg': 'HS256', 'typ': 'JWT'})}.${parte(payload)}.firma';
}

void main() {
  group('expiracionDeToken', () {
    test('lee el exp del JWT (base64url sin relleno)', () {
      final exp = DateTime.utc(2030, 1, 2, 3, 4, 5);
      final token = _jwtCon({
        'sub': 'u-1',
        'exp': exp.millisecondsSinceEpoch ~/ 1000,
      });

      expect(SessionService.expiracionDeToken(token)?.toUtc(), exp);
    });

    test('devuelve null si el token no es un JWT legible', () {
      expect(SessionService.expiracionDeToken('no-es-jwt'), isNull);
      expect(SessionService.expiracionDeToken('a.b.c'), isNull);
      expect(SessionService.expiracionDeToken(_jwtCon({'sub': 'x'})), isNull);
    });
  });
}
