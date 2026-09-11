// lib/api/cronograma_herramienta_api.dart
import 'dart:convert';

import '../model/necesidad_herramienta_model.dart';
import '../service/api_client.dart';
import '../service/api_exception.dart';
import '../service/app_constants.dart';
import '../service/session_service.dart';

/// Cronograma general de herramientas: necesidades de todos los conjuntos de la
/// empresa y asignación (del stock del conjunto y, si falta, en préstamo
/// automático de la empresa) sobre el cronograma publicado.
class CronogramaHerramientaApi {
  final ApiClient _client = ApiClient();
  final SessionService _session = SessionService();

  static String get _base =>
      '${AppConstants.baseUrl}/cronograma-herramienta/empresas';

  Future<String> _resolverEmpresaId(String empresaNit) async {
    final recibido = empresaNit.trim();
    if (recibido.isNotEmpty) return recibido;
    final sesion = (await _session.getEmpresaId())?.trim() ?? '';
    if (sesion.isNotEmpty) return sesion;
    throw StateError(
      'No se pudo identificar la empresa de la sesion. Vuelve a iniciar sesion.',
    );
  }

  Future<CronogramaHerramientaResponse> listarNecesidades({
    required String empresaNit,
    required int anio,
    required int mes,
    int? herramientaId,
    String? conjuntoId,
    bool soloPendientes = false,
  }) async {
    final empresaId = await _resolverEmpresaId(empresaNit);
    final uri =
        Uri.parse(
          '$_base/${Uri.encodeComponent(empresaId)}/necesidades',
        ).replace(
          queryParameters: {
            'anio': '$anio',
            'mes': '$mes',
            if (herramientaId != null) 'herramientaId': '$herramientaId',
            if (conjuntoId != null) 'conjuntoId': conjuntoId,
            if (soloPendientes) 'soloPendientes': 'true',
          },
        );

    final resp = await _client.get(uri.toString());
    if (resp.statusCode != 200) {
      throw ApiException.fromResponse(
        statusCode: resp.statusCode,
        body: resp.body,
        fallback: 'No se pudieron cargar las necesidades de herramientas.',
      );
    }

    return CronogramaHerramientaResponse.fromJson(
      Map<String, dynamic>.from(jsonDecode(resp.body) as Map),
    );
  }

  Future<Map<String, dynamic>> asignarHerramienta({
    required String empresaNit,
    required List<int> tareaIds,
    required int herramientaId,
    double? cantidad,
    String? observacion,
  }) async {
    final empresaId = await _resolverEmpresaId(empresaNit);
    final resp = await _client.post(
      '$_base/${Uri.encodeComponent(empresaId)}/asignaciones',
      body: {
        'tareaIds': tareaIds,
        'herramientaId': herramientaId,
        if (cantidad != null) 'cantidad': cantidad,
        if (observacion != null && observacion.trim().isNotEmpty)
          'observacion': observacion.trim(),
      },
    );

    if (resp.statusCode != 200) {
      throw ApiException.fromResponse(
        statusCode: resp.statusCode,
        body: resp.body,
        fallback: 'No se pudo asignar la herramienta.',
      );
    }
    return Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
  }

  Future<void> liberarAsignacion({
    required String empresaNit,
    required int usoId,
  }) async {
    final empresaId = await _resolverEmpresaId(empresaNit);
    final resp = await _client.delete(
      '$_base/${Uri.encodeComponent(empresaId)}/asignaciones/$usoId',
    );

    if (resp.statusCode != 200) {
      throw ApiException.fromResponse(
        statusCode: resp.statusCode,
        body: resp.body,
        fallback: 'No se pudo liberar la herramienta asignada.',
      );
    }
  }
}
