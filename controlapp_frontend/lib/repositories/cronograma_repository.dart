import 'dart:convert';
import '../service/api_client.dart';
import '../service/app_constants.dart';
import '../model/cronograma_model.dart';

class CronogramaRepository {
  final ApiClient _apiClient = ApiClient();

  /// Crear o actualizar un cronograma
  Future<void> crearCronograma(CronogramaModel cronograma) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/conjuntos/${cronograma.conjuntoId}/cronograma',
      body: cronograma.toJson(),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Error al crear o actualizar cronograma');
    }
  }

  /// Editar tareas dentro del cronograma
  Future<void> editarCronograma(
      String nit, List<Map<String, dynamic>> tareas) async {
    final response = await _apiClient.put(
      '${AppConstants.baseUrl}/conjuntos/$nit/cronograma',
      body: {'tareas': tareas},
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Error al editar cronograma');
    }
  }

  /// Obtener tareas por operario
  Future<List<TareaModel>> tareasPorOperario(
      String nit, int operarioId) async {
    final response = await _apiClient.get(
      '${AppConstants.baseUrl}/conjuntos/$nit/cronograma/tareas/por-operario/$operarioId',
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((e) => TareaModel.fromJson(e)).toList();
    } else {
      throw Exception('Error al obtener tareas por operario');
    }
  }

  /// Obtener tareas por fecha
  Future<List<TareaModel>> tareasPorFecha(String nit, String fecha) async {
    final response = await _apiClient.get(
      '${AppConstants.baseUrl}/conjuntos/$nit/cronograma/tareas/por-fecha?fecha=$fecha',
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((e) => TareaModel.fromJson(e)).toList();
    } else {
      throw Exception('Error al obtener tareas por fecha');
    }
  }

  /// Obtener tareas en rango de fechas
  Future<List<TareaModel>> tareasEnRango(
      String nit, String inicio, String fin) async {
    final response = await _apiClient.get(
      '${AppConstants.baseUrl}/conjuntos/$nit/cronograma/tareas/en-rango?inicio=$inicio&fin=$fin',
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((e) => TareaModel.fromJson(e)).toList();
    } else {
      throw Exception('Error al obtener tareas en rango');
    }
  }

  /// Obtener tareas por ubicación
  Future<List<TareaModel>> tareasPorUbicacion(
      String nit, String ubicacion) async {
    final response = await _apiClient.get(
      '${AppConstants.baseUrl}/conjuntos/$nit/cronograma/tareas/por-ubicacion?ubicacion=$ubicacion',
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((e) => TareaModel.fromJson(e)).toList();
    } else {
      throw Exception('Error al obtener tareas por ubicación');
    }
  }

  /// Filtrar tareas por criterios
  Future<List<TareaModel>> tareasPorFiltro(
      String nit, Map<String, dynamic> filtro) async {
    final response = await _apiClient.post(
      '${AppConstants.baseUrl}/conjuntos/$nit/cronograma/tareas/filtrar',
      body: filtro,
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((e) => TareaModel.fromJson(e)).toList();
    } else {
      throw Exception('Error al filtrar tareas');
    }
  }

  /// Exportar cronograma como eventos de calendario
  Future<List<Map<String, dynamic>>> exportarEventosCalendario(
      String nit) async {
    final response = await _apiClient.get(
      '${AppConstants.baseUrl}/conjuntos/$nit/cronograma/eventos',
    );

    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(json.decode(response.body));
    } else {
      throw Exception('Error al exportar eventos del calendario');
    }
  }
}
