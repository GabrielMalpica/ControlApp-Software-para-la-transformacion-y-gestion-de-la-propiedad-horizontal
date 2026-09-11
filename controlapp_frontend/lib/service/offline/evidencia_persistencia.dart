// Copia las evidencias elegidas por el operario a un lugar persistente
// para que sobrevivan hasta que se pueda sincronizar el cierre.
//
// En mobile/desktop se copian a un directorio propio de la app (el path
// que entrega la cámara/picker es temporal). En web no hay filesystem
// persistente, así que los bytes se guardan directamente en el store.
export 'evidencia_persistencia_io.dart'
    if (dart.library.html) 'evidencia_persistencia_web.dart';
