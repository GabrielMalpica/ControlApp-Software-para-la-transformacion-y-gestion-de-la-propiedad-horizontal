import 'dart:convert';

import 'package:flutter_application_1/model/conjunto_order_models.dart';
import 'package:flutter_application_1/service/api_client.dart';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:flutter_application_1/service/app_error.dart';

class ConjuntoOrdersApi {
  final ApiClient _client = ApiClient();

  Future<ConjuntoOrderSummary> crearPedido({
    required List<ConjuntoCartItem> items,
    String? conjuntoId,
    String notas = '',
    String? idempotencyKey,
  }) async {
    final body = <String, dynamic>{
      'items': items.map((item) => item.toRequestJson()).toList(),
      'notas': notas.trim(),
      if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
    };
    if (conjuntoId?.trim().isNotEmpty == true) {
      body['conjuntoId'] = conjuntoId!.trim();
    }

    final response = await _client.post(
      '${AppConstants.commerceBase}/conjunto/pedidos',
      body: body,
    );
    if (response.statusCode != 201) {
      throw Exception(
        AppError.fromResponseBody(
          response.body,
          fallback: 'No se pudo crear el pedido del conjunto.',
        ),
      );
    }

    return ConjuntoOrderSummary.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<List<ConjuntoOrderSummary>> listarPedidos() async {
    final response = await _client.get(
      '${AppConstants.commerceBase}/conjunto/pedidos',
    );
    if (response.statusCode != 200) {
      throw Exception(
        AppError.fromResponseBody(
          response.body,
          fallback: 'No se pudieron cargar los pedidos de conjuntos.',
        ),
      );
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .whereType<Map<String, dynamic>>()
        .map(ConjuntoOrderSummary.fromJson)
        .toList();
  }

  Future<ConjuntoOrderSummary> obtenerPedido(int pedidoId) async {
    final response = await _client.get(
      '${AppConstants.commerceBase}/conjunto/pedidos/$pedidoId',
    );
    if (response.statusCode != 200) {
      throw Exception(
        AppError.fromResponseBody(
          response.body,
          fallback: 'No se pudo cargar el detalle del pedido.',
        ),
      );
    }

    return ConjuntoOrderSummary.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}
