import 'dart:convert';
import 'package:flutter_application_1/service/api_client.dart';
import 'package:flutter_application_1/model/inventario_item_model.dart';
import 'package:flutter_application_1/model/insumo_model.dart';
import 'package:flutter_application_1/service/app_constants.dart';

class InventarioApi {
  final ApiClient _client = ApiClient();

  Future<List<InventarioItemResponse>> listarInventarioConjunto(
    String conjuntoNit,
  ) async {
    final resp = await _client.get('/inventario/conjunto/$conjuntoNit/insumos');

    if (resp.statusCode != 200) {
      throw Exception('Error al listar inventario: ${resp.body}');
    }

    final List<dynamic> data = jsonDecode(resp.body) as List<dynamic>;
    return data
        .map((e) => InventarioItemResponse.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<InventarioItemResponse>> listarInsumosBajos(
    String conjuntoNit, {
    int? umbral,
  }) async {
    final path = umbral == null
        ? '/inventario/conjunto/$conjuntoNit/insumos-bajos'
        : '/inventario/conjunto/$conjuntoNit/insumos-bajos?umbral=$umbral';

    final resp = await _client.get(path);

    if (resp.statusCode != 200) {
      throw Exception('Error al listar insumos bajos: ${resp.body}');
    }

    final List<dynamic> data = jsonDecode(resp.body) as List<dynamic>;
    return data
        .map((e) => InventarioItemResponse.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Catálogo empresa (ya lo tienes en EmpresaApi, pero te lo dejo aquí por si quieres centralizar)
  Future<List<InsumoResponse>> listarCatalogoInsumosEmpresa(
    String empresaNit,
  ) async {
    final resp = await _client.get('${AppConstants.baseUrl}/empresa/$empresaNit/catalogo');
    if (resp.statusCode != 200) {
      throw Exception('Error al listar catálogo: ${resp.body}');
    }
    final List<dynamic> data = jsonDecode(resp.body);
    return data
        .map((e) => InsumoResponse.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Crear solicitud de insumos (con items)
  Future<void> crearSolicitudInsumo({
    required String conjuntoNit,
    required String empresaNit,
    required List<Map<String, dynamic>> items, // [{insumoId, cantidad}]
  }) async {
    final resp = await _client.post(
      '/solicitud-insumo',
      body: {
        'conjuntoId': conjuntoNit,
        'empresaId': empresaNit,
        'insumosSolicitados': items,
      },
    );

    if (resp.statusCode != 201 && resp.statusCode != 200) {
      throw Exception('Error al crear solicitud: ${resp.body}');
    }
  }
}
