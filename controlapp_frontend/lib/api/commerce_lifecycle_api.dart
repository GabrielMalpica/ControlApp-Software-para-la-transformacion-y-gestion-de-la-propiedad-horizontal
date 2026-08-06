import 'dart:convert';

import 'package:flutter_application_1/model/commerce_lifecycle_models.dart';
import 'package:flutter_application_1/service/api_client.dart';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:flutter_application_1/service/app_error.dart';

class CommerceLifecycleApi {
  final ApiClient _client = ApiClient();

  Future<CommerceOrderDetail> obtenerPedido(int pedidoId) async {
    final response = await _client.get(
      '${AppConstants.commerceBase}/pedidos/$pedidoId',
    );
    _ensureSuccess(response.statusCode, response.body);
    return CommerceOrderDetail.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<CommerceOrderDetail> cambiarEstado(
    int pedidoId,
    String estadoDestino,
  ) async {
    final response = await _client.post(
      '${AppConstants.commerceBase}/pedidos/$pedidoId/estado',
      body: {'estadoDestino': estadoDestino},
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
  }) async {
    final response = await _client.post(
      '${AppConstants.commerceBase}/pedidos/$pedidoId/items/$itemId/mapeo',
      body: {'insumoId': insumoId},
    );
    _ensureSuccess(response.statusCode, response.body);
    return ReceiptPreview.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
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
