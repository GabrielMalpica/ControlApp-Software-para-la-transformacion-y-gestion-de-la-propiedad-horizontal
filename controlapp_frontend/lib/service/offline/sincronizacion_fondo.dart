// Envío de la cola sin señal con la app cerrada (WorkManager de Android).
// En web no hay segundo plano: la cola se envía mientras la página esté
// abierta.
export 'sincronizacion_fondo_io.dart'
    if (dart.library.js_interop) 'sincronizacion_fondo_web.dart';
