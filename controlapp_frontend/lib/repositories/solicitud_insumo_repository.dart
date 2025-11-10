// lib/repositories/solicitud_insumo_repository.dart

import 'dart:convert';
import '../service/api_client.dart';
import '../service/app_constants.dart';
import '../model/solicitud_insumo_model.dart';

class SolicitudInsumoRepository {
  final ApiClient _apiClient = ApiClient();

  /// Crear nueva solicitud de insumos
  Future<void> crearSolicitud(SolicitudInsumoModel solicitud) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/solicitudes-insumo',
      body: solicitud.toJson(),
    );

    if (response.statusCode != 201) {
      throw Exception('Error al crear la solicitud de insumo');
    }
  }

  /// Aprobar una solicitud de insumo
  Future<void> aprobarSolicitud(String solicitudId,
      {String? empresaId, DateTime? fechaAprobacion}) async {
    final body = {
      if (empresaId != null) 'empresaId': empresaId,
      if (fechaAprobacion != null)
        'fechaAprobacion': fechaAprobacion.toIso8601String(),
    };

    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/solicitudes-insumo/$solicitudId/aprobar',
      body: body,
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Error al aprobar la solicitud');
    }
  }

  /// Listar solicitudes con filtros opcionales
  Future<List<SolicitudInsumoModel>> listarSolicitudes({
    String? conjuntoId,
    String? empresaId,
    bool? aprobado,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
  }) async {
    final queryParams = <String, String>{};

    if (conjuntoId != null) queryParams['conjuntoId'] = conjuntoId;
    if (empresaId != null) queryParams['empresaId'] = empresaId;
    if (aprobado != null) queryParams['aprobado'] = aprobado.toString();
    if (fechaDesde != null) queryParams['fechaDesde'] = fechaDesde.toIso8601String();
    if (fechaHasta != null) queryParams['fechaHasta'] = fechaHasta.toIso8601String();

    final uri = Uri.parse('${AppConstants.baseUrl}/solicitudes-insumo')
        .replace(queryParameters: queryParams);

    final response = await _apiClient.get(uri.toString());

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List;
      return data.map((e) => SolicitudInsumoModel.fromJson(e)).toList();
    } else {
      throw Exception('Error al obtener las solicitudes de insumo');
    }
  }
}
