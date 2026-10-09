import 'package:flutter_application_1/service/api_client.dart';

class EvidenciaApi {
  EvidenciaApi({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  /// Puntos ya pedidos en esta sesión (~11 m): fotos del mismo sitio no
  /// repiten la consulta.
  static final Set<String> _yaPedidas = {};

  /// Le pide al backend la dirección de donde se tomó una foto apenas se
  /// toma, en segundo plano. El backend la deja en caché y así, al cerrar la
  /// tarea, la marca de agua no tiene que esperar al servicio de mapas. Es
  /// de mejor esfuerzo: cualquier falla se ignora.
  Future<void> precalentarDireccion(double latitud, double longitud) async {
    final clave =
        '${latitud.toStringAsFixed(4)},${longitud.toStringAsFixed(4)}';
    if (!_yaPedidas.add(clave)) return;
    try {
      final resp = await _client
          .get(
            '/evidencias/direccion?lat=${latitud.toStringAsFixed(6)}'
            '&lng=${longitud.toStringAsFixed(6)}',
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) _yaPedidas.remove(clave);
    } catch (_) {
      _yaPedidas.remove(clave);
    }
  }
}
