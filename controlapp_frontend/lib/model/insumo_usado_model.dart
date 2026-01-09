class InsumoUsadoItem {
  final int insumoId;
  final int cantidad;

  InsumoUsadoItem({
    required this.insumoId,
    required this.cantidad,
  });

  factory InsumoUsadoItem.fromJson(Map<String, dynamic> json) {
    return InsumoUsadoItem(
      insumoId: json['insumoId'] as int,
      cantidad: json['cantidad'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'insumoId': insumoId,
      'cantidad': cantidad,
    };
  }
}
