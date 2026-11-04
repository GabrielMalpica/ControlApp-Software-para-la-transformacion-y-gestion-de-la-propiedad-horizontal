import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/service/actualizacion_app_service.dart';

ManifiestoAndroid _m({int versionCode = 5, int minima = 0}) =>
    ManifiestoAndroid.fromJson(
      {
        'versionCode': versionCode,
        'versionName': '1.$versionCode.0',
        'url': 'controlapp.apk',
        'sha256': 'a' * 64,
        'tamanoBytes': 123,
        'publicadaEn': '2026-11-04T15:00:00Z',
        'minimaVersionCode': minima,
        'notas': 'Mejoras',
      },
      base: Uri.parse(
        'https://controlapp.controlsas.com.co/descargas/android.json',
      ),
    )!;

void main() {
  group('decidirActualizacion', () {
    test('al día: nada', () {
      expect(
        decidirActualizacion(instalada: 5, manifiesto: _m(versionCode: 5)),
        EstadoActualizacion.ninguna,
      );
    });

    test('más nueva publicada: se ofrece', () {
      expect(
        decidirActualizacion(instalada: 4, manifiesto: _m(versionCode: 5)),
        EstadoActualizacion.disponible,
      );
    });

    test('por debajo de la mínima: obligatoria', () {
      expect(
        decidirActualizacion(
          instalada: 3,
          manifiesto: _m(versionCode: 5, minima: 4),
        ),
        EstadoActualizacion.obligatoria,
      );
    });

    test(
      'el servidor respondió 426: obligatoria aunque no haya manifiesto',
      () {
        expect(
          decidirActualizacion(
            instalada: 5,
            manifiesto: null,
            servidorExige: true,
          ),
          EstadoActualizacion.obligatoria,
        );
      },
    );

    test('sin versión instalada o sin manifiesto: nada', () {
      expect(
        decidirActualizacion(instalada: null, manifiesto: _m()),
        EstadoActualizacion.ninguna,
      );
      expect(
        decidirActualizacion(instalada: 2, manifiesto: null),
        EstadoActualizacion.ninguna,
      );
    });
  });

  test('consulta al abrir y luego como mucho cada 30 min', () {
    final t = DateTime(2026, 11, 4, 10);
    expect(debeConsultarActualizacion(ultimaConsulta: null, ahora: t), isTrue);
    expect(
      debeConsultarActualizacion(
        ultimaConsulta: t,
        ahora: t.add(const Duration(minutes: 29)),
      ),
      isFalse,
    );
    expect(
      debeConsultarActualizacion(
        ultimaConsulta: t,
        ahora: t.add(const Duration(minutes: 30)),
      ),
      isTrue,
    );
  });

  group('ManifiestoAndroid', () {
    test('resuelve la URL relativa contra la del manifiesto', () {
      expect(
        _m().url.toString(),
        'https://controlapp.controlsas.com.co/descargas/controlapp.apk',
      );
    });

    test('sin sha256 válido o sin versionCode no sirve', () {
      expect(
        ManifiestoAndroid.fromJson({
          'versionCode': 2,
          'url': 'x.apk',
          'sha256': 'corto',
        }),
        isNull,
      );
      expect(
        ManifiestoAndroid.fromJson({'url': 'x.apk', 'sha256': 'b' * 64}),
        isNull,
      );
      expect(ManifiestoAndroid.fromJson('no'), isNull);
    });
  });
}
