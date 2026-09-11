import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

Future<Database> openOfflineDatabase() async {
  final dir = await getApplicationDocumentsDirectory();
  final path = p.join(dir.path, 'controlapp_offline.db');
  return databaseFactoryIo.openDatabase(path);
}

/// Directorio persistente propio de la app donde se copian las evidencias
/// de cierres pendientes (el path que entrega el picker/cámara es temporal
/// y puede ser purgado por el sistema operativo).
Future<String> directorioEvidenciasPendientes(String clienteCierreId) async {
  final dir = await getApplicationDocumentsDirectory();
  return p.join(dir.path, 'cierres_pendientes', clienteCierreId);
}
