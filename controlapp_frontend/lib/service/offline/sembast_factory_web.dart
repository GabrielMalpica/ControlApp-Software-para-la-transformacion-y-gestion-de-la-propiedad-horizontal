import 'package:sembast_web/sembast_web.dart';

Future<Database> openOfflineDatabase() async {
  return databaseFactoryWeb.openDatabase('controlapp_offline.db');
}

/// En web no hay filesystem persistente accesible: las evidencias se
/// guardan como bytes dentro del propio store (ver [EvidenciaPersistencia]),
/// así que esta función no aplica. Se deja por simetría con la variante io.
Future<String> directorioEvidenciasPendientes(String clienteCierreId) async {
  throw UnsupportedError(
    'directorioEvidenciasPendientes no aplica en web: las evidencias se '
    'guardan como bytes en el store.',
  );
}
