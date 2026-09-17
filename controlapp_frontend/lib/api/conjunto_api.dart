import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/model/maquinaria_model.dart';
import 'package:flutter_application_1/model/necesidad_operario_model.dart';
import 'package:flutter_application_1/service/api_client.dart';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:flutter_application_1/service/app_error.dart';
import 'package:flutter_application_1/service/session_service.dart';
import 'package:flutter_application_1/service/upload_media_type.dart';
import 'package:flutter_application_1/utils/pickers/selected_upload_file.dart';
import 'package:http/http.dart' as http;

/// Lanzada por [ConjuntoApi.eliminarNecesidad] cuando la plaza está ocupada
/// o tiene preventivas vinculadas y hace falta `confirmar: true` para
/// eliminarla de todas formas (mismo patrón 409 que
/// DeleteConjuntoConfirmationRequired en gerente_api.dart).
class EliminarNecesidadConfirmationRequired implements Exception {
  final String mensaje;
  final String motivo;

  EliminarNecesidadConfirmationRequired({
    required this.mensaje,
    required this.motivo,
  });

  factory EliminarNecesidadConfirmationRequired.fromJson(
    Map<String, dynamic> json,
  ) {
    return EliminarNecesidadConfirmationRequired(
      mensaje: (json['mensaje'] ?? 'La plaza tiene datos vinculados.')
          .toString(),
      motivo: (json['motivo'] ?? '').toString(),
    );
  }

  @override
  String toString() => mensaje;
}

class ConjuntoApi {
  final ApiClient _client = ApiClient();
  final SessionService _session = SessionService();

  Future<Map<String, String>> _authHeaders({bool json = true}) async {
    final token = await _session.getToken();
    final headers = <String, String>{'Accept': 'application/json'};

    if (json) {
      headers['Content-Type'] = 'application/json';
    }
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    return headers;
  }

  /// GET /conjunto/:nit/maquinaria
  Future<List<MaquinariaResponse>> listarMaquinariaConjunto(
    String conjuntoNit,
  ) async {
    final resp = await _client.get('/conjunto/$conjuntoNit/maquinaria');

    if (resp.statusCode != 200) {
      throw Exception('Error al listar maquinaria del conjunto: ${resp.body}');
    }

    final List<dynamic> data = jsonDecode(resp.body) as List<dynamic>;
    return data
        .map((e) => MaquinariaResponse.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Carga horarios solo desde rutas conocidas para el rol actual y evita
  /// probes que generan 404 visibles en web.
  Future<List<HorarioConjunto>> obtenerHorariosConjunto(
    String conjuntoNit,
  ) async {
    final rol = (await _session.getRol())?.trim().toLowerCase() ?? '';
    final usuarioId = (await _session.getUserId())?.trim() ?? '';

    switch (rol) {
      case 'gerente':
      case 'jefe_operaciones':
      case 'supervisor':
      case 'operario':
      case 'residente':
        return _obtenerHorariosDesdeRuta(
          '${AppConstants.conjuntosGerente}/$conjuntoNit',
        );
      case 'administrador':
        return _obtenerHorariosAdministrador(
          usuarioId: usuarioId,
          conjuntoNit: conjuntoNit,
        );
      default:
        return _obtenerHorariosDesdeRuta(
          '${AppConstants.conjuntosGerente}/$conjuntoNit',
        );
    }
  }

  Future<Conjunto> obtenerDetalleMapaConjunto(String conjuntoNit) async {
    final resp = await _client.get('/conjunto/conjuntos/$conjuntoNit/mapa');
    if (resp.statusCode != 200) {
      throw Exception(
        AppError.fromResponseBody(
          resp.body,
          fallback: 'No se pudo cargar el mapa del conjunto.',
        ),
      );
    }

    final Map<String, dynamic> data = jsonDecode(resp.body);
    return Conjunto.fromJson(data);
  }

  Future<Uint8List> descargarMapaConjunto(String conjuntoNit) async {
    final uri = Uri.parse(
      '${AppConstants.baseUrl}/conjunto/conjuntos/$conjuntoNit/mapa/archivo',
    );
    final resp = await http.get(uri, headers: await _authHeaders(json: false));

    if (resp.statusCode != 200) {
      throw Exception(
        AppError.fromResponseBody(
          resp.body,
          fallback: 'No se pudo descargar la imagen del mapa.',
        ),
      );
    }

    return resp.bodyBytes;
  }

  Future<Conjunto> subirMapaConjunto({
    required String conjuntoNit,
    required SelectedUploadFile archivo,
  }) async {
    final uri = Uri.parse(
      '${AppConstants.baseUrl}/conjunto/conjuntos/$conjuntoNit/mapa',
    );
    final req = http.MultipartRequest('PUT', uri);
    req.headers.addAll(await _authHeaders(json: false));

    if (kIsWeb) {
      if (!archivo.hasBytes) {
        throw Exception('El archivo seleccionado no contiene datos.');
      }
      req.files.add(
        http.MultipartFile.fromBytes(
          'file',
          archivo.bytes!,
          filename: archivo.name,
          contentType: uploadMediaTypeFromName(
            archivo.name,
            fallbackMimeType: archivo.mimeType,
          ),
        ),
      );
    } else if (archivo.hasPath) {
      req.files.add(
        await http.MultipartFile.fromPath(
          'file',
          archivo.path!,
          filename: archivo.name,
          contentType: uploadMediaTypeFromName(
            archivo.name,
            fallbackMimeType: archivo.mimeType,
          ),
        ),
      );
    } else if (archivo.hasBytes) {
      req.files.add(
        http.MultipartFile.fromBytes(
          'file',
          archivo.bytes!,
          filename: archivo.name,
          contentType: uploadMediaTypeFromName(
            archivo.name,
            fallbackMimeType: archivo.mimeType,
          ),
        ),
      );
    } else {
      throw Exception(
        'El archivo seleccionado no tiene una ruta o bytes validos.',
      );
    }

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode != 200) {
      throw Exception(
        AppError.fromResponseBody(
          resp.body,
          fallback: 'No se pudo subir la imagen del mapa.',
        ),
      );
    }

    final Map<String, dynamic> data = jsonDecode(resp.body);
    return Conjunto.fromJson(data);
  }

  Future<List<HorarioConjunto>> _obtenerHorariosDesdeRuta(String ruta) async {
    final resp = await _client.get(ruta);
    if (resp.statusCode != 200) return const [];
    return _extraerHorarios(resp.body);
  }

  Future<List<HorarioConjunto>> _obtenerHorariosAdministrador({
    required String usuarioId,
    required String conjuntoNit,
  }) async {
    if (usuarioId.isEmpty) return const [];

    final resp = await _client.get('/administrador/$usuarioId/conjuntos');
    if (resp.statusCode != 200) return const [];

    final decoded = jsonDecode(resp.body);
    if (decoded is! List) return const [];

    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      final nit = (item['nit'] ?? '').toString().trim();
      if (nit != conjuntoNit.trim()) continue;
      return _extraerHorarios(jsonEncode(item));
    }

    return const [];
  }

  List<HorarioConjunto> _extraerHorarios(String body) {
    final dynamic decoded = jsonDecode(body);
    final List<dynamic> raw = _buscarListaHorarios(decoded);
    if (raw.isEmpty) return const [];

    final out = <HorarioConjunto>[];
    for (final item in raw) {
      if (item is! Map<String, dynamic>) continue;
      final parsed = _parseHorario(item);
      if (parsed != null) out.add(parsed);
    }
    return out;
  }

  List<dynamic> _buscarListaHorarios(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      final direct = decoded['horarios'];
      if (direct is List<dynamic>) return direct;

      final nestedConjunto = decoded['conjunto'];
      if (nestedConjunto is Map<String, dynamic>) {
        final nestedHorarios = nestedConjunto['horarios'];
        if (nestedHorarios is List<dynamic>) return nestedHorarios;
      }

      final nestedData = decoded['data'];
      if (nestedData is Map<String, dynamic>) {
        final nestedHorarios = nestedData['horarios'];
        if (nestedHorarios is List<dynamic>) return nestedHorarios;
      }
    }

    return const [];
  }

  HorarioConjunto? _parseHorario(Map<String, dynamic> json) {
    final dia = (json['dia'] ?? json['day'] ?? '').toString().trim();
    final apertura =
        (json['horaApertura'] ?? json['horaInicio'] ?? json['apertura'])
            ?.toString()
            .trim();
    final cierre = (json['horaCierre'] ?? json['horaFin'] ?? json['cierre'])
        ?.toString()
        .trim();

    if (dia.isEmpty ||
        apertura == null ||
        apertura.isEmpty ||
        cierre == null ||
        cierre.isEmpty) {
      return null;
    }

    final descansoInicio = json['descansoInicio']?.toString().trim();
    final descansoFin = json['descansoFin']?.toString().trim();

    return HorarioConjunto(
      dia: dia,
      horaApertura: apertura,
      horaCierre: cierre,
      descansoInicio: (descansoInicio == null || descansoInicio.isEmpty)
          ? null
          : descansoInicio,
      descansoFin: (descansoFin == null || descansoFin.isEmpty)
          ? null
          : descansoFin,
    );
  }

  /* ===================== Necesidades operativas (plazas/cargos) ===================== */

  String _necesidadesBase(String conjuntoNit) =>
      '/conjunto/conjuntos/$conjuntoNit/necesidades';

  /// GET /conjunto/conjuntos/:nit/necesidades
  Future<List<NecesidadOperario>> listarNecesidades(String conjuntoNit) async {
    final resp = await _client.get(_necesidadesBase(conjuntoNit));
    if (resp.statusCode != 200) {
      throw Exception(
        AppError.fromResponseBody(
          resp.body,
          fallback: 'No se pudieron cargar las necesidades del conjunto.',
        ),
      );
    }
    final List<dynamic> data = jsonDecode(resp.body) as List<dynamic>;
    return data
        .map((e) => NecesidadOperario.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /conjunto/conjuntos/:nit/necesidades
  Future<NecesidadOperario> crearNecesidad({
    required String conjuntoNit,
    required List<String> roles,
    required String etiqueta,
    int orden = 0,
    bool horarioEspecial = false,
    List<HorarioConjunto> horarios = const [],
    String? observaciones,
    String? operarioId,
  }) async {
    final body = <String, dynamic>{
      'roles': roles,
      'etiqueta': etiqueta,
      'orden': orden,
      'horarioEspecial': horarioEspecial,
      'horarios': horarios.map((h) => h.toJson()).toList(),
      if (observaciones != null) 'observaciones': observaciones,
      if (operarioId != null) 'operarioId': operarioId,
    };
    final resp = await _client.post(_necesidadesBase(conjuntoNit), body: body);
    if (resp.statusCode != 201) {
      throw Exception(
        AppError.fromResponseBody(
          resp.body,
          fallback: 'No se pudo crear la necesidad.',
        ),
      );
    }
    return NecesidadOperario.fromJson(jsonDecode(resp.body));
  }

  /// PATCH /conjunto/conjuntos/:nit/necesidades/:necesidadId
  Future<NecesidadOperario> editarNecesidad({
    required String conjuntoNit,
    required int necesidadId,
    List<String>? roles,
    String? etiqueta,
    int? orden,
    bool? horarioEspecial,
    List<HorarioConjunto>? horarios,
    String? observaciones,
    bool? activo,
  }) async {
    final body = <String, dynamic>{
      if (roles != null) 'roles': roles,
      if (etiqueta != null) 'etiqueta': etiqueta,
      if (orden != null) 'orden': orden,
      if (horarioEspecial != null) 'horarioEspecial': horarioEspecial,
      if (horarios != null)
        'horarios': horarios.map((h) => h.toJson()).toList(),
      if (observaciones != null) 'observaciones': observaciones,
      if (activo != null) 'activo': activo,
    };
    final resp = await _client.patch(
      '${_necesidadesBase(conjuntoNit)}/$necesidadId',
      body: body,
    );
    if (resp.statusCode != 200) {
      throw Exception(
        AppError.fromResponseBody(
          resp.body,
          fallback: 'No se pudo editar la necesidad.',
        ),
      );
    }
    return NecesidadOperario.fromJson(jsonDecode(resp.body));
  }

  /// DELETE /conjunto/conjuntos/:nit/necesidades/:necesidadId
  /// Lanza [EliminarNecesidadConfirmationRequired] si la plaza está ocupada
  /// o tiene preventivas vinculadas y `confirmar` es false.
  Future<void> eliminarNecesidad({
    required String conjuntoNit,
    required int necesidadId,
    bool confirmar = false,
  }) async {
    final path =
        '${_necesidadesBase(conjuntoNit)}/$necesidadId${confirmar ? '?confirmar=true' : ''}';
    final resp = await _client.delete(path);

    if (resp.statusCode == 409) {
      dynamic data;
      try {
        data = jsonDecode(resp.body);
      } catch (_) {
        data = null;
      }
      if (data is Map<String, dynamic> && data['requiresConfirmation'] == true) {
        throw EliminarNecesidadConfirmationRequired.fromJson(data);
      }
    }
    if (resp.statusCode != 204) {
      throw Exception(
        AppError.fromResponseBody(
          resp.body,
          fallback: 'No se pudo eliminar la necesidad.',
        ),
      );
    }
  }

  /// POST /conjunto/conjuntos/:nit/necesidades/:necesidadId/operario
  Future<NecesidadOperario> asignarOperarioNecesidad({
    required String conjuntoNit,
    required int necesidadId,
    required String operarioId,
  }) async {
    final resp = await _client.post(
      '${_necesidadesBase(conjuntoNit)}/$necesidadId/operario',
      body: {'operarioId': operarioId},
    );
    if (resp.statusCode != 200) {
      throw Exception(
        AppError.fromResponseBody(
          resp.body,
          fallback: 'No se pudo asignar el operario a la plaza.',
        ),
      );
    }
    return NecesidadOperario.fromJson(jsonDecode(resp.body));
  }

  /// DELETE /conjunto/conjuntos/:nit/necesidades/:necesidadId/operario
  Future<NecesidadOperario> liberarNecesidad({
    required String conjuntoNit,
    required int necesidadId,
  }) async {
    final resp = await _client.delete(
      '${_necesidadesBase(conjuntoNit)}/$necesidadId/operario',
    );
    if (resp.statusCode != 200) {
      throw Exception(
        AppError.fromResponseBody(
          resp.body,
          fallback: 'No se pudo liberar la plaza.',
        ),
      );
    }
    return NecesidadOperario.fromJson(jsonDecode(resp.body));
  }

  /// POST /conjunto/conjuntos/:nit/necesidades/migrar-desde-operarios
  /// Backfill idempotente: crea una plaza por cada operario del conjunto
  /// que todavía no ocupa ninguna (paso G.2 del plan de necesidades).
  Future<List<String>> migrarNecesidadesDesdeOperarios(
    String conjuntoNit,
  ) async {
    final resp = await _client.post(
      '${_necesidadesBase(conjuntoNit)}/migrar-desde-operarios',
    );
    if (resp.statusCode != 201) {
      throw Exception(
        AppError.fromResponseBody(
          resp.body,
          fallback: 'No se pudo migrar los operarios actuales a necesidades.',
        ),
      );
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final creadas = (data['creadas'] as List?) ?? const [];
    return creadas
        .map((c) => (c as Map<String, dynamic>)['etiqueta']?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
  }
}
