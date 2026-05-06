// lib/api/preventiva_api.dart

import 'dart:convert';

import 'package:flutter_application_1/model/maquinaria_model.dart';
import 'package:flutter_application_1/model/preventiva_excluida_borrador_model.dart';

import '../model/preventiva_model.dart';
import '../service/api_client.dart';
import '../service/app_constants.dart';

class DefinicionPreventivaApi {
  final ApiClient _client = ApiClient();

  Never _throwCrudApiError(dynamic resp, {required String fallback}) {
    dynamic body;
    try {
      body = jsonDecode(resp.body);
    } catch (_) {
      body = null;
    }

    final friendly = _friendlyMessageFromBody(body, fallback: fallback);
    String? reason;
    if (body is Map<String, dynamic>) {
      reason = body['reason']?.toString();
    }

    throw ApiError(
      statusCode: resp.statusCode as int,
      message: friendly,
      reason: reason,
      details: body ?? resp.body,
    );
  }

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
      _throwCrudApiError(
        resp,
        fallback:
            'No se pudo crear la preventiva. Revisa maquinaria, fechas y recursos.',
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
      _throwCrudApiError(
        resp,
        fallback:
            'No se pudo editar la preventiva. Revisa maquinaria, fechas y recursos.',
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
    List<Map<String, dynamic>>? confirmacionesReemplazo,
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
      if (confirmacionesReemplazo != null && confirmacionesReemplazo.isNotEmpty)
        'confirmacionesReemplazo': confirmacionesReemplazo,
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
    if (decoded is Map<String, dynamic>) {
      return _normalizarRespuestaGenerarCronograma(decoded);
    }
    return {'creadas': 0, 'novedades': []};
  }

  Future<Map<String, dynamic>> listarOpcionesReprogramacionBorrador({
    required String nit,
    required int tareaId,
  }) async {
    final resp = await _client.get(
      '${AppConstants.definicionPreventivaBase}/conjuntos/$nit/preventivas/borrador/tarea/$tareaId/opciones-reprogramacion',
    );
    if (resp.statusCode != 200) {
      throw Exception(
        'Error consultando huecos de reprogramacion: ${resp.statusCode} ${resp.body}',
      );
    }
    return Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
  }

  Future<void> editarBloqueBorrador({
    required String nit,
    required int tareaId,
    DateTime? fechaInicio,
    DateTime? fechaFin,
    List<int>? operariosIds,
  }) async {
    final body = <String, dynamic>{
      if (fechaInicio != null) 'fechaInicio': fechaInicio.toIso8601String(),
      if (fechaFin != null) 'fechaFin': fechaFin.toIso8601String(),
      if (operariosIds != null) 'operariosIds': operariosIds,
    };
    final resp = await _client.patch(
      '${AppConstants.definicionPreventivaBase}/conjuntos/$nit/preventivas/borrador/tarea/$tareaId',
      body: body,
    );
    if (resp.statusCode != 200) {
      throw Exception(
        'Error reprogramando preventiva reemplazada: ${resp.statusCode} ${resp.body}',
      );
    }
  }

  Future<void> reordenarTareasDiaBorrador({
    required String nit,
    required DateTime fecha,
    required List<int> tareaIds,
  }) async {
    final resp = await _client.post(
      '${AppConstants.definicionPreventivaBase}/conjuntos/$nit/preventivas/borrador/tareas/reordenar-dia',
      body: {'fecha': fecha.toIso8601String(), 'tareaIds': tareaIds},
    );
    if (resp.statusCode != 200) {
      throw Exception(
        'Error reordenando tareas del día: ${resp.statusCode} ${resp.body}',
      );
    }
  }

  Future<void> eliminarBloqueBorrador({
    required String nit,
    required int tareaId,
  }) async {
    final resp = await _client.delete(
      '${AppConstants.definicionPreventivaBase}/conjuntos/$nit/preventivas/borrador/tarea/$tareaId',
    );
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      throw Exception(
        'Error eliminando bloque borrador: ${resp.statusCode} ${resp.body}',
      );
    }
  }

  Future<List<PreventivaExcluidaBorradorModel>> listarExcluidasBorrador({
    required String nit,
    required int anio,
    required int mes,
    DateTime? fecha,
  }) async {
    final uri =
        Uri.parse(
          '${AppConstants.definicionPreventivaBase}/conjuntos/$nit/preventivas/borrador/excluidas',
        ).replace(
          queryParameters: {
            'anio': anio.toString(),
            'mes': mes.toString(),
            if (fecha != null) 'fecha': fecha.toIso8601String(),
          },
        );

    final resp = await _client.get(uri.toString());
    if (resp.statusCode != 200) {
      throw Exception(
        'Error listando excluidas: ${resp.statusCode} ${resp.body}',
      );
    }

    final data = jsonDecode(resp.body) as List<dynamic>;
    return data
        .map(
          (e) => PreventivaExcluidaBorradorModel.fromJson(
            e as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<void> descartarExcluidaBorrador({
    required String nit,
    required int excluidaId,
  }) async {
    final resp = await _client.delete(
      '${AppConstants.definicionPreventivaBase}/conjuntos/$nit/preventivas/borrador/excluidas/$excluidaId',
    );
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      throw Exception(
        'Error descartando excluida: ${resp.statusCode} ${resp.body}',
      );
    }
  }

  Future<Map<String, dynamic>> sugerirHuecosExcluida({
    required String nit,
    required int excluidaId,
    DateTime? fechaPreferida,
  }) async {
    final uri =
        Uri.parse(
          '${AppConstants.definicionPreventivaBase}/conjuntos/$nit/preventivas/borrador/excluidas/$excluidaId/huecos',
        ).replace(
          queryParameters: {
            if (fechaPreferida != null)
              'fechaPreferida': fechaPreferida.toIso8601String(),
          },
        );
    final resp = await _client.get(uri.toString());
    if (resp.statusCode != 200) {
      throw Exception(
        'Error consultando huecos: ${resp.statusCode} ${resp.body}',
      );
    }
    return Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
  }

  Future<Map<String, dynamic>> agendarExcluidaBorrador({
    required String nit,
    required int excluidaId,
    DateTime? fechaInicio,
    DateTime? fechaFin,
    List<Map<String, String>>? bloques,
  }) async {
    final resp = await _client.post(
      '${AppConstants.definicionPreventivaBase}/conjuntos/$nit/preventivas/borrador/excluidas/$excluidaId/agendar',
      body: {
        if (fechaInicio != null) 'fechaInicio': fechaInicio.toIso8601String(),
        if (fechaFin != null) 'fechaFin': fechaFin.toIso8601String(),
        if (bloques != null) 'bloques': bloques,
      },
    );
    if (resp.statusCode != 200) {
      throw Exception(
        'Error agendando excluida: ${resp.statusCode} ${resp.body}',
      );
    }
    return Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
  }

  Future<Map<String, dynamic>> reemplazarTareaConExcluida({
    required String nit,
    required int tareaId,
    required int excluidaId,
  }) async {
    final resp = await _client.post(
      '${AppConstants.definicionPreventivaBase}/conjuntos/$nit/preventivas/borrador/tarea/$tareaId/reemplazar-por-excluida',
      body: {'excluidaId': excluidaId},
    );
    if (resp.statusCode != 200) {
      throw Exception(
        'Error reemplazando tarea: ${resp.statusCode} ${resp.body}',
      );
    }
    return Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
  }

  Future<Map<String, dynamic>> reasignarOperarioBorrador({
    required String nit,
    required int tareaId,
    required int nuevoOperarioId,
    required bool aplicarADefinicion,
  }) async {
    final resp = await _client.post(
      '${AppConstants.definicionPreventivaBase}/conjuntos/$nit/preventivas/borrador/tarea/$tareaId/reasignar-operario',
      body: {
        'nuevoOperarioId': nuevoOperarioId,
        'aplicarADefinicion': aplicarADefinicion,
      },
    );
    if (resp.statusCode != 200) {
      throw Exception(
        'Error reasignando operario: ${resp.statusCode} ${resp.body}',
      );
    }
    return Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
  }

  Future<Map<String, dynamic>> reasignarOperarioExcluidaBorrador({
    required String nit,
    required int excluidaId,
    required int nuevoOperarioId,
    required bool aplicarADefinicion,
  }) async {
    final resp = await _client.post(
      '${AppConstants.definicionPreventivaBase}/conjuntos/$nit/preventivas/borrador/excluidas/$excluidaId/reasignar-operario',
      body: {
        'nuevoOperarioId': nuevoOperarioId,
        'aplicarADefinicion': aplicarADefinicion,
      },
    );
    if (resp.statusCode != 200) {
      throw Exception(
        'Error reasignando operario de excluida: ${resp.statusCode} ${resp.body}',
      );
    }
    return Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
  }

  Future<Map<String, dynamic>> dividirExcluidaManual({
    required String nit,
    required int excluidaId,
    required List<int> bloquesDuracionMinutos,
  }) async {
    final resp = await _client.post(
      '${AppConstants.definicionPreventivaBase}/conjuntos/$nit/preventivas/borrador/excluidas/$excluidaId/dividir-manual',
      body: {
        'bloques': bloquesDuracionMinutos
            .map((duracion) => {'duracionMinutos': duracion})
            .toList(),
      },
    );
    if (resp.statusCode != 200) {
      throw Exception(
        'Error dividiendo excluida: ${resp.statusCode} ${resp.body}',
      );
    }
    return Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
  }

  Future<Map<String, dynamic>> sugerirHuecosBloqueExcluida({
    required String nit,
    required int excluidaId,
    required String bloqueId,
    DateTime? fechaPreferida,
  }) async {
    final uri =
        Uri.parse(
          '${AppConstants.definicionPreventivaBase}/conjuntos/$nit/preventivas/borrador/excluidas/$excluidaId/bloques/$bloqueId/huecos',
        ).replace(
          queryParameters: {
            if (fechaPreferida != null)
              'fechaPreferida': fechaPreferida.toIso8601String(),
          },
        );
    final resp = await _client.get(uri.toString());
    if (resp.statusCode != 200) {
      throw Exception(
        'Error consultando huecos del bloque: ${resp.statusCode} ${resp.body}',
      );
    }
    return Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
  }

  Future<Map<String, dynamic>> agendarBloqueExcluida({
    required String nit,
    required int excluidaId,
    required String bloqueId,
    DateTime? fechaInicio,
    DateTime? fechaFin,
  }) async {
    final resp = await _client.post(
      '${AppConstants.definicionPreventivaBase}/conjuntos/$nit/preventivas/borrador/excluidas/$excluidaId/bloques/$bloqueId/agendar',
      body: {
        if (fechaInicio != null) 'fechaInicio': fechaInicio.toIso8601String(),
        if (fechaFin != null) 'fechaFin': fechaFin.toIso8601String(),
      },
    );
    if (resp.statusCode != 200) {
      throw Exception(
        'Error agendando bloque excluido: ${resp.statusCode} ${resp.body}',
      );
    }
    return Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
  }

  Future<List<Map<String, dynamic>>> informeActividadBorrador({
    required String nit,
    required int anio,
    required int mes,
  }) async {
    final uri = Uri.parse(
      '${AppConstants.definicionPreventivaBase}/conjuntos/$nit/preventivas/borrador/informe-actividad',
    ).replace(queryParameters: {'anio': '$anio', 'mes': '$mes'});
    final resp = await _client.get(uri.toString());
    if (resp.statusCode != 200) {
      throw Exception(
        'Error cargando informe de borrador: ${resp.statusCode} ${resp.body}',
      );
    }
    final data = jsonDecode(resp.body) as List<dynamic>;
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
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
      'fechaInicioUso': fechaInicioUso.toUtc().toIso8601String(),
      'fechaFinUso': fechaFinUso.toUtc().toIso8601String(),
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

Map<String, dynamic> _normalizarRespuestaGenerarCronograma(
  Map<String, dynamic> raw,
) {
  final candidatos = <Map<String, dynamic>>[
    raw,
    if (raw['data'] is Map<String, dynamic>)
      raw['data'] as Map<String, dynamic>,
    if (raw['resultado'] is Map<String, dynamic>)
      raw['resultado'] as Map<String, dynamic>,
    if (raw['result'] is Map<String, dynamic>)
      raw['result'] as Map<String, dynamic>,
  ];

  Map<String, dynamic> elegido = raw;
  for (final c in candidatos) {
    if (c.containsKey('creadas') || c.containsKey('novedades')) {
      elegido = c;
      break;
    }
  }

  final creadas = _parseIntFlexible(
    elegido['creadas'] ??
        elegido['totalCreadas'] ??
        elegido['creadasCount'] ??
        raw['creadas'] ??
        raw['totalCreadas'] ??
        raw['creadasCount'],
  );

  final novedadesRaw =
      elegido['novedades'] ??
      elegido['items'] ??
      elegido['listaNovedades'] ??
      raw['novedades'];

  List<dynamic> novedades = const [];
  if (novedadesRaw is List) {
    novedades = novedadesRaw;
  } else if (novedadesRaw is Map<String, dynamic>) {
    final nested =
        novedadesRaw['items'] ??
        novedadesRaw['novedades'] ??
        novedadesRaw['data'];
    if (nested is List) {
      novedades = nested;
    }
  }

  return {'creadas': creadas, 'novedades': novedades};
}

int _parseIntFlexible(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? 0}') ?? 0;
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
