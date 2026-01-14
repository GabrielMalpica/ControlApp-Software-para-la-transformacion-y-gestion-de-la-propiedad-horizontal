import 'dart:convert';

import 'package:flutter_application_1/model/maquinaria_model.dart';
import 'package:flutter_application_1/service/app_constants.dart';

import '../model/insumo_model.dart';
import '../service/api_client.dart';

class EmpresaApi {
  final ApiClient _client;

  EmpresaApi() : _client = ApiClient();

  String get _empresaNit => AppConstants.empresaNit;

  Future<int> getLimiteMinSemanaPorConjunto() async {
    final resp = await _client.get('/$_empresaNit/limite-min-semana');

    if (resp.statusCode != 200) {
      throw Exception('Error límite semanal: ${resp.statusCode} ${resp.body}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return int.parse(data['limiteMinSemana'].toString());
  }

  Future<InsumoResponse> crearInsumoCatalogo(InsumoRequest req) async {
    final resp = await _client.post(
      '${AppConstants.baseUrl}/empresa/$_empresaNit/catalogo/insumos',
      body: req.toJson(),
    );

    if (resp.statusCode != 201) {
      throw Exception('Error al crear insumo: ${resp.body}');
    }

    final Map<String, dynamic> data = jsonDecode(resp.body);
    return InsumoResponse.fromJson(data);
  }

  Future<List<InsumoResponse>> listarCatalogo() async {
    final resp = await _client.get(
      '${AppConstants.baseUrl}/empresa/$_empresaNit/catalogo',
    );

    if (resp.statusCode != 200) {
      throw Exception('Error al listar catálogo: ${resp.body}');
    }

    final List<dynamic> data = jsonDecode(resp.body);
    return data
        .map((e) => InsumoResponse.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<InsumoResponse?> buscarInsumoPorId(int id) async {
    final resp = await _client.get(
      '${AppConstants.baseUrl}/empresa/$_empresaNit/catalogo/insumos/$id',
    );

    if (resp.statusCode == 404) {
      // el backend manda 404 cuando no existe
      return null;
    }

    if (resp.statusCode != 200) {
      throw Exception('Error al buscar insumo: ${resp.body}');
    }

    final Map<String, dynamic> data = jsonDecode(resp.body);
    return InsumoResponse.fromJson(data);
  }

  Future<InsumoResponse> editarInsumo(int id, InsumoRequest req) async {
    final resp = await _client.patch(
      '${AppConstants.baseUrl}/empresa/$_empresaNit/catalogo/insumos/$id',
      body: req.toJson(),
    );

    if (resp.statusCode != 200) {
      throw Exception('Error al editar insumo: ${resp.body}');
    }

    final Map<String, dynamic> data = jsonDecode(resp.body);
    return InsumoResponse.fromJson(data);
  }

  Future<void> eliminarInsumo(int id) async {
    final resp = await _client.delete(
      '${AppConstants.baseUrl}/empresa/$_empresaNit/catalogo/insumos/$id',
    );

    if (resp.statusCode != 204 && resp.statusCode != 200) {
      throw Exception('Error al eliminar insumo: ${resp.body}');
    }
  }

  /* ===================== MAQUINARIA ===================== */

  Future<MaquinariaResponse> crearMaquinaria(MaquinariaRequest req) async {
    final resp = await _client.post(
      '${AppConstants.baseUrl}/empresa/$_empresaNit/maquinaria',
      body: req.toJson(),
    );

    if (resp.statusCode != 201) {
      throw Exception('Error al crear maquinaria: ${resp.body}');
    }

    final Map<String, dynamic> data = jsonDecode(resp.body);
    return MaquinariaResponse.fromJson(data);
  }

  Future<List<MaquinariaResponse>> listarMaquinaria() async {
    final resp = await _client.get(
      '${AppConstants.baseUrl}/empresa/$_empresaNit/maquinaria',
    );

    if (resp.statusCode != 200) {
      throw Exception('Error al listar maquinaria: ${resp.body}');
    }

    final List<dynamic> data = jsonDecode(resp.body);
    return data
        .map((e) => MaquinariaResponse.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<MaquinariaResponse>> listarMaquinariaFiltrada({
    String? conjuntoNit,
    EstadoMaquinaria? estado,
    TipoMaquinariaFlutter? tipo,
    PropietarioMaquinaria? propietario,
    bool? disponible,
  }) async {
    final params = <String, String>{};

    if (conjuntoNit != null && conjuntoNit.isNotEmpty) {
      params['conjuntoId'] = conjuntoNit;
    }
    if (estado != null) params['estado'] = estado.name;
    if (tipo != null) params['tipo'] = tipo.backendValue;
    if (propietario != null)
      params['propietarioTipo'] = propietario.backendValue;
    if (disponible != null) params['disponible'] = disponible.toString();

    final basePath = '/empresa/$_empresaNit/maquinaria';

    final path = params.isEmpty
        ? basePath
        : '$basePath?${Uri(queryParameters: params).query}';

    final resp = await _client.get(path);

    if (resp.statusCode != 200) {
      throw Exception('Error al listar maquinaria: ${resp.body}');
    }

    final List<dynamic> data = jsonDecode(resp.body) as List<dynamic>;
    return data
        .map((e) => MaquinariaResponse.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<MaquinariaResponse>> listarMaquinariaDisponible() async {
    final resp = await _client.get(
      '${AppConstants.baseUrl}/empresa/$_empresaNit/maquinaria/disponible',
    );

    if (resp.statusCode != 200) {
      throw Exception('Error al listar maquinaria disponible: ${resp.body}');
    }

    final List<dynamic> data = jsonDecode(resp.body);
    return data
        .map((e) => MaquinariaResponse.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<MaquinariaResponse> editarMaquinaria(
    int id,
    MaquinariaRequest req,
  ) async {
    final resp = await _client.patch(
      '${AppConstants.baseUrl}/empresa/$_empresaNit/maquinaria/$id',
      body: req.toJson(),
    );

    if (resp.statusCode != 200) {
      throw Exception('Error al editar maquinaria: ${resp.body}');
    }

    final Map<String, dynamic> data = jsonDecode(resp.body);
    return MaquinariaResponse.fromJson(data);
  }

  Future<void> eliminarMaquinaria(int id) async {
    final resp = await _client.delete(
      '${AppConstants.baseUrl}/empresa/$_empresaNit/maquinaria/$id',
    );

    if (resp.statusCode != 204 && resp.statusCode != 200) {
      throw Exception('Error al eliminar maquinaria: ${resp.body}');
    }
  }
}
