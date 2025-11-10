import 'dart:convert';
import 'package:http/http.dart' as http;

import '../service/api_client.dart';
import '../service/app_constants.dart';
import '../model/conjunto_model.dart';

class ConjuntoRepository {
  final ApiClient _apiClient = ApiClient();

  /// Obtener todos los conjuntos
  Future<List<ConjuntoModel>> getConjuntos() async {
    final response = await _apiClient.get('${AppConstants.baseUrl}/conjuntos');
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((e) => ConjuntoModel.fromJson(e)).toList();
    } else {
      throw Exception('Error al obtener los conjuntos');
    }
  }

  /// Obtener un conjunto por NIT
  Future<ConjuntoModel> getConjuntoByNit(String nit) async {
    final response =
        await _apiClient.get('${AppConstants.baseUrl}/conjuntos/$nit');
    if (response.statusCode == 200) {
      return ConjuntoModel.fromJson(json.decode(response.body));
    } else {
      throw Exception('Error al obtener el conjunto con NIT $nit');
    }
  }

  /// Crear un nuevo conjunto
  Future<void> crearConjunto(ConjuntoModel conjunto) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/conjuntos',
      body: conjunto.toJson(), // ✅ Se pasa el Map, no el String
    );

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('Error al crear el conjunto');
    }
  }

  /// Editar conjunto existente
  Future<void> editarConjunto(String nit, Map<String, dynamic> body) async {
    final response = await _apiClient.put(
      '${AppConstants.baseUrl}/conjuntos/$nit',
      body: body, // ✅ ya es Map
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Error al editar el conjunto');
    }
  }

  /// Cambiar el estado activo/inactivo
  Future<void> setActivo(String nit, bool activo) async {
    final response = await _apiClient.put(
      '${AppConstants.baseUrl}/conjuntos/$nit/activo',
      body: {'activo': activo},
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Error al actualizar el estado del conjunto');
    }
  }

  /// Asignar un administrador
  Future<void> asignarAdministrador(String nit, int administradorId) async {
    final response = await _apiClient.put(
      '${AppConstants.baseUrl}/conjuntos/$nit/administrador',
      body: {'administradorId': administradorId},
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Error al asignar administrador');
    }
  }

  /// Eliminar el administrador asignado
  Future<void> eliminarAdministrador(String nit) async {
    final response =
        await _apiClient.delete('${AppConstants.baseUrl}/conjuntos/$nit/administrador');

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Error al eliminar administrador');
    }
  }

  /// Asignar un operario al conjunto
  Future<void> asignarOperario(String nit, int operarioId) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/conjuntos/$nit/operarios',
      body: {'operarioId': operarioId},
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Error al asignar operario');
    }
  }

  /// Agregar maquinaria al conjunto
  Future<void> agregarMaquinaria(String nit, int maquinariaId) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/conjuntos/$nit/maquinaria',
      body: {'maquinariaId': maquinariaId},
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Error al agregar maquinaria');
    }
  }

  /// Agregar ubicación
  Future<void> agregarUbicacion(String nit, Map<String, dynamic> body) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/conjuntos/$nit/ubicaciones',
      body: body, // ✅ sin json.encode
    );

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('Error al agregar ubicación');
    }
  }

  /// Buscar una ubicación dentro del conjunto
  Future<Map<String, dynamic>> buscarUbicacion(
      String nit, String nombreUbicacion) async {
    final response = await _apiClient.get(
      '${AppConstants.baseUrl}/conjuntos/$nit/ubicaciones/buscar?nombre=$nombreUbicacion',
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Ubicación no encontrada');
    }
  }

  /// Obtener tareas por fecha
  Future<List<dynamic>> tareasPorFecha(String nit, String fecha) async {
    final response = await _apiClient.get(
      '${AppConstants.baseUrl}/conjuntos/$nit/tareas/por-fecha?fecha=$fecha',
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Error al obtener tareas por fecha');
    }
  }

  /// Exportar cronograma a formato calendario
  Future<List<dynamic>> exportarEventosCalendario(String nit) async {
    final response = await _apiClient.get(
      '${AppConstants.baseUrl}/conjuntos/$nit/cronograma/eventos-calendario',
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Error al exportar eventos de calendario');
    }
  }
}
