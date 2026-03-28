import 'dart:convert';

import 'package:flutter_application_1/model/conjunto_model.dart';
import 'package:flutter_application_1/model/maquinaria_model.dart';
import 'package:flutter_application_1/service/api_client.dart';
import 'package:flutter_application_1/service/app_constants.dart';
import 'package:flutter_application_1/service/session_service.dart';

class ConjuntoApi {
  final ApiClient _client = ApiClient();
  final SessionService _session = SessionService();

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
        return _obtenerHorariosDesdeRuta(
          '${AppConstants.conjuntosGerente}/$conjuntoNit',
        );
      case 'administrador':
        return _obtenerHorariosAdministrador(
          usuarioId: usuarioId,
          conjuntoNit: conjuntoNit,
        );
      default:
        return const [];
    }
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
}
