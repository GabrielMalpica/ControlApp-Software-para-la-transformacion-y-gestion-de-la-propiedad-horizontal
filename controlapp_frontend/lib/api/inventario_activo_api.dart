import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_application_1/model/inventario_activo_model.dart';
import 'package:flutter_application_1/service/api_client.dart';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/session_service.dart';
import 'package:flutter_application_1/service/upload_media_type.dart';
import 'package:flutter_application_1/utils/pickers/selected_upload_file.dart';
import 'package:http/http.dart' as http;

class InventarioActivoApi {
  final ApiClient _client = ApiClient();
  final SessionService _session = SessionService();

  String _segmento(ClaseActivoInventario clase) =>
      clase == ClaseActivoInventario.maquinaria ? 'maquinaria' : 'herramientas';

  Future<Map<String, String>> _authHeaders() async {
    final token = await _session.getToken();
    return {
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Never _throw(http.Response response, String fallback) {
    throw Exception(
      AppError.fromResponseBody(response.body, fallback: fallback),
    );
  }

  Future<ResumenInventarioActivos> resumen({
    required String empresaId,
    String? conjuntoId,
  }) async {
    final path = conjuntoId == null
        ? '/inventario/empresa/$empresaId/resumen'
        : '/inventario/conjunto/$conjuntoId/resumen';
    final response = await _client.get(path);
    if (response.statusCode != 200) {
      _throw(response, 'No se pudo cargar el resumen del inventario.');
    }
    return ResumenInventarioActivos.fromJson(
      (jsonDecode(response.body) as Map).cast<String, dynamic>(),
    );
  }

  Future<List<CatalogoActivo>> catalogo({
    required String empresaId,
    required ClaseActivoInventario clase,
  }) async {
    final response = await _client.get(
      '/inventario/empresa/$empresaId/catalogos/${_segmento(clase)}',
    );
    if (response.statusCode != 200) {
      _throw(response, 'No se pudo cargar el catálogo.');
    }
    return (jsonDecode(response.body) as List)
        .map(
          (item) =>
              CatalogoActivo.fromJson((item as Map).cast<String, dynamic>()),
        )
        .toList();
  }

  Future<PaginaActivos> listar({
    required String empresaId,
    required ClaseActivoInventario clase,
    String? conjuntoId,
    String? busqueda,
    String? aprobacion,
    String? propietario,
    int page = 1,
    int pageSize = 100,
  }) async {
    final base = conjuntoId == null
        ? '/inventario/empresa/$empresaId/${_segmento(clase)}'
        : '/inventario/conjunto/$conjuntoId/${_segmento(clase)}';
    final query = <String, String>{
      'page': page.toString(),
      'pageSize': pageSize.toString(),
      if (busqueda != null && busqueda.trim().isNotEmpty) 'q': busqueda.trim(),
      if (aprobacion != null) 'aprobacion': aprobacion,
      if (propietario != null) 'propietario': propietario,
    };
    final response = await _client.get(
      Uri(path: base, queryParameters: query).toString(),
    );
    if (response.statusCode != 200) {
      _throw(response, 'No se pudo cargar el inventario.');
    }
    final json = (jsonDecode(response.body) as Map).cast<String, dynamic>();
    final data = (json['data'] as List? ?? const [])
        .map(
          (item) => ActivoInventario.fromJson(
            (item as Map).cast<String, dynamic>(),
            clase,
          ),
        )
        .toList();
    return PaginaActivos(
      data: data,
      total: (json['total'] as num?)?.toInt() ?? data.length,
      page: (json['page'] as num?)?.toInt() ?? page,
      pageSize: (json['pageSize'] as num?)?.toInt() ?? pageSize,
    );
  }

  Future<List<ActivoInventario>> crear({
    required String empresaId,
    required ClaseActivoInventario clase,
    required Map<String, dynamic> body,
    String? conjuntoId,
  }) async {
    final path = conjuntoId == null
        ? '/inventario/empresa/$empresaId/${_segmento(clase)}'
        : '/inventario/conjunto/$conjuntoId/${_segmento(clase)}';
    final response = await _client.post(path, body: body);
    if (response.statusCode != 201) {
      _throw(response, 'No se pudo registrar el activo.');
    }
    final decoded = jsonDecode(response.body);
    final raw = clase == ClaseActivoInventario.herramienta
        ? ((decoded as Map)['data'] as List? ?? const [])
        : [decoded];
    return raw
        .map(
          (item) => ActivoInventario.fromJson(
            (item as Map).cast<String, dynamic>(),
            clase,
          ),
        )
        .toList();
  }

  Future<void> editar(
    ClaseActivoInventario clase,
    int id,
    Map<String, dynamic> body,
  ) async {
    final response = await _client.patch(
      '/inventario/${_segmento(clase)}/$id',
      body: body,
    );
    if (response.statusCode != 200) {
      _throw(response, 'No se pudo editar el activo.');
    }
  }

  Future<void> aprobar(ClaseActivoInventario clase, int id) async {
    final response = await _client.post(
      '/inventario/${_segmento(clase)}/$id/aprobar',
      body: const <String, dynamic>{},
    );
    if (response.statusCode != 200) {
      _throw(response, 'No se pudo aprobar el registro.');
    }
  }

  Future<void> aprobarLoteHerramientas(String loteId) async {
    final response = await _client.post(
      '/inventario/herramientas/lotes/$loteId/aprobar',
      body: const <String, dynamic>{},
    );
    if (response.statusCode != 200) {
      _throw(response, 'No se pudo aprobar el lote de herramientas.');
    }
  }

  Future<void> rechazar(
    ClaseActivoInventario clase,
    int id,
    String motivo,
  ) async {
    final response = await _client.post(
      '/inventario/${_segmento(clase)}/$id/rechazar',
      body: {'motivo': motivo},
    );
    if (response.statusCode != 200) {
      _throw(response, 'No se pudo rechazar el registro.');
    }
  }

  Future<void> rechazarLoteHerramientas(String loteId, String motivo) async {
    final response = await _client.post(
      '/inventario/herramientas/lotes/$loteId/rechazar',
      body: {'motivo': motivo},
    );
    if (response.statusCode != 200) {
      _throw(response, 'No se pudo rechazar el lote de herramientas.');
    }
  }

  Future<void> cambiarEstado(
    ClaseActivoInventario clase,
    int id,
    String estado,
    String motivo, {
    String? condicion,
  }) async {
    final response = await _client.post(
      '/inventario/${_segmento(clase)}/$id/estado',
      body: {
        'estado': estado,
        'motivo': motivo,
        if (condicion != null) 'condicion': condicion,
      },
    );
    if (response.statusCode != 200) {
      _throw(response, 'No se pudo actualizar el estado.');
    }
  }

  Future<void> prestar({
    required ClaseActivoInventario clase,
    required int id,
    required String conjuntoId,
    required DateTime fechaDevolucion,
  }) async {
    final response = await _client.post(
      '/inventario/${_segmento(clase)}/$id/prestar',
      body: {
        'conjuntoId': conjuntoId,
        'fechaInicio': DateTime.now().toUtc().toIso8601String(),
        'fechaDevolucionEstimada': fechaDevolucion.toUtc().toIso8601String(),
      },
    );
    if (response.statusCode != 201) {
      _throw(response, 'No se pudo prestar el activo.');
    }
  }

  Future<void> devolver(ClaseActivoInventario clase, int id) async {
    final response = await _client.post(
      '/inventario/${_segmento(clase)}/$id/devolver',
    );
    if (response.statusCode != 200) {
      _throw(response, 'No se pudo registrar la devolución.');
    }
  }

  Future<void> subirFoto(
    ClaseActivoInventario clase,
    int id,
    SelectedUploadFile archivo,
  ) async {
    final uri = Uri.parse(
      '${AppConstants.baseUrl}/inventario/${_segmento(clase)}/$id/foto',
    );
    final request = http.MultipartRequest('PUT', uri)
      ..headers.addAll(await _authHeaders());
    if (kIsWeb || !archivo.hasPath) {
      if (!archivo.hasBytes) {
        throw Exception('La fotografía seleccionada no contiene datos.');
      }
      request.files.add(
        http.MultipartFile.fromBytes(
          'foto',
          archivo.bytes!,
          filename: archivo.name,
          contentType: uploadMediaTypeFromName(
            archivo.name,
            fallbackMimeType: archivo.mimeType,
          ),
        ),
      );
    } else {
      request.files.add(
        await http.MultipartFile.fromPath(
          'foto',
          archivo.path!,
          filename: archivo.name,
          contentType: uploadMediaTypeFromName(
            archivo.name,
            fallbackMimeType: archivo.mimeType,
          ),
        ),
      );
    }
    final response = await http.Response.fromStream(await request.send());
    if (response.statusCode != 200) {
      _throw(response, 'No se pudo subir la fotografía.');
    }
  }

  Future<void> eliminar(ClaseActivoInventario clase, int id) async {
    final response = await _client.delete(
      '/inventario/${_segmento(clase)}/$id',
    );
    if (response.statusCode != 204) {
      _throw(response, 'No se pudo eliminar el activo.');
    }
  }

  Future<void> eliminarFoto(ClaseActivoInventario clase, int id) async {
    final response = await _client.delete(
      '/inventario/${_segmento(clase)}/$id/foto',
    );
    if (response.statusCode != 204) {
      _throw(response, 'No se pudo eliminar la fotografía.');
    }
  }

  Future<Uint8List> foto(ClaseActivoInventario clase, int id) async {
    final response = await http.get(
      Uri.parse(
        '${AppConstants.baseUrl}/inventario/${_segmento(clase)}/$id/foto',
      ),
      headers: await _authHeaders(),
    );
    if (response.statusCode != 200) {
      _throw(response, 'No se pudo cargar la fotografía.');
    }
    return response.bodyBytes;
  }
}
