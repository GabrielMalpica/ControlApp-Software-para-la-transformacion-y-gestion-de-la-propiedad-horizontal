import 'package:http/http.dart' as http;
import 'dart:convert';

class ApiService {
  static const String baseUrl = 'http://localhost:3000';

  static Future<List<dynamic>> getOperarios(String nit) async {
    final res = await http.get(Uri.parse('$baseUrl/conjuntos/$nit/operarios'));
    if (res.statusCode == 200) return jsonDecode(res.body)['operarios'];
    throw Exception('Error al obtener operarios');
  }

  static Future<Map<String, dynamic>?> getAdministrador(String nit) async {
    final res = await http.get(Uri.parse('$baseUrl/conjuntos/$nit/administrador'));
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
