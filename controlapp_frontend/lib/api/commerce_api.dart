import 'dart:convert';

import 'package:flutter_application_1/model/commerce_models.dart';
import 'package:flutter_application_1/service/api_client.dart';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:flutter_application_1/service/app_error.dart';

class CommerceApi {
  final ApiClient _client = ApiClient();

  Future<CommerceCatalogResponse> listarCatalogo({
    String target = 'todos',
    String q = '',
    String category = '',
    int page = 1,
    int perPage = 24,
  }) async {
    final query = <String, String>{
      'target': target,
      'page': '$page',
      'perPage': '$perPage',
    };
    if (q.trim().isNotEmpty) query['q'] = q.trim();
    if (category.trim().isNotEmpty) query['category'] = category.trim();

    final uri = Uri.parse(
      '${AppConstants.commerceBase}/catalogo',
    ).replace(queryParameters: query);
    final resp = await _client.get(uri.toString());

    if (resp.statusCode != 200) {
      throw Exception(
        AppError.fromResponseBody(
          resp.body,
          fallback: 'No se pudo consultar el catalogo comercial.',
        ),
      );
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return CommerceCatalogResponse.fromJson(data);
  }

  Future<CommerceProduct> obtenerProducto(int productId) async {
    final resp = await _client.get(
      '${AppConstants.commerceBase}/catalogo/$productId',
    );

    if (resp.statusCode != 200) {
      throw Exception(
        AppError.fromResponseBody(
          resp.body,
          fallback: 'No se pudo cargar el detalle del producto.',
        ),
      );
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return CommerceProduct.fromJson(data);
  }

  Future<CommerceServiceAvailability> obtenerDisponibilidad({
    required int productId,
    required String date,
    required String slot,
  }) async {
    final uri = Uri.parse(
      '${AppConstants.commerceBase}/catalogo/$productId/disponibilidad',
    ).replace(queryParameters: <String, String>{'date': date, 'slot': slot});
    final resp = await _client.get(uri.toString());
    if (resp.statusCode != 200) {
      throw Exception(
        AppError.fromResponseBody(
          resp.body,
          fallback: 'No se pudo consultar la disponibilidad del servicio.',
        ),
      );
    }
    return CommerceServiceAvailability.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }
}
