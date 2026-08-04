import 'dart:convert';

import 'package:flutter_application_1/model/resident_order_models.dart';
import 'package:flutter_application_1/service/api_client.dart';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:flutter_application_1/service/app_error.dart';

class ResidentOrdersApi {
  final ApiClient _client = ApiClient();

  Future<ResidentOrderSummary> crearPedido({
    required List<ResidentCartItem> items,
    String notas = '',
  }) async {
    final resp = await _client.post(
      '${AppConstants.commerceBase}/residente/pedidos',
      body: {
        'items': items
            .map(
              (item) => {
                'productId': item.productId,
                'quantity': item.quantity,
              },
            )
            .toList(),
        'notas': notas.trim(),
      },
    );

    if (resp.statusCode != 201) {
      throw Exception(
        AppError.fromResponseBody(
          resp.body,
          fallback: 'No se pudo crear el pedido residente.',
        ),
      );
    }

    return ResidentOrderSummary.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  Future<List<ResidentOrderSummary>> listarPedidos() async {
    final resp = await _client.get('${AppConstants.commerceBase}/residente/pedidos');
    if (resp.statusCode != 200) {
      throw Exception(
        AppError.fromResponseBody(
          resp.body,
          fallback: 'No se pudieron cargar tus pedidos.',
        ),
      );
    }

    final data = jsonDecode(resp.body) as List<dynamic>;
    return data
        .whereType<Map<String, dynamic>>()
        .map(ResidentOrderSummary.fromJson)
        .toList();
  }

  Future<ResidentOrderSummary> obtenerPedido(int pedidoId) async {
    final resp = await _client.get('${AppConstants.commerceBase}/residente/pedidos/$pedidoId');
    if (resp.statusCode != 200) {
      throw Exception(
        AppError.fromResponseBody(
          resp.body,
          fallback: 'No se pudo cargar el detalle del pedido.',
        ),
      );
    }

    return ResidentOrderSummary.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }
}
