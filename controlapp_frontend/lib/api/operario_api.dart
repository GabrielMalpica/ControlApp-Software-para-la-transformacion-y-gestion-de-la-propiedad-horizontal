import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_application_1/api/api_error.dart';
import 'package:flutter_application_1/api/evidencias_multipart.dart';
import 'package:flutter_application_1/model/evidencia_adjunto_model.dart';
import 'package:flutter_application_1/model/tarea_model.dart';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:flutter_application_1/service/session_service.dart';
import 'package:http/http.dart' as http;

export 'package:flutter_application_1/api/api_error.dart';

/// Respuesta de una lectura con `If-None-Match`: [noModificado] = 304 (usar
/// la copia guardada).
class LecturaCondicional<T> {
  final T? datos;
  final String? etag;
  final bool noModificado;

  const LecturaCondicional({this.datos, this.etag, this.noModificado = false});
}

/// Lo que dice el servidor de un cierre por su `clienteCierreId`.
class EstadoCierreRemoto {
  final bool procesado;
  final int? tareaId;
  final String? estadoResultante;
  final DateTime? registradoEn;

  const EstadoCierreRemoto({
    required this.procesado,
    this.tareaId,
    this.estadoResultante,
    this.registradoEn,
  });

  factory EstadoCierreRemoto.fromJson(Map<String, dynamic> json) {
    return EstadoCierreRemoto(
      procesado: json['procesado'] == true,
      tareaId: (json['tareaId'] as num?)?.toInt(),
      estadoResultante: json['estadoResultante']?.toString(),
      registradoEn: DateTime.tryParse(json['registradoEn']?.toString() ?? ''),
    );
  }
}

class OperarioApi {
  final SessionService _session = SessionService();

  /// Tiempo límite de las lecturas de la agenda: sin señal real la pantalla
  /// pasa pronto a la copia guardada.
  static const Duration _tiempoLectura = Duration(seconds: 20);

  Future<Map<String, String>> _authHeaders() async {
    final token = await _session.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('Token requerido (no hay sesión guardada)');
    }
    return {'Authorization': 'Bearer $token', 'Accept': 'application/json'};
  }

  Uri _uriTareas(int operarioId, DateTime? desde, DateTime? hasta) {
    return Uri.parse(
      '${AppConstants.baseUrl}/operario/operarios/$operarioId/tareas',
    ).replace(
      queryParameters: {
        if (desde != null) 'desde': desde.toUtc().toIso8601String(),
        if (hasta != null) 'hasta': hasta.toUtc().toIso8601String(),
      },
    );
  }

  static List<TareaModel> _parsearTareas(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! List) return [];
    return decoded
        .map((e) => TareaModel.fromJson((e as Map).cast<String, dynamic>()))
        .where((t) => !t.borrador)
        .toList();
  }

  /// Actividades del operario. Con [desde]/[hasta] solo trae ese rango (por
  /// fecha de inicio); sin rango trae todo el historial.
  Future<List<TareaModel>> listarTareasOperario({
    required int operarioId,
    DateTime? desde,
    DateTime? hasta,
  }) async {
    final resp = await http
        .get(
          _uriTareas(operarioId, desde, hasta),
          headers: await _authHeaders(),
        )
        .timeout(_tiempoLectura);

    if (resp.statusCode != 200) {
      throw ApiError(resp.statusCode, resp.body);
    }
    return _parsearTareas(resp.body);
  }

  /// Igual que [listarTareasOperario] pero con `If-None-Match`: si la agenda
  /// no cambió desde [etag] el servidor responde 304 y no se descarga nada.
  Future<LecturaCondicional<List<TareaModel>>> listarTareasOperarioCondicional({
    required int operarioId,
    DateTime? desde,
    DateTime? hasta,
    String? etag,
  }) async {
    final headers = await _authHeaders();
    if (etag != null && etag.isNotEmpty) headers['If-None-Match'] = etag;
    final resp = await http
        .get(_uriTareas(operarioId, desde, hasta), headers: headers)
        .timeout(_tiempoLectura);

    if (resp.statusCode == 304) {
      return LecturaCondicional(etag: etag, noModificado: true);
    }
    if (resp.statusCode != 200) {
      throw ApiError(resp.statusCode, resp.body);
    }
    return LecturaCondicional(
      datos: _parsearTareas(resp.body),
      etag: resp.headers['etag'],
    );
  }

  /// Marca la actividad como iniciada (EN_PROCESO). Solo para actividades
  /// asignadas al operario.
  Future<void> iniciarTarea({
    required int operarioId,
    required int tareaId,
  }) async {
    final uri = Uri.parse(
      '${AppConstants.baseUrl}/operario/operarios/$operarioId/tareas/$tareaId/iniciar',
    );
    final resp = await http
        .post(uri, headers: await _authHeaders())
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200 && resp.statusCode != 204) {
      throw ApiError(resp.statusCode, resp.body);
    }
  }

  /// ¿El servidor ya registró este cierre? La cola lo pregunta antes de
  /// reenviar las fotos de un cierre cuya respuesta se perdió.
  Future<EstadoCierreRemoto> consultarCierre({
    required int operarioId,
    required String clienteCierreId,
  }) async {
    final uri = Uri.parse(
      '${AppConstants.baseUrl}/operario/operarios/$operarioId/cierres/'
      '${Uri.encodeComponent(clienteCierreId)}',
    );
    final resp = await http
        .get(uri, headers: await _authHeaders())
        .timeout(_tiempoLectura);
    if (resp.statusCode == 404) {
      return const EstadoCierreRemoto(procesado: false);
    }
    if (resp.statusCode != 200) {
      throw ApiError(resp.statusCode, resp.body);
    }
    final data = jsonDecode(resp.body);
    if (data is! Map) return const EstadoCierreRemoto(procesado: false);
    return EstadoCierreRemoto.fromJson(data.cast<String, dynamic>());
  }

  /// Cierra la actividad. Devuelve true si el servidor ya lo tenía
  /// (`duplicado`: el mismo [clienteCierreId] había entrado antes).
  ///
  /// [sinConexion] = el envío sale de la cola guardada sin señal: entonces
  /// viajan también la hora estimada del cierre ([horaEstimada]) y el reloj
  /// del celular al enviar, y el servidor toma la hora del cierre del
  /// celular (ver docs/app-android-sin-conexion.md, "Hora oficial").
  Future<bool> cerrarTareaConEvidencias({
    required int operarioId,
    required int tareaId,
    String accion = 'COMPLETADA',
    String? observaciones,
    List<Map<String, num>> insumosUsados = const [],
    List<EvidenciaAdjunto> evidencias = const [],
    String? clienteCierreId,
    DateTime? fechaFinalizarTarea,
    bool sinConexion = false,
    DateTime? horaEstimada,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final uri = Uri.parse(
      '${AppConstants.baseUrl}/operario/operarios/$operarioId/tareas/$tareaId/cerrar',
    );
    final idCierre = clienteCierreId?.trim() ?? '';

    Future<http.StreamedResponse> enviar() async {
      final token = await _session.getToken();
      if (token == null || token.isEmpty) {
        throw Exception('Token requerido (no hay sesión guardada)');
      }
      final req = http.MultipartRequest('POST', uri);
      req.headers.addAll({
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        // Con la cabecera el servidor reconoce un reenvío antes de recibir
        // las fotos.
        if (idCierre.isNotEmpty) 'X-Cliente-Cierre-Id': idCierre,
      });

      req.fields['accion'] = accion;
      if (idCierre.isNotEmpty) req.fields['clienteCierreId'] = idCierre;
      if (fechaFinalizarTarea != null) {
        req.fields['fechaFinalizarTarea'] = fechaFinalizarTarea
            .toUtc()
            .toIso8601String();
      }
      if (sinConexion) {
        req.fields['sinConexion'] = 'true';
        req.fields['horaDispositivoEnvio'] = DateTime.now()
            .toUtc()
            .toIso8601String();
        if (horaEstimada != null) {
          req.fields['horaEstimada'] = horaEstimada.toUtc().toIso8601String();
        }
      }

      if (observaciones != null && observaciones.trim().isNotEmpty) {
        req.fields['observaciones'] = observaciones.trim();
      }

      if (insumosUsados.isNotEmpty) {
        req.fields['insumosUsados'] = jsonEncode(insumosUsados);
      }

      await adjuntarEvidencias(req, evidencias);
      return req.send().timeout(timeout);
    }

    var streamed = await enviar();
    var body = await streamed.stream.bytesToString().timeout(timeout);

    // Token vencido: se renueva una vez y se repite (un multipart no lo puede
    // repetir el cliente HTTP global).
    if (streamed.statusCode == 401 && await _renovarSesion()) {
      streamed = await enviar();
      body = await streamed.stream.bytesToString().timeout(timeout);
    }

    if (streamed.statusCode != 200) {
      throw ApiError(streamed.statusCode, body);
    }
    try {
      final data = jsonDecode(body);
      return data is Map && data['duplicado'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _renovarSesion() async {
    if (kIsWeb) return _session.renovarSesionWeb();
    return await _session.renovarSesionApp() == ResultadoRenovacion.renovada;
  }
}
