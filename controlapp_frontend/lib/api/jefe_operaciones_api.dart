import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/utils/pickers/selected_upload_file.dart';

import '../service/api_client.dart';
import '../service/app_constants.dart';

class JefeOperacionesApi {
  final ApiClient _client = ApiClient();

  Future<List<TareaModel>> listarPendientes({String? conjuntoId}) async {
    final qs = (conjuntoId != null && conjuntoId.trim().isNotEmpty)
        ? '?conjuntoId=${Uri.encodeComponent(conjuntoId.trim())}'
        : '';

    final resp = await _client.get(
      '${AppConstants.jefeOperacionesBase}/tareas/pendientes$qs',
    );

    if (resp.statusCode != 200) {
      throw Exception('Error listando pendientes: ${resp.body}');
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

    throw Exception('Error veredicto: ${resp.statusCode} - ${resp.body}');
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
            contentType: _contentTypeByName(f.name, fallback: f.mimeType),
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
            contentType: _contentTypeByName(f.name, fallback: f.mimeType),
          ),
        );
      } else if (f.hasBytes) {
        req.files.add(
          http.MultipartFile.fromBytes(
            'files',
            f.bytes!,
            filename: f.name,
            contentType: _contentTypeByName(f.name, fallback: f.mimeType),
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

    throw Exception('Error multipart: ${resp.statusCode} - ${resp.body}');
  }

  MediaType? _contentTypeByName(String filename, {String? fallback}) {
    final lower = filename.toLowerCase();

    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return MediaType('image', 'jpeg');
    }
    if (lower.endsWith('.png')) {
      return MediaType('image', 'png');
    }
    if (lower.endsWith('.pdf')) {
      return MediaType('application', 'pdf');
    }

    // fallback: "image/webp", etc
    if (fallback != null && fallback.contains('/')) {
      final parts = fallback.split('/');
      if (parts.length == 2) return MediaType(parts[0], parts[1]);
    }

    return null;
  }
}
