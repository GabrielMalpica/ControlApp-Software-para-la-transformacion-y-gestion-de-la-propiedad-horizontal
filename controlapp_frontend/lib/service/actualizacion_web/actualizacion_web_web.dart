import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Puente con las funciones que define `web/flutter_bootstrap.js` al cargar
/// la app (ver docs/actualizacion-web.md).
class ActualizacionWeb {
  /// true si se publicó otra versión desde que se abrió esta pestaña.
  static Future<bool> hayVersionNueva() async {
    // Una pestaña abierta antes de este cambio no tiene la función.
    if (!globalContext.has('controlappHayVersionNueva')) return false;
    try {
      final nueva = await globalContext
          .callMethod<JSPromise<JSBoolean>>('controlappHayVersionNueva'.toJS)
          .toDart;
      return nueva.toDart;
    } catch (_) {
      return false;
    }
  }

  /// Fecha de publicación (Last-Modified de main.dart.js) de la versión que
  /// se está usando, tal como la guardó el arranque al abrir la app.
  static String? fechaVersion() {
    final valor = globalContext.getProperty<JSAny?>(
      'controlappFechaVersionWeb'.toJS,
    );
    return valor.isA<JSString>() ? (valor as JSString).toDart : null;
  }

  /// Baja de nuevo lo que no cambia de nombre entre versiones y recarga.
  static Future<void> actualizar() async {
    if (globalContext.has('controlappActualizar')) {
      await globalContext
          .callMethod<JSPromise<JSAny?>>('controlappActualizar'.toJS)
          .toDart;
      return;
    }
    globalContext
        .getProperty<JSObject>('location'.toJS)
        .callMethod<JSAny?>('reload'.toJS);
  }
}
