import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_constants.dart';

class ApiService {
  static String get baseUrl => AppConstants.baseUrl;

  static Future<List<dynamic>> getOperarios(String nit) async {
    final res = await http.get(Uri.parse('$baseUrl/conjuntos/$nit/operarios'));
    if (res.statusCode == 200) return jsonDecode(res.body)['operarios'];
    throw Exception('Error al obtener operarios');
  }

  static Future<Map<String, dynamic>?> getAdministrador(String nit) async {
    final res =
        await http.get(Uri.parse('$baseUrl/conjuntos/$nit/administrador'));
    if (res.statusCode == 200) return jsonDecode(res.body)['administrador'];
    throw Exception('Error al obtener administrador');
  }

  static Future<List<dynamic>> getMaquinaria(String nit) async {
    final res = await http.get(Uri.parse('$baseUrl/conjuntos/$nit/maquinaria'));
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Error al obtener maquinaria');
  }

  static Future<Map<String, dynamic>> getInventario(String nit) async {
    final res = await http.get(Uri.parse('$baseUrl/conjuntos/$nit/inventario'));
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Error al obtener inventario');
  }
}
