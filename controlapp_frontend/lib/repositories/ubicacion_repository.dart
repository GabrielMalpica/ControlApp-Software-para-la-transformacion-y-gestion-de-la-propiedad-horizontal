// lib/repositories/ubicacion_repository.dart
import 'dart:convert';
import '../service/app_constants.dart';
import '../service/api_client.dart';

class UbicacionRepository {
  final ApiClient _apiClient = ApiClient();
  final String baseUrl = AppConstants.ubicaciones;

  Future<void> agregarElemento({
    required int ubicacionId,
    required String nombre,
  }) async {
    final response = await _apiClient.post(
      '$baseUrl/$ubicacionId/elementos',
      body: {'nombre': nombre},
    );

    if (response.statusCode != 201) {
      throw Exception('Error al agregar elemento: ${response.body}');
    }
  }

  Future<List<Map<String, dynamic>>> listarElementos(int ubicacionId) async {
    final response = await _apiClient.get('$baseUrl/$ubicacionId/elementos');

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data);
    } else {
      throw Exception('Error al listar elementos: ${response.body}');
    }
  }

  Future<Map<String, dynamic>?> buscarElementoPorNombre({
    required int ubicacionId,
    required String nombre,
  }) async {
    final response = await _apiClient.get(
      '$baseUrl/$ubicacionId/elementos/buscar?nombre=$nombre',
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else if (response.statusCode == 404) {
      return null;
    } else {
      throw Exception('Error al buscar elemento: ${response.body}');
    }
  }
}
