import 'dart:convert';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/service/api_client.dart';
import 'package:flutter_application_1/service/app_constants.dart';

class AdministradorApi {
  final ApiClient _client = ApiClient();

  Future<List<Conjunto>> listarMisConjuntos(String adminId) async {
    final resp = await _client.get(
      '${AppConstants.administradorBase}/$adminId/conjuntos',
    );

    if (resp.statusCode != 200) {
      throw Exception(
        'Error listando conjuntos del administrador: ${resp.body}',
      );
    }

    final List<dynamic> data = jsonDecode(resp.body) as List<dynamic>;
    return data.map((e) {
      final raw = Map<String, dynamic>.from(e as Map);
      return Conjunto.fromJson({
        'nit': raw['nit'] ?? '',
        'nombre': raw['nombre'] ?? 'Sin nombre',
        'direccion': raw['direccion'] ?? '',
        'correo': raw['correo'] ?? '',
        'activo': raw['activo'] ?? true,
        'tipoServicio': raw['tipoServicio'] ?? const <dynamic>[],
        'consignasEspeciales': raw['consignasEspeciales'] ?? const <dynamic>[],
        'valorAgregado': raw['valorAgregado'] ?? const <dynamic>[],
        ...raw,
      });
    }).toList();
  }

  Future<List<Map<String, dynamic>>> listarPqrsConjunto({
    required String adminId,
    required String conjuntoId,
  }) async {
    final resp = await _client.get(
      '${AppConstants.administradorBase}/$adminId/conjuntos/$conjuntoId/compromisos',
    );

    if (resp.statusCode != 200) {
      throw Exception('Error listando PQRS: ${resp.body}');
    }

    final data = jsonDecode(resp.body) as List<dynamic>;
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> crearPqrsConjunto({
    required String adminId,
    required String conjuntoId,
    required String titulo,
  }) async {
    final resp = await _client.post(
      '${AppConstants.administradorBase}/$adminId/conjuntos/$conjuntoId/compromisos',
      body: {'titulo': titulo},
    );

    if (resp.statusCode != 201 && resp.statusCode != 200) {
      throw Exception('Error creando PQRS: ${resp.body}');
    }

    return Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
  }
}
