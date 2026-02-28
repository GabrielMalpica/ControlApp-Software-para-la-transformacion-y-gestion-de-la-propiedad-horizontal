// lib/model/novedad_cronograma_model.dart

class NovedadCronogramaModel {
  /// Ejemplos: FESTIVO_MOVIDO | REEMPLAZO_PRIORIDAD | SIN_CANDIDATAS | SIN_HUECO | OTRO
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
  });

  factory NovedadCronogramaModel.fromJson(Map<String, dynamic> j) {
    List<int> toIntList(dynamic x) {
      if (x is List) {
        return x
            .map((e) => int.tryParse('$e') ?? 0)
            .where((n) => n > 0)
            .toList();
      }
      return <int>[];
    }

    String? strOrNull(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    String tipoNormalizado(dynamic v) {
      final t = (v ?? 'OTRO').toString().trim().toUpperCase();
      if (t.isEmpty) return 'OTRO';
      switch (t) {
        case 'FESTIVO_MOVIDO':
        case 'FESTIVOMOVIDO':
          return 'FESTIVO_MOVIDO';
        case 'REEMPLAZO_PRIORIDAD':
        case 'REEMPLAZOPRIORIDAD':
          return 'REEMPLAZO_PRIORIDAD';
        case 'SIN_CANDIDATAS':
        case 'SINCANDIDATAS':
          return 'SIN_CANDIDATAS';
        case 'SIN_HUECO':
        case 'SINHUECO':
          return 'SIN_HUECO';
        default:
          return t;
      }
    }

    return NovedadCronogramaModel(
      tipo: tipoNormalizado(j['tipo']),
      defId: int.tryParse(
        '${j['defId'] ?? j['definicionId'] ?? j['definicionPreventivaId']}',
      ),
      descripcion:
          strOrNull(j['descripcion']) ??
          strOrNull(j['detalle']) ??
          strOrNull(j['mensaje']),
      prioridad: int.tryParse('${j['prioridad']}'),
      fechaOriginal:
          strOrNull(j['fechaOriginal']) ??
          strOrNull(j['fechaPrevia']) ??
          strOrNull(j['from']),
      fechaNueva: strOrNull(j['fechaNueva']) ?? strOrNull(j['to']),
      fecha:
          strOrNull(j['fecha']) ??
          strOrNull(j['dia']) ??
          strOrNull(j['fechaProgramada']),
      nuevaTareaIds: toIntList(
        j['nuevaTareaIds'] ?? j['nuevasTareasIds'] ?? j['createdIds'],
      ),
      reprogramadasIds: toIntList(
        j['reprogramadasIds'] ?? j['reemplazadasIds'] ?? j['reprogramadas'],
      ),
    );
  }
}
