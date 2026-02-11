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
    List<int> _toIntList(dynamic x) {
      if (x is List) {
        return x
            .map((e) => int.tryParse('$e') ?? 0)
            .where((n) => n > 0)
            .toList();
      }
      return <int>[];
    }

    return NovedadCronogramaModel(
      tipo: (j['tipo'] ?? 'OTRO').toString(),
      defId: int.tryParse('${j['defId']}'),
      descripcion: j['descripcion']?.toString(),
      prioridad: int.tryParse('${j['prioridad']}'),
      fechaOriginal: j['fechaOriginal']?.toString(),
      fechaNueva: j['fechaNueva']?.toString(),
      fecha: j['fecha']?.toString(),
      nuevaTareaIds: _toIntList(j['nuevaTareaIds']),
      reprogramadasIds: _toIntList(j['reprogramadasIds']),
    );
  }
}
