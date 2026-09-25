import 'package:flutter_application_1/model/commerce_lifecycle_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _pedido({Object? verificacion}) => <String, dynamic>{
  'id': 6,
  'tipo': 'CONJUNTO',
  'estado': 'PENDIENTE_PAGO',
  'estadoWoo': 'pending',
  'wooOrderId': '2395',
  'total': 374500,
  'comprobanteUrl': 'https://drive.google.com/file/d/abc/view',
  'verificacionComprobante': verificacion,
};

void main() {
  group('CommerceOrderDetail.verificacionComprobante', () {
    test('interpreta la lectura automática del comprobante', () {
      final order = CommerceOrderDetail.fromJson(
        _pedido(
          verificacion: <String, dynamic>{
            'veredicto': 'REVISAR',
            'montoDetectado': 10000,
            'referencia': 'M1122334',
            'analizadoEn': '2026-09-24T16:00:00.000Z',
            'checks': <Map<String, dynamic>>[
              <String, dynamic>{
                'clave': 'monto',
                'ok': false,
                'detalle': 'El comprobante dice \$10.000',
              },
              <String, dynamic>{
                'clave': 'destino',
                'ok': null,
                'detalle': 'No configurado',
              },
            ],
          },
        ),
      );

      final v = order.verificacionComprobante!;
      expect(v.veredicto, 'REVISAR');
      expect(v.montoDetectado, 10000);
      expect(v.referencia, 'M1122334');
      expect(v.checks.map((c) => c.ok), <bool?>[false, null]);
      expect(v.analizadoEn, isNotNull);
    });

    test(
      'es null para quien no revisa pagos (residente) o si aún no hay lectura',
      () {
        expect(
          CommerceOrderDetail.fromJson(_pedido()).verificacionComprobante,
          isNull,
        );
      },
    );
  });
}
