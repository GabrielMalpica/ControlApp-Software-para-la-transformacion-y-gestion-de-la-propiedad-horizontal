// lib/api/tarea_api.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/model/evidencia_adjunto_model.dart';
import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:http/http.dart' as http;

import '../service/api_client.dart';
import '../service/app_constants.dart';
import '../service/session_service.dart';
import '../service/upload_media_type.dart';

class TareaRequest {
  final String descripcion;
  final DateTime fechaInicio;
  final DateTime fechaFin;

  /// Duración en minutos (SIEMPRE minutos)
  final int duracionMinutos;

  /// 🔹 NUEVO
  final int prioridad;
  final String tipo;

  final int ubicacionId;
  final int elementoId;
  final String conjuntoId;

  final String? supervisorId;
  final List<String> operariosIds;
  final String? observaciones;
  final List<int> maquinariaIds;
  final List<Map<String, dynamic>> herramientas;

  TareaRequest({
    required this.descripcion,
    required this.fechaInicio,
    required this.fechaFin,
    required this.duracionMinutos,
    this.prioridad = 2,
    this.tipo = "CORRECTIVA", // por defecto en esta pantalla
    required this.ubicacionId,
    required this.elementoId,
    required this.conjuntoId,
    this.supervisorId,
    this.operariosIds = const [],
    this.observaciones,
    this.maquinariaIds = const [],
    this.herramientas = const [],
  });

  Map<String, dynamic> toJson() => {
    'descripcion': descripcion,
    'fechaInicio': fechaInicio.toUtc().toIso8601String(),
    'fechaFin': fechaFin.toUtc().toIso8601String(),
    'duracionMinutos': duracionMinutos,

    /// 🔹 NUEVO
    'prioridad': prioridad,
    'tipo': tipo,

    'ubicacionId': ubicacionId,
    'elementoId': elementoId,
    'conjuntoId': conjuntoId,
    if (supervisorId != null) 'supervisorId': supervisorId,
    if (operariosIds.isNotEmpty) 'operariosIds': operariosIds,
    if (observaciones != null && observaciones!.trim().isNotEmpty)
      'observaciones': observaciones,
    'maquinariaIds': maquinariaIds,
    'herramientas': herramientas,
  };
}

class TareaApi {
  final ApiClient _client = ApiClient();
  final SessionService _session = SessionService();

  Future<Map<String, String>> _authHeaders() async {
    final token = await _session.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('Token requerido (no hay sesiÃ³n guardada)');
    }
    return {
      'Authorization': 'Bearer $token',
      'x-empresa-id': AppConstants.empresaNit,
      'Accept': 'application/json',
    };
  }

  Future<Map<String, dynamic>> crearTarea(TareaRequest req) async {
    final resp = await _client.post(
      '${AppConstants.gerenteBase}/tareas',
      body: req.toJson(),
    );

    Map<String, dynamic> data = {};
    if (resp.body.isNotEmpty) {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    }

    // ✅ Si el backend manda needsReplacement, lo devolvemos tal cual
    if (data['needsReplacement'] == true) return data;

    // ✅ Si el backend manda ok:true/false, lo devolvemos tal cual (sin lanzar exception)
    if (data.containsKey('ok')) return data;

    // ✅ Si el backend devuelve la tarea creada directa (sin ok), también sirve
    if (resp.statusCode == 201) return data;

    // ❌ Solo aquí es error “duro” (500, no JSON, etc.)
    throw Exception('Error HTTP ${resp.statusCode}: ${resp.body}');
  }

  Future<void> editarTarea(int id, TareaRequest req) async {
    final resp = await _client.patch(
      '${AppConstants.gerenteBase}/tareas/$id',
      body: req.toJson(),
    );

    if (resp.statusCode != 200) {
      throw Exception('Error al editar tarea: ${resp.body}');
    }
  }

  Future<void> eliminarTarea(int id) async {
    final resp = await _client.delete('${AppConstants.gerenteBase}/tareas/$id');

    if (resp.statusCode != 204 && resp.statusCode != 200) {
      throw Exception('Error al eliminar tarea: ${resp.body}');
    }
  }

  Future<List<TareaModel>> listarTareasPorConjunto(String conjuntoId) async {
    final resp = await _client.get(
      '${AppConstants.gerenteBase}/conjuntos/$conjuntoId/tareas',
    );

    if (resp.statusCode != 200) {
      throw Exception('Error al listar tareas: ${resp.body}');
    }

    final List<dynamic> data = jsonDecode(resp.body);
    return data
        .map((e) => TareaModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> crearTareaConReemplazo({
    required TareaRequest tarea,
    required List<int> reemplazarIds,
    String? motivoReemplazo,
    String? accionReemplazadas, // REPROGRAMAR | CANCELAR
    List<Map<String, dynamic>> reprogramaciones = const [],
  }) async {
    final resp = await _client.post(
      '${AppConstants.gerenteBase}/tareas/reemplazo',
      body: {
        'tarea': tarea.toJson(),
        'reemplazarIds': reemplazarIds,
        if (accionReemplazadas != null && accionReemplazadas.trim().isNotEmpty)
          'accionReemplazadas': accionReemplazadas.trim(),
        if (motivoReemplazo != null && motivoReemplazo.trim().isNotEmpty)
          'motivoReemplazo': motivoReemplazo.trim(),
        if (reprogramaciones.isNotEmpty) 'reprogramaciones': reprogramaciones,
      },
    );

    Map<String, dynamic> data = {};
    if (resp.body.isNotEmpty) {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    }

    if (data.containsKey('ok')) return data;
    if (resp.statusCode == 200 || resp.statusCode == 201) return data;
    if (resp.statusCode == 400 && data.isNotEmpty) return data;

    throw Exception(
      'Error al crear con reemplazo: ${resp.statusCode} - ${resp.body}',
    );
  }

  Future<void> cerrarTareaConEvidencias({
    required int tareaId,
    String? observaciones,
    DateTime? fechaFinalizarTarea,
    List<Map<String, num>> insumosUsados = const [],
    List<EvidenciaAdjunto> evidencias = const [],
  }) async {
    final uri = Uri.parse('${AppConstants.supervisorBase}/tareas/$tareaId/cerrar');

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
      final fileName = evidencia.nombre.trim().isNotEmpty
          ? evidencia.nombre.trim()
          : (path?.split(RegExp(r'[\\/]')).last ?? 'evidencia.jpg');
      final contentType = uploadMediaTypeFromName(fileName);

      if (path != null && path.isNotEmpty) {
        final file = File(path);
        if (await file.exists()) {
          req.files.add(
            await http.MultipartFile.fromPath(
              'files',
              path,
              filename: fileName,
              contentType: contentType,
            ),
          );
          continue;
        }
      }

      if (kIsWeb && bytes != null && bytes.isNotEmpty) {
        req.files.add(
          http.MultipartFile.fromBytes(
            'files',
            bytes,
            filename: fileName,
            contentType: contentType,
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
}
