import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
    return {
      'Authorization': 'Bearer $token',
      'x-empresa-id': AppConstants.empresaNit,
      'Accept': 'application/json',
    };
  }

  Future<void> cerrarTareaConEvidencias({
    required int operarioId,
    required int tareaId,
    String? observaciones,
    DateTime? fechaFinalizarTarea,
    List<Map<String, num>> insumosUsados = const [],
    List<String> evidenciaPaths = const [],
  }) async {
    final uri = Uri.parse(
      '${AppConstants.baseUrl}/operario/operarios/$operarioId/tareas/$tareaId/cerrar',
    );

    final req = http.MultipartRequest('POST', uri);
    req.headers.addAll(await _authHeaders());

    if (observaciones != null && observaciones.trim().isNotEmpty) {
      req.fields['observaciones'] = observaciones.trim();
    }
    if (fechaFinalizarTarea != null) {
      req.fields['fechaFinalizarTarea'] = fechaFinalizarTarea.toIso8601String();
    }
    if (insumosUsados.isNotEmpty) {
      req.fields['insumosUsados'] = jsonEncode(insumosUsados);
    }

    for (final path in evidenciaPaths) {
      if (path.trim().isEmpty) continue;

      if (kIsWeb) {
        throw Exception('En web no hay File path. Para web toca XFile/bytes.');
      }

      final file = File(path);
      if (!await file.exists()) continue;

      req.files.add(await http.MultipartFile.fromPath('files', path));
    }

    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      throw Exception('Error cerrando tarea: ${streamed.statusCode} - $body');
    }
  }
}
