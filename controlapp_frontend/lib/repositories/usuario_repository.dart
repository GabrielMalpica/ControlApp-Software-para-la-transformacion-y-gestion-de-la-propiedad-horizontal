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

  /// 🔹 LISTAR TODOS LOS USUARIOS
  Future<List<Usuario>> obtenerUsuarios() async {
    final res = await _apiClient.get(
      '${AppConstants.baseUrl}/gerente/usuarios',
    );

    if (res.statusCode != 200) {
      throw Exception('Error al obtener usuarios: ${res.body}');
    }

    final data = jsonDecode(res.body) as List<dynamic>;
    return data.map((e) => Usuario.fromJson(e)).toList();
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

  /// 🔹 EDITAR USUARIO
  Future<Usuario> editarUsuario(
    String cedula,
    Map<String, dynamic> cambios,
  ) async {
    cambios.removeWhere((key, value) => value == null);

    final res = await _apiClient.put(
      '${AppConstants.baseUrl}/gerente/usuarios/$cedula',
      body: cambios,
    );

    if (res.statusCode != 200) {
      throw Exception('Error al editar usuario: ${res.body}');
    }

    final data = jsonDecode(res.body);
    return Usuario.fromJson(data);
  }

  /// 🔹 ELIMINAR USUARIO
  Future<void> eliminarUsuario(String cedula) async {
    final res = await _apiClient.delete(
      '${AppConstants.baseUrl}/gerente/usuarios/$cedula',
    );

    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception('Error al eliminar usuario: ${res.body}');
    }
  }
}
