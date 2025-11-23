// lib/repositories/operario_repository.dart
import 'dart:convert';
import '../service/api_client.dart';
import '../service/app_constants.dart';
import '../model/operario_model.dart';

class OperarioRepository {
  final ApiClient _apiClient = ApiClient();

  Future<List<OperarioModel>> listarTareas(int operarioId) async {
    final response = await _apiClient.get(
      '${AppConstants.baseUrl}/operarios/$operarioId/tareas',
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List;
      return data.map((e) => OperarioModel.fromJson(e)).toList();
    } else {
      throw Exception('Error al obtener las tareas del operario');
    }
  }


  Future<void> asignarTarea(int operarioId, int tareaId) async {
    final body = {'tareaId': tareaId};
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/operarios/$operarioId/tareas/asignar',
      body: body,
    );

    if (response.statusCode != 204) {
      throw Exception('Error al asignar tarea');
    }
  }

  Future<void> iniciarTarea(int operarioId, int tareaId) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/operarios/$operarioId/tareas/$tareaId/iniciar',
    );

    if (response.statusCode != 204) {
      throw Exception('Error al iniciar tarea');
    }
  }

  Future<void> marcarComoCompletada(
      int operarioId, int tareaId, List<String> evidencias) async {
    final body = {'tareaId': tareaId, 'evidencias': evidencias};
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/operarios/$operarioId/tareas/completar',
      body: body,
    );

    if (response.statusCode != 204) {
      throw Exception('Error al completar la tarea');
    }
  }

  Future<void> marcarComoNoCompletada(int operarioId, int tareaId) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/operarios/$operarioId/tareas/$tareaId/no-completada',
    );

    if (response.statusCode != 204) {
      throw Exception('Error al marcar tarea como no completada');
    }
  }

  Future<Map<String, dynamic>> horasRestantesEnSemana(
      int operarioId, DateTime fecha) async {
    final response = await _apiClient.get(
      '${AppConstants.baseUrl}/operarios/$operarioId/horas/restantes?fecha=${fecha.toIso8601String()}',
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Error al obtener horas restantes');
    }
  }

  Future<Map<String, dynamic>> resumenDeHoras(
      int operarioId, DateTime fecha) async {
    final response = await _apiClient.get(
      '${AppConstants.baseUrl}/operarios/$operarioId/horas/resumen?fecha=${fecha.toIso8601String()}',
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Error al obtener resumen de horas');
    }
  }
}
