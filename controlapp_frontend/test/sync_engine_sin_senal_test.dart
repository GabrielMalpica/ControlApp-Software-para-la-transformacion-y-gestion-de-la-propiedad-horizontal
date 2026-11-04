import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

import 'package:flutter_application_1/api/operario_api.dart';
import 'package:flutter_application_1/model/asistencia_model.dart';
import 'package:flutter_application_1/model/asistencia_pendiente_model.dart';
import 'package:flutter_application_1/model/cierre_tarea_pendiente_model.dart';
import 'package:flutter_application_1/model/evidencia_adjunto_model.dart';
import 'package:flutter_application_1/service/offline/cierre_tarea_offline_store.dart';
import 'package:flutter_application_1/service/offline/tarea_sync_engine.dart';
import 'package:flutter_application_1/service/session_service.dart';

/// Servidor falso: cada envío consume la siguiente respuesta programada
/// (una excepción o null = éxito) y deja registro de lo que se envió.
class _ServidorFalso implements TransporteSync {
  final List<String> llamadas = [];
  final Map<String, List<Object?>> respuestas = {};
  final List<ResultadoRenovacion> renovaciones = [];
  bool cierreYaProcesado = false;

  Object? _siguiente(String clave) {
    final cola = respuestas[clave];
    if (cola == null || cola.isEmpty) return null;
    return cola.removeAt(0);
  }

  @override
  Future<bool> enviarCierre(
    CierreTareaPendiente cierre,
    List<EvidenciaAdjunto> evidencias,
  ) async {
    llamadas.add('cierre:${cierre.tareaId}');
    final r = _siguiente('cierre:${cierre.tareaId}');
    if (r != null) throw r;
    return false;
  }

  @override
  Future<EstadoCierreRemoto> consultarCierre(
    int operarioId,
    String clienteCierreId,
  ) async {
    llamadas.add('consulta:$clienteCierreId');
    return EstadoCierreRemoto(procesado: cierreYaProcesado);
  }

  @override
  Future<AsistenciaCheckinResultado> enviarAsistencia(
    AsistenciaPendiente a,
  ) async {
    llamadas.add('asistencia:${a.clienteRegistroId}');
    final r = _siguiente('asistencia:${a.clienteRegistroId}');
    if (r != null) throw r;
    return AsistenciaCheckinResultado.fromJson({
      'tipo': 'ENTRADA',
      'conjuntoNombre': 'Conjunto Prueba',
      'registro': {'id': 1, 'conceptoId': 1},
    });
  }

  @override
  Future<ResultadoRenovacion> renovarSesion() async {
    llamadas.add('renovar');
    return renovaciones.isEmpty
        ? ResultadoRenovacion.invalida
        : renovaciones.removeAt(0);
  }
}

ApiError _error(int status, String code, String message) =>
    ApiError(status, jsonEncode({'code': code, 'message': message}));

void main() {
  const uid = '7';
  late CierreTareaOfflineStore store;
  late _ServidorFalso servidor;
  late TareaSyncEngine engine;
  var ahora = DateTime(2026, 11, 4, 10);

  CierreTareaPendiente cierre(
    int tareaId, {
    int minuto = 0,
    int intentos = 0,
  }) => CierreTareaPendiente(
    clienteCierreId: 'c-$tareaId',
    tareaId: tareaId,
    rol: 'operario',
    usuarioId: uid,
    accion: 'COMPLETADA',
    insumosUsados: const [],
    fechaCierreLocal: DateTime(2026, 11, 4, 8, minuto),
    evidencias: const [],
    creadoEn: DateTime(2026, 11, 4, 8, minuto),
    intentos: intentos,
  );

  AsistenciaPendiente asistencia(String id, {int minuto = 0}) =>
      AsistenciaPendiente(
        clienteRegistroId: id,
        usuarioId: uid,
        rol: 'operario',
        conjuntoId: '900',
        qrPayload: 'CTRLAPP-ASISTENCIA|900|x',
        latitud: 4.1,
        longitud: -73.6,
        registradaEn: DateTime.utc(2026, 11, 4, 12, minuto),
        creadoEn: DateTime(2026, 11, 4, 7, minuto),
      );

  setUp(() async {
    final db = await newDatabaseFactoryMemory().openDatabase('cola.db');
    store = CierreTareaOfflineStore.conBase(db);
    servidor = _ServidorFalso();
    ahora = DateTime(2026, 11, 4, 10);
    engine = TareaSyncEngine.paraPruebas(
      store: store,
      transporte: servidor,
      usuarioId: uid,
      ahora: () => ahora,
    );
  });

  tearDown(() {
    engine.pausarTemporizador();
    TareaSyncEngine.alAppDesactualizada = null;
  });

  test('envía primero las asistencias y luego los cierres, en orden', () async {
    await store.guardarCierre(cierre(2, minuto: 5));
    await store.guardarCierre(cierre(1, minuto: 1));
    await store.guardarAsistencia(asistencia('salida', minuto: 30));
    await store.guardarAsistencia(asistencia('entrada', minuto: 0));

    final r = await engine.sincronizarAhora();

    expect(servidor.llamadas, [
      'asistencia:entrada',
      'asistencia:salida',
      'cierre:1',
      'cierre:2',
    ]);
    expect(r.enviados, 4);
    final cierres = await store.listarCierres(usuarioId: uid);
    expect(
      cierres.every((c) => c.estadoSync == CierreSyncEstado.sincronizado),
      isTrue,
    );
    final asistencias = await store.listarAsistencias(usuarioId: uid);
    expect(asistencias.first.tipoRegistrado, 'ENTRADA');
  });

  test('401: renueva la sesión una vez y repite el envío', () async {
    await store.guardarCierre(cierre(1));
    servidor.respuestas['cierre:1'] = [ApiError(401, '{"message":"vencido"}')];
    servidor.renovaciones.add(ResultadoRenovacion.renovada);

    final r = await engine.sincronizarAhora();

    expect(servidor.llamadas, ['cierre:1', 'renovar', 'cierre:1']);
    expect(r.enviados, 1);
    expect(engine.sesionExpirada, isFalse);
  });

  test('401 sin sesión renovable: pausa la cola y no pierde nada', () async {
    await store.guardarCierre(cierre(1));
    await store.guardarCierre(cierre(2, minuto: 2));
    servidor.respuestas['cierre:1'] = [ApiError(401, '{}')];

    final r = await engine.sincronizarAhora();

    expect(r.sesionExpirada, isTrue);
    expect(servidor.llamadas, ['cierre:1', 'renovar']);
    final cierres = await store.listarCierres(usuarioId: uid);
    expect(cierres, hasLength(2));
    expect(cierres.first.estadoSync, CierreSyncEstado.pendiente);
    expect(cierres.first.ultimoError, contains('Inicia sesión'));

    // Tras volver a entrar, sigue sola.
    engine.notificarSesionRestaurada();
    await engine.sincronizarAhora();
    final despues = await store.listarCierres(usuarioId: uid);
    expect(
      despues.every((c) => c.estadoSync == CierreSyncEstado.sincronizado),
      isTrue,
    );
  });

  test('426: pide actualizar la app y conserva la cola', () async {
    var avisos = 0;
    TareaSyncEngine.alAppDesactualizada = () => avisos++;
    await store.guardarAsistencia(asistencia('entrada'));
    await store.guardarCierre(cierre(1));
    servidor.respuestas['asistencia:entrada'] = [
      _error(426, 'APP_DESACTUALIZADA', 'Actualiza la app'),
    ];

    final r = await engine.sincronizarAhora();

    expect(r.appDesactualizada, isTrue);
    expect(avisos, 1);
    expect(servidor.llamadas, ['asistencia:entrada']);
    final asistencias = await store.listarAsistencias(usuarioId: uid);
    expect(asistencias.single.estadoSync, CierreSyncEstado.pendiente);
    expect(await store.listarCierres(usuarioId: uid), hasLength(1));
  });

  test(
    'rechazo de negocio: queda con el motivo del servidor y no se reintenta solo',
    () async {
      await store.guardarCierre(cierre(1));
      servidor.respuestas['cierre:1'] = [
        _error(409, 'TAREA_YA_CERRADA', 'La cerró Ana a las 9:10.'),
      ];

      final r = await engine.sincronizarAhora();
      expect(r.rechazados, 1);
      var c = (await store.listarCierres(usuarioId: uid)).single;
      expect(c.estadoSync, CierreSyncEstado.error);
      expect(c.ultimoError, 'La cerró Ana a las 9:10.');

      servidor.llamadas.clear();
      await engine.sincronizarAhora(ignorarEspera: true);
      expect(servidor.llamadas, isEmpty);
      c = (await store.listarCierres(usuarioId: uid)).single;
      expect(
        c.estadoSync,
        CierreSyncEstado.error,
        reason: 'nunca se descarta solo',
      );
    },
  );

  test(
    'asistencia rechazada guarda el code y no frena las siguientes',
    () async {
      await store.guardarAsistencia(asistencia('a1', minuto: 0));
      await store.guardarAsistencia(asistencia('a2', minuto: 5));
      servidor.respuestas['asistencia:a1'] = [
        _error(400, 'QR_INVALIDO', 'El QR fue regenerado.'),
      ];

      await engine.sincronizarAhora();

      final lista = await store.listarAsistencias(usuarioId: uid);
      expect(lista.first.estadoSync, CierreSyncEstado.error);
      expect(lista.first.codigoError, 'QR_INVALIDO');
      expect(lista.last.estadoSync, CierreSyncEstado.sincronizado);
    },
  );

  test('sin red: backoff, y antes de reenviar pregunta si ya entró', () async {
    await store.guardarCierre(cierre(1));
    servidor.respuestas['cierre:1'] = [TimeoutException('sin respuesta')];

    final r = await engine.sincronizarAhora();
    expect(r.pendientes, 1);
    var c = (await store.listarCierres(usuarioId: uid)).single;
    expect(c.estadoSync, CierreSyncEstado.pendiente);
    expect(c.intentos, 1);
    expect(c.nextAttemptAt, ahora.add(const Duration(seconds: 30)));

    // Antes del backoff no se reintenta (salvo que vuelva la señal).
    servidor.llamadas.clear();
    await engine.sincronizarAhora();
    expect(servidor.llamadas, isEmpty);

    // La respuesta se había perdido pero el servidor sí lo registró: no se
    // vuelven a subir las fotos.
    servidor.cierreYaProcesado = true;
    await engine.sincronizarAhora(ignorarEspera: true);
    expect(servidor.llamadas, ['consulta:c-1']);
    c = (await store.listarCierres(usuarioId: uid)).single;
    expect(c.estadoSync, CierreSyncEstado.sincronizado);
  });

  test('una asistencia esperando reintento frena las posteriores', () async {
    await store.guardarAsistencia(asistencia('entrada', minuto: 0));
    await store.guardarAsistencia(asistencia('salida', minuto: 30));
    servidor.respuestas['asistencia:entrada'] = [
      TimeoutException('sin respuesta'),
    ];

    await engine.sincronizarAhora();

    expect(servidor.llamadas, ['asistencia:entrada']);
    final lista = await store.listarAsistencias(usuarioId: uid);
    expect(lista.last.estadoSync, CierreSyncEstado.pendiente);
    expect(lista.last.intentos, 0);
  });
}
