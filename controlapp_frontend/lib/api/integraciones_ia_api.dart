import 'dart:convert';

import 'package:flutter_application_1/model/integracion_ia_model.dart';
import 'package:flutter_application_1/service/api_client.dart';
import 'package:flutter_application_1/service/app_error.dart';

/// Panel "Integraciones IA" (solo gerentes): rutas /integraciones-ia.
class IntegracionesIaApi {
  final ApiClient _client = ApiClient();
  static const _base = '/integraciones-ia';

  void _ok(int status, String body, String fallback) {
    if (status >= 200 && status < 300) return;
    throw Exception(AppError.fromResponseBody(body, fallback: fallback));
  }

  Future<ConfiguracionIntegracionesIa> configuracion() async {
    final r = await _client.get('$_base/configuracion');
    _ok(r.statusCode, r.body, 'No se pudo cargar la configuración.');
    return ConfiguracionIntegracionesIa.fromJson(
      jsonDecode(r.body) as Map<String, dynamic>,
    );
  }

  Future<List<ConexionIa>> conexiones() async {
    final r = await _client.get('$_base/conexiones');
    _ok(r.statusCode, r.body, 'No se pudieron cargar las integraciones.');
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    return (data['conexiones'] as List<dynamic>? ?? const [])
        .map((c) => ConexionIa.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  Future<void> revocar(String conexionId) async {
    final r = await _client.post('$_base/conexiones/$conexionId/revocar');
    _ok(r.statusCode, r.body, 'No se pudo revocar la integración.');
  }

  Future<int> revocarTodas() async {
    final r = await _client.post('$_base/conexiones/revocar-todas');
    _ok(r.statusCode, r.body, 'No se pudieron revocar las integraciones.');
    return ((jsonDecode(r.body) as Map<String, dynamic>)['revocadas'] as num?)
            ?.toInt() ??
        0;
  }

  Future<void> reducirPermisos(String conexionId, List<String> permisos) async {
    final r = await _client.put(
      '$_base/conexiones/$conexionId/permisos',
      body: {'permisos': permisos},
    );
    _ok(r.statusCode, r.body, 'No se pudieron cambiar los permisos.');
  }

  Future<List<ActividadIa>> actividad(String conexionId) async {
    final r = await _client.get('$_base/conexiones/$conexionId/actividad');
    _ok(r.statusCode, r.body, 'No se pudo cargar la actividad.');
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    return (data['actividad'] as List<dynamic>? ?? const [])
        .map((a) => ActividadIa.fromJson(a as Map<String, dynamic>))
        .toList();
  }

  Future<List<AprobacionIa>> aprobaciones() async {
    final r = await _client.get('$_base/aprobaciones');
    _ok(r.statusCode, r.body, 'No se pudieron cargar las aprobaciones.');
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    return (data['aprobaciones'] as List<dynamic>? ?? const [])
        .map((a) => AprobacionIa.fromJson(a as Map<String, dynamic>))
        .toList();
  }

  Future<void> decidir(String aprobacionId, {required bool aprobar}) async {
    final r = await _client.post(
      '$_base/aprobaciones/$aprobacionId/decision',
      body: {'decision': aprobar ? 'aprobar' : 'rechazar'},
    );
    _ok(r.statusCode, r.body, 'No se pudo registrar tu decisión.');
  }
}
