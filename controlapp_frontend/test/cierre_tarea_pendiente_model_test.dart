import 'package:flutter_application_1/model/cierre_tarea_pendiente_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('un cierre pendiente sobrevive a un round-trip por JSON (simula guardarlo y releerlo del store)', () {
    final original = CierreTareaPendiente(
      clienteCierreId: 'c1',
      tareaId: 88,
      rol: 'operario',
      usuarioId: '77',
      accion: 'COMPLETADA',
      observaciones: 'Todo listo',
      insumosUsados: [
        {'insumoId': 4, 'cantidad': 2.5},
      ],
      fechaCierreLocal: DateTime.utc(2026, 9, 11, 10, 30),
      evidencias: const [
        EvidenciaPendiente(nombre: 'foto1.jpg', path: '/data/foto1.jpg'),
        EvidenciaPendiente(nombre: 'foto2.jpg', bytesBase64: 'YWJj'),
      ],
      creadoEn: DateTime.utc(2026, 9, 11, 10, 30),
      estadoSync: CierreSyncEstado.pendiente,
      intentos: 2,
      ultimoError: 'Timeout',
      nextAttemptAt: DateTime.utc(2026, 9, 11, 10, 32),
    );

    final reconstruido = CierreTareaPendiente.fromJson(original.toJson());

    expect(reconstruido.clienteCierreId, 'c1');
    expect(reconstruido.tareaId, 88);
    expect(reconstruido.insumosUsados, [{'insumoId': 4, 'cantidad': 2.5}]);
    expect(reconstruido.evidencias.length, 2);
    expect(reconstruido.evidencias[0].path, '/data/foto1.jpg');
    expect(reconstruido.evidencias[1].bytesBase64, 'YWJj');
    expect(reconstruido.estadoSync, CierreSyncEstado.pendiente);
    expect(reconstruido.intentos, 2);
    expect(reconstruido.ultimoError, 'Timeout');
    expect(reconstruido.fechaCierreLocal, original.fechaCierreLocal);
    expect(reconstruido.nextAttemptAt, original.nextAttemptAt);
  });

  test('copyWith limpia nextAttemptAt cuando no se pasa explícitamente', () {
    final base = CierreTareaPendiente(
      clienteCierreId: 'c1',
      tareaId: 1,
      rol: 'operario',
      usuarioId: '1',
      accion: 'COMPLETADA',
      insumosUsados: const [],
      fechaCierreLocal: DateTime.utc(2026, 1, 1),
      evidencias: const [],
      creadoEn: DateTime.utc(2026, 1, 1),
      nextAttemptAt: DateTime.utc(2026, 1, 1, 1),
    );

    final marcadoSincronizando = base.copyWith(
      estadoSync: CierreSyncEstado.sincronizando,
    );

    expect(marcadoSincronizando.nextAttemptAt, isNull);
    expect(marcadoSincronizando.estadoSync, CierreSyncEstado.sincronizando);
  });

  test('copyWith conserva ultimoError salvo que se pida limpiarlo', () {
    final base = CierreTareaPendiente(
      clienteCierreId: 'c1',
      tareaId: 1,
      rol: 'operario',
      usuarioId: '1',
      accion: 'COMPLETADA',
      insumosUsados: const [],
      fechaCierreLocal: DateTime.utc(2026, 1, 1),
      evidencias: const [],
      creadoEn: DateTime.utc(2026, 1, 1),
      ultimoError: 'Timeout',
    );

    expect(base.copyWith(estadoSync: CierreSyncEstado.pendiente).ultimoError, 'Timeout');
    expect(
      base
          .copyWith(estadoSync: CierreSyncEstado.sincronizado, limpiarError: true)
          .ultimoError,
      isNull,
    );
  });
}
