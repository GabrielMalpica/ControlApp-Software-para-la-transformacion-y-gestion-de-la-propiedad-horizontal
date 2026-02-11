// lib/api/reporte_api.dart
import 'dart:convert';

import 'package:flutter_application_1/model/reporte_model.dart';
import 'package:flutter_application_1/service/api_client.dart';
import 'package:flutter_application_1/service/app_constants.dart';

class ReporteApi {
  final ApiClient _client = ApiClient();

  String get _base => AppConstants.reportesBase;

  String _qs(Map<String, String?> p) {
    final m = <String, String>{};
    p.forEach((k, v) {
      if (v != null && v.trim().isNotEmpty) m[k] = v.trim();
    });
    final uri = Uri(queryParameters: m);
    final q = uri.query;
    return q.isEmpty ? '' : '?$q';
  }

  Future<Map<String, dynamic>> _getJson(
    String path,
    Map<String, String?> query,
  ) async {
    final resp = await _client.get('$_base$path${_qs(query)}');
    if (resp.statusCode != 200) {
      throw Exception('Error ${resp.statusCode}: ${resp.body}');
    }
    if (resp.body.isEmpty) return {};
    final decoded = jsonDecode(resp.body);
    if (decoded is Map<String, dynamic>) return decoded;
    // cuando el backend devuelve {ok:true, data:[...]} o lista directa
    if (decoded is Map) return decoded.cast<String, dynamic>();
    return {'data': decoded};
  }

  Future<List<dynamic>> _getList(
    String path,
    Map<String, String?> query,
  ) async {
    final resp = await _client.get('$_base$path${_qs(query)}');
    if (resp.statusCode != 200) {
      throw Exception('Error ${resp.statusCode}: ${resp.body}');
    }
    if (resp.body.isEmpty) return [];
    final decoded = jsonDecode(resp.body);
    if (decoded is List) return decoded;
    if (decoded is Map && decoded['data'] is List)
      return decoded['data'] as List;
    return [];
  }

  Future<ReporteKpis> kpis({
    required DateTime desde,
    required DateTime hasta,
    String? conjuntoId,
  }) async {
    final j = await _getJson('/kpis', {
      'desde': desde.toIso8601String(),
      'hasta': hasta.toIso8601String(),
      'conjuntoId': conjuntoId,
    });
    return ReporteKpis.fromJson(j);
  }

  Future<SerieDiariaPorEstado> serieDiaria({
    required DateTime desde,
    required DateTime hasta,
    String? conjuntoId,
  }) async {
    final j = await _getJson('/serie-diaria', {
      'desde': desde.toIso8601String(),
      'hasta': hasta.toIso8601String(),
      'conjuntoId': conjuntoId,
    });
    return SerieDiariaPorEstado.fromJson(j);
  }

  Future<List<ResumenConjuntoRow>> resumenPorConjunto({
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final list = await _getList('/por-conjunto', {
      'desde': desde.toIso8601String(),
      'hasta': hasta.toIso8601String(),
    });

    return list
        .map(
          (e) =>
              ResumenConjuntoRow.fromJson((e as Map).cast<String, dynamic>()),
        )
        .toList();
  }

  Future<List<ResumenOperarioRow>> resumenPorOperario({
    required DateTime desde,
    required DateTime hasta,
    String? conjuntoId,
  }) async {
    final j = await _getJson('/por-operario', {
      'desde': desde.toIso8601String(),
      'hasta': hasta.toIso8601String(),
      'conjuntoId': conjuntoId,
    });

    final data = (j['data'] is List) ? (j['data'] as List) : <dynamic>[];
    return data
        .map(
          (e) =>
              ResumenOperarioRow.fromJson((e as Map).cast<String, dynamic>()),
        )
        .toList();
  }

  Future<List<InsumoUsoRow>> usoInsumos({
    required String conjuntoId,
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final j = await _getJson('/insumos/uso', {
      'conjuntoId': conjuntoId,
      'desde': desde.toIso8601String(),
      'hasta': hasta.toIso8601String(),
    });

    final data = (j['data'] is List) ? (j['data'] as List) : <dynamic>[];
    return data
        .map((e) => InsumoUsoRow.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<List<UsoEquipoRow>> topMaquinaria({
    required DateTime desde,
    required DateTime hasta,
    String? conjuntoId,
  }) async {
    final j = await _getJson('/maquinaria/top', {
      'desde': desde.toIso8601String(),
      'hasta': hasta.toIso8601String(),
      'conjuntoId': conjuntoId,
    });

    final data = (j['data'] is List) ? (j['data'] as List) : <dynamic>[];
    return data
        .map(
          (e) => UsoEquipoRow.fromJson(
            (e as Map).cast<String, dynamic>(),
            idKey: 'maquinariaId',
          ),
        )
        .toList();
  }

  Future<List<UsoEquipoRow>> topHerramientas({
    required DateTime desde,
    required DateTime hasta,
    String? conjuntoId,
  }) async {
    final j = await _getJson('/herramientas/top', {
      'desde': desde.toIso8601String(),
      'hasta': hasta.toIso8601String(),
      'conjuntoId': conjuntoId,
    });

    final data = (j['data'] is List) ? (j['data'] as List) : <dynamic>[];
    return data
        .map(
          (e) => UsoEquipoRow.fromJson(
            (e as Map).cast<String, dynamic>(),
            idKey: 'herramientaId',
          ),
        )
        .toList();
  }

  Future<List<PdfDatasetRow>> datasetPdf({
    required DateTime desde,
    required DateTime hasta,
    String? conjuntoId,
  }) async {
    final j = await _getJson('/mensual-detalle', {
      'desde': desde.toIso8601String(),
      'hasta': hasta.toIso8601String(),
      'conjuntoId': conjuntoId,
    });

    final data = (j['data'] is List) ? (j['data'] as List) : <dynamic>[];
    return data
        .map((e) => PdfDatasetRow.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<List<TareaDetalleRow>> mensualDetalle({
    required DateTime desde,
    required DateTime hasta,
    String? conjuntoId,
  }) async {
    final j = await _getJson('/mensual-detalle', {
      'desde': desde.toIso8601String(),
      'hasta': hasta.toIso8601String(),
      'conjuntoId': conjuntoId,
    });

    final data = (j['data'] is List) ? (j['data'] as List) : <dynamic>[];
    return data
        .map(
          (e) => TareaDetalleRow.fromJson((e as Map).cast<String, dynamic>()),
        )
        .toList();
  }
}
