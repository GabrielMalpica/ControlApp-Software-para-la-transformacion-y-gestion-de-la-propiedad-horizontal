// lib/api/preventiva_api.dart

import 'dart:convert';

import '../model/preventiva_model.dart';
import '../service/api_client.dart';
import '../service/app_constants.dart';

class DefinicionPreventivaApi {
  final ApiClient _client = ApiClient();

  /// Listar definiciones preventivas de un conjunto
  /// GET /definicion-preventiva/conjuntos/:nit/preventivas
  Future<List<DefinicionPreventiva>> listarPorConjunto(String nit) async {
    final resp = await _client.get(
      '${AppConstants.definicionPreventivaBase}/conjuntos/$nit/preventivas',
    );

    if (resp.statusCode != 200) {
      throw Exception(
        'Error al listar preventivas: ${resp.statusCode} ${resp.body}',
      );
    }

    final List<dynamic> data = jsonDecode(resp.body);
    return data
        .map((e) => DefinicionPreventiva.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Crear definición preventiva
  /// POST /definicion-preventiva/conjuntos/:nit/preventivas
  Future<DefinicionPreventiva> crear(
    String nit,
    DefinicionPreventivaRequest req,
  ) async {
    final resp = await _client.post(
      '${AppConstants.definicionPreventivaBase}/conjuntos/$nit/preventivas',
      body: req.toJson(),
    );

    if (resp.statusCode != 201) {
      throw Exception(
        'Error al crear preventiva: ${resp.statusCode} ${resp.body}',
      );
    }

    final Map<String, dynamic> data = jsonDecode(resp.body);
    return DefinicionPreventiva.fromJson(data);
  }

  /// Editar definición preventiva
  /// PATCH /definicion-preventiva/conjuntos/:nit/preventivas/:id
  Future<DefinicionPreventiva> editar(
    String nit,
    int id,
    DefinicionPreventivaRequest req,
  ) async {
    final resp = await _client.patch(
      '${AppConstants.definicionPreventivaBase}/conjuntos/$nit/preventivas/$id',
      body: req.toJson(),
    );

    if (resp.statusCode != 200) {
      throw Exception(
        'Error al editar preventiva: ${resp.statusCode} ${resp.body}',
      );
    }

    final Map<String, dynamic> data = jsonDecode(resp.body);
    return DefinicionPreventiva.fromJson(data);
  }

  /// Eliminar definición preventiva
  /// DELETE /definicion-preventiva/conjuntos/:nit/preventivas/:id
  Future<void> eliminar(String nit, int id) async {
    final resp = await _client.delete(
      '${AppConstants.definicionPreventivaBase}/conjuntos/$nit/preventivas/$id',
    );

    if (resp.statusCode != 204 && resp.statusCode != 200) {
      throw Exception(
        'Error al eliminar preventiva: ${resp.statusCode} ${resp.body}',
      );
    }
  }

  /// Generar cronograma mensual desde las definiciones
  /// POST /definicion-preventiva/conjuntos/:nit/preventivas/generar-cronograma
  Future<void> generarCronogramaMensual({
    required String nit,
    required int anio,
    required int mes,
    int? tamanoBloqueHoras,
  }) async {
    final body = <String, dynamic>{
      'anio': anio,
      'mes': mes,
      if (tamanoBloqueHoras != null) 'tamanoBloqueHoras': tamanoBloqueHoras,
    };

    final resp = await _client.post(
      '${AppConstants.definicionPreventivaBase}/conjuntos/$nit/preventivas/generar-cronograma',
      body: body,
    );

    if (resp.statusCode != 201 && resp.statusCode != 200) {
      throw Exception(
        'Error al generar cronograma: ${resp.statusCode} ${resp.body}',
      );
    }
  }

  Future<void> publicarCronogramaMensual({
    required String nit,
    required int anio,
    required int mes,
    bool consolidar = true,
  }) async {
    final uri =
        Uri.parse(
          '${AppConstants.definicionPreventivaBase}/conjuntos/$nit/preventivas/publicar',
        ).replace(
          queryParameters: {
            'anio': anio.toString(),
            'mes': mes.toString(),
            'consolidar': consolidar.toString(),
          },
        );

    final resp = await _client.post(uri.toString());

    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw Exception(
        'Error al publicar cronograma: ${resp.statusCode} ${resp.body}',
      );
    }
  }
}
