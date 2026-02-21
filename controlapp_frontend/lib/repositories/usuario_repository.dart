import 'dart:convert';

import '../model/usuario_model.dart';
import '../service/api_client.dart';
import '../service/app_constants.dart';

class UsuarioRepository {
  UsuarioRepository({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<List<Usuario>> obtenerUsuarios() async {
    final response = await _apiClient.get(AppConstants.usuarios);

    if (response.statusCode != 200) {
      throw Exception('Error al obtener usuarios: ${response.body}');
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    return data.map((item) => Usuario.fromJson(item)).toList();
  }

  Future<Usuario> crearUsuario(Usuario usuario) async {
    final body = usuario.toJson()..['contrasena'] = usuario.cedula;

    final response = await _apiClient.post(
      AppConstants.usuarios,
      body: body,
    );

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('Error al crear usuario: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return Usuario.fromJson(data);
  }

  Future<Usuario> editarUsuario(String cedula, Map<String, dynamic> cambios) async {
    final payload = Map<String, dynamic>.from(cambios)
      ..removeWhere((key, value) => value == null);

    final response = await _apiClient.put(
      '${AppConstants.usuarios}/$cedula',
      body: payload,
    );

    if (response.statusCode != 200) {
      throw Exception('Error al editar usuario: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return Usuario.fromJson(data);
  }

  Future<void> eliminarUsuario(String cedula) async {
    final response = await _apiClient.delete('${AppConstants.usuarios}/$cedula');

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Error al eliminar usuario: ${response.body}');
    }
  }
}
