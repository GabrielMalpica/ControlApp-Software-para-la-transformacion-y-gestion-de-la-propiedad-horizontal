// lib/repositories/solicitud_tarea_repository.dart

import 'dart:convert';
import '../service/api_client.dart';
import '../service/app_constants.dart';
import '../model/solicitud_tarea_model.dart';

class SolicitudTareaRepository {
  final ApiClient _apiClient = ApiClient();

  /// Crear nueva solicitud de tarea
  Future<void> crearSolicitud(SolicitudTareaModel solicitud) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/solicitudes-tarea',
      body: solicitud.toJson(),
    );

    if (response.statusCode != 201) {
      throw Exception('Error al crear la solicitud de tarea');
    }
  }

  /// Editar una solicitud existente
  Future<void> editarSolicitud(int solicitudId, SolicitudTareaModel solicitud) async {
    final response = await _apiClient.put(
      '${AppConstants.baseUrl}/solicitudes-tarea/$solicitudId',
      body: solicitud.toJson(),
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Error al editar la solicitud de tarea');
    }
  }

  /// Aprobar una solicitud
  Future<void> aprobarSolicitud(int solicitudId) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/solicitudes-tarea/$solicitudId/aprobar',
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Error al aprobar la solicitud');
    }
  }

  /// Rechazar una solicitud
  Future<void> rechazarSolicitud(int solicitudId, {String? observacion}) async {
    final body = {
      if (observacion != null) 'observacion': observacion,
    };

    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/solicitudes-tarea/$solicitudId/rechazar',
      body: body,
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Error al rechazar la solicitud');
    }
  }

  /// Consultar estado actual
  Future<EstadoSolicitud> obtenerEstado(int solicitudId) async {
    final response = await _apiClient.get(
      '${AppConstants.baseUrl}/solicitudes-tarea/$solicitudId/estado',
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return EstadoSolicitud.fromString(data['estado']);
    } else {
      throw Exception('Error al obtener el estado de la solicitud');
    }
  }

  /// Filtrar solicitudes
  Future<List<SolicitudTareaModel>> listarSolicitudes({
    String? conjuntoId,
    String? empresaId,
    EstadoSolicitud? estado,
  }) async {
    final queryParams = <String, String>{};

    if (conjuntoId != null) queryParams['conjuntoId'] = conjuntoId;
    if (empresaId != null) queryParams['empresaId'] = empresaId;
    if (estado != null) queryParams['estado'] = estado.toJson();

    final uri = Uri.parse('${AppConstants.baseUrl}/solicitudes-tarea')
        .replace(queryParameters: queryParams);

    final response = await _apiClient.get(uri.toString());

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List;
      return data.map((e) => SolicitudTareaModel.fromJson(e)).toList();
    } else {
      throw Exception('Error al listar solicitudes de tarea');
    }
  }
}
