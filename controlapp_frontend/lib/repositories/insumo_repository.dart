import 'dart:convert';
import '../model/insumo_model.dart';
import '../service/api_client.dart';
import '../service/app_constants.dart';

class InsumoRepository {
  final ApiClient _apiClient = ApiClient();

  /// Crear un nuevo insumo
  Future<void> crearInsumo(InsumoModel insumo) async {
    final response = await _apiClient.post(
      AppConstants.insumos,
      body: insumo.toJson(),
    );

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('Error al crear el insumo');
    }
  }

  /// Actualizar insumo existente
  Future<void> actualizarInsumo(int id, Map<String, dynamic> body) async {
    final response = await _apiClient.patch(
      '${AppConstants.insumos}/$id',
      body: body,
    );

    if (response.statusCode != 200) {
      throw Exception('Error al actualizar el insumo');
    }
  }

  /// Obtener todos los insumos (con filtros opcionales)
  Future<List<InsumoModel>> listarInsumos({
    String? empresaId,
    String? nombre,
    String? categoria,
  }) async {
    final queryParams = <String, String>{};
    if (empresaId != null) queryParams['empresaId'] = empresaId;
    if (nombre != null) queryParams['nombre'] = nombre;
    if (categoria != null) queryParams['categoria'] = categoria;

    final uri = Uri.parse(AppConstants.insumos)
        .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

    final response = await _apiClient.get(uri.toString());

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((e) => InsumoModel.fromJson(e)).toList();
    } else {
      throw Exception('Error al listar los insumos');
    }
  }

  /// Obtener un insumo por ID
  Future<InsumoModel> obtenerInsumoPorId(int id) async {
    final response = await _apiClient.get('${AppConstants.insumos}/$id');

    if (response.statusCode == 200) {
      return InsumoModel.fromJson(json.decode(response.body));
    } else {
      throw Exception('Error al obtener el insumo con ID $id');
    }
  }

  /// Eliminar un insumo por ID
  Future<void> eliminarInsumo(int id) async {
    final response = await _apiClient.delete('${AppConstants.insumos}/$id');

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Error al eliminar el insumo');
    }
  }
}
