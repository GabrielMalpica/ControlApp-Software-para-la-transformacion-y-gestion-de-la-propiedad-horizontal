// lib/model/insumo_model.dart
enum CategoriaInsumo { LIMPIEZA, JARDINERIA, PISCINA }

extension CategoriaInsumoExt on CategoriaInsumo {
  String get label {
    switch (this) {
      case CategoriaInsumo.LIMPIEZA:
        return 'Limpieza';
      case CategoriaInsumo.JARDINERIA:
        return 'Jardinería';
      case CategoriaInsumo.PISCINA:
        return 'Piscina';
    }
  }

  /// Valor que espera el backend (igual al enum de Prisma)
  String get backendValue => name; // "LIMPIEZA", "JARDINERIA", "PISCINA"
}

class InsumoRequest {
  final String nombre;
  final String unidad;
  final CategoriaInsumo categoria;
  final int? umbralBajo;

  InsumoRequest({
    required this.nombre,
    required this.unidad,
    required this.categoria,
    this.umbralBajo,
  });

  Map<String, dynamic> toJson() {
    return {
      'nombre': nombre,
      'unidad': unidad,
      'categoria': categoria.backendValue,
      if (umbralBajo != null) 'umbralBajo': umbralBajo,
    };
  }
}

class InsumoResponse {
  final int id;
  final String nombre;
  final String unidad;
  final CategoriaInsumo categoria;
  final int? umbralBajo;

  InsumoResponse({
    required this.id,
    required this.nombre,
    required this.unidad,
    required this.categoria,
    this.umbralBajo,
  });

  factory InsumoResponse.fromJson(Map<String, dynamic> json) {
    final catStr = json['categoria'] as String;
    final cat = CategoriaInsumo.values.firstWhere(
      (e) => e.name == catStr,
      orElse: () => CategoriaInsumo.LIMPIEZA,
    );

    return InsumoResponse(
      id: json['id'] as int,
      nombre: json['nombre'] as String,
      unidad: json['unidad'] as String,
      categoria: cat,
      umbralBajo: json['umbralBajo'] as int?,
    );
  }
}
