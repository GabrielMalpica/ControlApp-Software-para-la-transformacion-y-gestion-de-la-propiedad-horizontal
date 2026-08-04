import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_application_1/model/residente_admin_models.dart';
import 'package:flutter_application_1/service/api_client.dart';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/session_service.dart';
import 'package:http/http.dart' as http;

class ResidentesApi {
  final ApiClient _client = ApiClient();
  final SessionService _session = SessionService();

  Future<Map<String, String>> _authHeaders() async {
    final token = await _session.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('Token requerido');
    }

    return {
      'Authorization': 'Bearer $token',
      'x-empresa-id': AppConstants.empresaNit,
      'Accept': 'application/json',
    };
  }

  Future<ResidenteCreado> crearResidenteManual({
    required String conjuntoId,
    required String cedula,
    required String nombre,
    required String correo,
    String? telefono,
    required String tipoUnidad,
    String? sector,
    required String unidad,
  }) async {
    final resp = await _client.post(
      '${AppConstants.gerenteBase}/residentes',
      body: {
        'conjuntoId': conjuntoId,
        'cedula': cedula.trim(),
        'nombre': nombre.trim(),
        'correo': correo.trim().toLowerCase(),
        'telefono': telefono?.trim(),
        'tipoUnidad': tipoUnidad,
        'sector': sector?.trim(),
        'unidad': unidad.trim(),
      },
    );

    if (resp.statusCode != 201 && resp.statusCode != 200) {
      throw Exception(
        AppError.fromResponseBody(
          resp.body,
          fallback: 'No se pudo crear el residente.',
        ),
      );
    }

    return ResidenteCreado.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  Future<CargaResidentesResult> cargarResidentesMasivo({
    required String conjuntoId,
    required PlatformFile file,
  }) async {
    final uri = Uri.parse('${AppConstants.gerenteBase}/residentes/carga-masiva');
    final req = http.MultipartRequest('POST', uri);
    req.headers.addAll(await _authHeaders());
    req.fields['conjuntoId'] = conjuntoId;

    final filename = file.name.trim().isEmpty ? 'residentes.xlsx' : file.name.trim();

    if (kIsWeb) {
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw Exception('No se pudo leer el archivo seleccionado.');
      }
      req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    } else {
      final path = file.path;
      if (path == null || path.trim().isEmpty) {
        throw Exception('No se pudo leer la ruta del archivo seleccionado.');
      }
      req.files.add(await http.MultipartFile.fromPath('file', path, filename: filename));
    }

    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 201 && streamed.statusCode != 200) {
      throw Exception(
        AppError.fromResponseBody(
          body,
          fallback: 'No se pudo cargar el archivo de residentes.',
        ),
      );
    }

    return CargaResidentesResult.fromJson(
      jsonDecode(body) as Map<String, dynamic>,
    );
  }

  Future<List<ResidenteAdminItem>> listarResidentes({
    required String conjuntoId,
    String? query,
  }) async {
    final qs = StringBuffer('?conjuntoId=${Uri.encodeQueryComponent(conjuntoId)}');
    if (query != null && query.trim().isNotEmpty) {
      qs.write('&q=${Uri.encodeQueryComponent(query.trim())}');
    }
    final resp = await _client.get('${AppConstants.gerenteBase}/residentes$qs');

    if (resp.statusCode != 200) {
      throw Exception(
        AppError.fromResponseBody(
          resp.body,
          fallback: 'No se pudieron listar los residentes.',
        ),
      );
    }

    final data = jsonDecode(resp.body) as List<dynamic>;
    return data
        .whereType<Map<String, dynamic>>()
        .map(ResidenteAdminItem.fromJson)
        .toList();
  }

  Future<ResidenteAdminItem> editarResidente({
    required String residenteId,
    required String conjuntoId,
    required String nombre,
    required String correo,
    String? telefono,
    required bool activo,
    required String tipoUnidad,
    String? sector,
    required String unidad,
  }) async {
    final resp = await _client.put(
      '${AppConstants.gerenteBase}/residentes/$residenteId',
      body: {
        'conjuntoId': conjuntoId,
        'nombre': nombre.trim(),
        'correo': correo.trim().toLowerCase(),
        'telefono': telefono?.trim(),
        'activo': activo,
        'tipoUnidad': tipoUnidad,
        'sector': sector?.trim(),
        'unidad': unidad.trim(),
      },
    );

    if (resp.statusCode != 200) {
      throw Exception(
        AppError.fromResponseBody(
          resp.body,
          fallback: 'No se pudo actualizar el residente.',
        ),
      );
    }

    return ResidenteAdminItem.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  Future<void> eliminarResidente({
    required String residenteId,
    required String conjuntoId,
  }) async {
    final resp = await _client.delete(
      '${AppConstants.gerenteBase}/residentes/$residenteId?conjuntoId=${Uri.encodeQueryComponent(conjuntoId)}',
    );

    if (resp.statusCode != 200) {
      throw Exception(
        AppError.fromResponseBody(
          resp.body,
          fallback: 'No se pudo eliminar el residente.',
        ),
      );
    }
  }
}
