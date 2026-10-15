import 'package:flutter_application_1/model/pago_admin_models.dart';
import 'package:flutter_application_1/model/saldo_servicio_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SaldoServicio', () {
    test('lee el saldo y su último código de pago', () {
      final saldo = SaldoServicio.fromJson(<String, dynamic>{
        'id': 5,
        'wooOrderId': '2434',
        'estado': 'PENDIENTE',
        'totalOrden': 71000,
        'pagadoAntes': 36000,
        'montoSaldo': 35000,
        'servicios': 'Revisión de daño',
        'servicioTerminadoEn': '2026-10-15T16:46:39.000Z',
        'pedidoAppId': null,
        'cobro': <String, dynamic>{
          'id': 7,
          'canal': 'SALDO_SERVICIO',
          'referenceCode': 'SA-1',
          'estado': 'PENDIENTE',
          'montoEsperado': 35000,
          'moneda': 'COP',
          'qrBase64': 'data:image/png;base64,AAAA',
          'brebKey': '@FC82VAY4K1I0CZ6YU39L',
          'expiraLocalEn': DateTime.now()
              .add(const Duration(hours: 20))
              .toIso8601String(),
          'creadoEn': DateTime.now().toIso8601String(),
        },
      });

      expect(saldo.pendiente, isTrue);
      expect(saldo.montoSaldo, 35000);
      expect(saldo.pagadoAntes + saldo.montoSaldo, saldo.totalOrden);
      expect(saldo.cobro?.brebKey, '@FC82VAY4K1I0CZ6YU39L');
      expect(saldo.tieneCodigoVigente, isTrue);
    });

    test('sin código, o con el código vencido, no hay código vigente', () {
      final sinCodigo = SaldoServicio.fromJson(<String, dynamic>{
        'id': 1,
        'estado': 'PENDIENTE',
        'montoSaldo': 1000,
      });
      expect(sinCodigo.cobro, isNull);
      expect(sinCodigo.tieneCodigoVigente, isFalse);

      final vencido = SaldoServicio.fromJson(<String, dynamic>{
        'id': 1,
        'estado': 'PENDIENTE',
        'cobro': <String, dynamic>{
          'id': 2,
          'estado': 'PENDIENTE',
          'expiraLocalEn': DateTime.now()
              .subtract(const Duration(minutes: 1))
              .toIso8601String(),
        },
      });
      expect(vencido.tieneCodigoVigente, isFalse);
    });

    test('pagado (con Bre-B o por fuera) ya no está pendiente', () {
      for (final estado in <String>['PAGADO', 'PAGADO_POR_FUERA']) {
        final saldo = SaldoServicio.fromJson(<String, dynamic>{
          'id': 1,
          'estado': estado,
        });
        expect(saldo.pendiente, isFalse);
      }
    });
  });

  group('Clientes en mora', () {
    test(
      'lee los datos del cliente, los días en mora y los pedidos en mora',
      () {
        final listado = MoraListado.fromJson(<String, dynamic>{
          'total': 1,
          'resumen': <String, dynamic>{
            'clientesEnMora': 1,
            'montoPendiente': 35000,
          },
          'items': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 1,
              'estado': 'PENDIENTE',
              'canal': 'tienda',
              'wooOrderId': '2434',
              'pedidoAppId': null,
              'documento': null,
              'nombre': 'martin hidalgo',
              'correo': 'martin@correo.com',
              'telefono': '3208262940',
              'direccion': 'carre 6 n 3 58, villavicencio',
              'servicios': 'Revisión de daño',
              'totalOrden': 71000,
              'pagadoAntes': 36000,
              'montoSaldo': 35000,
              'diasEnMora': 3,
              'pedidosEnMora': <Map<String, dynamic>>[
                <String, dynamic>{'wooOrderId': '2500'},
              ],
            },
          ],
        });

        expect(listado.clientesEnMora, 1);
        expect(listado.montoPendiente, 35000);
        final item = listado.items.single;
        expect(item.pendiente, isTrue);
        expect(item.documento, isNull);
        expect(item.telefono, '3208262940');
        expect(item.diasEnMora, 3);
        expect(item.pedidosEnMora, <String>['2500']);
      },
    );
  });

  test('el panel de pagos nombra el canal del saldo de servicio', () {
    PagoAdminItem item(String canal) => PagoAdminItem.fromJson(
      <String, dynamic>{'id': 1, 'canal': canal, 'estado': 'PAGADO'},
    );
    expect(item('SALDO_SERVICIO').canalLabel, 'Saldo de servicio');
    expect(item('WOOCOMMERCE').canalLabel, 'Tienda web');
    expect(item('CONTROLAPP').canalLabel, 'App');
  });
}
