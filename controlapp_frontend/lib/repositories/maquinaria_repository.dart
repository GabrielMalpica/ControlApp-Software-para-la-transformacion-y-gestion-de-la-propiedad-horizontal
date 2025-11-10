// lib/repositories/maquinaria_repository.dart

import 'dart:convert';
import '../service/api_client.dart';
import '../service/app_constants.dart';
import '../model/maquinaria_model.dart';

class MaquinariaRepository {
  final ApiClient _apiClient = ApiClient();

  /// 🔹 Listar todas las maquinarias (GET /maquinarias)
  Future<List<Maquinaria>> listar() async {
    final response = await _apiClient.get('${AppConstants.baseUrl}/maquinarias');
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((e) => Maquinaria.fromJson(e)).toList();
    } else {
      throw Exception('Error al listar maquinarias');
    }
  }

  /// ➕ Crear maquinaria (POST /maquinarias)
  Future<Maquinaria> crear(Map<String, dynamic> body) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/maquinarias',
      body: body,
    );

    if (response.statusCode == 201) {
      return Maquinaria.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Error al crear maquinaria');
    }
  }

  /// ✏️ Editar maquinaria (PATCH /maquinarias/:id)
  Future<Maquinaria> editar(int id, Map<String, dynamic> body) async {
    final response = await _apiClient.patch(
      '${AppConstants.baseUrl}/maquinarias/$id',
      body: body,
    );

    if (response.statusCode == 200) {
      return Maquinaria.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Error al editar maquinaria');
    }
  }

  /// 🏗️ Asignar maquinaria a conjunto (POST /maquinarias/:id/asignar)
  Future<Maquinaria> asignarAConjunto({
    required int maquinariaId,
    required String conjuntoId,
    int? responsableId,
    int? diasPrestamo,
  }) async {
    final body = {
      'conjuntoId': conjuntoId,
      if (responsableId != null) 'responsableId': responsableId,
      if (diasPrestamo != null) 'diasPrestamo': diasPrestamo,
    };

    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/maquinarias/$maquinariaId/asignar',
      body: body,
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      return Maquinaria.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Error al asignar maquinaria');
    }
  }

  /// 🔄 Devolver maquinaria (POST /maquinarias/:id/devolver)
  Future<Maquinaria> devolver(int maquinariaId) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/maquinarias/$maquinariaId/devolver',
    );

    if (response.statusCode == 200) {
      return Maquinaria.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Error al devolver maquinaria');
    }
  }

  /// ✅ Verificar disponibilidad (GET /maquinarias/:id/disponible)
  Future<bool> estaDisponible(int maquinariaId) async {
    final response = await _apiClient.get(
      '${AppConstants.baseUrl}/maquinarias/$maquinariaId/disponible',
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['disponible'] ?? false;
    } else {
      throw Exception('Error al verificar disponibilidad');
    }
  }

  /// 👷 Obtener responsable (GET /maquinarias/:id/responsable)
  Future<Map<String, dynamic>?> obtenerResponsable(int maquinariaId) async {
    final response = await _apiClient.get(
      '${AppConstants.baseUrl}/maquinarias/$maquinariaId/responsable',
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['responsable'];
    } else {
      throw Exception('Error al obtener responsable de la maquinaria');
    }
  }

  /// 📊 Resumen del estado (GET /maquinarias/:id/resumen)
  Future<Map<String, dynamic>?> resumenEstado(int maquinariaId) async {
    final response = await _apiClient.get(
      '${AppConstants.baseUrl}/maquinarias/$maquinariaId/resumen',
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['resumen'];
    } else {
      throw Exception('Error al obtener resumen del estado');
    }
  }
}
