class ResidentCartItem {
  final int productId;
  final String name;
  final String sku;
  final String imageUrl;
  final double unitPrice;
  final int quantity;
  final String type;

  const ResidentCartItem({
    required this.productId,
    required this.name,
    required this.sku,
    required this.imageUrl,
    required this.unitPrice,
    required this.quantity,
    required this.type,
  });

  ResidentCartItem copyWith({int? quantity}) {
    return ResidentCartItem(
      productId: productId,
      name: name,
      sku: sku,
      imageUrl: imageUrl,
      unitPrice: unitPrice,
      quantity: quantity ?? this.quantity,
      type: type,
    );
  }

  double get subtotal => unitPrice * quantity;
}

class ResidentOrderItem {
  final int id;
  final String nombreProducto;
  final double cantidad;
  final double precioUnitario;
  final double subtotal;

  const ResidentOrderItem({
    required this.id,
    required this.nombreProducto,
    required this.cantidad,
    required this.precioUnitario,
    required this.subtotal,
  });

  factory ResidentOrderItem.fromJson(Map<String, dynamic> json) {
    return ResidentOrderItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      nombreProducto: json['nombreProducto']?.toString() ?? '',
      cantidad: (json['cantidad'] as num?)?.toDouble() ?? 0,
      precioUnitario: (json['precioUnitario'] as num?)?.toDouble() ?? 0,
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
    );
  }
}

class ResidentOrderSummary {
  final int id;
  final String wooOrderId;
  final String estado;
  final String estadoWoo;
  final double total;
  final String moneda;
  final DateTime? creadoEn;
  final int cantidadItems;
  final List<ResidentOrderItem> items;
  final String? pagoUrl;

  const ResidentOrderSummary({
    required this.id,
    required this.wooOrderId,
    required this.estado,
    required this.estadoWoo,
    required this.total,
    required this.moneda,
    required this.creadoEn,
    required this.cantidadItems,
    required this.items,
    required this.pagoUrl,
  });

  factory ResidentOrderSummary.fromJson(Map<String, dynamic> json) {
    return ResidentOrderSummary(
      id: (json['id'] as num?)?.toInt() ?? 0,
      wooOrderId: json['wooOrderId']?.toString() ?? '',
      estado: json['estado']?.toString() ?? '',
      estadoWoo: json['estadoWoo']?.toString() ?? '',
      total: (json['total'] as num?)?.toDouble() ?? 0,
      moneda: json['moneda']?.toString() ?? 'COP',
      creadoEn: json['creadoEn'] != null ? DateTime.tryParse(json['creadoEn'].toString()) : null,
      cantidadItems: (json['cantidadItems'] as num?)?.toInt() ?? 0,
      pagoUrl: json['pagoUrl']?.toString(),
      items: (json['items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ResidentOrderItem.fromJson)
          .toList(),
    );
  }
}
