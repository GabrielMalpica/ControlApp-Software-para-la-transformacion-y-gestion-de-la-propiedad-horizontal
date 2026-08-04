// lib/api/auditoria_api.dart
import 'dart:convert';

import '../model/auditoria_model.dart';
import '../service/api_client.dart';
import '../service/api_exception.dart';
import '../service/app_constants.dart';

/// Consulta de la bitácora de auditoría. Hoy solo se usa para tareas y
/// cronograma, pero el backend acepta cualquier módulo.
class AuditoriaApi {
  final ApiClient _client = ApiClient();

  Future<List<AuditoriaEventoModel>> listar({
    required String nit,
    String? modulo,
    String? entidad,
    String? entidadId,
    String? accion,
    int? anio,
    int? mes,
    int? limit,
  }) async {
    final uri =
        Uri.parse(
          '${AppConstants.cronogramaBase}/conjuntos/$nit/auditoria',
        ).replace(
          queryParameters: {
            if (modulo != null) 'modulo': modulo,
            if (entidad != null) 'entidad': entidad,
            if (entidadId != null) 'entidadId': entidadId,
            if (accion != null) 'accion': accion,
            if (anio != null) 'anio': '$anio',
            if (mes != null) 'mes': '$mes',
            if (limit != null) 'limit': '$limit',
          },
        );

    final resp = await _client.get(uri.toString());
    if (resp.statusCode != 200) {
      throw ApiException.fromResponse(
        statusCode: resp.statusCode,
        body: resp.body,
        fallback: 'No se pudo cargar el historial de auditoría.',
      );
    }

    final data = jsonDecode(resp.body) as List<dynamic>;
    return data
        .map(
          (e) => AuditoriaEventoModel.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();
  }

  /// Resumen de trazabilidad de varias entidades en una sola llamada,
  /// para no hacer N+1 al pintar el cronograma.
  Future<Map<String, TrazabilidadEntidad>> trazabilidad({
    required String nit,
    required String entidad,
    required List<String> entidadIds,
    String? modulo,
  }) async {
    if (entidadIds.isEmpty) return <String, TrazabilidadEntidad>{};

    final resp = await _client.post(
      '${AppConstants.cronogramaBase}/conjuntos/$nit/auditoria/trazabilidad',
      body: {
        'entidad': entidad,
        'entidadIds': entidadIds,
        if (modulo != null) 'modulo': modulo,
      },
    );

    if (resp.statusCode != 200) {
      throw ApiException.fromResponse(
        statusCode: resp.statusCode,
        body: resp.body,
        fallback: 'No se pudo cargar la trazabilidad de las tareas.',
      );
    }

    final data = Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
    return data.map(
      (key, value) => MapEntry(
        key,
        TrazabilidadEntidad.fromJson(
          key,
          Map<String, dynamic>.from(value as Map),
        ),
      ),
    );
  }

  /// Resumen del periodo agrupado por acción y por responsable.
  Future<Map<String, dynamic>> informePeriodo({
    required String nit,
    required int anio,
    required int mes,
    String? modulo,
  }) async {
    final uri =
        Uri.parse(
          '${AppConstants.cronogramaBase}/conjuntos/$nit/cronograma/informe-auditoria',
        ).replace(
          queryParameters: {
            'anio': '$anio',
            'mes': '$mes',
            if (modulo != null) 'modulo': modulo,
          },
        );

    final resp = await _client.get(uri.toString());
    if (resp.statusCode != 200) {
      throw ApiException.fromResponse(
        statusCode: resp.statusCode,
        body: resp.body,
        fallback: 'No se pudo cargar el informe de auditoría.',
      );
    }
    return Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
  }
}
