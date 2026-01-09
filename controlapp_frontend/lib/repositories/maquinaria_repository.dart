// lib/repositories/maquinaria_repository.dart

import 'dart:convert';

import '../service/api_client.dart';
import '../service/app_constants.dart';
import '../model/maquinaria_model.dart';

class MaquinariaRepository {
  final ApiClient _apiClient = ApiClient();

  /// 🏗️ Asignar maquinaria a conjunto (POST /maquinarias/:id/asignar)
  Future<MaquinariaResponse> asignarAConjunto({
    required int maquinariaId,
    required String conjuntoId,
    int? responsableId,
    int? diasPrestamo,
  }) async {
    final body = <String, dynamic>{
      'conjuntoId': conjuntoId,
      if (responsableId != null) 'responsableId': responsableId,
      if (diasPrestamo != null) 'diasPrestamo': diasPrestamo,
    };

    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/maquinarias/$maquinariaId/asignar',
      body: body,
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return MaquinariaResponse.fromJson(json);
    } else {
      throw Exception(
        'Error al asignar maquinaria: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// 🔄 Devolver maquinaria (POST /maquinarias/:id/devolver)
  Future<MaquinariaResponse> devolver(int maquinariaId) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/maquinarias/$maquinariaId/devolver',
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return MaquinariaResponse.fromJson(json);
    } else {
      throw Exception(
        'Error al devolver maquinaria: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// ✅ Verificar disponibilidad (GET /maquinarias/:id/disponible)
  Future<bool> estaDisponible(int maquinariaId) async {
    final response = await _apiClient.get(
      '${AppConstants.baseUrl}/maquinarias/$maquinariaId/disponible',
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (data['disponible'] as bool?) ?? false;
    } else {
      throw Exception(
        'Error al verificar disponibilidad: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// 👷 Obtener responsable (GET /maquinarias/:id/responsable)
  Future<Map<String, dynamic>?> obtenerResponsable(int maquinariaId) async {
    final response = await _apiClient.get(
      '${AppConstants.baseUrl}/maquinarias/$maquinariaId/responsable',
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      // asumiendo que el backend devuelve { responsable: { ... } }
      return data['responsable'] as Map<String, dynamic>?;
    } else if (response.statusCode == 404) {
      // sin responsable
      return null;
    } else {
      throw Exception(
        'Error al obtener responsable de la maquinaria: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// 📊 Resumen del estado (GET /maquinarias/:id/resumen)
  Future<String?> resumenEstado(int maquinariaId) async {
    final response = await _apiClient.get(
      '${AppConstants.baseUrl}/maquinarias/$maquinariaId/resumen',
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['resumen'] as String?;
    } else if (response.statusCode == 404) {
      return null;
    } else {
      throw Exception(
        'Error al obtener resumen del estado: ${response.statusCode} ${response.body}',
      );
    }
  }
}
