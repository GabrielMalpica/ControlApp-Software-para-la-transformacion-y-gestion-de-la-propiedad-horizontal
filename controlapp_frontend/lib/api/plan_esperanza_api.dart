import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_application_1/model/plan_esperanza_model.dart';
import 'package:flutter_application_1/service/api_client.dart';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/session_service.dart';
import 'package:flutter_application_1/utils/pickers/selected_upload_file.dart';
import 'package:http/http.dart' as http;

class PlanEsperanzaApi {
  final ApiClient _client = ApiClient();
  final SessionService _session = SessionService();

  String get _base => '${AppConstants.baseUrl}/plan-esperanza';

  Future<Map<String, String>> _authHeaders({bool json = true}) async {
    final token = await _session.getToken();
    final headers = <String, String>{
      'Accept': 'application/json',
      'x-empresa-id': AppConstants.empresaNit,
    };
    if (json) {
      headers['Content-Type'] = 'application/json';
    }
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<PlanEsperanzaConfig> obtenerConfig(String nit) async {
    final resp = await _client.get('$_base/conjuntos/$nit/config');
    if (resp.statusCode != 200) {
      throw Exception(AppError.fromResponseBody(resp.body,
          fallback: 'No se pudo cargar la configuracion.'));
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return PlanEsperanzaConfig.fromJson(data);
  }

  Future<PlanEsperanzaConfig> actualizarConfig(
      String nit, int intervaloMeses) async {
    final resp = await _client.put('$_base/conjuntos/$nit/config',
        body: {'intervaloMeses': intervaloMeses});
    if (resp.statusCode != 200) {
      throw Exception(AppError.fromResponseBody(resp.body,
          fallback: 'No se pudo actualizar la configuracion.'));
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return PlanEsperanzaConfig.fromJson(data);
  }

  Future<PlanEsperanzaActivo> iniciarPlan(String nit,
      {bool mantenerEvidencias = false, int? planAnteriorId}) async {
    final body = <String, dynamic>{
      'mantenerEvidencias': mantenerEvidencias,
    };
    if (planAnteriorId != null) {
      body['planAnteriorId'] = planAnteriorId;
    }
    final resp =
        await _client.post('$_base/conjuntos/$nit/iniciar', body: body);
    if (resp.statusCode != 201) {
      throw Exception(AppError.fromResponseBody(resp.body,
          fallback: 'No se pudo iniciar el plan.'));
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return PlanEsperanzaActivo.fromJson(data);
  }

  Future<PlanEsperanzaActivo?> obtenerPlanActivo(String nit) async {
    final resp = await _client.get('$_base/conjuntos/$nit/plan-activo');
    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) {
      throw Exception(AppError.fromResponseBody(resp.body,
          fallback: 'No se pudo cargar el plan activo.'));
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data.isEmpty || data['id'] == null) return null;
    return PlanEsperanzaActivo.fromJson(data);
  }

  Future<List<PlanResumen>> listarPlanes(String nit) async {
    final resp = await _client.get('$_base/conjuntos/$nit/planes');
    if (resp.statusCode != 200) {
      throw Exception(AppError.fromResponseBody(resp.body,
          fallback: 'No se pudieron cargar los planes.'));
    }
    final data = jsonDecode(resp.body) as List<dynamic>;
    return data
        .map((p) => PlanResumen.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  Future<DiagnosticoAreaModel> guardarDiagnostico(
    int diagnosticoId, {
    double? valoracion,
    String? observaciones,
    SelectedUploadFile? foto,
  }) async {
    if (foto != null) {
      final uri = Uri.parse('$_base/diagnosticos/$diagnosticoId');
      final request = http.MultipartRequest('PUT', uri);
      final headers = await _authHeaders(json: false);
      request.headers.addAll(headers);

      if (valoracion != null) {
        request.fields['valoracion'] = valoracion.toString();
      }
      if (observaciones != null) {
        request.fields['observaciones'] = observaciones;
      }

      if (kIsWeb) {
        if (foto.bytes != null) {
          request.files.add(http.MultipartFile.fromBytes(
            'foto',
            foto.bytes!,
            filename: foto.name,
          ));
        }
      } else {
        if (foto.path != null) {
          request.files.add(await http.MultipartFile.fromPath(
            'foto',
            foto.path!,
            filename: foto.name,
          ));
        }
      }

      final streamed = await request.send();
      final resp = await http.Response.fromStream(streamed);

      if (resp.statusCode != 200) {
        throw Exception(AppError.fromResponseBody(resp.body,
            fallback: 'No se pudo guardar el diagnostico.'));
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return DiagnosticoAreaModel.fromJson(data);
    } else {
      final body = <String, dynamic>{};
      if (valoracion != null) body['valoracion'] = valoracion;
      if (observaciones != null) body['observaciones'] = observaciones;
      final resp = await _client.put('$_base/diagnosticos/$diagnosticoId',
          body: body);
      if (resp.statusCode != 200) {
        throw Exception(AppError.fromResponseBody(resp.body,
            fallback: 'No se pudo guardar el diagnostico.'));
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return DiagnosticoAreaModel.fromJson(data);
    }
  }

  Future<void> finalizarPlan(int planId) async {
    final resp = await _client.post('$_base/planes/$planId/finalizar');
    if (resp.statusCode != 200) {
      throw Exception(AppError.fromResponseBody(resp.body,
          fallback: 'No se pudo finalizar el plan.'));
    }
  }

  Future<InformeResponse> obtenerInforme(int planId) async {
    final resp = await _client.get('$_base/planes/$planId/informe');
    if (resp.statusCode != 200) {
      throw Exception(AppError.fromResponseBody(resp.body,
          fallback: 'No se pudo cargar el informe.'));
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return InformeResponse.fromJson(data);
  }

  Future<HistoricoResponse> obtenerHistorico(String nit) async {
    final resp = await _client.get('$_base/conjuntos/$nit/historico');
    if (resp.statusCode != 200) {
      throw Exception(AppError.fromResponseBody(resp.body,
          fallback: 'No se pudo cargar el historico.'));
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return HistoricoResponse.fromJson(data);
  }

  Future<PlanEsperanzaActivo> reiniciarPlan(String nit,
      {bool mantenerEvidencias = false}) async {
    final resp = await _client.post('$_base/conjuntos/$nit/reiniciar',
        body: {'mantenerEvidencias': mantenerEvidencias});
    if (resp.statusCode != 200) {
      throw Exception(AppError.fromResponseBody(resp.body,
          fallback: 'No se pudo reiniciar el plan.'));
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return PlanEsperanzaActivo.fromJson(data);
  }

  Future<ZonasNuevasCheck> verificarZonasNuevas(String nit) async {
    final resp = await _client.get('$_base/conjuntos/$nit/verificar-zonas');
    if (resp.statusCode != 200) {
      throw Exception(AppError.fromResponseBody(resp.body,
          fallback: 'No se pudieron verificar las zonas.'));
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return ZonasNuevasCheck.fromJson(data);
  }
}
