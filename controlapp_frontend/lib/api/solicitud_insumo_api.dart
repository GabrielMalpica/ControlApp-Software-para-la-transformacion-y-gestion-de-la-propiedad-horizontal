import 'dart:convert';
import 'package:http/http.dart' as http;

import '../model/solicitud_insumo_model.dart';

class SolicitudInsumoItemResponse {
  final int insumoId;
  final num cantidad;

  final String? nombre;
  final String? unidad;

  SolicitudInsumoItemResponse({
    required this.insumoId,
    required this.cantidad,
    this.nombre,
    this.unidad,
  });

  static int _parseInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  static num _parseNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }

  factory SolicitudInsumoItemResponse.fromJson(Map<String, dynamic> json) {
    // Puede venir como { insumo: {nombre, unidad} } si hiciste include en backend
    final insumo = json['insumo'];

    return SolicitudInsumoItemResponse(
      insumoId: _parseInt(json['insumoId']),
      cantidad: _parseNum(json['cantidad']),
      nombre:
          (json['nombre'] as String?) ??
          (insumo is Map ? (insumo['nombre'] as String?) : null),
      unidad:
          (json['unidad'] as String?) ??
          (insumo is Map ? (insumo['unidad'] as String?) : null),
    );
  }
}

class SolicitudInsumoResponse {
  final int id;
  final String conjuntoId;
  final String? empresaId;
  final bool aprobado;
  final DateTime? fechaSolicitud;
  final DateTime? fechaAprobacion;
  final List<SolicitudInsumoItemResponse> items;

  SolicitudInsumoResponse({
    required this.id,
    required this.conjuntoId,
    required this.aprobado,
    required this.items,
    this.empresaId,
    this.fechaSolicitud,
    this.fechaAprobacion,
  });

  static int _parseInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  static bool _parseBool(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    final s = v.toString().toLowerCase().trim();
    return s == 'true' || s == '1' || s == 'si' || s == 'sí';
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  factory SolicitudInsumoResponse.fromJson(Map<String, dynamic> json) {
    // En Prisma se llama "insumosSolicitados"
    final raw = json['insumosSolicitados'];
    final List rawItems = (raw is List) ? raw : const [];

    return SolicitudInsumoResponse(
      id: _parseInt(json['id']),
      conjuntoId: (json['conjuntoId'] ?? '').toString(),
      empresaId: json['empresaId'] as String?,
      aprobado: _parseBool(json['aprobado']),
      fechaSolicitud: _parseDate(json['fechaSolicitud']),
      fechaAprobacion: _parseDate(json['fechaAprobacion']),
      items: rawItems
          .whereType<Map<String, dynamic>>() // evita nulls
          .map((e) => SolicitudInsumoItemResponse.fromJson(e))
          .toList(),
    );
  }
}

class SolicitudInsumoApi {
  final String baseUrl;
  final String? authToken;

  SolicitudInsumoApi({required this.baseUrl, this.authToken});

  Map<String, String> _headers() => {
    'Content-Type': 'application/json',
    if (authToken != null) 'Authorization': 'Bearer $authToken',
  };

  Uri _uri(String path, [Map<String, String>? q]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: q);

  Future<List<SolicitudInsumoResponse>> listar({
    String? conjuntoId,
    bool? aprobado,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
  }) async {
    final q = <String, String>{};
    if (conjuntoId != null && conjuntoId.isNotEmpty)
      q['conjuntoId'] = conjuntoId;
    if (aprobado != null) q['aprobado'] = aprobado.toString();
    if (fechaDesde != null) q['fechaDesde'] = fechaDesde.toIso8601String();
    if (fechaHasta != null) q['fechaHasta'] = fechaHasta.toIso8601String();

    final resp = await http.get(
      _uri('/solicitud-insumo', q.isEmpty ? null : q),
      headers: _headers(),
    );

    if (resp.statusCode != 200) {
      throw Exception('Error al listar solicitudes insumo: ${resp.body}');
    }

    final decoded = jsonDecode(resp.body);
    final List data = (decoded is List) ? decoded : const [];

    return data
        .whereType<Map<String, dynamic>>() // evita nulls
        .map((e) => SolicitudInsumoResponse.fromJson(e))
        .toList();
  }

  Future<void> crearSolicitud(SolicitudInsumoRequest request) async {
    final resp = await http.post(
      _uri('/solicitud-insumo'),
      headers: _headers(),
      body: jsonEncode(request.toJson()),
    );

    if (resp.statusCode != 201) {
      throw Exception('Error al crear solicitud: ${resp.body}');
    }
  }

  Future<SolicitudInsumoResponse> obtener(int id) async {
    final resp = await http.get(
      _uri('/solicitud-insumo/$id'),
      headers: _headers(),
    );

    if (resp.statusCode != 200) {
      throw Exception('Error al obtener solicitud insumo: ${resp.body}');
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Respuesta inválida del servidor');
    }
    return SolicitudInsumoResponse.fromJson(decoded);
  }

  Future<SolicitudInsumoResponse> aprobar(
    int id, {
    DateTime? fechaAprobacion,
  }) async {
    final body = <String, dynamic>{};
    if (fechaAprobacion != null) {
      body['fechaAprobacion'] = fechaAprobacion.toIso8601String();
    }

    final resp = await http.post(
      _uri('/solicitud-insumo/$id/aprobar'),
      headers: _headers(),
      body: jsonEncode(body),
    );

    if (resp.statusCode != 200) {
      throw Exception('Error al aprobar solicitud insumo: ${resp.body}');
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Respuesta inválida del servidor');
    }
    return SolicitudInsumoResponse.fromJson(decoded);
  }

  Future<void> rechazar(int id) async {
    final resp = await http.delete(
      _uri('/solicitud-insumo/$id'),
      headers: _headers(),
    );

    if (resp.statusCode != 204) {
      throw Exception(
        'Error al rechazar/eliminar solicitud insumo: ${resp.body}',
      );
    }
  }
}
