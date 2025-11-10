// lib/repository/gerente_repository.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../model/gerente_model.dart';
import '../../service/api_client.dart';
import '../../service/app_constants.dart';

class GerenteRepository {
  final ApiClient _apiClient = ApiClient();

  /// Obtener todos los gerentes
  Future<List<GerenteModel>> getGerentes() async {
    final response = await _apiClient.get('${AppConstants.baseUrl}/gerentes');

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((e) => GerenteModel.fromJson(e)).toList();
    } else {
      throw Exception('Error al obtener la lista de gerentes');
    }
  }

  /// Obtener un gerente por ID
  Future<GerenteModel> getGerenteById(int id) async {
    final response = await _apiClient.get('${AppConstants.baseUrl}/gerentes/$id');

    if (response.statusCode == 200) {
      return GerenteModel.fromJson(json.decode(response.body));
    } else {
      throw Exception('Error al obtener el gerente con ID $id');
    }
  }

  /// Crear un nuevo gerente
  Future<void> crearGerente(GerenteModel gerente) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/gerentes',
      body: gerente.toJson(),
    );

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('Error al crear el gerente');
    }
  }

  /// Editar un gerente existente (empresaId opcional)
  Future<void> editarGerente(int id, {String? empresaId}) async {
    final Map<String, dynamic> body = {
      'empresaId': empresaId,
    };

    final response = await _apiClient.put(
      '${AppConstants.baseUrl}/gerentes/$id',
      body: body,
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Error al editar el gerente');
    }
  }

  /// Eliminar un gerente por ID
  Future<void> eliminarGerente(int id) async {
    final response = await _apiClient.delete('${AppConstants.baseUrl}/gerentes/$id');

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Error al eliminar el gerente');
    }
  }
}
