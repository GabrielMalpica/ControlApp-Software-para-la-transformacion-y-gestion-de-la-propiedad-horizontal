import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/model/usuario_model.dart';
import 'dart:convert';

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

  Future<void> asignarOperarioAConjunto({
    required String conjuntoNit,
    required String operarioCedula,
  }) async {
    final dynamic operarioIdPayload =
        int.tryParse(operarioCedula) ?? operarioCedula;

    final resp = await _apiClient.post(
      '${AppConstants.gerenteBase}/conjuntos/$conjuntoNit/operarios',
      body: {'operarioId': operarioIdPayload},
    );

    if (resp.statusCode >= 400) {
      throw Exception(
        'Error asignando operario a conjunto: ${resp.statusCode} ${resp.body}',
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

  Future<List<Usuario>> listarUsuarios({String? rol}) async {
    String url = '${AppConstants.baseUrl}/gerente/usuarios';
    if (rol != null) {
      url += '?rol=$rol';
    }

    final resp = await _apiClient.get(url);

    if (resp.statusCode != 200) {
      throw Exception(
        'Error obteniendo usuarios: ${resp.statusCode} ${resp.body}',
      );
    }

    final List<dynamic> jsonList = jsonDecode(resp.body);
    return jsonList.map((e) => Usuario.fromJson(e)).toList();
  }

  Future<List<Usuario>> listarSupervisores() async {
    final resp = await _apiClient.get(
      '${AppConstants.baseUrl}/gerente/supervisores',
    );

    if (resp.statusCode != 200) {
      throw Exception('Error al listar supervisores: ${resp.body}');
    }

    final List<dynamic> data = jsonDecode(resp.body);
    return data
        .map((e) => Usuario.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> crearConjunto({
    required String nitConjunto,
    required String nombre,
    required String direccion,
    required String correo,
    required String empresaId,
    String? administradorId,
    double? valorMensual,
    required List<String> tiposServicio,
    required List<String> consignasEspeciales,
    required List<String> valorAgregado,
    DateTime? fechaInicioContrato,
    List<Map<String, String>> horarios = const [],
    List<Map<String, dynamic>> ubicaciones = const [],
  }) async {
    final body = <String, dynamic>{
      'nit': nitConjunto,
      'nombre': nombre,
      'direccion': direccion,
      'correo': correo,
      'empresaId': empresaId,
      if (administradorId != null && administradorId.isNotEmpty)
        'administradorId': administradorId,
      if (fechaInicioContrato != null)
        'fechaInicioContrato': fechaInicioContrato.toIso8601String(),
      'tipoServicio': tiposServicio,
      if (valorMensual != null) 'valorMensual': valorMensual,
      'consignasEspeciales': consignasEspeciales,
      'valorAgregado': valorAgregado,
      if (horarios.isNotEmpty) 'horarios': horarios,
      if (ubicaciones.isNotEmpty) 'ubicaciones': ubicaciones,
    };

    final resp = await _apiClient.post(
      '${AppConstants.baseUrl}/gerente/conjuntos',
      body: body,
    );

    if (resp.statusCode >= 400) {
      throw Exception(
        'Error creando conjunto: ${resp.statusCode} ${resp.body}',
      );
    }
  }

  Future<List<Conjunto>> listarConjuntos() async {
    final resp = await _apiClient.get(
      '${AppConstants.baseUrl}/gerente/conjuntos',
    );

    if (resp.statusCode != 200) {
      throw Exception('Error al listar conjuntos: ${resp.body}');
    }

    final List<dynamic> data = jsonDecode(resp.body);
    return data
        .map((e) => Conjunto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Conjunto> obtenerConjunto(String nit) async {
    final resp = await _apiClient.get('${AppConstants.conjuntosGerente}/$nit');

    if (resp.statusCode != 200) {
      throw Exception(
        'Error obteniendo conjunto: ${resp.statusCode} ${resp.body}',
      );
    }

    final Map<String, dynamic> data = jsonDecode(resp.body);
    return Conjunto.fromJson(data);
  }

  Future<void> eliminarConjunto(String nit) async {
    final resp = await _apiClient.delete(
      '${AppConstants.conjuntosGerente}/$nit',
    );

    if (resp.statusCode >= 400) {
      throw Exception(
        'Error eliminando conjunto: ${resp.statusCode} ${resp.body}',
      );
    }
  }

  Future<void> actualizarConjunto(
    String conjuntoNit, {
    String? nombre,
    String? direccion,
    String? correo,
    bool? activo,
    double? valorMensual,
    DateTime? fechaInicioContrato,
    DateTime? fechaFinContrato,
    String? administradorId,
    List<String>? operariosIds,
    List<Map<String, dynamic>>? ubicaciones,
  }) async {
    final Map<String, dynamic> body = {};
    if (nombre != null) body['nombre'] = nombre;
    if (direccion != null) body['direccion'] = direccion;
    if (correo != null) body['correo'] = correo;
    if (activo != null) body['activo'] = activo;
    if (valorMensual != null) body['valorMensual'] = valorMensual;
    if (fechaInicioContrato != null) {
      body['fechaInicioContrato'] = fechaInicioContrato.toIso8601String();
    }
    if (fechaFinContrato != null) {
      body['fechaFinContrato'] = fechaFinContrato.toIso8601String();
    }
    if (administradorId != null) body['administradorId'] = administradorId;
    if (operariosIds != null) body['operariosIds'] = operariosIds;
    if (ubicaciones != null) body['ubicaciones'] = ubicaciones;

    final resp = await _apiClient.patch(
      '${AppConstants.conjuntosGerente}/$conjuntoNit',
      body: body,
    );

    if (resp.statusCode >= 400) {
      throw Exception(
        'Error actualizando conjunto: ${resp.statusCode} ${resp.body}',
      );
    }
  }
}
