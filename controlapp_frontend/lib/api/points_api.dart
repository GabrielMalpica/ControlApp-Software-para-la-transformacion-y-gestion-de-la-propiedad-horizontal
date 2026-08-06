import 'dart:convert';

import 'package:flutter_application_1/model/points_models.dart';
import 'package:flutter_application_1/service/api_client.dart';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:flutter_application_1/service/app_error.dart';

class PointsApi {
  final ApiClient _client = ApiClient();

  String _query(String path, String? conjuntoId) {
    if (conjuntoId?.trim().isNotEmpty != true) return path;
    return '$path?conjuntoId=${Uri.encodeQueryComponent(conjuntoId!.trim())}';
  }

  Future<PointsSummary> obtenerResumen({String? conjuntoId}) async {
    final response = await _client.get(
      _query('${AppConstants.commerceBase}/puntos/resumen', conjuntoId),
    );
    _ensureSuccess(response.statusCode, response.body);
    return PointsSummary.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> redimir({required int beneficioId, String? conjuntoId}) async {
    final response = await _client.post(
      '${AppConstants.commerceBase}/puntos/redenciones',
      body: <String, dynamic>{
        'beneficioId': beneficioId,
        if (conjuntoId?.trim().isNotEmpty == true) 'conjuntoId': conjuntoId,
      },
    );
    _ensureSuccess(response.statusCode, response.body);
  }

  Future<PointsConfig> guardarConfiguracion(PointsConfig config) async {
    final response = await _client.put(
      '${AppConstants.commerceBase}/puntos/configuracion',
      body: <String, dynamic>{
        'conjuntoId': config.conjuntoId,
        'activo': config.activo,
        'montoPorPuntoResidente': config.montoPorPuntoResidente,
        'montoPorPuntoConjunto': config.montoPorPuntoConjunto,
        'minimoRedencionPuntos': config.minimoRedencionPuntos,
        'beneficios': config.beneficios.map((item) => item.toJson()).toList(),
      },
    );
    _ensureSuccess(response.statusCode, response.body);
    return PointsConfig.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> ajustar({
    required String conjuntoId,
    required String usuarioId,
    required int puntos,
    required String descripcion,
  }) async {
    final response = await _client.post(
      '${AppConstants.commerceBase}/puntos/ajustes',
      body: <String, dynamic>{
        'conjuntoId': conjuntoId,
        'usuarioId': usuarioId,
        'puntos': puntos,
        'descripcion': descripcion,
      },
    );
    _ensureSuccess(response.statusCode, response.body);
  }

  void _ensureSuccess(int statusCode, String body) {
    if (statusCode >= 200 && statusCode < 300) return;
    throw Exception(
      AppError.fromResponseBody(
        body,
        fallback: 'No se pudo completar la operación de puntos.',
      ),
    );
  }
}
