// agenda_evento_model.dart

enum TipoEventoAgenda { ENTREGA, PRESTAMO, RETORNO }

extension TipoEventoAgendaExt on TipoEventoAgenda {
  String get code {
    switch (this) {
      case TipoEventoAgenda.ENTREGA:
        return 'E';
      case TipoEventoAgenda.PRESTAMO:
        return 'P';
      case TipoEventoAgenda.RETORNO:
        return 'R';
    }
  }

  String get backendValue => name;
}

TipoEventoAgenda tipoEventoFromString(String? v) {
  final x = (v ?? '').toUpperCase();
  return TipoEventoAgenda.values.firstWhere(
    (e) => e.name == x,
    orElse: () => TipoEventoAgenda.PRESTAMO,
  );
}

DateTime _parseDate(dynamic v) {
  if (v == null) throw ArgumentError('Fecha null en AgendaEventoMaquinaria');
  if (v is DateTime) return v;
  return DateTime.parse(v.toString());
}

class AgendaEventoMaquinaria {
  final int id;
  final String conjuntoId;
  final int maquinariaId;

  /// Día del evento
  final DateTime fecha;

  /// ENTREGA / PRESTAMO / RETORNO  => E / P / R
  final TipoEventoAgenda tipo;

  final int? grupo; // 1..4
  final String? ubicacionNombre;
  final String? observacion;

  const AgendaEventoMaquinaria({
    required this.id,
    required this.conjuntoId,
    required this.maquinariaId,
    required this.fecha,
    required this.tipo,
    this.grupo,
    this.ubicacionNombre,
    this.observacion,
  });

  factory AgendaEventoMaquinaria.fromJson(Map<String, dynamic> json) {
    final rawFecha = json['fecha'] ?? json['inicio'];

    return AgendaEventoMaquinaria(
      id: (json['id'] as num).toInt(),
      conjuntoId: (json['conjuntoId'] ?? json['conjuntoNit'] ?? '').toString(),
      maquinariaId: (json['maquinariaId'] as num).toInt(),
      fecha: _parseDate(rawFecha),
      tipo: tipoEventoFromString(json['tipo']?.toString()),
      grupo: (json['grupo'] as num?)?.toInt(),
      ubicacionNombre: json['ubicacionNombre']?.toString(),
      observacion: json['observacion']?.toString(),
    );
  }
}
