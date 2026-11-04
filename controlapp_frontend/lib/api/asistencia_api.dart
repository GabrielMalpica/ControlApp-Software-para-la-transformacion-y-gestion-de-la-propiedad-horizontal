import 'dart:convert';
import 'dart:typed_data';

import '../model/asistencia_model.dart';
import 'api_error.dart';
import '../service/api_client.dart';
import '../service/app_constants.dart';

class AsistenciaApi {
  final ApiClient _client = ApiClient();

  String get _base => '${AppConstants.baseUrl}/asistencia';

  Future<dynamic> _decode(dynamic resp) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(_errorMessage(resp));
    }
    if (resp.body.isEmpty) return Future.value(null);
    return Future.value(jsonDecode(resp.body));
  }

  String _errorMessage(dynamic resp) {
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map && decoded['message'] != null) {
        return decoded['message'].toString();
      }
    } catch (_) {}
    return 'Error ${resp.statusCode}: ${resp.body}';
  }

  Future<List<ConceptoAsistencia>> listarConceptos() async {
    final resp = await _client.get('$_base/conceptos');
    final data = await _decode(resp) as List<dynamic>;
    return data
        .map((e) => ConceptoAsistencia.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<AsistenciaQr> obtenerQr(String conjuntoId) async {
    final resp = await _client.get('$_base/conjuntos/$conjuntoId/qr');
    final data = await _decode(resp) as Map<String, dynamic>;
    return AsistenciaQr.fromJson(data);
  }

  Future<AsistenciaQr> regenerarQr(String conjuntoId) async {
    final resp = await _client.post(
      '$_base/conjuntos/$conjuntoId/qr/regenerar',
    );
    final data = await _decode(resp) as Map<String, dynamic>;
    return AsistenciaQr.fromJson(data);
  }

  /// Marca entrada o salida con el QR del conjunto. Lanza [ApiError] con el
  /// código HTTP y el `code` del servidor (QR_INVALIDO, ASISTENCIA_COMPLETA…)
  /// o la excepción de red tal cual (sin señal → se guarda en la cola).
  ///
  /// [clienteRegistroId] deduplica reintentos (el servidor responde lo mismo
  /// con `duplicado: true`). [sinConexion]: el envío sale de la cola; entonces
  /// viajan [registradaEn] (reloj del celular al escanear),
  /// [registradaEnEstimada] y el reloj del celular al enviar, y el servidor
  /// usa la hora del escaneo. En línea el servidor usa su propia hora.
  Future<AsistenciaCheckinResultado> checkin({
    required String conjuntoId,
    required String qrPayload,
    // Obligatoria: el backend no registra asistencia sin ubicación.
    required double latitud,
    required double longitud,
    double? precisionMetros,
    String? clienteRegistroId,
    bool sinConexion = false,
    DateTime? registradaEn,
    DateTime? registradaEnEstimada,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final resp = await _client.post(
      '$_base/checkin',
      timeout: timeout,
      body: {
        'conjuntoId': conjuntoId,
        'qrPayload': qrPayload,
        'latitud': latitud,
        'longitud': longitud,
        if (precisionMetros != null) 'precisionMetros': precisionMetros,
        if (clienteRegistroId != null) 'clienteRegistroId': clienteRegistroId,
        if (sinConexion) ...{
          'sinConexion': true,
          'horaDispositivoEnvio': DateTime.now().toUtc().toIso8601String(),
          if (registradaEn != null)
            'registradaEn': registradaEn.toUtc().toIso8601String(),
          if (registradaEnEstimada != null)
            'registradaEnEstimada': registradaEnEstimada
                .toUtc()
                .toIso8601String(),
        },
      },
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiError(resp.statusCode, resp.body);
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return AsistenciaCheckinResultado.fromJson(data);
  }

  Future<AsistenciaGrid> getGrid({
    String? conjuntoId,
    required int anio,
    required int mes,
  }) async {
    final uri = Uri.parse('$_base/grid').replace(
      queryParameters: {
        if (conjuntoId != null && conjuntoId.isNotEmpty)
          'conjuntoId': conjuntoId,
        'anio': '$anio',
        'mes': '$mes',
      },
    );
    final resp = await _client.get(uri.toString());
    final data = await _decode(resp) as Map<String, dynamic>;
    return AsistenciaGrid.fromJson(data);
  }

  Future<List<VisitasSupervisor>> getVisitasSupervisores({
    String? conjuntoId,
    required int anio,
    required int mes,
  }) async {
    final uri = Uri.parse('$_base/visitas-supervisores').replace(
      queryParameters: {
        if (conjuntoId != null && conjuntoId.isNotEmpty)
          'conjuntoId': conjuntoId,
        'anio': '$anio',
        'mes': '$mes',
      },
    );
    final resp = await _client.get(uri.toString());
    final data = await _decode(resp) as Map<String, dynamic>;
    return ((data['supervisores'] as List?) ?? const [])
        .map((e) => VisitasSupervisor.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<AsistenciaResumen> getResumen({
    String? conjuntoId,
    required int anio,
    required int mes,
  }) async {
    final uri = Uri.parse('$_base/resumen').replace(
      queryParameters: {
        if (conjuntoId != null && conjuntoId.isNotEmpty)
          'conjuntoId': conjuntoId,
        'anio': '$anio',
        'mes': '$mes',
      },
    );
    final resp = await _client.get(uri.toString());
    final data = await _decode(resp) as Map<String, dynamic>;
    return AsistenciaResumen.fromJson(data);
  }

  Future<Uint8List> descargarExcel({
    String? conjuntoId,
    required int anio,
    required int mes,
  }) async {
    final uri = Uri.parse('$_base/exportar').replace(
      queryParameters: {
        if (conjuntoId != null && conjuntoId.isNotEmpty)
          'conjuntoId': conjuntoId,
        'anio': '$anio',
        'mes': '$mes',
      },
    );
    final resp = await _client.get(uri.toString());
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(_errorMessage(resp));
    }
    return resp.bodyBytes;
  }

  Future<RegistroAsistenciaDia> upsertRegistro({
    required String operarioId,
    required String fecha,
    required int conceptoId,
    String? conjuntoId,
    String? observacion,
  }) async {
    final resp = await _client.put(
      '$_base/registro',
      body: {
        'operarioId': operarioId,
        'fecha': fecha,
        'conceptoId': conceptoId,
        if (conjuntoId != null) 'conjuntoId': conjuntoId,
        if (observacion != null) 'observacion': observacion,
      },
    );
    final data = await _decode(resp) as Map<String, dynamic>;
    return RegistroAsistenciaDia.fromJson(data);
  }

  Future<void> eliminarRegistro(int id) async {
    final resp = await _client.delete('$_base/registro/$id');
    await _decode(resp);
  }

  Future<int> bulkUpsertRegistro({
    required List<String> operarioIds,
    required String fechaInicio,
    required String fechaFin,
    required int conceptoId,
    String? conjuntoId,
    String? observacion,
  }) async {
    final resp = await _client.post(
      '$_base/registro/bulk',
      body: {
        'operarioIds': operarioIds,
        'fechaInicio': fechaInicio,
        'fechaFin': fechaFin,
        'conceptoId': conceptoId,
        if (conjuntoId != null) 'conjuntoId': conjuntoId,
        if (observacion != null) 'observacion': observacion,
      },
    );
    final data = await _decode(resp) as Map<String, dynamic>;
    return int.tryParse(data['registrosActualizados']?.toString() ?? '') ?? 0;
  }

  Future<List<TurnoExtra>> listarTurnosExtra({
    String? conjuntoId,
    String? operarioId,
    int? anio,
    int? mes,
  }) async {
    final uri = Uri.parse('$_base/turnos-extra').replace(
      queryParameters: {
        if (conjuntoId != null && conjuntoId.isNotEmpty)
          'conjuntoId': conjuntoId,
        if (operarioId != null && operarioId.isNotEmpty)
          'operarioId': operarioId,
        if (anio != null) 'anio': '$anio',
        if (mes != null) 'mes': '$mes',
      },
    );
    final resp = await _client.get(uri.toString());
    final data = await _decode(resp) as List<dynamic>;
    return data
        .map((e) => TurnoExtra.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<TurnoExtra> crearTurnoExtra({
    required String operarioId,
    String? conjuntoId,
    required String fecha,
    String tipo = 'TURNO',
    bool esReemplazo = false,
    String? operarioReemplazadoId,
    String? reemplazadoNombreLibre,
    String? motivo,
    double? valorNegociado,
    int turnosOrdinarios = 0,
    int turnosDominicales = 0,
  }) async {
    final resp = await _client.post(
      '$_base/turnos-extra',
      body: {
        'operarioId': operarioId,
        if (conjuntoId != null) 'conjuntoId': conjuntoId,
        'fecha': fecha,
        'tipo': tipo,
        'esReemplazo': esReemplazo,
        if (operarioReemplazadoId != null)
          'operarioReemplazadoId': operarioReemplazadoId,
        if (reemplazadoNombreLibre != null)
          'reemplazadoNombreLibre': reemplazadoNombreLibre,
        if (motivo != null) 'motivo': motivo,
        if (valorNegociado != null) 'valorNegociado': valorNegociado,
        'turnosOrdinarios': turnosOrdinarios,
        'turnosDominicales': turnosDominicales,
      },
    );
    final data = await _decode(resp) as Map<String, dynamic>;
    return TurnoExtra.fromJson(data);
  }

  Future<void> actualizarTurnoExtra(
    int id, {
    String? motivo,
    double? valorNegociado,
    int? turnosOrdinarios,
    int? turnosDominicales,
    String? estado,
  }) async {
    final resp = await _client.put(
      '$_base/turnos-extra/$id',
      body: {
        if (motivo != null) 'motivo': motivo,
        if (valorNegociado != null) 'valorNegociado': valorNegociado,
        if (turnosOrdinarios != null) 'turnosOrdinarios': turnosOrdinarios,
        if (turnosDominicales != null) 'turnosDominicales': turnosDominicales,
        if (estado != null) 'estado': estado,
      },
    );
    await _decode(resp);
  }

  Future<void> eliminarTurnoExtra(int id) async {
    final resp = await _client.delete('$_base/turnos-extra/$id');
    await _decode(resp);
  }
}
