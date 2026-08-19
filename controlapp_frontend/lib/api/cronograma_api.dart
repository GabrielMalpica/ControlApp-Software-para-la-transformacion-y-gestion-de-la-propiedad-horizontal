// lib/api/cronograma_api.dart
import 'dart:convert';

import '../service/api_client.dart';
import '../service/app_error.dart';
import '../service/app_constants.dart';
import '../service/api_exception.dart';
import '../model/cronograma_actividad_informe_model.dart';
import '../model/cronograma_informe_jerarquico_model.dart';
import '../model/preventiva_excluida_borrador_model.dart';
import '../model/tarea_model.dart';
import '../model/zona_cronograma_model.dart';

class CronogramaApi {
  final ApiClient _client = ApiClient();

  Future<List<ZonaCronogramaModel>> listarConfiguracionZonas({
    required String nit,
  }) async {
    final resp = await _client.get(
      '${AppConstants.cronogramaBase}/conjuntos/$nit/cronograma/zonas-configuracion',
    );
    if (resp.statusCode != 200) {
      throw ApiException.fromResponse(
        statusCode: resp.statusCode,
        body: resp.body,
        fallback: 'No se pudo cargar la configuración de zonas.',
      );
    }
    final data = jsonDecode(resp.body) as List<dynamic>;
    return data
        .map(
          (item) => ZonaCronogramaModel.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  Future<List<ZonaCronogramaModel>> guardarConfiguracionZonas({
    required String nit,
    required List<ZonaCronogramaModel> zonas,
  }) async {
    final resp = await _client.put(
      '${AppConstants.cronogramaBase}/conjuntos/$nit/cronograma/zonas-configuracion',
      body: {
        'zonas': zonas
            .asMap()
            .entries
            .map(
              (entry) => {
                'elementoZonaId': entry.value.elementoZonaId,
                'orden': (entry.key + 1) * 10,
                'colorHex': entry.value.colorHex,
              },
            )
            .toList(),
      },
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiException.fromResponse(
        statusCode: resp.statusCode,
        body: resp.body,
        fallback: 'No se pudo guardar la configuración de zonas.',
      );
    }
    final data = jsonDecode(resp.body) as List<dynamic>;
    return data
        .map(
          (item) => ZonaCronogramaModel.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  /// Lista todas las tareas (preventivas + correctivas) del mes de un conjunto.
  /// GET /cronograma/conjuntos/:nit/cronograma?anio=&mes=&borrador=
  Future<List<TareaModel>> listarPorConjuntoYMes({
    required String nit,
    required int anio,
    required int mes,
    bool? borrador,
  }) async {
    final uri =
        Uri.parse(
          '${AppConstants.cronogramaBase}/conjuntos/$nit/cronograma',
        ).replace(
          queryParameters: {
            'anio': anio.toString(),
            'mes': mes.toString(),
            if (borrador != null) 'borrador': borrador.toString(),
          },
        );

    final resp = await _client.get(uri.toString());

    if (resp.statusCode != 200) {
      throw Exception(
        'Error al traer cronograma: ${resp.statusCode} ${resp.body}',
      );
    }

    final List<dynamic> data = jsonDecode(resp.body) as List<dynamic>;

    return data
        .map((e) => TareaModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Lista de tareas del mes (puede ser borrador o definitivo)
  /// GET /cronograma/conjuntos/:nit/cronograma?anio=&mes=&borrador=&tipo=
  Future<List<TareaModel>> cronogramaMensual({
    required String nit,
    required int anio,
    required int mes,
    bool borrador = false,
    String? tipo,
  }) async {
    final base = '${AppConstants.baseUrl}/cronograma/conjuntos/$nit/cronograma';

    final uri = Uri.parse(base).replace(
      queryParameters: {
        'anio': anio.toString(),
        'mes': mes.toString(),
        'borrador': borrador.toString(),
        if (tipo != null) 'tipo': tipo,
      },
    );

    final resp = await _client.get(uri.toString());

    if (resp.statusCode != 200) {
      throw Exception(
        'Error al cargar cronograma: ${resp.statusCode} ${resp.body}',
      );
    }

    final data = jsonDecode(resp.body) as List<dynamic>;
    return data
        .map((e) => TareaModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Publicar cronograma de preventivas (pasa borrador=false en backend)
  /// POST /definicion-preventiva/conjuntos/:nit/preventivas/publicar?anio=&mes=&consolidar=
  Future<Map<String, dynamic>> publicarCronogramaPreventivas({
    required String nit,
    required int anio,
    required int mes,
    bool consolidar = false,
  }) async {
    final baseUrl =
        '${AppConstants.definicionPreventivaBase}/conjuntos/$nit/preventivas/publicar';

    final uri = Uri.parse(baseUrl).replace(
      queryParameters: {
        'anio': anio.toString(),
        'mes': mes.toString(),
        'consolidar': consolidar.toString(),
      },
    );

    final resp = await _client.post(uri.toString());

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiException.fromResponse(
        statusCode: resp.statusCode,
        body: resp.body,
        fallback:
            'No se pudo publicar el cronograma. Revisa la agenda de maquinaria y vuelve a intentarlo.',
      );
    }

    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> eliminarCronogramaPublicado({
    required String nit,
    required int anio,
    required int mes,
  }) async {
    final uri =
        Uri.parse(
          '${AppConstants.cronogramaBase}/conjuntos/$nit/cronograma/publicado',
        ).replace(
          queryParameters: {'anio': anio.toString(), 'mes': mes.toString()},
        );

    final resp = await _client.delete(
      uri.toString(),
      body: {'anio': anio, 'mes': mes},
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(
        AppError.fromResponseBody(
          resp.body,
          fallback: 'No se pudo eliminar el cronograma publicado.',
        ),
      );
    }

    if (resp.body.trim().isEmpty) return <String, dynamic>{};
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<int> getLimiteMinSemanaPorConjunto({required String nit}) async {
    final uri = Uri.parse('${AppConstants.empresaBase}/$nit/limite-min-semana');

    final resp = await _client.get(uri.toString());

    if (resp.statusCode != 200) {
      throw Exception(
        'Error al traer límite semanal: ${resp.statusCode} ${resp.body}',
      );
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;

    final limite = data['limiteMinSemana'];
    if (limite == null) throw Exception('Respuesta sin limiteMinSemana');

    return int.parse(limite.toString());
  }

  Future<List<CronogramaActividadInformeModel>> informeActividadMensual({
    required String nit,
    required int anio,
    required int mes,
    required bool borrador,
  }) async {
    final uri =
        Uri.parse(
          '${AppConstants.cronogramaBase}/conjuntos/$nit/cronograma/informe-actividad',
        ).replace(
          queryParameters: {
            'anio': '$anio',
            'mes': '$mes',
            'borrador': borrador.toString(),
          },
        );

    final resp = await _client.get(uri.toString());
    if (resp.statusCode != 200) {
      throw Exception(
        AppError.fromResponseBody(
          resp.body,
          fallback: 'No se pudo cargar el informe mensual.',
        ),
      );
    }

    final data = jsonDecode(resp.body) as List<dynamic>;
    return data
        .map(
          (e) => CronogramaActividadInformeModel.fromJson(
            e as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<CronogramaInformeJerarquicoModel> informeActividadJerarquico({
    required String nit,
    required int anio,
    required int mes,
    required bool borrador,
    String? operarioId,
    DateTime? semanaInicio,
  }) async {
    String dateKey(DateTime date) =>
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final uri =
        Uri.parse(
          '${AppConstants.cronogramaBase}/conjuntos/$nit/cronograma/informe-actividad-v2',
        ).replace(
          queryParameters: {
            'anio': '$anio',
            'mes': '$mes',
            'borrador': borrador.toString(),
            if (operarioId != null && operarioId.trim().isNotEmpty)
              'operarioId': operarioId.trim(),
            if (semanaInicio != null) 'semanaInicio': dateKey(semanaInicio),
          },
        );
    final resp = await _client.get(uri.toString());
    if (resp.statusCode != 200) {
      throw Exception(
        AppError.fromResponseBody(
          resp.body,
          fallback: 'No se pudo cargar el informe de cumplimiento.',
        ),
      );
    }
    return CronogramaInformeJerarquicoModel.fromJson(
      (jsonDecode(resp.body) as Map).cast<String, dynamic>(),
    );
  }

  Future<List<PreventivaExcluidaBorradorModel>> listarExcluidasStandby({
    required String nit,
    required int anio,
    required int mes,
    DateTime? fecha,
  }) async {
    final uri =
        Uri.parse(
          '${AppConstants.cronogramaBase}/conjuntos/$nit/cronograma/excluidas-standby',
        ).replace(
          queryParameters: {
            'anio': '$anio',
            'mes': '$mes',
            if (fecha != null) 'fecha': fecha.toIso8601String(),
          },
        );

    final resp = await _client.get(uri.toString());
    if (resp.statusCode != 200) {
      throw Exception(
        AppError.fromResponseBody(
          resp.body,
          fallback: 'No se pudieron cargar las tareas excluidas en standby.',
        ),
      );
    }

    final data = jsonDecode(resp.body) as List<dynamic>;
    return data
        .map(
          (e) => PreventivaExcluidaBorradorModel.fromJson(
            e as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<Map<String, dynamic>> programarExcluidaComoCorrectiva({
    required String nit,
    required int excluidaId,
    required DateTime fechaInicio,
    required DateTime fechaFin,
    int? reemplazarTareaId,
    List<int>? reemplazarTareaIds,
    String? accionReemplazadas,
    String? motivoReemplazo,
  }) async {
    final resp = await _client.post(
      '${AppConstants.cronogramaBase}/conjuntos/$nit/cronograma/excluidas-standby/$excluidaId/programar-correctiva',
      body: {
        'fechaInicio': fechaInicio.toIso8601String(),
        'fechaFin': fechaFin.toIso8601String(),
        if (reemplazarTareaId != null) 'reemplazarTareaId': reemplazarTareaId,
        if (reemplazarTareaIds != null && reemplazarTareaIds.isNotEmpty)
          'reemplazarTareaIds': reemplazarTareaIds,
        if (accionReemplazadas != null)
          'accionReemplazadas': accionReemplazadas,
        if (motivoReemplazo != null && motivoReemplazo.trim().isNotEmpty)
          'motivoReemplazo': motivoReemplazo.trim(),
      },
    );

    if (resp.statusCode != 200) {
      throw ApiException.fromResponse(
        statusCode: resp.statusCode,
        body: resp.body,
        fallback: 'No se pudo programar la tarea excluida.',
      );
    }

    if (resp.body.trim().isEmpty) return <String, dynamic>{};
    return Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
  }

  /// Tareas publicadas de un dia que podrian desplazarse para dar espacio a una
  /// excluida, con la combinacion minima que libera los minutos necesarios.
  Future<Map<String, dynamic>> opcionesReemplazoExcluida({
    required String nit,
    required int excluidaId,
    required DateTime fecha,
  }) async {
    final uri = Uri.parse(
      '${AppConstants.cronogramaBase}/conjuntos/$nit/cronograma/excluidas-standby/$excluidaId/opciones-reemplazo',
    ).replace(queryParameters: {'fecha': fecha.toIso8601String()});

    final resp = await _client.get(uri.toString());
    if (resp.statusCode != 200) {
      throw ApiException.fromResponse(
        statusCode: resp.statusCode,
        body: resp.body,
        fallback: 'No se pudieron cargar las tareas que se pueden desplazar.',
      );
    }
    return Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
  }

  /// Cambia el operario de una excluida del cronograma publicado como excepcion
  /// puntual: no modifica la definicion preventiva ni los periodos siguientes.
  Future<Map<String, dynamic>> reasignarOperarioExcluidaStandby({
    required String nit,
    required int excluidaId,
    required String nuevoOperarioId,
    String? motivo,
  }) async {
    final resp = await _client.post(
      '${AppConstants.cronogramaBase}/conjuntos/$nit/cronograma/excluidas-standby/$excluidaId/reasignar-operario',
      body: {
        'nuevoOperarioId': nuevoOperarioId,
        if (motivo != null && motivo.trim().isNotEmpty) 'motivo': motivo.trim(),
      },
    );

    if (resp.statusCode != 200) {
      throw ApiException.fromResponse(
        statusCode: resp.statusCode,
        body: resp.body,
        fallback: 'No se pudo cambiar el operario de la tarea excluida.',
      );
    }
    return Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
  }

  /// Informe de excluidas del periodo: programadas posteriormente (con las
  /// tareas que se desplazaron), excepciones de operario y pendientes.
  Future<Map<String, dynamic>> informeExcluidas({
    required String nit,
    required int anio,
    required int mes,
  }) async {
    final uri = Uri.parse(
      '${AppConstants.cronogramaBase}/conjuntos/$nit/cronograma/informe-excluidas',
    ).replace(queryParameters: {'anio': '$anio', 'mes': '$mes'});

    final resp = await _client.get(uri.toString());
    if (resp.statusCode != 200) {
      throw ApiException.fromResponse(
        statusCode: resp.statusCode,
        body: resp.body,
        fallback: 'No se pudo cargar el informe de tareas excluidas.',
      );
    }
    return Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
  }

  Future<List<Map<String, dynamic>>> sugerirOperarios({
    required String nit,
    required DateTime inicio,
    required DateTime fin,
    int? max,
  }) async {
    final uri =
        Uri.parse(
          '${AppConstants.baseUrl}/cronograma/conjuntos/$nit/operarios/sugerir',
        ).replace(
          queryParameters: {
            'inicio': inicio.toIso8601String(),
            'fin': fin.toIso8601String(),
            if (max != null) 'max': '$max',
          },
        );

    final resp = await _client.get(uri.toString());
    if (resp.statusCode != 200) {
      throw Exception(
        'Error al sugerir operarios: ${resp.statusCode} ${resp.body}',
      );
    }

    final data = jsonDecode(resp.body) as List<dynamic>;
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
}
