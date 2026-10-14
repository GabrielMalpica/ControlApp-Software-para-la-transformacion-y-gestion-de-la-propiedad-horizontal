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
          {'tipo': 'SIN_COBRO_LOCAL', 'referenceCode': 'WC-2', 'detalle': 'y'},
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

  group('trazabilidad del webhook de Factus', () {
    test(
      'el cobro trae como se confirmo, los avisos y el pagador recortado',
      () {
        final item = PagoAdminItem.fromJson(
          _cobro(
            extra: {
              'estado': 'PAGADO',
              'origenConfirmacion': 'WEBHOOK',
              'webhooksRecibidos': 2,
              'webhookPrimeroEn': '2026-10-14T15:00:00.000Z',
              'ultimaVerificacionEn': '2026-10-14T15:00:02.000Z',
              'ultimaVerificacionOrigen': 'WEBHOOK',
              'pagadorNombre': 'Juan Pérez',
              'pagadorTipoDocumento': 'CC',
              'pagadorDocumentoUltimos4': '7890',
              'verificable': false,
            },
          ),
        );
        expect(item.origenConfirmacion, 'WEBHOOK');
        expect(item.webhooksRecibidos, 2);
        expect(item.webhookPrimeroEn, isNotNull);
        expect(item.pagador, 'Juan Pérez · CC ···7890');
        expect(item.verificable, isFalse);
      },
    );

    test('un cobro viejo sin esos campos no falla', () {
      final item = PagoAdminItem.fromJson(_cobro());
      expect(item.webhooksRecibidos, 0);
      expect(item.pagador, isNull);
      expect(item.verificable, isFalse);
    });

    test('el detalle trae las entregas del webhook', () {
      final detalle = PagoAdminDetalle.fromJson(
        _cobro(
          extra: {
            'eventos': [],
            'webhooks': [
              {
                'id': 1,
                'recibidoEn': '2026-10-14T15:00:00.000Z',
                'estado': 'PROCESADO',
                'resultado': 'CONFIRMADO',
                'detalle': 'Factus confirmo el pago por API',
                'montoReportado': 50000,
              },
            ],
          },
        ),
      );
      expect(detalle.webhooks, hasLength(1));
      expect(detalle.webhooks.first.resultado, 'CONFIRMADO');
      expect(webhookResultadoLabel('CONFIRMADO'), 'Confirmó el pago');
      expect(webhookResultadoLabel(null), 'En proceso');
    });

    test(
      'los eventos muestran quien disparo la consulta y la verificacion pedida por el equipo',
      () {
        final evento = PagoAdminEvento.fromJson({
          'tipo': 'ACCION_MANUAL',
          'payload': {
            'accion': 'VERIFICAR_CON_FACTUS',
            'nombre': 'Gerente Uno',
            'origen': 'ADMIN',
          },
        });
        expect(evento.detalle, contains('Gerente Uno'));
        expect(evento.origen, 'ADMIN');
        expect(pagoOrigenLabel('WEBHOOK'), contains('webhook'));
        expect(pagoEventoLabel('WEBHOOK_RECIBIDO'), 'Aviso de Factus recibido');
      },
    );
  });

  group('SaludPagos', () {
    test('modo webhook funcionando', () {
      final salud = SaludPagos.fromJson({
        'modoConfigurado': 'webhook',
        'modoEfectivo': 'webhook',
        'motivo': null,
        'webhookConfigurado': true,
        'ultimoWebhookEn': '2026-10-14T15:00:00.000Z',
        'avisos24h': 3,
        'avisosSinProcesar': 0,
        'confirmados7d': {
          'total': 5,
          'porOrigen': {'WEBHOOK': 4, 'USUARIO': 1},
        },
        'pagosSinWebhook24h': 0,
        'cobrosPendientes': 2,
      });
      expect(salud.usaWebhook, isTrue);
      expect(salud.conNovedades, isFalse);
      expect(salud.confirmados7d, 5);
      expect(salud.confirmadosPorWebhook7d, 4);
    });

    test('modo degradado: el aviso no llega', () {
      final salud = SaludPagos.fromJson({
        'modoConfigurado': 'webhook',
        'modoEfectivo': 'polling',
        'motivo':
            '1 pago(s) de las ultimas 24 h se confirmaron sin que llegara el aviso',
        'webhookConfigurado': true,
        'pagosSinWebhook24h': 1,
      });
      expect(salud.usaWebhook, isFalse);
      expect(salud.conNovedades, isTrue);
      expect(salud.ultimoWebhookEn, isNull);
      expect(salud.confirmados7d, 0);
    });
  });
}
