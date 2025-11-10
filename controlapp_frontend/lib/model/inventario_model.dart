// lib/models/inventario_insumo_model.dart

class Inventario {
  final int id;
  final int inventarioId;
  final int insumoId;
  final int cantidad;
  final int? umbralMinimo;

  Inventario({
    required this.id,
    required this.inventarioId,
    required this.insumoId,
    required this.cantidad,
    this.umbralMinimo,
  });

  factory Inventario.fromJson(Map<String, dynamic> json) {
    return Inventario(
      id: json['id'],
      inventarioId: json['inventarioId'],
      insumoId: json['insumoId'],
      cantidad: json['cantidad'],
      umbralMinimo: json['umbralMinimo'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'inventarioId': inventarioId,
      'insumoId': insumoId,
      'cantidad': cantidad,
      'umbralMinimo': umbralMinimo,
    };
  }
}
