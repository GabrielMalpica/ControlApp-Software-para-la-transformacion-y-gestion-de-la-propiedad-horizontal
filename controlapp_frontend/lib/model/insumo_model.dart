// lib/model/insumo_model.dart

/// Categorías de insumos, debe coincidir con el enum del backend `CategoriaInsumo`
enum CategoriaInsumo {
  limpieza,
  jardineria,
  construccion,
  seguridad,
  otro,
}

class InsumoModel {
  final int id;
  final String nombre;
  final String unidad;
  final CategoriaInsumo categoria;
  final int? umbralGlobalMinimo;
  final String? empresaId;

  InsumoModel({
    required this.id,
    required this.nombre,
    required this.unidad,
    required this.categoria,
    this.umbralGlobalMinimo,
    this.empresaId,
  });

  /// Crear desde JSON (backend → app)
  factory InsumoModel.fromJson(Map<String, dynamic> json) {
    return InsumoModel(
      id: json['id'] as int,
      nombre: json['nombre'] as String,
      unidad: json['unidad'] as String,
      categoria: CategoriaInsumo.values.firstWhere(
        (e) => e.name.toLowerCase() == json['categoria'].toString().toLowerCase(),
        orElse: () => CategoriaInsumo.otro,
      ),
      umbralGlobalMinimo: json['umbralGlobalMinimo'] != null
          ? json['umbralGlobalMinimo'] as int
          : null,
      empresaId: json['empresaId'] as String?,
    );
  }

  /// Convertir a JSON (app → backend)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'unidad': unidad,
      'categoria': categoria.name,
      'umbralGlobalMinimo': umbralGlobalMinimo,
      'empresaId': empresaId,
    };
  }
}
