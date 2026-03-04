// lib/model/novedad_cronograma_model.dart

class NovedadCronogramaModel {
  /// Ejemplos: FESTIVO_MOVIDO | FESTIVO_OMITIDO | REEMPLAZO_PRIORIDAD | SIN_CANDIDATAS | SIN_HUECO | OTRO
  final String tipo;

  final int? defId;
  final String? descripcion;
  final int? prioridad;

  /// FESTIVO_MOVIDO
  final String? fechaOriginal; // "YYYY-MM-DD"
  final String? fechaNueva; // "YYYY-MM-DD"

  /// REEMPLAZO_PRIORIDAD / SIN_HUECO / SIN_CANDIDATAS (según tu backend)
  final String? fecha; // "YYYY-MM-DD"

  final List<int> nuevaTareaIds;
  final List<int> reprogramadasIds;
  final List<int> candidatasIds;
  final int? prioridadObjetivo;
  final String? mensaje;

  NovedadCronogramaModel({
    required this.tipo,
    this.defId,
    this.descripcion,
    this.prioridad,
    this.fechaOriginal,
    this.fechaNueva,
    this.fecha,
    this.nuevaTareaIds = const [],
    this.reprogramadasIds = const [],
    this.candidatasIds = const [],
    this.prioridadObjetivo,
    this.mensaje,
  });

  factory NovedadCronogramaModel.fromJson(Map<String, dynamic> j) {
    String? strOrNull(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    int? toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) {
        final match = RegExp(r'\d+').firstMatch(v);
        if (match != null) return int.tryParse(match.group(0)!);
      }
      if (v is Map) {
        for (final key in const [
          'id',
          'tareaId',
          'tarea_id',
          'preventivaId',
          'preventiva_id',
          'reemplazarId',
          'reemplazoId',
          'targetId',
        ]) {
          final parsed = toInt(v[key]);
          if (parsed != null && parsed > 0) return parsed;
        }
      }
      return int.tryParse('${v ?? ''}');
    }

    List<int> toIntList(dynamic v) {
      final out = <int>[];
      final seen = <int>{};

      void push(dynamic raw) {
        final parsed = toInt(raw);
        if (parsed == null || parsed <= 0 || seen.contains(parsed)) return;
        seen.add(parsed);
        out.add(parsed);
      }

      if (v is List) {
        for (final e in v) {
          push(e);
        }
        return out;
      }

      if (v is String) {
        for (final part in v.split(RegExp(r'[,;|\s]+'))) {
          if (part.trim().isEmpty) continue;
          push(part);
        }
        return out;
      }

      if (v != null) {
        push(v);
      }

      return out;
    }

    String tipoNormalizado(
      dynamic rawTipo, {
      required String? descripcion,
      required String? mensaje,
      required String? fechaOriginal,
      required String? fechaNueva,
      required List<int> nuevasIds,
      required List<int> reemplazadasIds,
      required List<int> candidatasIds,
    }) {
      final t = (rawTipo ?? '').toString().trim().toUpperCase();
      switch (t) {
        case 'FESTIVO_MOVIDO':
        case 'FESTIVOMOVIDO':
          return 'FESTIVO_MOVIDO';
        case 'FESTIVO_OMITIDO':
        case 'FESTIVOOMITIDO':
          return 'FESTIVO_OMITIDO';
        case 'REEMPLAZO_PRIORIDAD':
        case 'REEMPLAZOPRIORIDAD':
          return 'REEMPLAZO_PRIORIDAD';
        case 'SIN_CANDIDATAS':
        case 'SINCANDIDATAS':
          return 'SIN_CANDIDATAS';
        case 'SIN_HUECO':
        case 'SINHUECO':
          return 'SIN_HUECO';
        case 'REQUIERE_CONFIRMACION_REEMPLAZO':
        case 'REQUIERECONFIRMACIONREEMPLAZO':
          return 'REQUIERE_CONFIRMACION_REEMPLAZO';
      }

      final text = '${descripcion ?? ''} ${mensaje ?? ''}'.toUpperCase();
      if (text.contains('SIN CANDIDAT')) return 'SIN_CANDIDATAS';
      if (text.contains('SIN HUECO') ||
          text.contains('SIN CUPO') ||
          text.contains('SIN ESPACIO')) {
        return 'SIN_HUECO';
      }

      if (t.contains('CONFIRM')) return 'REQUIERE_CONFIRMACION_REEMPLAZO';
      if (t.contains('REEMPLAZ')) return 'REEMPLAZO_PRIORIDAD';
      if (t.contains('FESTIV') && t.contains('OMIT')) return 'FESTIVO_OMITIDO';
      if (t.contains('FESTIV') && t.contains('MOV')) return 'FESTIVO_MOVIDO';

      if (fechaOriginal != null && fechaNueva != null) return 'FESTIVO_MOVIDO';
      if (nuevasIds.isNotEmpty || reemplazadasIds.isNotEmpty) {
        return 'REEMPLAZO_PRIORIDAD';
      }
      if (candidatasIds.isNotEmpty) return 'REQUIERE_CONFIRMACION_REEMPLAZO';

      if (t.isEmpty || t == 'NOVEDAD' || t == 'OTRO' || t == 'INFO') {
        return 'OTRO';
      }
      return t;
    }

    final descripcion =
        strOrNull(j['descripcion']) ??
        strOrNull(j['detalle']) ??
        strOrNull(j['observacion']);

    final mensaje =
        strOrNull(j['mensaje']) ??
        strOrNull(j['message']) ??
        strOrNull(j['detalle']) ??
        strOrNull(j['observacion']);

    final fechaOriginal =
        strOrNull(j['fechaOriginal']) ??
        strOrNull(j['fechaPrevia']) ??
        strOrNull(j['from']);
    final fechaNueva = strOrNull(j['fechaNueva']) ?? strOrNull(j['to']);
    final fecha =
        strOrNull(j['fecha']) ??
        strOrNull(j['dia']) ??
        strOrNull(j['fechaProgramada']) ??
        strOrNull(j['fechaObjetivo']);

    final nuevasIds = toIntList(
      j['nuevaTareaIds'] ??
          j['nuevasTareasIds'] ??
          j['createdIds'] ??
          j['nuevaTareaId'] ??
          j['createdId'],
    );

    final reprogramadasIds = toIntList(
      j['reprogramadasIds'] ??
          j['reemplazadasIds'] ??
          j['reprogramadas'] ??
          j['reemplazadas'] ??
          j['preventivasReemplazadasIds'],
    );

    final candidatasIds = toIntList(
      j['candidatasIds'] ??
          j['opcionesIds'] ??
          j['candidateIds'] ??
          j['reemplazarIds'] ??
          j['candidatas'] ??
          j['opciones'],
    );

    return NovedadCronogramaModel(
      tipo: tipoNormalizado(
        j['tipo'],
        descripcion: descripcion,
        mensaje: mensaje,
        fechaOriginal: fechaOriginal,
        fechaNueva: fechaNueva,
        nuevasIds: nuevasIds,
        reemplazadasIds: reprogramadasIds,
        candidatasIds: candidatasIds,
      ),
      defId: int.tryParse(
        '${j['defId'] ?? j['definicionId'] ?? j['definicionPreventivaId']}',
      ),
      descripcion: descripcion ?? mensaje,
      prioridad: int.tryParse('${j['prioridad']}'),
      fechaOriginal: fechaOriginal,
      fechaNueva: fechaNueva,
      fecha: fecha,
      nuevaTareaIds: nuevasIds,
      reprogramadasIds: reprogramadasIds,
      candidatasIds: candidatasIds,
      prioridadObjetivo: int.tryParse(
        '${j['prioridadObjetivo'] ?? j['prioridadCandidata'] ?? j['targetPriority']}',
      ),
      mensaje: mensaje,
    );
  }
}
