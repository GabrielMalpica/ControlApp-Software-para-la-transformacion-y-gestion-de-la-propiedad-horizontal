import 'dart:convert';
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/service/api_client.dart';

class AdministradorApi {
  final ApiClient _client = ApiClient();

  Future<List<Conjunto>> listarMisConjuntos(String adminId) async {
    final resp = await _client.get('/administrador/$adminId/conjuntos');

    if (resp.statusCode != 200) {
      throw Exception(
        'Error listando conjuntos del administrador: ${resp.body}',
      );
    }

    final List<dynamic> data = jsonDecode(resp.body) as List<dynamic>;
    return data
        .map((e) => Conjunto.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
