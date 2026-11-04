import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_application_1/service/http/cliente_http_app.dart';
import 'package:flutter_application_1/service/session_service.dart';

void main() {
  test(
    'agrega la versión, renueva ante un 401 y repite con el token nuevo',
    () async {
      final vistos = <http.Request>[];
      var renovaciones = 0;
      DateTime? hora;
      final cliente = ClienteHttpApp(
        MockClient((req) async {
          vistos.add(req);
          if (req.headers['Authorization'] == 'Bearer viejo') {
            return http.Response('{"message":"vencido"}', 401);
          }
          return http.Response(
            '{"ok":true}',
            200,
            headers: {'date': 'Wed, 04 Nov 2026 15:00:00 GMT'},
          );
        }),
        renovar: () async {
          renovaciones++;
          return ResultadoRenovacion.renovada;
        },
        tokenActual: () async => 'nuevo',
        cabecerasVersion: () async => {
          'X-App-Version': '2',
          'X-App-Plataforma': 'android',
        },
        alHoraServidor: (h) => hora = h,
        alAppDesactualizada: () {},
        alEstadoRed: (_) {},
      );

      final resp = await cliente.post(
        Uri.parse('https://api.test/asistencia/checkin'),
        headers: {'Authorization': 'Bearer viejo'},
        body: '{"a":1}',
      );

      expect(resp.statusCode, 200);
      expect(renovaciones, 1);
      expect(vistos, hasLength(2));
      expect(vistos.last.headers['Authorization'], 'Bearer nuevo');
      expect(vistos.last.body, '{"a":1}');
      expect(vistos.first.headers['X-App-Version'], '2');
      expect(vistos.first.headers['X-App-Plataforma'], 'android');
      expect(hora, DateTime.utc(2026, 11, 4, 15));
    },
  );

  test(
    'un 401 del login no se renueva (son credenciales, no un token vencido)',
    () async {
      var renovaciones = 0;
      final cliente = ClienteHttpApp(
        MockClient((_) async => http.Response('{"message":"mal"}', 401)),
        renovar: () async {
          renovaciones++;
          return ResultadoRenovacion.renovada;
        },
        tokenActual: () async => 'x',
        cabecerasVersion: () async => const {},
        alHoraServidor: (_) {},
        alAppDesactualizada: () {},
        alEstadoRed: (_) {},
      );
      final resp = await cliente.post(Uri.parse('https://api.test/auth/login'));
      expect(resp.statusCode, 401);
      expect(renovaciones, 0);
    },
  );

  test(
    '426 APP_DESACTUALIZADA avisa y devuelve la respuesta intacta',
    () async {
      var avisos = 0;
      final cliente = ClienteHttpApp(
        MockClient(
          (_) async => http.Response('{"code":"APP_DESACTUALIZADA"}', 426),
        ),
        renovar: () async => ResultadoRenovacion.invalida,
        tokenActual: () async => null,
        cabecerasVersion: () async => const {},
        alHoraServidor: (_) {},
        alAppDesactualizada: () => avisos++,
        alEstadoRed: (_) {},
      );
      final resp = await cliente.get(Uri.parse('https://api.test/tarea'));
      expect(resp.statusCode, 426);
      expect(resp.body, contains('APP_DESACTUALIZADA'));
      expect(avisos, 1);
    },
  );

  test('informa si hubo respuesta o falla de red', () async {
    final estados = <bool>[];
    final cliente = ClienteHttpApp(
      MockClient((req) async {
        if (req.url.path == '/caido') throw http.ClientException('sin red');
        return http.Response('ok', 200);
      }),
      renovar: () async => ResultadoRenovacion.sinRed,
      tokenActual: () async => null,
      cabecerasVersion: () async => const {},
      alHoraServidor: (_) {},
      alAppDesactualizada: () {},
      alEstadoRed: estados.add,
    );
    await expectLater(
      cliente.get(Uri.parse('https://api.test/caido')),
      throwsA(isA<http.ClientException>()),
    );
    await cliente.get(Uri.parse('https://api.test/ping'));
    expect(estados, [false, true]);
  });
}
