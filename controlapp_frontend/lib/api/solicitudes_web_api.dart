import 'dart:convert';

import 'package:flutter_application_1/model/solicitud_web_model.dart';
import 'package:flutter_application_1/service/api_client.dart';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:flutter_application_1/service/app_error.dart';

/// Solicitudes de la página web (gerente / jefe de operaciones): rutas
/// /commerce/web del backend. Además de consultar, permite marcar una
/// postulación como revisada o borrarla (permiso web.solicitudes.gestionar).
class SolicitudesWebApi {
  final ApiClient _client = ApiClient();

  /// Archivo de una solicitud servido por el backend desde Drive. Lleva el
  /// token de sesión (EvidenceImage lo agrega solo a URLs de nuestro backend).
  static String urlArchivo(String driveFileId) =>
      '${AppConstants.commerceBase}/web/archivos/$driveFileId';

  /// [revision]: 'pendientes' (sin revisar) o 'revisadas'; null = todas.
  Future<PaginaWeb<PostulacionWeb>> listarPostulaciones({
    String? estado,
    String? revision,
    int pagina = 1,
  }) async {
    final response = await _client.get(
      '${AppConstants.commerceBase}/web/postulaciones?${_query(estado, pagina, revision: revision)}',
    );
    _ensureSuccess(response.statusCode, response.body);
    return PaginaWeb.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
      PostulacionWeb.fromJson,
    );
  }

  Future<PostulacionWeb> marcarRevision(
    int id, {
    required bool revisada,
  }) async {
    final response = await _client.post(
      '${AppConstants.commerceBase}/web/postulaciones/$id/revision',
      body: <String, dynamic>{'revisada': revisada},
    );
    _ensureSuccess(
      response.statusCode,
      response.body,
      fallback: 'No se pudo actualizar la postulación.',
    );
    return PostulacionWeb.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<PostulacionEliminada> eliminarPostulacion(int id) async {
    final response = await _client.delete(
      '${AppConstants.commerceBase}/web/postulaciones/$id',
    );
    _ensureSuccess(
      response.statusCode,
      response.body,
      fallback: 'No se pudo borrar la postulación.',
    );
    return PostulacionEliminada.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<PaginaWeb<RegistroConjuntoWeb>> listarConjuntos({
    String? estado,
    int pagina = 1,
  }) async {
    final response = await _client.get(
      '${AppConstants.commerceBase}/web/conjuntos?${_query(estado, pagina)}',
    );
    _ensureSuccess(response.statusCode, response.body);
    return PaginaWeb.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
      RegistroConjuntoWeb.fromJson,
    );
  }

  String _query(String? estado, int pagina, {String? revision}) => Uri(
    queryParameters: <String, String>{
      'pagina': '$pagina',
      if (estado != null && estado.isNotEmpty) 'estado': estado,
      if (revision != null && revision.isNotEmpty) 'revision': revision,
    },
  ).query;

  void _ensureSuccess(
    int statusCode,
    String body, {
    String fallback =
        'No se pudieron consultar las solicitudes de la página web.',
  }) {
    if (statusCode >= 200 && statusCode < 300) return;
    throw Exception(AppError.fromResponseBody(body, fallback: fallback));
  }
}
