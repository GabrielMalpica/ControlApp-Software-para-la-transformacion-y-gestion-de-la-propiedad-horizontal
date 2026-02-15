// lib/api/supervisor_api.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/model/evidencia_adjunto_model.dart';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:flutter_application_1/service/session_service.dart';
import 'package:http/http.dart' as http;

import '../service/api_client.dart';

class SupervisorApi {
  final ApiClient _client = ApiClient();
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
      // OJO: no Content-Type aquí; multipart lo define solo
    };
  }

  /// GET /supervisor/tareas?...
  Future<List<TareaModel>> listarTareas({
    required String conjuntoId,
    String? operarioId,
    String? estado,
    DateTime? desde,
    DateTime? hasta,
    bool? borrador,
  }) async {
    final qp = <String, String>{
      'conjuntoId': conjuntoId,
      if (operarioId != null && operarioId.trim().isNotEmpty)
        'operarioId': operarioId.trim(),
      if (estado != null && estado.trim().isNotEmpty) 'estado': estado.trim(),
      if (desde != null) 'desde': desde.toIso8601String(),
      if (hasta != null) 'hasta': hasta.toIso8601String(),
      if (borrador != null) 'borrador': borrador.toString(),
    };

    final uri = Uri.parse(
      '${AppConstants.supervisorBase}/tareas',
    ).replace(queryParameters: qp);


    final resp = await _client.get(uri.toString());

    if (resp.statusCode != 200) {
      throw Exception(
        'Error listando tareas: ${resp.statusCode} - ${resp.body}',
      );
    }

    final data = jsonDecode(resp.body);
    if (data is! List) return [];

    return data
        .map((e) => TareaModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /supervisor/tareas/:id/cerrar (multipart con fotos + insumos)
  Future<void> cerrarTareaConEvidencias({
    required int tareaId,
    String? observaciones,
    DateTime? fechaFinalizarTarea,
    List<Map<String, num>> insumosUsados = const [],
    List<EvidenciaAdjunto> evidencias = const [],
  }) async {
    final uri = Uri.parse(
      '${AppConstants.supervisorBase}/tareas/$tareaId/cerrar',
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

    for (final evidencia in evidencias) {
      final path = evidencia.path?.trim();
      final bytes = evidencia.bytes;

      if (path != null && path.isNotEmpty) {
        final file = File(path);
        if (await file.exists()) {
          req.files.add(await http.MultipartFile.fromPath('files', path));
          continue;
        }
      }

      if (kIsWeb && bytes != null && bytes.isNotEmpty) {
        req.files.add(
          http.MultipartFile.fromBytes(
            'files',
            bytes,
            filename: evidencia.nombre,
          ),
        );
      }
    }

    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      throw Exception('Error cerrando tarea: ${streamed.statusCode} - $body');
    }
  }

  /// POST /supervisor/tareas/:id/veredicto (json normal)
  Future<void> veredicto(int tareaId, Map<String, dynamic> body) async {
    final resp = await _client.post(
      '${AppConstants.supervisorBase}/tareas/$tareaId/veredicto',
      body: body,
    );

    if (resp.statusCode != 200) {
      throw Exception('Error veredicto: ${resp.statusCode} - ${resp.body}');
    }
  }

  Future<Map<String, dynamic>> cronogramaImprimible({
    required String conjuntoId,
    required String operarioId,
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final uri =
        Uri.parse(
          '${AppConstants.baseUrl}/supervisor/cronograma-imprimible',
        ).replace(
          queryParameters: {
            'conjuntoId': conjuntoId,
            'operarioId': operarioId,
            'desde': desde.toIso8601String(),
            'hasta': hasta.toIso8601String(),
          },
        );

    final resp = await _client.get(uri.toString());
    if (resp.statusCode != 200) {
      throw Exception('Error cronograma: ${resp.statusCode} ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }
}
