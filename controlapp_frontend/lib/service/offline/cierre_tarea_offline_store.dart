import 'package:sembast/sembast.dart';

import '../../model/cierre_tarea_pendiente_model.dart';
import 'evidencia_persistencia.dart';
import 'sembast_factory_provider.dart';

/// Envoltorio de una lectura cacheada (tareas del operario, inventario del
/// conjunto) con la fecha en la que se obtuvo, para poder avisar al
/// operario que está viendo datos desactualizados mientras está offline.
class LecturaCacheada {
  final List<Map<String, dynamic>> datos;
  final DateTime actualizadoEn;

  const LecturaCacheada({required this.datos, required this.actualizadoEn});
}

/// Persistencia local para la cola de cierres de tarea pendientes de
/// sincronizar, más una caché de solo-lectura de tareas/inventario para
/// que el operario pueda seguir trabajando sin conexión.
///
/// Un único store (no hay variantes io/web): usa sembast en mobile/desktop
/// y sembast_web (IndexedDB) en navegador a través de [openOfflineDatabase].
class CierreTareaOfflineStore {
  CierreTareaOfflineStore._();
  static final CierreTareaOfflineStore instance = CierreTareaOfflineStore._();

  static final _cierresStore = StoreRef<String, Map<String, dynamic>>(
    'cierres_pendientes',
  );
  static final _cacheStore = StoreRef<String, Map<String, dynamic>>(
    'cache_lecturas',
  );

  Database? _db;

  Future<Database> _database() async {
    return _db ??= await openOfflineDatabase();
  }

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
    return records
        .map((r) => CierreTareaPendiente.fromJson(r.value))
        .toList();
  }

  /// Purga cierres ya sincronizados con más de [antiguedad] desde que se
  /// confirmaron, para no dejar crecer el store indefinidamente.
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
  }

  Future<void> cachearLectura(String clave, List<Map<String, dynamic>> datos) async {
    final db = await _database();
    await _cacheStore.record(clave).put(db, {
      'datos': datos,
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
    );
  }

  static String claveTareasOperario(String usuarioId) => 'tareas:$usuarioId';
  static String claveInventarioConjunto(String conjuntoNit) =>
      'inventario:$conjuntoNit';
}
