import 'dart:convert';

import 'package:flutter_application_1/model/maquinaria_model.dart';
import 'package:flutter_application_1/service/api_client.dart';

class ConjuntoApi {
  final ApiClient _client = ApiClient();

  /// GET /conjunto/:nit/maquinaria
  Future<List<MaquinariaResponse>> listarMaquinariaConjunto(
    String conjuntoNit,
  ) async {
    // Compatibilidad entre despliegues:
    // algunos exponen /conjunto/:nit/..., otros /conjuntos/:nit/...
    var resp = await _client.get('/conjunto/$conjuntoNit/maquinaria');
    if (resp.statusCode == 404) {
      resp = await _client.get('/conjuntos/$conjuntoNit/maquinaria');
    }

    if (resp.statusCode != 200) {
      throw Exception('Error al listar maquinaria del conjunto: ${resp.body}');
    }

    final List<dynamic> data = jsonDecode(resp.body) as List<dynamic>;
    return data
        .map((e) => MaquinariaResponse.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
