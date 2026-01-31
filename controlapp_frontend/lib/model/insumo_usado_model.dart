class InsumoUsadoItem {
  final int insumoId;
  final num cantidad;

  InsumoUsadoItem({
    required this.insumoId,
    required this.cantidad,
  });

  factory InsumoUsadoItem.fromJson(Map<String, dynamic> json) {
    return InsumoUsadoItem(
      insumoId: int.parse(json['insumoId'].toString()),
      cantidad: num.tryParse(json['cantidad'].toString()) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'insumoId': insumoId,
      'cantidad': cantidad,
    };
  }
}
