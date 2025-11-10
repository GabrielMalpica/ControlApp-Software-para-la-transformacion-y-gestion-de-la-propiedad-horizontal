// lib/repositories/supervisor_repository.dart

import 'dart:convert';
import '../service/api_client.dart';
import '../service/app_constants.dart';
import '../model/supervisor_model.dart';

class SupervisorRepository {
  final ApiClient _apiClient = ApiClient();

  /// Crear un nuevo supervisor
  Future<void> crearSupervisor(CrearSupervisorDTO dto) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/supervisores',
      body: dto.toJson(),
    );

    if (response.statusCode != 201) {
      throw Exception('Error al crear supervisor');
    }
  }

  /// Editar supervisor existente
  Future<void> editarSupervisor(int supervisorId, EditarSupervisorDTO dto) async {
    final response = await _apiClient.put(
      '${AppConstants.baseUrl}/supervisores/$supervisorId',
      body: dto.toJson(),
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Error al editar supervisor');
    }
  }

  /// Supervisor recibe una tarea finalizada
  Future<void> recibirTareaFinalizada(int supervisorId, int tareaId) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/supervisores/$supervisorId/tareas/$tareaId/recibir',
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Error al recibir tarea finalizada');
    }
  }

  /// Supervisor aprueba una tarea
  Future<void> aprobarTarea(int supervisorId, int tareaId) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/supervisores/$supervisorId/tareas/$tareaId/aprobar',
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Error al aprobar tarea');
    }
  }

  /// Supervisor rechaza una tarea
  Future<void> rechazarTarea(
    int supervisorId,
    int tareaId, {
    required String observaciones,
  }) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/supervisores/$supervisorId/tareas/$tareaId/rechazar',
      body: {'observaciones': observaciones},
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Error al rechazar tarea');
    }
  }

  /// Listar tareas pendientes del supervisor
  Future<List<Map<String, dynamic>>> listarTareasPendientes(int supervisorId) async {
    final response = await _apiClient.get(
      '${AppConstants.baseUrl}/supervisores/$supervisorId/tareas/pendientes',
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data);
    } else {
      throw Exception('Error al listar tareas pendientes');
    }
  }
}
