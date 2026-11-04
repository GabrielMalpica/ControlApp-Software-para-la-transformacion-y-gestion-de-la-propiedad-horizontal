import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sembast/sembast.dart';

import '../../model/asistencia_pendiente_model.dart';
import '../../model/cierre_tarea_pendiente_model.dart';
import 'evidencia_persistencia.dart';
import 'sembast_factory_provider.dart';

/// Envoltorio de una lectura cacheada (tareas del operario, inventario del
/// conjunto) con la fecha en la que se obtuvo, para poder avisar al
/// operario que está viendo datos desactualizados mientras está offline.
class LecturaCacheada {
  final List<Map<String, dynamic>> datos;
  final DateTime actualizadoEn;

  /// ETag de la respuesta que se guardó: se manda en `If-None-Match` y, si el
  /// servidor responde 304, se usa esta copia.
  final String? etag;

  const LecturaCacheada({
    required this.datos,
    required this.actualizadoEn,
    this.etag,
  });
}

/// Persistencia local para la cola de cierres de tarea y de asistencias
/// pendientes de sincronizar, más una caché de solo-lectura de
/// tareas/inventario para que el operario pueda seguir trabajando sin
/// conexión.
///
/// Un único store (no hay variantes io/web): usa sembast en mobile/desktop
/// y sembast_web (IndexedDB) en navegador a través de [openOfflineDatabase].
///
/// La base la abre también el proceso de segundo plano (WorkManager): la app
/// la cierra al irse a segundo plano ([cerrar]) y la vuelve a abrir al
/// volver, para leer lo que ese proceso haya enviado.
class CierreTareaOfflineStore {
  CierreTareaOfflineStore._(this._abrir);

  static final CierreTareaOfflineStore instance = CierreTareaOfflineStore._(
    openOfflineDatabase,
  );

  /// Store sobre una base dada (sembast en memoria en las pruebas).
  @visibleForTesting
  factory CierreTareaOfflineStore.conBase(Database db) =>
      CierreTareaOfflineStore._(() async => db);

  final Future<Database> Function() _abrir;

  static final _cierresStore = StoreRef<String, Map<String, dynamic>>(
    'cierres_pendientes',
  );
  static final _asistenciasStore = StoreRef<String, Map<String, dynamic>>(
    'asistencias_pendientes',
  );
  static final _cacheStore = StoreRef<String, Map<String, dynamic>>(
    'cache_lecturas',
  );

  Future<Database>? _db;

  Future<Database> _database() {
    return _db ??= _abrir().catchError((Object e) {
      _db = null;
      throw e;
    });
  }

  /// Cierra la base (se reabre sola en el próximo uso).
  Future<void> cerrar() async {
    final abierta = _db;
    _db = null;
    if (abierta == null) return;
    try {
      await (await abierta).close();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------
  // Cierres de tarea
  // ---------------------------------------------------------------------

  Future<void> guardarCierre(CierreTareaPendiente cierre) async {
    final db = await _database();
    await _cierresStore.record(cierre.clienteCierreId).put(db, cierre.toJson());
  }

  Future<void> actualizarCierre(CierreTareaPendiente cierre) =>
      guardarCierre(cierre);

  Future<void> eliminarCierre(String clienteCierreId) async {
    final db = await _database();
    await _cierresStore.record(clienteCierreId).delete(db);
    await EvidenciaPersistencia.eliminar(clienteCierreId);
  }

  /// Todos los cierres guardados localmente para un usuario, más recientes
  /// al final. Incluye los ya sincronizados (hasta que se purguen) para que
  /// la UI pueda mostrar una confirmación breve.
  Future<List<CierreTareaPendiente>> listarCierres({
    required String usuarioId,
  }) async {
    final db = await _database();
    final finder = Finder(
      filter: Filter.equals('usuarioId', usuarioId),
      sortOrders: [SortOrder('creadoEn')],
    );
    final records = await _cierresStore.find(db, finder: finder);
    return records.map((r) => CierreTareaPendiente.fromJson(r.value)).toList();
  }

  /// Purga cierres y asistencias ya sincronizados con más de [antiguedad]
  /// desde que se confirmaron, para no dejar crecer el store
  /// indefinidamente. Los rechazados NUNCA se purgan: solo el operario los
  /// descarta.
  Future<void> purgarSincronizados({
    Duration antiguedad = const Duration(hours: 24),
  }) async {
    final db = await _database();
    final limite = DateTime.now().subtract(antiguedad);
    final finder = Finder(
      filter: Filter.equals('estadoSync', CierreSyncEstado.sincronizado.name),
    );
    final records = await _cierresStore.find(db, finder: finder);
    for (final r in records) {
      final cierre = CierreTareaPendiente.fromJson(r.value);
      final marcaTiempo = cierre.sincronizadoEn ?? cierre.creadoEn;
      if (marcaTiempo.isBefore(limite)) {
        await eliminarCierre(cierre.clienteCierreId);
      }
    }
    final asistencias = await _asistenciasStore.find(db, finder: finder);
    for (final r in asistencias) {
      final a = AsistenciaPendiente.fromJson(r.value);
      final marcaTiempo = a.sincronizadoEn ?? a.creadoEn;
      if (marcaTiempo.isBefore(limite)) {
        await _asistenciasStore.record(r.key).delete(db);
      }
    }
  }

  // ---------------------------------------------------------------------
  // Asistencias por QR
  // ---------------------------------------------------------------------

  Future<void> guardarAsistencia(AsistenciaPendiente asistencia) async {
    final db = await _database();
    await _asistenciasStore
        .record(asistencia.clienteRegistroId)
        .put(db, asistencia.toJson());
  }

  Future<void> actualizarAsistencia(AsistenciaPendiente asistencia) =>
      guardarAsistencia(asistencia);

  Future<void> eliminarAsistencia(String clienteRegistroId) async {
    final db = await _database();
    await _asistenciasStore.record(clienteRegistroId).delete(db);
  }

  /// Asistencias guardadas de un usuario, en orden de escaneo.
  Future<List<AsistenciaPendiente>> listarAsistencias({
    required String usuarioId,
  }) async {
    final db = await _database();
    final finder = Finder(
      filter: Filter.equals('usuarioId', usuarioId),
      sortOrders: [SortOrder('creadoEn')],
    );
    final records = await _asistenciasStore.find(db, finder: finder);
    return records.map((r) => AsistenciaPendiente.fromJson(r.value)).toList();
  }

  /// Pendientes (sin enviar o rechazados) de un usuario: cierres +
  /// asistencias. Para avisar antes de cerrar sesión.
  Future<int> contarSinEnviar({required String usuarioId}) async {
    final cierres = await listarCierres(usuarioId: usuarioId);
    final asistencias = await listarAsistencias(usuarioId: usuarioId);
    return cierres
            .where((c) => c.estadoSync != CierreSyncEstado.sincronizado)
            .length +
        asistencias
            .where((a) => a.estadoSync != CierreSyncEstado.sincronizado)
            .length;
  }

  // ---------------------------------------------------------------------
  // Caché de lecturas
  // ---------------------------------------------------------------------

  Future<void> cachearLectura(
    String clave,
    List<Map<String, dynamic>> datos, {
    String? etag,
  }) async {
    final db = await _database();
    await _cacheStore.record(clave).put(db, {
      'datos': datos,
      'actualizadoEn': DateTime.now().toIso8601String(),
      if (etag != null && etag.isNotEmpty) 'etag': etag,
    });
  }

  /// El servidor confirmó (304) que la copia sigue vigente.
  Future<void> marcarLecturaVigente(String clave) async {
    final db = await _database();
    final record = await _cacheStore.record(clave).get(db);
    if (record == null) return;
    await _cacheStore.record(clave).put(db, {
      ...record,
      'actualizadoEn': DateTime.now().toIso8601String(),
    });
  }

  Future<LecturaCacheada?> obtenerLecturaCacheada(String clave) async {
    final db = await _database();
    final record = await _cacheStore.record(clave).get(db);
    if (record == null) return null;

    final datos = ((record['datos'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    return LecturaCacheada(
      datos: datos,
      actualizadoEn: DateTime.parse(record['actualizadoEn']),
      etag: record['etag'] as String?,
    );
  }

  static String claveTareasOperario(String usuarioId) => 'tareas:$usuarioId';
  static String claveInventarioConjunto(String conjuntoNit) =>
      'inventario:$conjuntoNit';
}
