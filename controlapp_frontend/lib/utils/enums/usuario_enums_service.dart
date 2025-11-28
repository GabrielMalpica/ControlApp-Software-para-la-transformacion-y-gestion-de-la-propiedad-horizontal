import 'dart:convert';
import '../../service/api_client.dart';
import '../../service/app_constants.dart';
import 'usuario_enums.dart';

class UsuarioEnumsService {
  final ApiClient _apiClient = ApiClient();

  Future<UsuarioEnums> cargarEnumsUsuario() async {
    final response =
        await _apiClient.get('${AppConstants.baseUrl}/meta/enums/usuario');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return UsuarioEnums.fromJson(data);
    } else {
      throw Exception(
          'Error al cargar catálogos de usuario: ${response.statusCode}');
    }
  }
}
