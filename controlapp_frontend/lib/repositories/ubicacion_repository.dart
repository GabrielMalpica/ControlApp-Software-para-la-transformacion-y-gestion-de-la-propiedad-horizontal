// lib/repositories/ubicacion_repository.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../model/ubicacion_model.dart';
import '../service/app_constants.dart';

class UbicacionRepository {
  final String baseUrl = '${AppConstants.apiUrl}/ubicaciones';

  /// 🧩 Agregar un elemento dentro de una ubicación
  Future<void> agregarElemento({
    required int ubicacionId,
    required String nombre,
  }) async {
    final url = Uri.parse('$baseUrl/$ubicacionId/elementos');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'nombre': nombre}),
    );

    if (response.statusCode != 201) {
      throw Exception('Error al agregar elemento: ${response.body}');
    }
  }

  /// 📋 Listar elementos dentro de una ubicación
  Future<List<Map<String, dynamic>>> listarElementos(int ubicacionId) async {
    final url = Uri.parse('$baseUrl/$ubicacionId/elementos');
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data);
    } else {
      throw Exception('Error al listar elementos: ${response.body}');
    }
  }

  /// 🔍 Buscar un elemento por nombre dentro de una ubicación
  Future<Map<String, dynamic>?> buscarElementoPorNombre({
    required int ubicacionId,
    required String nombre,
  }) async {
    final url = Uri.parse('$baseUrl/$ubicacionId/elementos/buscar?nombre=$nombre');
    final response = await http.get(url);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else if (response.statusCode == 404) {
      return null;
    } else {
      throw Exception('Error al buscar elemento: ${response.body}');
    }
  }
}
