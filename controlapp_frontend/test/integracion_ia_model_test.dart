import 'package:flutter_application_1/model/integracion_ia_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('configuración: URL vacía es null y títulos de permisos', () {
    final config = ConfiguracionIntegracionesIa.fromJson({
      'urlServidor': '  ',
      'habilitadoParaMi': true,
      'permisos': [
        {
          'scope': 'personal:write',
          'titulo': 'Gestionar personal',
          'descripcion': 'x',
          'nivel': 'escritura',
        },
      ],
    });
    expect(config.urlServidor, isNull);
    expect(config.tituloPermiso('personal:write'), 'Gestionar personal');
    expect(config.tituloPermiso('desconocido'), 'desconocido');
    expect(config.permisos.single.modificaDatos, isTrue);
  });

  test('conexión: estado legible y fechas locales', () {
    final c = ConexionIa.fromJson({
      'id': 'c-1',
      'propia': true,
      'gerente': 'Gabriela',
      'cliente': 'Claude',
      'clienteHost': 'claude.ai',
      'permisos': ['conjuntos:read'],
      'estado': 'SUSPENDIDA',
      'ultimoUsoEn': '2026-10-20T15:00:00.000Z',
    });
    expect(c.suspendida, isTrue);
    expect(c.activa, isFalse);
    expect(c.estadoLegible, 'Suspendida por seguridad');
    expect(c.ultimoUsoEn, isNotNull);
    expect(c.autorizadaEn, isNull);
  });

  test('actividad: fallos y nombre legible de la herramienta', () {
    final ok = ActividadIa.fromJson({
      'id': '1',
      'herramienta': 'listar_conjuntos',
      'nivelRiesgo': 'LECTURA',
      'resultado': 'OK',
    });
    final denegada = ActividadIa.fromJson({
      'id': '2',
      'herramienta': 'previsualizar_traslado_operario',
      'nivelRiesgo': 'ESCRITURA',
      'resultado': 'DENEGADO',
    });
    expect(ok.fallo, isFalse);
    expect(denegada.fallo, isTrue);
    expect(denegada.herramientaLegible, 'Previsualizar traslado operario');
  });
}
