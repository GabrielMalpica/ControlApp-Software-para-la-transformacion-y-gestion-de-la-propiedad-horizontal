// lib/api/herramienta_api.dart

import 'dart:convert';

import '../service/api_client.dart';
import '../service/app_constants.dart';

class HerramientaApi {
  final ApiClient _client = ApiClient();

  static const String _herramientasBase = '/herramientas';
  static const String _solicitudesHerramientasBase =
      '/solicitudes-herramientas';

  Future<Map<String, dynamic>> crearHerramienta({
    required String empresaId,
    required String nombre,
    String unidad = "UNIDAD",
    String modoControl = "PRESTAMO",
    int? vidaUtilDias,
    int? umbralBajo,
  }) async {
    final body = {
      "empresaId": empresaId,
      "nombre": nombre,
      "unidad": unidad,
      "modoControl": modoControl,
      "vidaUtilDias": vidaUtilDias,
      "umbralBajo": umbralBajo,
    };

    final resp = await _client.post(_herramientasBase, body: body);

    if (resp.statusCode != 201 && resp.statusCode != 200) {
      throw Exception(
        'Error al crear herramienta: ${resp.statusCode} ${resp.body}',
      );
    }

    final Map<String, dynamic> data = jsonDecode(resp.body);
    return data;
  }

  /// GET /herramientas?empresaId=...&nombre=...&take=...&skip=...
  /// Retorna: { total, data: [...] }
  Future<Map<String, dynamic>> listarHerramientas({
    required String empresaId,
    String? nombre,
    int take = 50,
    int skip = 0,
  }) async {
    final qp = <String, String>{
      "empresaId": empresaId,
      "take": take.toString(),
      "skip": skip.toString(),
      if (nombre != null && nombre.trim().isNotEmpty) "nombre": nombre.trim(),
    };

    final uri = Uri.parse(
      '${AppConstants.baseUrl}$_herramientasBase',
    ).replace(queryParameters: qp);

    final resp = await _client.get(uri.toString());

    if (resp.statusCode != 200) {
      throw Exception(
        'Error al listar herramientas: ${resp.statusCode} ${resp.body}',
      );
    }

    final Map<String, dynamic> data = jsonDecode(resp.body);
    return data; // { total, data: [...] }
  }

  /// GET /herramientas/:herramientaId
  Future<Map<String, dynamic>> obtenerHerramienta({
    required int herramientaId,
  }) async {
    final resp = await _client.get('$_herramientasBase/$herramientaId');

    if (resp.statusCode != 200) {
      throw Exception(
        'Error al obtener herramienta: ${resp.statusCode} ${resp.body}',
      );
    }

    final Map<String, dynamic> data = jsonDecode(resp.body);
    return data;
  }

  /// PATCH /herramientas/:herramientaId
  Future<Map<String, dynamic>> editarHerramienta({
    required int herramientaId,
    String? nombre,
    String? unidad,
    String? modoControl, // PRESTAMO | CONSUMO | VIDA_CORTA
    int? vidaUtilDias,
    int? umbralBajo,
  }) async {
    final body = <String, dynamic>{
      if (nombre != null) "nombre": nombre,
      if (unidad != null) "unidad": unidad,
      if (modoControl != null) "modoControl": modoControl,
      if (vidaUtilDias != null) "vidaUtilDias": vidaUtilDias,
      if (umbralBajo != null) "umbralBajo": umbralBajo,
    };

    final resp = await _client.patch(
      '$_herramientasBase/$herramientaId',
      body: body,
    );

    if (resp.statusCode != 200) {
      throw Exception(
        'Error al editar herramienta: ${resp.statusCode} ${resp.body}',
      );
    }

    final Map<String, dynamic> data = jsonDecode(resp.body);
    return data;
  }

  /// DELETE /herramientas/:herramientaId
  Future<void> eliminarHerramienta({required int herramientaId}) async {
    final resp = await _client.delete('$_herramientasBase/$herramientaId');

    if (resp.statusCode != 204 && resp.statusCode != 200) {
      throw Exception(
        'Error al eliminar herramienta: ${resp.statusCode} ${resp.body}',
      );
    }
  }

  // ==========================================================
  // 2) STOCK POR CONJUNTO - /herramientas/conjunto/:nit/stock
  // ==========================================================

  /// GET /herramientas/conjunto/:nit/stock?estado=
  Future<List<dynamic>> listarStockConjunto({
    required String nitConjunto,
    String? estado, // OPERATIVA | DANADA | PERDIDA | BAJA
  }) async {
    final qp = <String, String>{
      if (estado != null && estado.trim().isNotEmpty) "estado": estado.trim(),
    };

    final uri = Uri.parse(
      '${AppConstants.baseUrl}$_herramientasBase/conjunto/$nitConjunto/stock',
    ).replace(queryParameters: qp.isEmpty ? null : qp);

    final resp = await _client.get(uri.toString());

    if (resp.statusCode != 200) {
      throw Exception('Error al listar stock: ${resp.statusCode} ${resp.body}');
    }

    final decoded = jsonDecode(resp.body);

    // tu backend puede devolver List o {data:[]}
    if (decoded is List) return decoded;
    if (decoded is Map && decoded['data'] is List)
      return decoded['data'] as List;

    throw Exception('Respuesta inesperada del backend en listarStockConjunto');
  }

  /// POST /herramientas/conjunto/:nit/stock
  /// body: { herramientaId, cantidad, estado? }
  Future<Map<String, dynamic>> upsertStockConjunto({
    required String nitConjunto,
    required int herramientaId,
    required num cantidad,
    String estado = "OPERATIVA",
  }) async {
    final body = {
      "herramientaId": herramientaId,
      "cantidad": cantidad,
      "estado": estado,
    };

    final resp = await _client.post(
      '$_herramientasBase/conjunto/$nitConjunto/stock',
      body: body,
    );

    if (resp.statusCode != 201 && resp.statusCode != 200) {
      throw Exception('Error al upsert stock: ${resp.statusCode} ${resp.body}');
    }

    final Map<String, dynamic> data = jsonDecode(resp.body);
    return data;
  }

  /// PATCH /herramientas/conjunto/:nit/stock/:herramientaId/ajustar
  /// body: { delta, estado? }
  Future<Map<String, dynamic>> ajustarStockConjunto({
    required String nitConjunto,
    required int herramientaId,
    required num delta,
    String estado = "OPERATIVA",
  }) async {
    final body = {"delta": delta, "estado": estado};

    final resp = await _client.patch(
      '$_herramientasBase/conjunto/$nitConjunto/stock/$herramientaId/ajustar',
      body: body,
    );

    if (resp.statusCode != 200) {
      throw Exception(
        'Error al ajustar stock: ${resp.statusCode} ${resp.body}',
      );
    }

    final Map<String, dynamic> data = jsonDecode(resp.body);
    return data;
  }

  /// DELETE /herramientas/conjunto/:nit/stock/:herramientaId?estado=
  Future<void> eliminarStockConjunto({
    required String nitConjunto,
    required int herramientaId,
    String estado = "OPERATIVA",
  }) async {
    final uri = Uri.parse(
      '${AppConstants.baseUrl}$_herramientasBase/conjunto/$nitConjunto/stock/$herramientaId',
    ).replace(queryParameters: {"estado": estado});

    final resp = await _client.delete(uri.toString());

    if (resp.statusCode != 204 && resp.statusCode != 200) {
      throw Exception(
        'Error al eliminar stock: ${resp.statusCode} ${resp.body}',
      );
    }
  }

  // ==========================================================
  // 3) SOLICITUDES - /solicitudes-herramientas
  // ==========================================================

  /// POST /solicitudes-herramientas
  /// body: { conjuntoId, empresaId?, items:[{herramientaId,cantidad}] }
  Future<Map<String, dynamic>> crearSolicitudHerramientas({
    required String conjuntoId,
    String? empresaId,
    required List<Map<String, dynamic>> items,
  }) async {
    final body = {
      "conjuntoId": conjuntoId,
      "empresaId": empresaId,
      "items": items,
    };

    final resp = await _client.post(_solicitudesHerramientasBase, body: body);

    if (resp.statusCode != 201 && resp.statusCode != 200) {
      throw Exception(
        'Error al crear solicitud herramientas: ${resp.statusCode} ${resp.body}',
      );
    }

    final Map<String, dynamic> data = jsonDecode(resp.body);
    return data;
  }

  /// GET /solicitudes-herramientas?conjuntoId=&empresaId=&estado=
  Future<List<dynamic>> listarSolicitudesHerramientas({
    String? conjuntoId,
    String? empresaId,
    String? estado, // PENDIENTE | APROBADA | RECHAZADA
  }) async {
    final qp = <String, String>{
      if (conjuntoId != null && conjuntoId.trim().isNotEmpty)
        "conjuntoId": conjuntoId.trim(),
      if (empresaId != null && empresaId.trim().isNotEmpty)
        "empresaId": empresaId.trim(),
      if (estado != null && estado.trim().isNotEmpty) "estado": estado.trim(),
    };

    final uri = Uri.parse(
      '${AppConstants.baseUrl}$_solicitudesHerramientasBase',
    ).replace(queryParameters: qp.isEmpty ? null : qp);

    final resp = await _client.get(uri.toString());

    if (resp.statusCode != 200) {
      throw Exception(
        'Error al listar solicitudes herramientas: ${resp.statusCode} ${resp.body}',
      );
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is List) return decoded;
    if (decoded is Map && decoded['data'] is List)
      return decoded['data'] as List;

    throw Exception(
      'Respuesta inesperada del backend en listarSolicitudesHerramientas',
    );
  }

  /// GET /solicitudes-herramientas/:id
  Future<Map<String, dynamic>> obtenerSolicitudHerramientas({
    required int solicitudId,
  }) async {
    final resp = await _client.get(
      '$_solicitudesHerramientasBase/$solicitudId',
    );

    if (resp.statusCode != 200) {
      throw Exception(
        'Error al obtener solicitud herramientas: ${resp.statusCode} ${resp.body}',
      );
    }

    final Map<String, dynamic> data = jsonDecode(resp.body);
    return data;
  }

  /// PATCH /solicitudes-herramientas/:id/estado
  /// body: { estado, observacionRespuesta? }
  Future<Map<String, dynamic>> cambiarEstadoSolicitudHerramientas({
    required int solicitudId,
    required String estado, // PENDIENTE | APROBADA | RECHAZADA
    String? observacionRespuesta,
  }) async {
    final body = {
      "estado": estado,
      "observacionRespuesta": observacionRespuesta,
    };

    final resp = await _client.patch(
      '$_solicitudesHerramientasBase/$solicitudId/estado',
      body: body,
    );

    if (resp.statusCode != 200) {
      throw Exception(
        'Error al cambiar estado solicitud herramientas: ${resp.statusCode} ${resp.body}',
      );
    }

    final Map<String, dynamic> data = jsonDecode(resp.body);
    return data;
  }
}
