import 'package:flutter_application_1/model/pago_admin_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _cobro({Map<String, dynamic> extra = const {}}) => {
  'id': 5,
  'referenceCode': 'CA-x',
  'canal': 'CONTROLAPP',
  'estado': 'PAGADO_HUERFANO',
  'estadoProveedor': 'paid',
  'montoEsperado': 50000,
  'montoProveedor': 50000,
  'pedidoAppId': 41,
  'wooOrderId': null,
  'conjuntoNombre': 'Conjunto Uno',
  'pagadoDetectadoEn': '2026-09-25T10:00:00.000Z',
  'pendienteSincronizarWoo': false,
  'requiereAccion': true,
  'creadoEn': '2026-09-25T09:30:00.000Z',
  ...extra,
};

void main() {
  group('PagoAdminItem', () {
    test('parsea un cobro que requiere acción', () {
      final item = PagoAdminItem.fromJson(_cobro());
      expect(item.montoEsperado, 50000);
      expect(item.requiereAccion, isTrue);
      expect(item.origen, 'Pedido #41');
      expect(item.esTienda, isFalse);
    });

    test('origen distingue orden web y referencia', () {
      final web = PagoAdminItem.fromJson(
        _cobro(
          extra: {
            'canal': 'WOOCOMMERCE',
            'pedidoAppId': null,
            'wooOrderId': '900',
          },
        ),
      );
      expect(web.origen, 'Orden web #900');
      expect(web.esTienda, isTrue);

      final sinNada = PagoAdminItem.fromJson(
        _cobro(extra: {'pedidoAppId': null, 'wooOrderId': null}),
      );
      expect(sinNada.origen, 'CA-x');
    });
  });

  group('PagoAdminPagina', () {
    test('hayMas se calcula con total, página y tamaño', () {
      PagoAdminPagina pagina(int p, int total) => PagoAdminPagina.fromJson({
        'total': total,
        'pagina': p,
        'porPagina': 25,
        'items': [_cobro()],
      });
      expect(pagina(1, 26).hayMas, isTrue);
      expect(pagina(2, 26).hayMas, isFalse);
      expect(pagina(1, 25).hayMas, isFalse);
    });
  });

  group('PagoAdminEvento', () {
    test('saca el motivo o el error del payload', () {
      final conMotivo = PagoAdminEvento.fromJson({
        'tipo': 'CAMBIO_ESTADO',
        'estadoNuevo': 'PAGADO_HUERFANO',
        'payload': {'motivo': 'el pedido está cancelado'},
        'creadoEn': '2026-09-25T10:00:00.000Z',
      });
      expect(conMotivo.detalle, 'el pedido está cancelado');

      final conError = PagoAdminEvento.fromJson({
        'tipo': 'ERROR',
        'payload': {'error': '429: Too many requests'},
      });
      expect(conError.detalle, '429: Too many requests');

      final sinPayload = PagoAdminEvento.fromJson({'tipo': 'CREADO'});
      expect(sinPayload.detalle, isNull);
    });
  });

  group('ConciliacionReporte', () {
    test('cuenta las anomalías sin corregir', () {
      final reporte = ConciliacionReporte.fromJson({
        'ejecutadaEn': '2026-09-25T10:00:00.000Z',
        'completo': true,
        'remotosPagados': 12,
        'anomalias': [
          {
            'tipo': 'PAGADO_EN_FACTUS_NO_LOCAL',
            'referenceCode': 'CA-1',
            'detalle': 'x',
            'corregida': true,
          },
          {
            'tipo': 'SIN_COBRO_LOCAL',
            'referenceCode': 'WC-2',
            'detalle': 'y',
          },
        ],
      });
      expect(reporte.remotosPagados, 12);
      expect(reporte.anomalias, hasLength(2));
      expect(reporte.sinCorregir, 1);
    });
  });

  test('pagoEstadoLabel traduce los estados', () {
    expect(pagoEstadoLabel('PAGADO_HUERFANO'), 'Pagado sin pedido');
    expect(pagoEstadoLabel('CREADO'), 'Pendiente');
    expect(pagoEstadoLabel('OTRO'), 'OTRO');
  });
}
