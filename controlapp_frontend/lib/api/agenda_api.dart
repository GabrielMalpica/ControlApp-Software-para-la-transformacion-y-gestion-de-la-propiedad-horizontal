// agenda_api.dart
import 'dart:convert';
import 'package:flutter_application_1/model/agenda_herramienta_model.dart';
import 'package:flutter_application_1/model/agenda_maquinaria_model.dart';
import 'package:flutter_application_1/model/agenda_model.dart';
import 'package:flutter_application_1/service/api_client.dart';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:flutter_application_1/service/session_service.dart';

class AgendaApi {
  final ApiClient _client = ApiClient();
  final SessionService _session = SessionService();

  Future<String> _resolverEmpresaId(String empresaNit) async {
    final recibido = empresaNit.trim();
    if (recibido.isNotEmpty) return recibido;

    final sesion = (await _session.getEmpresaId())?.trim() ?? '';
    if (sesion.isNotEmpty) return sesion;

    throw StateError(
      'No se pudo identificar la empresa de la sesion. Vuelve a iniciar sesion.',
    );
  }

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
    final empresaId = await _resolverEmpresaId(empresaNit);
    final uri =
        Uri.parse(
          '${AppConstants.baseUrl}/agenda/empresa/${Uri.encodeComponent(empresaId)}/maquinaria',
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

  Future<AgendaGlobalResponse> agendaMaquinariaConjunto({
    required String conjuntoId,
    required int anio,
    required int mes,
    String? tipo,
  }) async {
    final uri =
        Uri.parse(
          '${AppConstants.baseUrl}/agenda/conjunto/${Uri.encodeComponent(conjuntoId.trim())}/maquinaria',
        ).replace(
          queryParameters: {
            'anio': anio.toString(),
            'mes': mes.toString(),
            if (tipo != null && tipo.isNotEmpty) 'tipo': tipo,
          },
        );

    final resp = await _client.get(uri.toString());
    if (resp.statusCode != 200) {
      throw Exception(
        'Error agenda de maquinaria: ${resp.statusCode} ${resp.body}',
      );
    }
    return AgendaGlobalResponse.fromJson(jsonDecode(resp.body));
  }

  Future<AgendaHerramientaResponse> agendaGlobalHerramientas({
    required String empresaNit,
    required int anio,
    required int mes,
    String? categoria,
  }) async {
    final empresaId = await _resolverEmpresaId(empresaNit);
    final uri =
        Uri.parse(
          '${AppConstants.baseUrl}/agenda/empresa/${Uri.encodeComponent(empresaId)}/herramientas',
        ).replace(
          queryParameters: {
            'anio': anio.toString(),
            'mes': mes.toString(),
            if (categoria != null && categoria.isNotEmpty)
              'categoria': categoria,
          },
        );

    final resp = await _client.get(uri.toString());
    if (resp.statusCode != 200) {
      throw Exception(
        'Error agenda herramientas: ${resp.statusCode} ${resp.body}',
      );
    }
    return AgendaHerramientaResponse.fromJson(jsonDecode(resp.body));
  }

  Future<AgendaHerramientaResponse> agendaHerramientasConjunto({
    required String conjuntoId,
    required int anio,
    required int mes,
    String? categoria,
  }) async {
    final uri =
        Uri.parse(
          '${AppConstants.baseUrl}/agenda/conjunto/${Uri.encodeComponent(conjuntoId.trim())}/herramientas',
        ).replace(
          queryParameters: {
            'anio': anio.toString(),
            'mes': mes.toString(),
            if (categoria != null && categoria.isNotEmpty)
              'categoria': categoria,
          },
        );

    final resp = await _client.get(uri.toString());
    if (resp.statusCode != 200) {
      throw Exception(
        'Error agenda de herramientas: ${resp.statusCode} ${resp.body}',
      );
    }
    return AgendaHerramientaResponse.fromJson(jsonDecode(resp.body));
  }
}
