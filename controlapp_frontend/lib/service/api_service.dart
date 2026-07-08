import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_constants.dart';
import 'session_service.dart';

class ApiService {
  static String get baseUrl => AppConstants.baseUrl;
  static final SessionService _session = SessionService();

  static Future<Map<String, String>> _headers() async {
    final token = await _session.getToken();
    return {
      'Accept': 'application/json',
      'x-empresa-id': AppConstants.empresaNit,
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Future<List<dynamic>> getOperarios(String nit) async {
    final res = await http.get(
      Uri.parse('$baseUrl/conjuntos/$nit/operarios'),
      headers: await _headers(),
    );
    if (res.statusCode == 200) return jsonDecode(res.body)['operarios'];
    throw Exception('Error al obtener operarios');
  }

  static Future<Map<String, dynamic>?> getAdministrador(String nit) async {
    final res = await http.get(
      Uri.parse('$baseUrl/conjuntos/$nit/administrador'),
      headers: await _headers(),
    );
    if (res.statusCode == 200) return jsonDecode(res.body)['administrador'];
    throw Exception('Error al obtener administrador');
  }

  static Future<List<dynamic>> getMaquinaria(String nit) async {
    final res = await http.get(
      Uri.parse('$baseUrl/conjuntos/$nit/maquinaria'),
      headers: await _headers(),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Error al obtener maquinaria');
  }

  static Future<Map<String, dynamic>> getInventario(String nit) async {
    final res = await http.get(
      Uri.parse('$baseUrl/conjuntos/$nit/inventario'),
      headers: await _headers(),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Error al obtener inventario');
  }
}
