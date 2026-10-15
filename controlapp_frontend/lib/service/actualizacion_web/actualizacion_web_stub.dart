/// Fuera del navegador la app se actualiza por la tienda: nada que revisar.
class ActualizacionWeb {
  static Future<bool> hayVersionNueva() async => false;

  static Future<void> actualizar() async {}

  static String? fechaVersion() => null;
}
