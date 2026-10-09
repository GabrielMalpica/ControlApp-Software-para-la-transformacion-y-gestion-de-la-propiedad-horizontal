import 'dart:convert';

import 'package:flutter_application_1/model/catalogo_operativo_model.dart';
import 'package:flutter_application_1/service/api_client.dart';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:flutter_application_1/service/app_error.dart';

/// Catálogo operativo de la empresa: categorías de tarea y perfiles.
/// Endpoints: /catalogo-operativo/categorias y /catalogo-operativo/perfiles.
class CatalogoOperativoApi {
  final ApiClient _client = ApiClient();

  String get _base => '${AppConstants.baseUrl}/catalogo-operativo';

  dynamic _decode(
    dynamic resp, {
    required String fallback,
    List<int> okCodes = const [200],
  }) {
    if (!okCodes.contains(resp.statusCode)) {
      throw Exception(AppError.fromResponseBody(resp.body, fallback: fallback));
    }
    if ((resp.body as String).isEmpty) return null;
    return jsonDecode(resp.body);
  }

  /* ============================ CATEGORÍAS ============================ */

  Future<List<CategoriaTarea>> listarCategorias() async {
    final resp = await _client.get('$_base/categorias');
    final data =
        _decode(resp, fallback: 'No se pudieron cargar las categorías.')
            as List;
    return data
        .map((e) => CategoriaTarea.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CategoriaTarea> crearCategoria({
    required String nombre,
    String? colorHex,
    String? icono,
    List<String> palabrasClave = const [],
  }) async {
    final resp = await _client.post(
      '$_base/categorias',
      body: {
        'nombre': nombre,
        if (colorHex != null) 'colorHex': colorHex,
        if (icono != null) 'icono': icono,
        'palabrasClave': palabrasClave,
      },
    );
    return CategoriaTarea.fromJson(
      _decode(
            resp,
            fallback: 'No se pudo crear la categoría.',
            okCodes: const [201],
          )
          as Map<String, dynamic>,
    );
  }

  Future<CategoriaTarea> editarCategoria(
    int id, {
    String? nombre,
    String? colorHex,
    String? icono,
    List<String>? palabrasClave,
    bool? activa,
  }) async {
    final resp = await _client.patch(
      '$_base/categorias/$id',
      body: {
        if (nombre != null) 'nombre': nombre,
        if (colorHex != null) 'colorHex': colorHex,
        if (icono != null) 'icono': icono,
        if (palabrasClave != null) 'palabrasClave': palabrasClave,
        if (activa != null) 'activa': activa,
      },
    );
    return CategoriaTarea.fromJson(
      _decode(resp, fallback: 'No se pudo editar la categoría.')
          as Map<String, dynamic>,
    );
  }

  /// `ids` debe contener todas las categorías de la empresa, en el orden nuevo.
  Future<List<CategoriaTarea>> reordenarCategorias(List<int> ids) async {
    final resp = await _client.put('$_base/categorias/orden', body: {'ids': ids});
    final data =
        _decode(resp, fallback: 'No se pudo guardar el orden de las categorías.')
            as List;
    return data
        .map((e) => CategoriaTarea.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> eliminarCategoria(int id) async {
    final resp = await _client.delete('$_base/categorias/$id');
    _decode(resp, fallback: 'No se pudo eliminar la categoría.');
  }

  /* ============================== PERFILES ============================== */

  Future<List<PerfilOperativo>> listarPerfiles() async {
    final resp = await _client.get('$_base/perfiles');
    final data =
        _decode(resp, fallback: 'No se pudieron cargar los perfiles.') as List;
    return data
        .map((e) => PerfilOperativo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PerfilOperativo> crearPerfil({
    required String nombre,
    required List<String> roles,
    String? descripcion,
    List<int> categoriasIds = const [],
  }) async {
    final resp = await _client.post(
      '$_base/perfiles',
      body: {
        'nombre': nombre,
        'roles': roles,
        if (descripcion != null && descripcion.isNotEmpty)
          'descripcion': descripcion,
        'categoriasIds': categoriasIds,
      },
    );
    return PerfilOperativo.fromJson(
      _decode(
            resp,
            fallback: 'No se pudo crear el perfil.',
            okCodes: const [201],
          )
          as Map<String, dynamic>,
    );
  }

  Future<PerfilOperativo> editarPerfil(
    int id, {
    String? nombre,
    List<String>? roles,
    String? descripcion,
    bool? activo,
    List<int>? categoriasIds,
  }) async {
    final resp = await _client.patch(
      '$_base/perfiles/$id',
      body: {
        if (nombre != null) 'nombre': nombre,
        if (roles != null) 'roles': roles,
        if (descripcion != null) 'descripcion': descripcion,
        if (activo != null) 'activo': activo,
        if (categoriasIds != null) 'categoriasIds': categoriasIds,
      },
    );
    return PerfilOperativo.fromJson(
      _decode(resp, fallback: 'No se pudo editar el perfil.')
          as Map<String, dynamic>,
    );
  }

  Future<void> eliminarPerfil(int id) async {
    final resp = await _client.delete('$_base/perfiles/$id');
    _decode(resp, fallback: 'No se pudo eliminar el perfil.');
  }

  /* ===================== PREVENTIVAS DE UN CONJUNTO ===================== */

  String _preventivas(String nit) =>
      '${AppConstants.definicionPreventivaBase}/conjuntos/$nit/preventivas';

  Future<SugerenciasCategoriaResultado> sugerirCategorias(String nit) async {
    final resp = await _client.get('${_preventivas(nit)}/sugerencias-categoria');
    return SugerenciasCategoriaResultado.fromJson(
      _decode(resp, fallback: 'No se pudieron calcular las sugerencias.')
          as Map<String, dynamic>,
    );
  }

  /// Asigna (o quita con `null`) la categoría a varias preventivas.
  Future<AsignacionCategoriaResultado> asignarCategoriaLote(
    String nit, {
    required List<int> ids,
    required int? categoriaId,
  }) async {
    final resp = await _client.patch(
      '${_preventivas(nit)}/categoria-lote',
      body: {'ids': ids, 'categoriaId': categoriaId},
    );
    return AsignacionCategoriaResultado.fromJson(
      _decode(resp, fallback: 'No se pudo asignar la categoría.')
          as Map<String, dynamic>,
    );
  }

  /// Orden interno (1..n) de TODAS las preventivas de la categoría en el conjunto.
  Future<void> ordenarEnCategoria(
    String nit, {
    required int categoriaId,
    required List<int> ids,
  }) async {
    final resp = await _client.put(
      '${_preventivas(nit)}/orden-categoria',
      body: {'categoriaId': categoriaId, 'ids': ids},
    );
    _decode(resp, fallback: 'No se pudo guardar el orden.');
  }
}
