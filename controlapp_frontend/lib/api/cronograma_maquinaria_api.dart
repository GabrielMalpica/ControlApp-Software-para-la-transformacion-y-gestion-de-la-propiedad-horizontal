// lib/api/cronograma_maquinaria_api.dart
import 'dart:convert';

import '../model/necesidad_maquinaria_model.dart';
import '../service/api_client.dart';
import '../service/api_exception.dart';
import '../service/app_constants.dart';

/// Cronograma general de maquinaria: necesidades de todos los conjuntos de la
/// empresa y asignación de máquinas reales sobre el cronograma publicado.
class CronogramaMaquinariaApi {
  final ApiClient _client = ApiClient();

  static String get _base =>
      '${AppConstants.baseUrl}/cronograma-maquinaria/empresas';

  Future<CronogramaMaquinariaResponse> listarNecesidades({
    required String empresaNit,
    required int anio,
    required int mes,
    String? tipo,
    String? conjuntoId,
    bool soloPendientes = false,
  }) async {
    final uri = Uri.parse('$_base/$empresaNit/necesidades').replace(
      queryParameters: {
        'anio': '$anio',
        'mes': '$mes',
        if (tipo != null) 'tipo': tipo,
        if (conjuntoId != null) 'conjuntoId': conjuntoId,
        if (soloPendientes) 'soloPendientes': 'true',
      },
    );

    final resp = await _client.get(uri.toString());
    if (resp.statusCode != 200) {
      throw ApiException.fromResponse(
        statusCode: resp.statusCode,
        body: resp.body,
        fallback: 'No se pudieron cargar las necesidades de maquinaria.',
      );
    }

    return CronogramaMaquinariaResponse.fromJson(
      Map<String, dynamic>.from(jsonDecode(resp.body) as Map),
    );
  }

  Future<Map<String, dynamic>> asignarMaquinaria({
    required String empresaNit,
    required List<int> tareaIds,
    required int maquinariaId,
    String? observacion,
  }) async {
    final resp = await _client.post(
      '$_base/$empresaNit/asignaciones',
      body: {
        'tareaIds': tareaIds,
        'maquinariaId': maquinariaId,
        if (observacion != null && observacion.trim().isNotEmpty)
          'observacion': observacion.trim(),
      },
    );

    if (resp.statusCode != 200) {
      throw ApiException.fromResponse(
        statusCode: resp.statusCode,
        body: resp.body,
        fallback: 'No se pudo asignar la maquinaria.',
      );
    }
    return Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
  }

  Future<void> liberarAsignacion({
    required String empresaNit,
    required int usoId,
  }) async {
    final resp = await _client.delete('$_base/$empresaNit/asignaciones/$usoId');

    if (resp.statusCode != 200) {
      throw ApiException.fromResponse(
        statusCode: resp.statusCode,
        body: resp.body,
        fallback: 'No se pudo liberar la maquinaria asignada.',
      );
    }
  }
}
