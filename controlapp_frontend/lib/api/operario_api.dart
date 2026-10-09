import 'dart:convert';

import 'package:flutter_application_1/api/evidencias_multipart.dart';
import 'package:flutter_application_1/model/evidencia_adjunto_model.dart';
import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:flutter_application_1/service/session_service.dart';
import 'package:http/http.dart' as http;

class OperarioApi {
  final SessionService _session = SessionService();

  Future<Map<String, String>> _authHeaders() async {
    final token = await _session.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('Token requerido (no hay sesión guardada)');
    }
    return {'Authorization': 'Bearer $token', 'Accept': 'application/json'};
  }

  /// Actividades del operario. Con [desde]/[hasta] solo trae ese rango (por
  /// fecha de inicio); sin rango trae todo el historial.
  Future<List<TareaModel>> listarTareasOperario({
    required int operarioId,
    DateTime? desde,
    DateTime? hasta,
  }) async {
    final uri =
        Uri.parse(
          '${AppConstants.baseUrl}/operario/operarios/$operarioId/tareas',
        ).replace(
          queryParameters: {
            if (desde != null) 'desde': desde.toUtc().toIso8601String(),
            if (hasta != null) 'hasta': hasta.toUtc().toIso8601String(),
          },
        );

    final resp = await http.get(uri, headers: await _authHeaders());

    if (resp.statusCode != 200) {
      throw ApiError(resp.statusCode, resp.body);
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! List) return [];

    return decoded
        .map((e) => TareaModel.fromJson((e as Map).cast<String, dynamic>()))
        .where((t) => !t.borrador)
        .toList();
  }

  /// Marca la actividad como iniciada (EN_PROCESO). Solo para actividades
  /// asignadas al operario.
  Future<void> iniciarTarea({
    required int operarioId,
    required int tareaId,
  }) async {
    final uri = Uri.parse(
      '${AppConstants.baseUrl}/operario/operarios/$operarioId/tareas/$tareaId/iniciar',
    );
    final resp = await http
        .post(uri, headers: await _authHeaders())
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200 && resp.statusCode != 204) {
      throw ApiError(resp.statusCode, resp.body);
    }
  }

  Future<void> cerrarTareaConEvidencias({
    required int operarioId,
    required int tareaId,
    String accion = 'COMPLETADA',
    String? observaciones,
    List<Map<String, num>> insumosUsados = const [],
    List<EvidenciaAdjunto> evidencias = const [],
    String? clienteCierreId,
    DateTime? fechaFinalizarTarea,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final token = await _session.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('Token requerido (no hay sesión guardada)');
    }

    final uri = Uri.parse(
      '${AppConstants.baseUrl}/operario/operarios/$operarioId/tareas/$tareaId/cerrar',
    );

    final req = http.MultipartRequest('POST', uri);

    req.headers.addAll({
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    });

    req.fields['accion'] = accion;
    if (clienteCierreId != null && clienteCierreId.trim().isNotEmpty) {
      req.fields['clienteCierreId'] = clienteCierreId.trim();
    }
    if (fechaFinalizarTarea != null) {
      req.fields['fechaFinalizarTarea'] = fechaFinalizarTarea.toIso8601String();
    }

    if (observaciones != null && observaciones.trim().isNotEmpty) {
      req.fields['observaciones'] = observaciones.trim();
    }

    if (insumosUsados.isNotEmpty) {
      req.fields['insumosUsados'] = jsonEncode(insumosUsados);
    }

    await adjuntarEvidencias(req, evidencias);

    final streamed = await req.send().timeout(timeout);
    final body = await streamed.stream.bytesToString().timeout(timeout);

    if (streamed.statusCode != 200) {
      throw ApiError(streamed.statusCode, body);
    }
  }
}

/// Error con el código HTTP real, para poder distinguir en el motor de
/// sincronización offline entre fallas transitorias (red, 5xx) y fallas de
/// negocio (4xx) que no deben reintentarse indefinidamente.
class ApiError implements Exception {
  final int statusCode;
  final String body;
  ApiError(this.statusCode, this.body);

  @override
  String toString() => 'ApiError($statusCode): $body';
}
