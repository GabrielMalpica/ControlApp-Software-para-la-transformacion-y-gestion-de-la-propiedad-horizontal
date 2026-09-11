// Abre la base de datos local usada para la cola de cierres offline.
//
// Misma API de sembast en todas las plataformas; solo cambia el
// `DatabaseFactory` (archivo en disco en mobile/desktop, IndexedDB en web).
export 'sembast_factory_io.dart' if (dart.library.html) 'sembast_factory_web.dart';
