// agenda_api.dart
import 'dart:convert';
import 'package:flutter_application_1/model/agenda_maquinaria_model.dart';
import 'package:flutter_application_1/model/agenda_model.dart';
import 'package:flutter_application_1/service/api_client.dart';
import 'package:flutter_application_1/service/app_constants.dart';

class AgendaApi {
  final ApiClient _client = ApiClient();

  Future<AgendaMaquinaria?> obtenerAgenda({
    required String conjuntoId,
    required int maquinariaId,
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final cid = Uri.encodeComponent(conjuntoId);
    final qDesde = Uri.encodeComponent(desde.toIso8601String());
    final qHasta = Uri.encodeComponent(hasta.toIso8601String());

    final resp = await _client.get(
      '/maquinarias/$maquinariaId/agenda/$cid?desde=$qDesde&hasta=$qHasta',
    );

    if (resp.statusCode != 200) {
      throw Exception('Error al obtener agenda: ${resp.body}');
    }

    final decoded = jsonDecode(resp.body);

    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      if (data is Map<String, dynamic>) {
        return AgendaMaquinaria.fromJson(data);
      }
    }

    return null;
  }

  Future<AgendaGlobalResponse> agendaGlobalMaquinaria({
    required String empresaNit,
    required int anio,
    required int mes,
    String? tipo,
  }) async {
    final uri =
        Uri.parse(
          '${AppConstants.baseUrl}/agenda/empresa/$empresaNit/maquinaria',
        ).replace(
          queryParameters: {
            'anio': anio.toString(),
            'mes': mes.toString(),
            if (tipo != null && tipo.isNotEmpty) 'tipo': tipo,
          },
        );

    final resp = await _client.get(uri.toString());
    if (resp.statusCode != 200) {
      throw Exception('Error agenda global: ${resp.statusCode} ${resp.body}');
    }
    return AgendaGlobalResponse.fromJson(jsonDecode(resp.body));
  }
}
