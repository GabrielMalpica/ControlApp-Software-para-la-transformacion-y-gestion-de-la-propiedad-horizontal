import '../service/api_client.dart';
import '../service/app_constants.dart';

class GerenteApi {
  final ApiClient _apiClient = ApiClient();

  Future<void> asignarOperario({
    required String usuarioId,
    required List<String> funciones,
    required bool cursoSalvamentoAcuatico,
    required bool cursoAlturas,
    required bool examenIngreso,
    required DateTime fechaIngreso,
    DateTime? fechaSalida,
    DateTime? fechaUltimasVacaciones,
    String? observaciones,
  }) async {
    final url = '${AppConstants.baseUrl}/gerente/operarios';

    final body = <String, dynamic>{
      'Id': usuarioId,
      'funciones': funciones,
      'cursoSalvamentoAcuatico': cursoSalvamentoAcuatico,
      'cursoAlturas': cursoAlturas,
      'examenIngreso': examenIngreso,
      'fechaIngreso': fechaIngreso.toIso8601String(),
      if (fechaSalida != null) 'fechaSalida': fechaSalida.toIso8601String(),
      if (fechaUltimasVacaciones != null)
        'fechaUltimasVacaciones': fechaUltimasVacaciones.toIso8601String(),
      if (observaciones != null && observaciones.trim().isNotEmpty)
        'observaciones': observaciones.trim(),
    };

    final resp = await _apiClient.post(url, body: body);

    if (resp.statusCode != 201 &&
        resp.statusCode != 200 &&
        resp.statusCode != 204) {
      throw Exception(
        'Error asignando operario: ${resp.statusCode} ${resp.body}',
      );
    }
  }

  Future<void> asignarSupervisor({required String usuarioId}) async {
    final res = await _apiClient.post(
      AppConstants.supervisores,
      body: {'Id': usuarioId},
    );
    if (res.statusCode != 201 && res.statusCode != 200) {
      throw Exception('Error al asignar supervisor: ${res.body}');
    }
  }

  Future<void> asignarAdministrador({
    required String usuarioId,
    required String conjuntoId,
  }) async {
    final resp = await _apiClient.post(
      '${AppConstants.baseUrl}/gerente/administradores',
      body: {'Id': usuarioId, 'conjuntoId': conjuntoId},
    );

    if (resp.statusCode != 201 &&
        resp.statusCode != 200 &&
        resp.statusCode != 204) {
      throw Exception('Error al asignar administrador: ${resp.body}');
    }
  }

  Future<void> asignarJefeOperaciones({required String usuarioId}) async {
    final res = await _apiClient.post(
      AppConstants.jefesOperaciones,
      body: {'Id': usuarioId},
    );
    if (res.statusCode != 201 && res.statusCode != 200) {
      throw Exception('Error al asignar jefe de operaciones: ${res.body}');
    }
  }
}
