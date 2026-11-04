import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/service/reloj_confiable.dart';

class _AlmacenMemoria implements AlmacenReloj {
  ReferenciaReloj? guardada;
  int escrituras = 0;

  @override
  Future<ReferenciaReloj?> leer() async => guardada;

  @override
  Future<void> guardar(ReferenciaReloj referencia) async {
    guardada = referencia;
    escrituras++;
  }
}

void main() {
  final servidor = DateTime.utc(2026, 11, 4, 15, 0, 0);

  group('estimar', () {
    test('hora del servidor + lo que pasó según el reloj monotónico', () {
      final ref = ReferenciaReloj(horaServidor: servidor, elapsedMs: 1000);
      expect(
        RelojConfiable.estimar(referencia: ref, elapsedActual: 1000 + 90000),
        servidor.add(const Duration(seconds: 90)),
      );
    });

    test('si el celular se reinició (elapsed menor) no se estima', () {
      final ref = ReferenciaReloj(horaServidor: servidor, elapsedMs: 500000);
      expect(
        RelojConfiable.estimar(referencia: ref, elapsedActual: 1200),
        isNull,
      );
    });

    test('sin referencia o sin reloj monotónico no se estima', () {
      expect(
        RelojConfiable.estimar(referencia: null, elapsedActual: 5),
        isNull,
      );
      expect(
        RelojConfiable.estimar(
          referencia: ReferenciaReloj(horaServidor: servidor, elapsedMs: 1),
          elapsedActual: null,
        ),
        isNull,
      );
    });
  });

  test('la cabecera Date de HTTP se lee en UTC', () {
    expect(
      RelojConfiable.horaDeCabeceraDate('Wed, 04 Nov 2026 15:00:00 GMT'),
      servidor,
    );
    expect(RelojConfiable.horaDeCabeceraDate('no es fecha'), isNull);
    expect(RelojConfiable.horaDeCabeceraDate(null), isNull);
  });

  test(
    'registra, guarda la referencia y estima aunque cambie la hora del celular',
    () async {
      var elapsed = 10000;
      final almacen = _AlmacenMemoria();
      final reloj = RelojConfiable(
        leerElapsed: () async => elapsed,
        almacen: almacen,
      );

      expect(await reloj.estimarAhora(), isNull);
      await reloj.registrarHoraServidor(servidor);
      expect(almacen.guardada?.elapsedMs, 10000);

      elapsed += 5 * 60 * 1000;
      expect(
        await reloj.estimarAhora(),
        servidor.add(const Duration(minutes: 5)),
      );

      // Otra instancia (la app se reabrió sin reiniciar el celular) usa lo
      // guardado.
      final otra = RelojConfiable(
        leerElapsed: () async => elapsed,
        almacen: almacen,
      );
      expect(
        await otra.estimarAhora(),
        servidor.add(const Duration(minutes: 5)),
      );

      // Celular reiniciado: el reloj monotónico volvió a empezar.
      elapsed = 3000;
      final reiniciado = RelojConfiable(
        leerElapsed: () async => elapsed,
        almacen: almacen,
      );
      expect(await reiniciado.estimarAhora(), isNull);
    },
  );

  test('no reescribe la referencia en cada respuesta', () async {
    final almacen = _AlmacenMemoria();
    final reloj = RelojConfiable(leerElapsed: () async => 1, almacen: almacen);
    await reloj.registrarHoraServidor(servidor);
    await reloj.registrarHoraServidor(servidor.add(const Duration(seconds: 1)));
    expect(almacen.escrituras, 1);
  });

  test('sin canal (web o segundo plano) no registra ni estima', () async {
    final almacen = _AlmacenMemoria();
    final reloj = RelojConfiable(
      leerElapsed: () async => null,
      almacen: almacen,
    );
    await reloj.registrarHoraServidor(servidor);
    expect(almacen.guardada, isNull);
    expect(await reloj.estimarAhora(), isNull);
  });
}
