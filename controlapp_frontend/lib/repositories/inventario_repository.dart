// lib/repositories/inventario_insumo_repository.dart

import 'dart:convert';
import '../service/api_client.dart';
import '../service/app_constants.dart';
import '../model/inventario_model.dart';

class InventarioInsumoRepository {
  final ApiClient _apiClient = ApiClient();

  /// 📦 Listar todos los inventarios-insumo (GET /inventarioInsumos)
  Future<List<Inventario>> listar() async {
    final response = await _apiClient.get('${AppConstants.baseUrl}/inventarioInsumos');
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((e) => Inventario.fromJson(e)).toList();
    } else {
      throw Exception('Error al listar inventarios de insumo');
    }
  }

  /// ➕ Agregar stock (POST /inventarioInsumos/agregarStock)
  Future<void> agregarStock({
    required int inventarioId,
    required int insumoId,
    required int cantidad,
  }) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/inventarioInsumos/agregarStock',
      body: {
        'inventarioId': inventarioId,
        'insumoId': insumoId,
        'cantidad': cantidad,
      },
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Error al agregar stock');
    }
  }

  /// 🔻 Consumir stock (POST /inventarioInsumos/consumirStock)
  Future<void> consumirStock({
    required int inventarioId,
    required int insumoId,
    required int cantidad,
  }) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/inventarioInsumos/consumirStock',
      body: {
        'inventarioId': inventarioId,
        'insumoId': insumoId,
        'cantidad': cantidad,
      },
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Error al consumir stock');
    }
  }

  /// ⚙️ Fijar/actualizar umbral mínimo (PATCH /inventarioInsumos/setUmbralMinimo)
  Future<void> setUmbralMinimo({
    required int inventarioId,
    required int insumoId,
    required int umbralMinimo,
  }) async {
    final response = await _apiClient.patch(
      '${AppConstants.baseUrl}/inventarioInsumos/setUmbralMinimo',
      body: {
        'inventarioId': inventarioId,
        'insumoId': insumoId,
        'umbralMinimo': umbralMinimo,
      },
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Error al fijar umbral mínimo');
    }
  }

  /// ❌ Quitar umbral mínimo (PATCH /inventarioInsumos/unsetUmbralMinimo)
  Future<void> unsetUmbralMinimo({
    required int inventarioId,
    required int insumoId,
  }) async {
    final response = await _apiClient.patch(
      '${AppConstants.baseUrl}/inventarioInsumos/unsetUmbralMinimo',
      body: {
        'inventarioId': inventarioId,
        'insumoId': insumoId,
      },
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Error al quitar umbral mínimo');
    }
  }

  /// ⚠️ Listar insumos bajos (GET /inventarioInsumos/insumosBajos?inventarioId=1)
  Future<List<Inventario>> listarInsumosBajos({
    required int inventarioId,
    String? categoria,
    String? nombre,
  }) async {
    final queryParams = {
      'inventarioId': inventarioId.toString(),
      if (categoria != null) 'categoria': categoria,
      if (nombre != null) 'nombre': nombre,
    };

    final uri = Uri.parse('${AppConstants.baseUrl}/inventarioInsumos/insumosBajos')
        .replace(queryParameters: queryParams);

    final response = await _apiClient.get(uri.toString());

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((e) => Inventario.fromJson(e)).toList();
    } else {
      throw Exception('Error al listar insumos bajos');
    }
  }
}
