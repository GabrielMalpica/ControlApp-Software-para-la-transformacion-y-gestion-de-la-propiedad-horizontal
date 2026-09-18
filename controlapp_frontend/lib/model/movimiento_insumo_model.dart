class MovimientoInsumoResponse {
  final int id;

  /// "ENTRADA" o "SALIDA"
  final String tipo;
  final num cantidad;

  /// Saldo acumulado después de este movimiento.
  final num saldo;
  final DateTime fecha;
  final String? observacion;
  final String? operario;
  final int? tareaId;
  final String? tareaDescripcion;

  MovimientoInsumoResponse({
    required this.id,
    required this.tipo,
    required this.cantidad,
    required this.saldo,
    required this.fecha,
    this.observacion,
    this.operario,
    this.tareaId,
    this.tareaDescripcion,
  });

  bool get esEntrada => tipo.toUpperCase() == 'ENTRADA';

  static num _parseNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }

  static int? _parseIntNullable(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  factory MovimientoInsumoResponse.fromJson(Map<String, dynamic> json) {
    return MovimientoInsumoResponse(
      id: _parseIntNullable(json['id']) ?? 0,
      tipo: (json['tipo'] ?? '').toString(),
      cantidad: _parseNum(json['cantidad']),
      saldo: _parseNum(json['saldo']),
      fecha:
          DateTime.tryParse(json['fecha']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      observacion: json['observacion']?.toString(),
      operario: json['operario']?.toString(),
      tareaId: _parseIntNullable(json['tareaId']),
      tareaDescripcion: json['tareaDescripcion']?.toString(),
    );
  }
}
