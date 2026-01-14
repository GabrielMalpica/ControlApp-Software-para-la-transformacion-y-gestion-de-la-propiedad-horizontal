class InventarioItemResponse {
  final int insumoId;
  final String nombre;
  final String unidad;

  /// Puede venir null si backend no lo manda
  final String? categoria;

  final num cantidad;

  /// Umbral efectivo calculado por backend (o null)
  final int? umbralUsado;

  InventarioItemResponse({
    required this.insumoId,
    required this.nombre,
    required this.unidad,
    required this.cantidad,
    required this.umbralUsado,
    this.categoria,
  });

  static int _parseInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

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

  /// ✅ Calculado
  bool get agotado => cantidad <= 0;

  /// ✅ “Bajo” si hay umbral y está por debajo o igual
  bool get estaBajo => umbralUsado != null && cantidad <= (umbralUsado ?? 0);

  factory InventarioItemResponse.fromJson(Map<String, dynamic> json) {
    return InventarioItemResponse(
      insumoId: _parseInt(json['insumoId']),
      nombre: (json['nombre'] ?? '').toString(),
      unidad: (json['unidad'] ?? '').toString(),
      categoria: json['categoria']?.toString(),
      cantidad: _parseNum(json['cantidad']),
      umbralUsado: _parseIntNullable(json['umbralUsado']),
    );
  }
}
