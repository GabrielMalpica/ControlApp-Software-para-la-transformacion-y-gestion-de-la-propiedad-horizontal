// lib/api/preventiva_api.dart

import 'dart:convert';

import 'package:flutter_application_1/model/maquinaria_model.dart';

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

    final decoded = jsonDecode(resp.body);
    final List<dynamic> data;

    if (decoded is List) {
      data = decoded;
    } else if (decoded is Map<String, dynamic>) {
      final candidates = [
        decoded['items'],
        decoded['data'],
        decoded['preventivas'],
        decoded['definiciones'],
      ];

      List<dynamic> found = const [];
      for (final candidate in candidates) {
        if (candidate is List) {
          found = candidate;
          break;
        }
      }
      data = found;
    } else {
      data = const [];
    }

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
  Future<Map<String, dynamic>> generarCronogramaMensual({
    required String nit,
    required int anio,
    required int mes,
    int? tamanoBloqueHoras,
    int? tamanoBloqueMinutos,
  }) async {
    final body = <String, dynamic>{
      'conjuntoId': nit,
      'anio': anio,
      'mes': mes,
      if (tamanoBloqueHoras != null) 'tamanoBloqueHoras': tamanoBloqueHoras,
      if (tamanoBloqueMinutos != null)
        'tamanoBloqueMinutos': tamanoBloqueMinutos,
      if (tamanoBloqueMinutos == null && tamanoBloqueHoras != null)
        'tamanoBloqueHoras': tamanoBloqueHoras,
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

    // ✅ AHORA DEVUELVE JSON: {creadas, novedades}
    final decoded = jsonDecode(resp.body);
    if (decoded is Map<String, dynamic>) return decoded;

    // fallback por si backend responde otra cosa
    return {'creadas': 0, 'novedades': []};
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

    if (resp.statusCode == 200 || resp.statusCode == 201) return;

    // Intentar parsear JSON
    dynamic body;
    try {
      body = jsonDecode(resp.body);
    } catch (_) {
      body = null;
    }

    final friendly = _friendlyMessageFromBody(
      body,
      fallback:
          'No se pudo publicar el cronograma. Intenta de nuevo o revisa la agenda.',
    );

    String? reason;
    if (body is Map<String, dynamic>) {
      reason = body['reason']?.toString();
    }

    throw ApiError(
      statusCode: resp.statusCode,
      message: friendly,
      reason: reason,
      details: body ?? resp.body,
    );
  }

  Future<DisponibilidadMaquinariaResponse> maquinariaDisponible({
    required String nit,
    required DateTime fechaInicioUso,
    required DateTime fechaFinUso,
    int? excluirTareaId,
  }) async {
    final qp = <String, String>{
      'fechaInicioUso': fechaInicioUso.toIso8601String(),
      'fechaFinUso': fechaFinUso.toIso8601String(),
      if (excluirTareaId != null) 'excluirTareaId': excluirTareaId.toString(),
    };

    final uri = Uri.parse(
      '${AppConstants.definicionPreventivaBase}/conjuntos/$nit/preventivas/maquinaria-disponible',
    ).replace(queryParameters: qp);

    final resp = await _client.get(uri.toString());

    if (resp.statusCode != 200) {
      throw Exception(
        'Error disponibilidad maquinaria: ${resp.statusCode} ${resp.body}',
      );
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return DisponibilidadMaquinariaResponse.fromJson(data);
  }
}

class ApiError implements Exception {
  final int statusCode;
  final String message; // mensaje amigable
  final String? reason; // code: MAQUINARIA_NO_DISPONIBLE, etc
  final dynamic details; // json completo (para admin/debug)

  ApiError({
    required this.statusCode,
    required this.message,
    this.reason,
    this.details,
  });

  @override
  String toString() => 'ApiError($statusCode): $message';
}

String _friendlyMessageFromBody(
  dynamic body, {
  String fallback = 'Ocurrió un error.',
}) {
  if (body is Map<String, dynamic>) {
    final reason = body['reason']?.toString();
    final msg = body['message']?.toString();

    // Si backend ya envía message amigable, úsalo.
    if (msg != null && msg.trim().isNotEmpty) return msg.trim();

    // Si no, mapea reason -> texto humano
    switch (reason) {
      case 'MAQUINARIA_NO_DISPONIBLE':
        return 'La maquinaria seleccionada está ocupada en esas fechas. '
            'Cambia la máquina o ajusta el cronograma.';
      case 'SIN_HUECO_DIA':
        return 'No hay espacio en la agenda para programar esa tarea en el día.';
      default:
        return fallback;
    }
  }
  return fallback;
}
