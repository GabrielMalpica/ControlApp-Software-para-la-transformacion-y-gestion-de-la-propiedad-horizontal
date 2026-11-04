/// En web no hay WorkManager: todo queda en manos de la página abierta.
class SincronizacionFondo {
  SincronizacionFondo._();

  static Future<void> inicializar() async {}

  static Future<void> programar() async {}

  static Future<void> cancelarRespaldo() async {}

  /// En web nunca hay otro proceso enviando.
  static Future<bool> otroProcesoEnviando() async => false;

  static Future<void> marcarPrimerPlano(bool activo) async {}
}
