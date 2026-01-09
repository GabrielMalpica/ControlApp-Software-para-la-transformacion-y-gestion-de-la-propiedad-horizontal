// lib/api/tarea_api.dart
import 'dart:convert';
import 'package:flutter_application_1/model/tarea_model.dart';

import '../service/api_client.dart';
import '../service/app_constants.dart';

class TareaRequest {
  final String descripcion;
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final int duracionHoras;
  final int ubicacionId;
  final int elementoId;
  final String conjuntoId;
  final int? supervisorId;
  final List<int> operariosIds;
  final String? observaciones;

  TareaRequest({
    required this.descripcion,
    required this.fechaInicio,
    required this.fechaFin,
    required this.duracionHoras,
    required this.ubicacionId,
    required this.elementoId,
    required this.conjuntoId,
    this.supervisorId,
    this.operariosIds = const [],
    this.observaciones,
  });

  Map<String, dynamic> toJson() => {
    'descripcion': descripcion,
    'fechaInicio': fechaInicio.toIso8601String(),
    'fechaFin': fechaFin.toIso8601String(),
    'duracionHoras': duracionHoras,
    'ubicacionId': ubicacionId,
    'elementoId': elementoId,
    'conjuntoId': conjuntoId,
    if (supervisorId != null) 'supervisorId': supervisorId,
    if (operariosIds.isNotEmpty) 'operariosIds': operariosIds,
    if (observaciones != null && observaciones!.trim().isNotEmpty)
      'observaciones': observaciones,
  };
}

class TareaApi {
  final ApiClient _client = ApiClient();

  Future<void> crearTarea(TareaRequest req) async {
    final resp = await _client.post(
      '${AppConstants.gerenteBase}/tareas',
      body: req.toJson(),
    );

    if (resp.statusCode != 201) {
      throw Exception('Error al crear tarea: ${resp.body}');
    }
  }

  Future<void> editarTarea(int id, TareaRequest req) async {
    final resp = await _client.patch(
      '${AppConstants.gerenteBase}/tareas/$id',
      body: req.toJson(),
    );

    if (resp.statusCode != 200) {
      throw Exception('Error al editar tarea: ${resp.body}');
    }
  }

  Future<void> eliminarTarea(int id) async {
    final resp = await _client.delete('${AppConstants.gerenteBase}/tareas/$id');

    if (resp.statusCode != 204 && resp.statusCode != 200) {
      throw Exception('Error al eliminar tarea: ${resp.body}');
    }
  }

  Future<List<TareaModel>> listarTareasPorConjunto(String conjuntoId) async {
    final resp = await _client.get(
      '${AppConstants.gerenteBase}/conjuntos/$conjuntoId/tareas',
    );

    if (resp.statusCode != 200) {
      throw Exception('Error al listar tareas: ${resp.body}');
    }

    final List<dynamic> data = jsonDecode(resp.body);
    return data
        .map((e) => TareaModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
