import 'dart:convert';
import 'package:flutter_application_1/service/api_client.dart';
import 'package:flutter_application_1/model/inventario_item_model.dart';
import 'package:flutter_application_1/model/insumo_model.dart';
import 'package:flutter_application_1/model/movimiento_insumo_model.dart';
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
    final resp = await _client.get(
      '${AppConstants.baseUrl}/empresa/$empresaNit/catalogo',
    );
    if (resp.statusCode != 200) {
      throw Exception('Error al listar catálogo: ${resp.body}');
    }
    final List<dynamic> data = jsonDecode(resp.body);
    return data
        .map((e) => InsumoResponse.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Resta cantidad del stock de un insumo (salida manual, ej. corrección de
  /// conteo o uso fuera de una tarea). Para el consumo normal al cerrar una
  /// tarea no uses esto: eso ya pasa automático al cerrar.
  Future<void> consumirStock({
    required String conjuntoNit,
    required int insumoId,
    required num cantidad,
    String? observacion,
  }) async {
    final resp = await _client.post(
      '/inventario/conjunto/$conjuntoNit/consumir-stock',
      body: {
        'insumoId': insumoId,
        'cantidad': cantidad,
        if (observacion != null && observacion.trim().isNotEmpty)
          'observacion': observacion.trim(),
      },
    );

    if (resp.statusCode != 204 && resp.statusCode != 200) {
      throw Exception('Error al registrar salida: ${resp.body}');
    }
  }

  /// Kardex: historial de entradas/salidas de un insumo, con saldo corriente,
  /// más reciente primero.
  Future<List<MovimientoInsumoResponse>> listarMovimientos({
    required String conjuntoNit,
    required int insumoId,
  }) async {
    final resp = await _client.get(
      '/inventario/conjunto/$conjuntoNit/insumos/$insumoId/movimientos',
    );

    if (resp.statusCode != 200) {
      throw Exception('Error al cargar el kardex: ${resp.body}');
    }

    final List<dynamic> data = jsonDecode(resp.body) as List<dynamic>;
    return data
        .map(
          (e) =>
              MovimientoInsumoResponse.fromJson(e as Map<String, dynamic>),
        )
        .toList();
  }

  /// Crea un insumo personalizado directamente en el inventario de un
  /// conjunto (no pasa por el catálogo de empresa) y le asigna stock inicial.
  Future<InventarioItemResponse> crearInsumoPersonalizado({
    required String conjuntoNit,
    required String nombre,
    required String unidad,
    required CategoriaInsumo categoria,
    int? umbralBajo,
    num? cantidadInicial,
    num? contenidoPorUnidad,
    String? unidadContenido,
  }) async {
    final resp = await _client.post(
      '/inventario/conjunto/$conjuntoNit/insumos-personalizados',
      body: {
        'nombre': nombre,
        'unidad': unidad,
        'categoria': categoria.backendValue,
        if (umbralBajo != null) 'umbralBajo': umbralBajo,
        if (cantidadInicial != null) 'cantidadInicial': cantidadInicial,
        if (contenidoPorUnidad != null)
          'contenidoPorUnidad': contenidoPorUnidad,
        if (unidadContenido != null) 'unidadContenido': unidadContenido,
      },
    );

    if (resp.statusCode != 201 && resp.statusCode != 200) {
      throw Exception('Error al crear insumo personalizado: ${resp.body}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return InventarioItemResponse.fromJson({
      'insumoId': data['insumoId'],
      'nombre': data['nombre'],
      'unidad': data['unidad'],
      'categoria': data['categoria'],
      'cantidad': data['cantidad'],
      'umbralUsado': data['umbralBajo'],
      'personalizado': true,
      'contenidoPorUnidad': data['contenidoPorUnidad'],
      'unidadContenido': data['unidadContenido'],
      'totalDisponible': data['totalDisponible'],
    });
  }

  /// Edita un insumo personalizado de este conjunto. Pasa explícitamente
  /// `contenidoPorUnidad`/`unidadContenido` en null para borrar el contenido
  /// medible (volver a conteo simple); déjalos en null-sin-tocar (omitidos)
  /// si no quieres cambiar ese dato.
  Future<InventarioItemResponse> editarInsumoPersonalizado({
    required String conjuntoNit,
    required int insumoId,
    String? nombre,
    String? unidad,
    CategoriaInsumo? categoria,
    int? umbralBajo,
    bool limpiarContenido = false,
    num? contenidoPorUnidad,
    String? unidadContenido,
  }) async {
    final resp = await _client.patch(
      '/inventario/conjunto/$conjuntoNit/insumos-personalizados/$insumoId',
      body: {
        if (nombre != null) 'nombre': nombre,
        if (unidad != null) 'unidad': unidad,
        if (categoria != null) 'categoria': categoria.backendValue,
        if (umbralBajo != null) 'umbralBajo': umbralBajo,
        if (limpiarContenido) ...{
          'contenidoPorUnidad': null,
          'unidadContenido': null,
        } else ...{
          if (contenidoPorUnidad != null)
            'contenidoPorUnidad': contenidoPorUnidad,
          if (unidadContenido != null) 'unidadContenido': unidadContenido,
        },
      },
    );

    if (resp.statusCode != 200) {
      throw Exception('Error al editar insumo personalizado: ${resp.body}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return InventarioItemResponse.fromJson({
      'insumoId': data['insumoId'],
      'nombre': data['nombre'],
      'unidad': data['unidad'],
      'categoria': data['categoria'],
      'cantidad': data['cantidad'],
      'umbralUsado': data['umbralBajo'],
      'personalizado': true,
      'contenidoPorUnidad': data['contenidoPorUnidad'],
      'unidadContenido': data['unidadContenido'],
      'totalDisponible': data['totalDisponible'],
    });
  }

  /// Elimina un insumo personalizado del inventario de este conjunto.
  Future<void> eliminarInsumoPersonalizado({
    required String conjuntoNit,
    required int insumoId,
  }) async {
    final resp = await _client.delete(
      '/inventario/conjunto/$conjuntoNit/insumos-personalizados/$insumoId',
    );

    if (resp.statusCode != 204 && resp.statusCode != 200) {
      throw Exception('Error al eliminar insumo personalizado: ${resp.body}');
    }
  }

  /// Suma cantidad al stock de un insumo ya existente en el inventario del
  /// conjunto (catálogo o personalizado), ej. cuando el conjunto compra más.
  Future<void> agregarStock({
    required String conjuntoNit,
    required int insumoId,
    required num cantidad,
    String? observacion,
  }) async {
    final resp = await _client.post(
      '/inventario/conjunto/$conjuntoNit/agregar-stock',
      body: {
        'insumoId': insumoId,
        'cantidad': cantidad,
        if (observacion != null && observacion.trim().isNotEmpty)
          'observacion': observacion.trim(),
      },
    );

    if (resp.statusCode != 201 && resp.statusCode != 200) {
      throw Exception('Error al agregar stock: ${resp.body}');
    }
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
