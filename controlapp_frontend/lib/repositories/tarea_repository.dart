// lib/repositories/tarea_repository.dart

import 'dart:convert';
import '../service/api_client.dart';
import '../service/app_constants.dart';
import '../model/tarea_model.dart';

class TareaRepository {
  final ApiClient _apiClient = ApiClient();

  /// Crear tarea
  Future<void> crearTarea(CrearTareaDTO dto) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/tareas',
      body: dto.toJson(),
    );
    if (response.statusCode != 201) {
      throw Exception('Error al crear tarea');
    }
  }

  /// Agregar evidencia a una tarea
  Future<void> agregarEvidencia(int tareaId, String imagen) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/tareas/$tareaId/evidencias',
      body: {'imagen': imagen},
    );
    if (response.statusCode != 204) {
      throw Exception('Error al agregar evidencia');
    }
  }

  /// Iniciar tarea
  Future<void> iniciarTarea(int tareaId) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/tareas/$tareaId/iniciar',
    );
    if (response.statusCode != 204) {
      throw Exception('Error al iniciar tarea');
    }
  }

  /// Marcar tarea como no completada
  Future<void> marcarNoCompletada(int tareaId) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/tareas/$tareaId/no-completada',
    );
    if (response.statusCode != 204) {
      throw Exception('Error al marcar tarea no completada');
    }
  }

  /// Completar tarea con insumos usados
  Future<void> completarConInsumos(
    int tareaId,
    List<InsumoUsadoItem> insumosUsados,
  ) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/tareas/$tareaId/completar',
      body: {'insumosUsados': insumosUsados.map((e) => e.toJson()).toList()},
    );
    if (response.statusCode != 204) {
      throw Exception('Error al completar tarea');
    }
  }

  /// Aprobar tarea por supervisor
  Future<void> aprobarTarea(int tareaId, int supervisorId) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/tareas/$tareaId/aprobar',
      body: {'supervisorId': supervisorId},
    );
    if (response.statusCode != 204) {
      throw Exception('Error al aprobar tarea');
    }
  }

  /// Rechazar tarea
  Future<void> rechazarTarea(int tareaId, int supervisorId, String observacion) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/tareas/$tareaId/rechazar',
      body: {
        'supervisorId': supervisorId,
        'observacion': observacion,
      },
    );
    if (response.statusCode != 204) {
      throw Exception('Error al rechazar tarea');
    }
  }

  /// Obtener resumen de tarea
  Future<String> obtenerResumen(int tareaId) async {
    final response = await _apiClient.get(
      '${AppConstants.baseUrl}/tareas/$tareaId/resumen',
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['resumen'] ?? '';
    } else {
      throw Exception('Error al obtener resumen de tarea');
    }
  }
}
