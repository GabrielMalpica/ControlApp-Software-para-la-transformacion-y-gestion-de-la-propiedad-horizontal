import 'dart:convert';
import 'package:http/http.dart' as http;
import '../model/empresa_model.dart';
import '../../service/api_client.dart';
import '../../service/app_constants.dart';

class EmpresaRepository {
  final ApiClient _apiClient = ApiClient();

  /// Crear una nueva empresa
  Future<EmpresaModel> crearEmpresa(EmpresaModel empresa) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/empresa',
      body: empresa.toJson(),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      return EmpresaModel.fromJson(json.decode(response.body));
    } else {
      throw Exception('Error al crear la empresa');
    }
  }

  /// Agregar maquinaria a la empresa
  Future<void> agregarMaquinaria(Map<String, dynamic> body, String nit) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/empresa/$nit/maquinaria',
      body: body,
    );

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('Error al agregar maquinaria');
    }
  }

  /// Listar maquinaria disponible
  Future<List<dynamic>> listarMaquinariaDisponible(String nit) async {
    final response = await _apiClient.get(
      '${AppConstants.baseUrl}/empresa/$nit/maquinaria/disponible',
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Error al obtener maquinaria disponible');
    }
  }

  /// Obtener maquinaria prestada
  Future<List<dynamic>> obtenerMaquinariaPrestada(String nit) async {
    final response = await _apiClient.get(
      '${AppConstants.baseUrl}/empresa/$nit/maquinaria/prestada',
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Error al obtener maquinaria prestada');
    }
  }

  /// Agregar jefe de operaciones
  Future<void> agregarJefeOperaciones(Map<String, dynamic> body, String nit) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/empresa/$nit/jefe-operaciones',
      body: body,
    );

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('Error al agregar jefe de operaciones');
    }
  }

  /// Recibir solicitud de tarea
  Future<void> recibirSolicitudTarea(int id, String nit) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/empresa/$nit/solicitudes/$id/recibir',
    );

    if (response.statusCode != 200) {
      throw Exception('Error al recibir solicitud de tarea');
    }
  }

  /// Eliminar solicitud de tarea
  Future<void> eliminarSolicitudTarea(int id, String nit) async {
    final response = await _apiClient.delete(
      '${AppConstants.baseUrl}/empresa/$nit/solicitudes/$id',
    );

    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('Error al eliminar solicitud de tarea');
    }
  }

  /// Listar solicitudes pendientes
  Future<List<dynamic>> solicitudesTareaPendientes(String nit) async {
    final response = await _apiClient.get(
      '${AppConstants.baseUrl}/empresa/$nit/solicitudes/pendientes',
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Error al obtener solicitudes pendientes');
    }
  }

  /// Agregar insumo al catálogo
  Future<void> agregarInsumoAlCatalogo(Map<String, dynamic> body, String nit) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/empresa/$nit/catalogo',
      body: body,
    );

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('Error al agregar insumo al catálogo');
    }
  }

  /// Listar catálogo de insumos
  Future<List<dynamic>> listarCatalogo(String nit) async {
    final response = await _apiClient.get(
      '${AppConstants.baseUrl}/empresa/$nit/catalogo',
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Error al obtener el catálogo');
    }
  }

  /// Buscar insumo por ID
  Future<Map<String, dynamic>?> buscarInsumoPorId(int id, String nit) async {
    final response = await _apiClient.get(
      '${AppConstants.baseUrl}/empresa/$nit/catalogo/$id',
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else if (response.statusCode == 404) {
      return null;
    } else {
      throw Exception('Error al buscar el insumo');
    }
  }
}
