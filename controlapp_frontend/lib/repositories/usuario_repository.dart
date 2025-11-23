import 'dart:convert';
import '../service/app_constants.dart';
import '../model/usuario_model.dart';
import '../service/api_client.dart';

class UsuarioRepository {
  final ApiClient _apiClient = ApiClient();

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
    final response = await _apiClient.get('${AppConstants.usuarios}/$id');

    if (response.statusCode == 200) {
      return Usuario.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Usuario no encontrado');
    }
  }

  /// 🔹 Crear usuario
  Future<Usuario> crearUsuario(Usuario usuario) async {
    final body = usuario.toJson();

    body['contrasena'] = usuario.cedula;

    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/gerente/usuarios',
      body: body,
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return Usuario.fromJson(data); // ya no espera contrasena
    } else {
      throw Exception('Error al crear usuario: ${response.body}');
    }
  }

  /// 🔹 Editar usuario
  Future<void> editarUsuario(int id, Map<String, dynamic> data) async {
    final response = await _apiClient.put(
      '${AppConstants.usuarios}/$id',
      body: data,
    );

    if (response.statusCode != 200) {
      throw Exception('Error al editar usuario: ${response.body}');
    }
  }

  /// 🔹 Eliminar usuario
  Future<void> eliminarUsuario(int id) async {
    final response = await _apiClient.delete('${AppConstants.usuarios}/$id');

    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('Error al eliminar usuario: ${response.body}');
    }
  }
}
