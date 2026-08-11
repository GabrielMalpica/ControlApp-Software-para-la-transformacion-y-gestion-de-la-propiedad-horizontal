import 'package:flutter_application_1/model/commerce_models.dart';

class ResidentCartItem {
  final String cartKey;
  final int productId;
  final String name;
  final String sku;
  final String imageUrl;
  final double unitPrice;
  final int quantity;
  final String type;
  final CommerceServiceSelection? service;

  const ResidentCartItem({
    required this.cartKey,
    required this.productId,
    required this.name,
    required this.sku,
    required this.imageUrl,
    required this.unitPrice,
    required this.quantity,
    required this.type,
    this.service,
  });

  ResidentCartItem copyWith({int? quantity}) {
    return ResidentCartItem(
      cartKey: cartKey,
      productId: productId,
      name: name,
      sku: sku,
      imageUrl: imageUrl,
      unitPrice: unitPrice,
      quantity: quantity ?? this.quantity,
      type: type,
      service: service,
    );
  }

  double get subtotal => unitPrice * quantity;
  double get payNow => service?.payNowFor(subtotal) ?? 0;

  Map<String, dynamic> toRequestJson() => <String, dynamic>{
    'productId': productId,
    'quantity': quantity,
    if (service != null) 'service': service!.toRequestJson(),
  };
}

class ResidentOrderItem {
  final int id;
  final String nombreProducto;
  final String? sku;
  final double cantidad;
  final double precioUnitario;
  final double subtotal;
  final double pagarAhora;
  final String? fechaServicio;
  final String? turnoServicio;
  final String? opcionPagoServicio;
  final List<dynamic> addonsServicio;

  const ResidentOrderItem({
    required this.id,
    required this.nombreProducto,
    required this.sku,
    required this.cantidad,
    required this.precioUnitario,
    required this.subtotal,
    required this.pagarAhora,
    required this.fechaServicio,
    required this.turnoServicio,
    required this.opcionPagoServicio,
    required this.addonsServicio,
  });

  factory ResidentOrderItem.fromJson(Map<String, dynamic> json) {
    return ResidentOrderItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      nombreProducto: repairCommerceText(json['nombreProducto']),
      sku: json['sku']?.toString(),
      cantidad: (json['cantidad'] as num?)?.toDouble() ?? 0,
      precioUnitario: (json['precioUnitario'] as num?)?.toDouble() ?? 0,
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
      pagarAhora: (json['pagarAhora'] as num?)?.toDouble() ?? 0,
      fechaServicio: json['fechaServicio']?.toString(),
      turnoServicio: json['turnoServicio'] == null
          ? null
          : repairCommerceText(json['turnoServicio']),
      opcionPagoServicio: json['opcionPagoServicio']?.toString(),
      addonsServicio:
          (json['addonsServicio'] as List<dynamic>? ?? const <dynamic>[])
              .map(repairCommerceJsonValue)
              .toList(),
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
  final double pagarAhora;
  final String? fechaServicio;
  final String? turnoServicio;
  final String? opcionPagoServicio;
  final String whatsappPhone;

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
    required this.pagarAhora,
    required this.fechaServicio,
    required this.turnoServicio,
    required this.opcionPagoServicio,
    required this.whatsappPhone,
  });

  factory ResidentOrderSummary.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ResidentOrderItem.fromJson)
        .toList();
    return ResidentOrderSummary(
      id: (json['id'] as num?)?.toInt() ?? 0,
      wooOrderId: json['wooOrderId']?.toString() ?? '',
      estado: json['estado']?.toString() ?? '',
      estadoWoo: json['estadoWoo']?.toString() ?? '',
      total: (json['total'] as num?)?.toDouble() ?? 0,
      moneda: json['moneda']?.toString() ?? 'COP',
      creadoEn: json['creadoEn'] != null
          ? DateTime.tryParse(json['creadoEn'].toString())
          : null,
      cantidadItems: (json['cantidadItems'] as num?)?.toInt() ?? items.length,
      pagoUrl: json['pagoUrl']?.toString(),
      pagarAhora: (json['pagarAhora'] as num?)?.toDouble() ?? 0,
      fechaServicio: json['fechaServicio']?.toString(),
      turnoServicio: json['turnoServicio'] == null
          ? null
          : repairCommerceText(json['turnoServicio']),
      opcionPagoServicio: json['opcionPagoServicio']?.toString(),
      whatsappPhone: json['whatsappPhone']?.toString() ?? '',
      items: items,
    );
  }
}
