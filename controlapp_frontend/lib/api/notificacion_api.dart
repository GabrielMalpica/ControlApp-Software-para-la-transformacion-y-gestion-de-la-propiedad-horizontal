import 'dart:convert';

import 'package:flutter_application_1/model/notificacion_model.dart';
import 'package:flutter_application_1/service/api_client.dart';

class NotificacionApi {
  final ApiClient _client = ApiClient();

  Future<List<NotificacionModel>> listar({
    int limit = 30,
    bool soloNoLeidas = false,
  }) async {
    final resp = await _client.get(
      '/notificaciones?limit=$limit&soloNoLeidas=$soloNoLeidas',
    );

    if (resp.statusCode != 200) {
      throw Exception('Error listando notificaciones: ${resp.body}');
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! List) return [];

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(NotificacionModel.fromJson)
        .toList();
  }

  Future<int> contarNoLeidas() async {
    final resp = await _client.get('/notificaciones/no-leidas/count');
    if (resp.statusCode != 200) {
      throw Exception('Error contando notificaciones: ${resp.body}');
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map<String, dynamic>) return 0;
    final raw = decoded['total'];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  Future<void> marcarLeida(int id) async {
    final resp = await _client.patch('/notificaciones/$id/leida');
    if (resp.statusCode != 200) {
      throw Exception('Error marcando notificacion: ${resp.body}');
    }
  }

  Future<void> marcarTodasLeidas() async {
    final resp = await _client.patch('/notificaciones/leidas');
    if (resp.statusCode != 200) {
      throw Exception('Error marcando notificaciones: ${resp.body}');
    }
  }
}
