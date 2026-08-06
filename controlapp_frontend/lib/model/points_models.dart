class PointsBenefit {
  const PointsBenefit({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.puntosCosto,
    required this.valorDescuento,
    required this.disponible,
    required this.activo,
  });

  final int id;
  final String nombre;
  final String descripcion;
  final int puntosCosto;
  final double valorDescuento;
  final bool disponible;
  final bool activo;

  factory PointsBenefit.fromJson(Map<String, dynamic> json) {
    return PointsBenefit(
      id: (json['id'] as num?)?.toInt() ?? 0,
      nombre: json['nombre']?.toString() ?? '',
      descripcion: json['descripcion']?.toString() ?? '',
      puntosCosto: (json['puntosCosto'] as num?)?.toInt() ?? 0,
      valorDescuento: (json['valorDescuento'] as num?)?.toDouble() ?? 0,
      disponible: json['disponible'] as bool? ?? false,
      activo: json['activo'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (id > 0) 'id': id,
    'nombre': nombre,
    'descripcion': descripcion,
    'puntosCosto': puntosCosto,
    'valorDescuento': valorDescuento,
    'activo': activo,
  };
}

class PointsMovement {
  const PointsMovement({
    required this.id,
    required this.tipo,
    required this.puntos,
    required this.descripcion,
    required this.creadoEn,
    required this.pedidoId,
    required this.beneficioNombre,
  });

  final int id;
  final String tipo;
  final int puntos;
  final String descripcion;
  final DateTime? creadoEn;
  final int? pedidoId;
  final String? beneficioNombre;

  factory PointsMovement.fromJson(Map<String, dynamic> json) {
    return PointsMovement(
      id: (json['id'] as num?)?.toInt() ?? 0,
      tipo: json['tipo']?.toString() ?? '',
      puntos: (json['puntos'] as num?)?.toInt() ?? 0,
      descripcion: json['descripcion']?.toString() ?? '',
      creadoEn: DateTime.tryParse(json['creadoEn']?.toString() ?? ''),
      pedidoId: (json['pedidoId'] as num?)?.toInt(),
      beneficioNombre: json['beneficioNombre']?.toString(),
    );
  }
}

class PointsConfig {
  const PointsConfig({
    required this.conjuntoId,
    required this.activo,
    required this.montoPorPuntoResidente,
    required this.montoPorPuntoConjunto,
    required this.minimoRedencionPuntos,
    required this.beneficios,
  });

  final String conjuntoId;
  final bool activo;
  final double montoPorPuntoResidente;
  final double montoPorPuntoConjunto;
  final int minimoRedencionPuntos;
  final List<PointsBenefit> beneficios;

  factory PointsConfig.fromJson(Map<String, dynamic> json) {
    return PointsConfig(
      conjuntoId: json['conjuntoId']?.toString() ?? '',
      activo: json['activo'] as bool? ?? false,
      montoPorPuntoResidente:
          (json['montoPorPuntoResidente'] as num?)?.toDouble() ?? 1000,
      montoPorPuntoConjunto:
          (json['montoPorPuntoConjunto'] as num?)?.toDouble() ?? 1000,
      minimoRedencionPuntos:
          (json['minimoRedencionPuntos'] as num?)?.toInt() ?? 100,
      beneficios: (json['beneficios'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PointsBenefit.fromJson)
          .toList(),
    );
  }
}

class PointsSummary {
  const PointsSummary({
    required this.conjuntoId,
    required this.conjuntoNombre,
    required this.saldo,
    required this.config,
    required this.beneficios,
    required this.movimientos,
  });

  final String conjuntoId;
  final String conjuntoNombre;
  final int saldo;
  final PointsConfig config;
  final List<PointsBenefit> beneficios;
  final List<PointsMovement> movimientos;

  factory PointsSummary.fromJson(Map<String, dynamic> json) {
    return PointsSummary(
      conjuntoId: json['conjuntoId']?.toString() ?? '',
      conjuntoNombre: json['conjuntoNombre']?.toString() ?? '',
      saldo: (json['saldo'] as num?)?.toInt() ?? 0,
      config: PointsConfig.fromJson(
        json['config'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
      beneficios: (json['beneficios'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PointsBenefit.fromJson)
          .toList(),
      movimientos: (json['movimientos'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PointsMovement.fromJson)
          .toList(),
    );
  }
}
