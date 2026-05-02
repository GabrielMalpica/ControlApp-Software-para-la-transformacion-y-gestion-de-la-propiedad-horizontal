import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter_application_1/model/evidencia_adjunto_model.dart';
import 'package:http/http.dart' as http;

import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/utils/pickers/selected_upload_file.dart';

import '../service/api_client.dart';
import '../service/app_error.dart';
import '../service/app_constants.dart';
import '../service/session_service.dart';
import '../service/upload_media_type.dart';

class JefeOperacionesApi {
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

  Future<List<TareaModel>> listarPendientes({String? conjuntoId}) async {
    final qs = (conjuntoId != null && conjuntoId.trim().isNotEmpty)
        ? '?conjuntoId=${Uri.encodeComponent(conjuntoId.trim())}'
        : '';

    final resp = await _client.get(
      '${AppConstants.jefeOperacionesBase}/tareas/pendientes$qs',
    );

    if (resp.statusCode != 200) {
      throw Exception(
        AppError.fromResponseBody(
          resp.body,
          fallback: 'No se pudieron listar las tareas pendientes.',
        ),
      );
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is List) {
      return decoded
          .map((e) => TareaModel.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    }

    // Si tu backend devuelve {ok:true,data:[...]}
    if (decoded is Map && decoded['data'] is List) {
      final list = decoded['data'] as List;
      return list
          .map((e) => TareaModel.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    }

    throw Exception('Respuesta inválida: ${resp.body}');
  }

  Future<void> cerrarTareaConEvidencias({
    required int tareaId,
    String accion = 'COMPLETADA',
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
    req.fields['accion'] = accion;

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
      throw Exception(
        AppError.fromResponseBody(
          body,
          fallback: 'No se pudo cerrar la tarea.',
        ),
      );
    }
  }

  Future<Map<String, dynamic>> veredicto({
    required int tareaId,
    required String accion,
    String? observacionesRechazo,
    DateTime? fechaVerificacion,
  }) async {
    final body = <String, dynamic>{
      'accion': accion,
      if (observacionesRechazo != null &&
          observacionesRechazo.trim().isNotEmpty)
        'observacionesRechazo': observacionesRechazo.trim(),
      if (fechaVerificacion != null)
        'fechaVerificacion': fechaVerificacion.toIso8601String(),
    };

    final resp = await _client.post(
      '${AppConstants.jefeOperacionesBase}/tareas/$tareaId/veredicto',
      body: body,
    );

    Map<String, dynamic> data = {};
    if (resp.body.isNotEmpty) {
      final d = jsonDecode(resp.body);
      if (d is Map<String, dynamic>) data = d;
    }

    if (resp.statusCode == 200) return data;
    if (data.containsKey('ok')) return data;

    throw Exception(
      AppError.fromResponseBody(
        resp.body,
        fallback: 'No se pudo registrar el veredicto.',
      ),
    );
  }

  /// ✅ Multipart que sirve en WEB + MOBILE + PC
  Future<Map<String, dynamic>> veredictoConEvidencias({
    required int tareaId,
    required String accion,
    String? observacionesRechazo,
    DateTime? fechaVerificacion,
    List<SelectedUploadFile> archivos = const [],
  }) async {
    final url =
        '${AppConstants.jefeOperacionesBase}/tareas/$tareaId/veredicto-multipart';

    final uri = Uri.parse(url);
    final req = http.MultipartRequest('POST', uri);

    // ✅ Copia headers de tu ApiClient si usas token
    // (ajusta esto a tu ApiClient real)
    // req.headers.addAll(_client.defaultHeaders);

    req.fields['accion'] = accion;
    if (observacionesRechazo != null &&
        observacionesRechazo.trim().isNotEmpty) {
      req.fields['observacionesRechazo'] = observacionesRechazo.trim();
    }
    if (fechaVerificacion != null) {
      req.fields['fechaVerificacion'] = fechaVerificacion.toIso8601String();
    }

    for (final f in archivos) {
      // WEB: siempre bytes
      if (kIsWeb) {
        if (!f.hasBytes) {
          throw Exception('En Web el archivo "${f.name}" debe traer bytes.');
        }
        req.files.add(
          http.MultipartFile.fromBytes(
            'files',
            f.bytes!,
            filename: f.name,
            contentType: uploadMediaTypeFromName(
              f.name,
              fallbackMimeType: f.mimeType,
            ),
          ),
        );
        continue;
      }

      // IO: preferir path
      if (f.hasPath) {
        req.files.add(
          await http.MultipartFile.fromPath(
            'files',
            f.path!,
            filename: f.name,
            contentType: uploadMediaTypeFromName(
              f.name,
              fallbackMimeType: f.mimeType,
            ),
          ),
        );
      } else if (f.hasBytes) {
        req.files.add(
          http.MultipartFile.fromBytes(
            'files',
            f.bytes!,
            filename: f.name,
            contentType: uploadMediaTypeFromName(
              f.name,
              fallbackMimeType: f.mimeType,
            ),
          ),
        );
      } else {
        throw Exception('El archivo "${f.name}" no tiene path ni bytes.');
      }
    }

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);

    Map<String, dynamic> data = {};
    if (resp.body.isNotEmpty) {
      final d = jsonDecode(resp.body);
      if (d is Map<String, dynamic>) data = d;
    }

    if (resp.statusCode == 200) return data;
    if (data.containsKey('ok')) return data;

    throw Exception(
      AppError.fromResponseBody(
        resp.body,
        fallback: 'No se pudo registrar el veredicto.',
      ),
    );
  }
}
