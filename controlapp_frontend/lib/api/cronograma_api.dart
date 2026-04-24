// lib/api/cronograma_api.dart
import 'dart:convert';

import '../service/api_client.dart';
import '../service/app_error.dart';
import '../service/app_constants.dart';
import '../model/cronograma_actividad_informe_model.dart';
import '../model/tarea_model.dart';

class CronogramaApi {
  final ApiClient _client = ApiClient();

  /// Lista todas las tareas (preventivas + correctivas) del mes de un conjunto.
  /// GET /cronograma/conjuntos/:nit/cronograma?anio=&mes=&borrador=
  Future<List<TareaModel>> listarPorConjuntoYMes({
    required String nit,
    required int anio,
    required int mes,
    bool? borrador,
  }) async {
    final uri =
        Uri.parse(
          '${AppConstants.cronogramaBase}/conjuntos/$nit/cronograma',
        ).replace(
          queryParameters: {
            'anio': anio.toString(),
            'mes': mes.toString(),
            if (borrador != null) 'borrador': borrador.toString(),
          },
        );

    final resp = await _client.get(uri.toString());

    if (resp.statusCode != 200) {
      throw Exception(
        'Error al traer cronograma: ${resp.statusCode} ${resp.body}',
      );
    }

    final List<dynamic> data = jsonDecode(resp.body) as List<dynamic>;

    return data
        .map((e) => TareaModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Lista de tareas del mes (puede ser borrador o definitivo)
  /// GET /cronograma/conjuntos/:nit/cronograma?anio=&mes=&borrador=&tipo=
  Future<List<TareaModel>> cronogramaMensual({
    required String nit,
    required int anio,
    required int mes,
    bool borrador = false,
    String? tipo,
  }) async {
    final base = '${AppConstants.baseUrl}/cronograma/conjuntos/$nit/cronograma';

    final uri = Uri.parse(base).replace(
      queryParameters: {
        'anio': anio.toString(),
        'mes': mes.toString(),
        'borrador': borrador.toString(),
        if (tipo != null) 'tipo': tipo,
      },
    );

    final resp = await _client.get(uri.toString());

    if (resp.statusCode != 200) {
      throw Exception(
        'Error al cargar cronograma: ${resp.statusCode} ${resp.body}',
      );
    }

    final data = jsonDecode(resp.body) as List<dynamic>;
    return data
        .map((e) => TareaModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Publicar cronograma de preventivas (pasa borrador=false en backend)
  /// POST /definicion-preventiva/conjuntos/:nit/preventivas/publicar?anio=&mes=&consolidar=
  Future<Map<String, dynamic>> publicarCronogramaPreventivas({
    required String nit,
    required int anio,
    required int mes,
    bool consolidar = false,
  }) async {
    final baseUrl =
        '${AppConstants.definicionPreventivaBase}/conjuntos/$nit/preventivas/publicar';

    final uri = Uri.parse(baseUrl).replace(
      queryParameters: {
        'anio': anio.toString(),
        'mes': mes.toString(),
        'consolidar': consolidar.toString(),
      },
    );

    final resp = await _client.post(uri.toString());

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(
        'Error publicando cronograma: ${resp.statusCode} ${resp.body}',
      );
    }

    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> eliminarCronogramaPublicado({
    required String nit,
  }) async {
    final resp = await _client.delete(
      '${AppConstants.cronogramaBase}/conjuntos/$nit/cronograma/publicado',
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(
        AppError.fromResponseBody(
          resp.body,
          fallback: 'No se pudo eliminar el cronograma publicado.',
        ),
      );
    }

    if (resp.body.trim().isEmpty) return <String, dynamic>{};
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<int> getLimiteMinSemanaPorConjunto({required String nit}) async {
    final uri = Uri.parse('${AppConstants.empresaBase}/$nit/limite-min-semana');

    final resp = await _client.get(uri.toString());

    if (resp.statusCode != 200) {
      throw Exception(
        'Error al traer límite semanal: ${resp.statusCode} ${resp.body}',
      );
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;

    final limite = data['limiteMinSemana'];
    if (limite == null) throw Exception('Respuesta sin limiteMinSemana');

    return int.parse(limite.toString());
  }

  Future<List<CronogramaActividadInformeModel>> informeActividadMensual({
    required String nit,
    required int anio,
    required int mes,
    required bool borrador,
  }) async {
    final uri =
        Uri.parse(
          '${AppConstants.cronogramaBase}/conjuntos/$nit/cronograma/informe-actividad',
        ).replace(
          queryParameters: {
            'anio': '$anio',
            'mes': '$mes',
            'borrador': borrador.toString(),
          },
        );

    final resp = await _client.get(uri.toString());
    if (resp.statusCode != 200) {
      throw Exception(
        AppError.fromResponseBody(
          resp.body,
          fallback: 'No se pudo cargar el informe mensual.',
        ),
      );
    }

    final data = jsonDecode(resp.body) as List<dynamic>;
    return data
        .map(
          (e) => CronogramaActividadInformeModel.fromJson(
            e as Map<String, dynamic>,
          ),
        )
        .toList();
  }
}
