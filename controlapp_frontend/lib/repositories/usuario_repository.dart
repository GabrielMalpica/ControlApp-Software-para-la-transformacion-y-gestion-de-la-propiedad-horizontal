import 'dart:convert';
import 'package:http/http.dart' as http;
import '../service/app_constants.dart';
import '../model/usuario_model.dart';
import '../service/api_client.dart';

class UsuarioRepository {
  final ApiClient _apiClient = ApiClient();

  /// 🔹 Obtener todos los usuarios
  Future<List<Usuario>> getUsuarios() async {
    final response = await _apiClient.get('${AppConstants.baseUrl}/usuarios');

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((e) => Usuario.fromJson(e)).toList();
    } else {
      throw Exception('Error al obtener usuarios: ${response.statusCode}');
    }
  }

  /// 🔹 Obtener usuario por ID
  Future<Usuario> getUsuarioById(int id) async {
    final response = await _apiClient.get('${AppConstants.baseUrl}/usuarios/$id');

    if (response.statusCode == 200) {
      return Usuario.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Usuario no encontrado');
    }
  }

  /// 🔹 Crear usuario
  Future<void> crearUsuario(Usuario usuario) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/usuarios',
      body: usuario.toJson(),
    );

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('Error al crear usuario: ${response.body}');
    }
  }

  /// 🔹 Editar usuario
  Future<void> editarUsuario(int id, Map<String, dynamic> data) async {
    final response = await _apiClient.put(
      '${AppConstants.baseUrl}/usuarios/$id',
      body: data,
    );

    if (response.statusCode != 200) {
      throw Exception('Error al editar usuario: ${response.body}');
    }
  }

  /// 🔹 Eliminar usuario
  Future<void> eliminarUsuario(int id) async {
    final response = await _apiClient.delete('${AppConstants.baseUrl}/usuarios/$id');

    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('Error al eliminar usuario: ${response.body}');
    }
  }
}
