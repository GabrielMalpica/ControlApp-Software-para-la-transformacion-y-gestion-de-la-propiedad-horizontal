// lib/repositories/conjunto_repository.dart
import 'dart:convert';
import '../service/api_client.dart';
import '../service/app_constants.dart';

class ConjuntoRepository {
  final ApiClient _apiClient = ApiClient();

  Future<List<dynamic>> getOperarios(String nit) async {
    final res = await _apiClient.get(AppConstants.operariosPorConjunto(nit));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      // Si tu backend devuelve { "operarios": [...] }
      return data is Map && data['operarios'] != null
          ? List<dynamic>.from(data['operarios'])
          : List<dynamic>.from(data);
    }
    throw Exception('Error al obtener operarios');
  }

  Future<Map<String, dynamic>?> getAdministrador(String nit) async {
    final res = await _apiClient.get(AppConstants.administradorPorConjunto(nit));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return data is Map && data['administrador'] != null
          ? Map<String, dynamic>.from(data['administrador'])
          : Map<String, dynamic>.from(data);
    }
    throw Exception('Error al obtener administrador');
  }

  Future<List<dynamic>> getMaquinaria(String nit) async {
    final res = await _apiClient.get(AppConstants.maquinariaPorConjunto(nit));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return data is List ? data : List<dynamic>.from(data);
    }
    throw Exception('Error al obtener maquinaria');
  }

  Future<Map<String, dynamic>> getInventario(String nit) async {
    final res = await _apiClient.get(AppConstants.inventarioPorConjunto(nit));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return Map<String, dynamic>.from(data);
    }
    throw Exception('Error al obtener inventario');
  }
}
