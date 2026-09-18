class InventarioItemResponse {
  final int insumoId;
  final String nombre;
  final String unidad;

  /// Puede venir null si backend no lo manda
  final String? categoria;

  final num cantidad;

  /// Umbral efectivo calculado por backend (o null)
  final int? umbralUsado;

  /// true si el insumo fue creado directamente en este conjunto (no viene
  /// del catálogo de empresa / no es comprable vía la tienda de la app).
  final bool personalizado;

  /// Cuánto mide/pesa CADA "unidad" contada (ej. cada tarro = 1.8). Null si
  /// no se conoce (ej. items que se cuentan por unidad simple, como escobas).
  final num? contenidoPorUnidad;

  /// En qué se mide [contenidoPorUnidad] (ej. "L", "gal", "kg").
  final String? unidadContenido;

  /// cantidad * contenidoPorUnidad, calculado por el backend. Null si no
  /// aplica.
  final num? totalDisponible;

  InventarioItemResponse({
    required this.insumoId,
    required this.nombre,
    required this.unidad,
    required this.cantidad,
    required this.umbralUsado,
    this.categoria,
    this.personalizado = false,
    this.contenidoPorUnidad,
    this.unidadContenido,
    this.totalDisponible,
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

  static num? _parseNumNullable(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  /// ✅ Calculado
  bool get agotado => cantidad <= 0;

  /// ✅ “Bajo” si hay umbral y está por debajo o igual
  bool get estaBajo => umbralUsado != null && cantidad <= (umbralUsado ?? 0);

  /// Texto listo para mostrar en la columna "Total disponible" (ej. "7.2 L"),
  /// o null si el insumo no tiene contenido por unidad definido.
  String? get totalDisponibleTexto {
    if (totalDisponible == null || unidadContenido == null) return null;
    final valor = totalDisponible!;
    final texto = valor == valor.roundToDouble()
        ? valor.toStringAsFixed(0)
        : valor.toStringAsFixed(2);
    return '$texto $unidadContenido';
  }

  /// Cuántos envases/unidades de conteo hay en realidad, redondeando hacia
  /// arriba. Ej: 3 tarros de 1L (3L) que bajan a 2.5L siguen siendo 3 tarros
  /// físicos (uno parcialmente usado); solo al llegar a 2L pasan a ser 2.
  /// Null cuando el insumo no tiene contenido medible (se cuenta simple).
  int? get unidadesFisicas =>
      contenidoPorUnidad == null ? null : cantidad.ceil();

  /// Texto para mostrar cuántas unidades de conteo hay (ej. "3 tarro"),
  /// redondeado hacia arriba cuando aplica; si no, la cantidad tal cual.
  String get disponibleTexto {
    final redondeado = unidadesFisicas;
    if (redondeado == null) return '$cantidad $unidad';
    return '$redondeado $unidad';
  }

  factory InventarioItemResponse.fromJson(Map<String, dynamic> json) {
    return InventarioItemResponse(
      insumoId: _parseInt(json['insumoId']),
      nombre: (json['nombre'] ?? '').toString(),
      unidad: (json['unidad'] ?? '').toString(),
      categoria: json['categoria']?.toString(),
      cantidad: _parseNum(json['cantidad']),
      umbralUsado: _parseIntNullable(json['umbralUsado']),
      personalizado: json['personalizado'] == true,
      contenidoPorUnidad: _parseNumNullable(json['contenidoPorUnidad']),
      unidadContenido: json['unidadContenido']?.toString(),
      totalDisponible: _parseNumNullable(json['totalDisponible']),
    );
  }

  Map<String, dynamic> toJson() => {
    'insumoId': insumoId,
    'nombre': nombre,
    'unidad': unidad,
    'categoria': categoria,
    'cantidad': cantidad,
    'umbralUsado': umbralUsado,
    'personalizado': personalizado,
    'contenidoPorUnidad': contenidoPorUnidad,
    'unidadContenido': unidadContenido,
    'totalDisponible': totalDisponible,
  };
}
