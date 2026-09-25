import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_application_1/model/commerce_lifecycle_models.dart';
import 'package:flutter_application_1/service/api_client.dart';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/session_service.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// http.MultipartFile no adivina el content-type por la extension -sin
/// esto manda "application/octet-stream" para cualquier archivo, y el
/// backend (multer fileFilter) lo rechaza aunque sea un PDF/JPG/PNG valido.
MediaType? _mediaTypeForFilename(String filename) {
  final ext = filename.toLowerCase().split('.').lastOrNull;
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return MediaType('image', 'jpeg');
    case 'png':
      return MediaType('image', 'png');
    case 'pdf':
      return MediaType('application', 'pdf');
    default:
      return null;
  }
}

class CommerceLifecycleApi {
  final ApiClient _client = ApiClient();
  final SessionService _session = SessionService();

  Future<CommerceOrderDetail> obtenerPedido(int pedidoId) async {
    final response = await _client.get(
      '${AppConstants.commerceBase}/pedidos/$pedidoId',
    );
    _ensureSuccess(response.statusCode, response.body);
    return CommerceOrderDetail.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// [recepcion]: al recibir un pedido de conjunto, lo que llegó incompleto o
  /// no llegó (`itemId`, `cantidadRecibida`, `nota`). Vacío = llegó completo.
  Future<CommerceOrderDetail> cambiarEstado(
    int pedidoId,
    String estadoDestino, {
    List<Map<String, dynamic>>? recepcion,
  }) async {
    final response = await _client.post(
      '${AppConstants.commerceBase}/pedidos/$pedidoId/estado',
      body: {
        'estadoDestino': estadoDestino,
        if (recepcion != null && recepcion.isNotEmpty) 'recepcion': recepcion,
      },
    );
    _ensureSuccess(response.statusCode, response.body);
    return CommerceOrderDetail.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<ReceiptPreview> vistaPreviaRecepcion(int pedidoId) async {
    final response = await _client.get(
      '${AppConstants.commerceBase}/pedidos/$pedidoId/recepcion-preview',
    );
    _ensureSuccess(response.statusCode, response.body);
    return ReceiptPreview.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<ReceiptPreview> mapearItem({
    required int pedidoId,
    required int itemId,
    required int insumoId,
    double? factorConversion,
  }) async {
    final response = await _client.post(
      '${AppConstants.commerceBase}/pedidos/$pedidoId/items/$itemId/mapeo',
      body: {
        'insumoId': insumoId,
        if (factorConversion != null) 'factorConversion': factorConversion,
      },
    );
    _ensureSuccess(response.statusCode, response.body);
    return ReceiptPreview.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<CommerceOrderDetail> subirComprobante({
    required int pedidoId,
    required PlatformFile file,
    String? metodoPago,
  }) async {
    final token = await _session.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('Token requerido');
    }
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${AppConstants.commerceBase}/pedidos/$pedidoId/comprobante'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    if (metodoPago != null) request.fields['metodoPago'] = metodoPago;

    final filename = file.name.trim().isEmpty
        ? 'comprobante.jpg'
        : file.name.trim();
    final contentType = _mediaTypeForFilename(filename);
    if (kIsWeb) {
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw Exception('No se pudo leer el archivo seleccionado.');
      }
      request.files.add(
        http.MultipartFile.fromBytes(
          'comprobante',
          bytes,
          filename: filename,
          contentType: contentType,
        ),
      );
    } else {
      final path = file.path;
      if (path == null || path.trim().isEmpty) {
        throw Exception('No se pudo leer la ruta del archivo seleccionado.');
      }
      request.files.add(
        await http.MultipartFile.fromPath(
          'comprobante',
          path,
          filename: filename,
          contentType: contentType,
        ),
      );
    }

    final response = await request.send();
    final body = await response.stream.bytesToString();
    _ensureSuccess(response.statusCode, body);
    return CommerceOrderDetail.fromJson(
      jsonDecode(body) as Map<String, dynamic>,
    );
  }

  void _ensureSuccess(int statusCode, String body) {
    if (statusCode >= 200 && statusCode < 300) return;
    throw Exception(
      AppError.fromResponseBody(
        body,
        fallback: 'No se pudo completar la accion del pedido.',
      ),
    );
  }
}
