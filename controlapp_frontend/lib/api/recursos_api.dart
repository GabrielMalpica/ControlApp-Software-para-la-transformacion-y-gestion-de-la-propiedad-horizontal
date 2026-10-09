// lib/api/recursos_api.dart
import 'dart:convert';

import '../model/recurso_agenda_model.dart';
import '../service/api_client.dart';
import '../service/api_exception.dart';
import '../service/app_constants.dart';
import '../service/session_service.dart';

/// Agenda de recursos (maquinaria + herramientas): necesidades, candidatos,
/// reservas, agenda por unidad, alertas, vista por conjunto e histórico.
/// Contrato en `contorlapp_backend/src/routes/RecursoAgenda.ts`.
class RecursosApi {
  final ApiClient _client = ApiClient();
  final SessionService _session = SessionService();

  static String get _base => '${AppConstants.baseUrl}/recursos';

  Future<String> _empresa(String? empresaNit) async {
    final recibido = (empresaNit ?? '').trim();
    if (recibido.isNotEmpty) return Uri.encodeComponent(recibido);
    final sesion = (await _session.getEmpresaId())?.trim() ?? '';
    if (sesion.isNotEmpty) return Uri.encodeComponent(sesion);
    throw StateError(
      'No se pudo identificar la empresa de la sesión. Vuelve a iniciar sesión.',
    );
  }

  static String _dia(DateTime d) => claveDeFecha(d);

  Map<String, dynamic> _json(String body) =>
      Map<String, dynamic>.from(jsonDecode(body) as Map);

  void _ok(int status, String body, String fallback, {Set<int> esperados = const {200}}) {
    if (!esperados.contains(status)) {
      throw ApiException.fromResponse(statusCode: status, body: body, fallback: fallback);
    }
  }

  /* ----------------------------- lecturas ----------------------------- */

  Future<AgendaRecursosResponse> agenda({
    String? empresaNit,
    required DateTime desde,
    required DateTime hasta,
    String? q,
    ClaseRecurso? clase,
    String? conjuntoId,
    EstadoDiaRecurso? estado,
    String? propietario,
    bool soloConReservas = false,
    int? unidadId,
  }) async {
    final empresa = await _empresa(empresaNit);
    final uri = Uri.parse('$_base/empresas/$empresa/agenda').replace(
      queryParameters: {
        'desde': _dia(desde),
        'hasta': _dia(hasta),
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        if (clase != null) 'clase': clase.api,
        if (conjuntoId != null) 'conjuntoId': conjuntoId,
        if (estado != null) 'estado': estado.api,
        if (propietario != null) 'propietario': propietario,
        if (soloConReservas) 'soloConReservas': 'true',
        if (unidadId != null) 'unidadId': '$unidadId',
      },
    );
    final resp = await _client.get(uri.toString());
    _ok(resp.statusCode, resp.body, 'No se pudo cargar la agenda de recursos.');
    return AgendaRecursosResponse.fromJson(_json(resp.body));
  }

  Future<NecesidadesResponse> necesidades({
    String? empresaNit,
    required DateTime desde,
    required DateTime hasta,
    String? conjuntoId,
    ClaseRecurso? clase,
    String? cobertura,
    bool soloObligatorias = false,
    String? q,
  }) async {
    final empresa = await _empresa(empresaNit);
    final uri = Uri.parse('$_base/empresas/$empresa/necesidades').replace(
      queryParameters: {
        'desde': _dia(desde),
        'hasta': _dia(hasta),
        if (conjuntoId != null) 'conjuntoId': conjuntoId,
        if (clase != null) 'clase': clase.api,
        if (cobertura != null) 'cobertura': cobertura,
        if (soloObligatorias) 'soloObligatorias': 'true',
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      },
    );
    final resp = await _client.get(uri.toString());
    _ok(resp.statusCode, resp.body, 'No se pudieron cargar las necesidades de recursos.');
    return NecesidadesResponse.fromJson(_json(resp.body));
  }

  Future<CandidatosResponse> candidatos({String? empresaNit, required int necesidadId}) async {
    final empresa = await _empresa(empresaNit);
    final resp = await _client.get('$_base/empresas/$empresa/necesidades/$necesidadId/candidatos');
    _ok(resp.statusCode, resp.body, 'No se pudieron cargar los recursos disponibles.');
    return CandidatosResponse.fromJson(_json(resp.body));
  }

  Future<AlertasResponse> alertas({
    String? empresaNit,
    DateTime? desde,
    DateTime? hasta,
    String? conjuntoId,
  }) async {
    final empresa = await _empresa(empresaNit);
    final uri = Uri.parse('$_base/empresas/$empresa/alertas').replace(
      queryParameters: {
        if (desde != null) 'desde': _dia(desde),
        if (hasta != null) 'hasta': _dia(hasta),
        if (conjuntoId != null) 'conjuntoId': conjuntoId,
      },
    );
    final resp = await _client.get(uri.toString());
    _ok(resp.statusCode, resp.body, 'No se pudieron cargar las alertas de recursos.');
    return AlertasResponse.fromJson(_json(resp.body));
  }

  Future<HistorialUnidadResponse> historial({
    String? empresaNit,
    required ClaseRecurso clase,
    required int unidadId,
  }) async {
    final empresa = await _empresa(empresaNit);
    final resp = await _client.get('$_base/empresas/$empresa/unidades/${clase.api}/$unidadId/historial');
    _ok(resp.statusCode, resp.body, 'No se pudo cargar el historial del recurso.');
    return HistorialUnidadResponse.fromJson(_json(resp.body));
  }

  Future<ConfigLogisticaRecursos> configuracion({String? empresaNit}) async {
    final empresa = await _empresa(empresaNit);
    final resp = await _client.get('$_base/empresas/$empresa/configuracion');
    _ok(resp.statusCode, resp.body, 'No se pudo cargar la configuración logística.');
    return ConfigLogisticaRecursos.fromJson(_json(resp.body));
  }

  Future<SemanaConjuntoResponse> semanaConjunto({
    required String conjuntoId,
    DateTime? desde,
    int? dias,
  }) async {
    final uri = Uri.parse('$_base/conjuntos/${Uri.encodeComponent(conjuntoId)}/semana').replace(
      queryParameters: {
        if (desde != null) 'desde': _dia(desde),
        if (dias != null) 'dias': '$dias',
      },
    );
    final resp = await _client.get(uri.toString());
    _ok(resp.statusCode, resp.body, 'No se pudieron cargar los recursos del conjunto.');
    return SemanaConjuntoResponse.fromJson(_json(resp.body));
  }

  Future<List<CapacidadBorradorDia>> capacidadBorrador({
    required String conjuntoId,
    required int anio,
    required int mes,
  }) async {
    final uri = Uri.parse('$_base/conjuntos/${Uri.encodeComponent(conjuntoId)}/capacidad-borrador').replace(
      queryParameters: {'anio': '$anio', 'mes': '$mes'},
    );
    final resp = await _client.get(uri.toString());
    _ok(resp.statusCode, resp.body, 'No se pudo calcular la capacidad de recursos del borrador.');
    final json = _json(resp.body);
    return (json['insuficientes'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => CapacidadBorradorDia.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /* ---------------------------- escrituras ---------------------------- */

  /// Reserva una o varias unidades para una necesidad. Con `aplicarAGrupo` la
  /// misma unidad se reserva en los otros bloques del grupo que la necesitan.
  /// Devuelve las tareas omitidas del grupo (con su motivo), si las hubo.
  Future<List<String>> reservar({
    String? empresaNit,
    required int necesidadId,
    required List<CandidatoRecursoModel> unidades,
    bool aplicarAGrupo = false,
    String? observacion,
  }) async {
    final empresa = await _empresa(empresaNit);
    final resp = await _client.post(
      '$_base/empresas/$empresa/reservas',
      body: {
        'necesidadId': necesidadId,
        'unidades': unidades.map((u) => {'clase': u.clase.api, 'id': u.unidadId}).toList(),
        'aplicarAGrupo': aplicarAGrupo,
        if (observacion != null && observacion.trim().isNotEmpty) 'observacion': observacion.trim(),
      },
    );
    _ok(resp.statusCode, resp.body, 'No se pudo reservar el recurso.', esperados: const {200, 201});
    final json = _json(resp.body);
    return (json['omitidas'] as List? ?? const [])
        .whereType<Map>()
        .map((o) => o['motivo']?.toString() ?? '')
        .where((m) => m.isNotEmpty)
        .toList();
  }

  Future<void> cancelarReserva({
    String? empresaNit,
    required int reservaId,
    required String motivo,
  }) async {
    final empresa = await _empresa(empresaNit);
    final resp = await _client.post(
      '$_base/empresas/$empresa/reservas/$reservaId/cancelar',
      body: {'motivo': motivo.trim()},
    );
    _ok(resp.statusCode, resp.body, 'No se pudo cancelar la reserva.');
  }

  Future<void> reemplazarUnidad({
    String? empresaNit,
    required int reservaId,
    required int unidadId,
    String? motivo,
  }) async {
    final empresa = await _empresa(empresaNit);
    final resp = await _client.post(
      '$_base/empresas/$empresa/reservas/$reservaId/reemplazar',
      body: {
        'unidadId': unidadId,
        if (motivo != null && motivo.trim().isNotEmpty) 'motivo': motivo.trim(),
      },
    );
    _ok(resp.statusCode, resp.body, 'No se pudo cambiar la unidad.');
  }

  Future<void> bloquearMantenimiento({
    String? empresaNit,
    required ClaseRecurso clase,
    required int unidadId,
    required DateTime desde,
    required DateTime hasta,
    required String motivo,
  }) async {
    final empresa = await _empresa(empresaNit);
    final resp = await _client.post(
      '$_base/empresas/$empresa/mantenimientos',
      body: {
        'clase': clase.api,
        'unidadId': unidadId,
        'desde': desde.toUtc().toIso8601String(),
        'hasta': hasta.toUtc().toIso8601String(),
        'motivo': motivo.trim(),
      },
    );
    _ok(resp.statusCode, resp.body, 'No se pudo programar el mantenimiento.', esperados: const {200, 201});
  }

  Future<ConfigLogisticaRecursos> guardarConfiguracion({
    String? empresaNit,
    required ConfigLogisticaRecursos config,
  }) async {
    final empresa = await _empresa(empresaNit);
    final resp = await _client.patch('$_base/empresas/$empresa/configuracion', body: config.toJson());
    _ok(resp.statusCode, resp.body, 'No se pudo guardar la configuración logística.');
    return ConfigLogisticaRecursos.fromJson(_json(resp.body));
  }
}
