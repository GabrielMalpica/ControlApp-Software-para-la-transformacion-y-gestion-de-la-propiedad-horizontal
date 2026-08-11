import 'package:flutter_application_1/model/commerce_models.dart';

class CommerceInsumoRef {
  const CommerceInsumoRef({
    required this.id,
    required this.nombre,
    required this.unidad,
  });

  final int id;
  final String nombre;
  final String unidad;

  factory CommerceInsumoRef.fromJson(Map<String, dynamic> json) {
    return CommerceInsumoRef(
      id: (json['id'] as num?)?.toInt() ?? 0,
      nombre: repairCommerceText(json['nombre']),
      unidad: json['unidad']?.toString() ?? '',
    );
  }
}

class CommerceOrderDetailItem {
  const CommerceOrderDetailItem({
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
    required this.insumo,
  });

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
  final CommerceInsumoRef? insumo;

  factory CommerceOrderDetailItem.fromJson(Map<String, dynamic> json) {
    final rawInsumo = json['insumo'];
    return CommerceOrderDetailItem(
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
      insumo: rawInsumo is Map<String, dynamic>
          ? CommerceInsumoRef.fromJson(rawInsumo)
          : null,
    );
  }
}

class CommerceOrderHistoryItem {
  const CommerceOrderHistoryItem({
    required this.estadoAnterior,
    required this.estadoNuevo,
    required this.cambiadoPor,
    required this.cambiadoPorRol,
    required this.motivo,
    required this.creadoEn,
  });

  final String? estadoAnterior;
  final String estadoNuevo;
  final String cambiadoPor;
  final String cambiadoPorRol;
  final String? motivo;
  final DateTime? creadoEn;

  factory CommerceOrderHistoryItem.fromJson(Map<String, dynamic> json) {
    return CommerceOrderHistoryItem(
      estadoAnterior: json['estadoAnterior']?.toString(),
      estadoNuevo: json['estadoNuevo']?.toString() ?? '',
      cambiadoPor: json['cambiadoPor']?.toString() ?? '',
      cambiadoPorRol: json['cambiadoPorRol']?.toString() ?? '',
      motivo: json['motivo']?.toString(),
      creadoEn: DateTime.tryParse(json['creadoEn']?.toString() ?? ''),
    );
  }
}

class CommerceInventoryEntry {
  const CommerceInventoryEntry({
    required this.insumoNombre,
    required this.unidad,
    required this.cantidad,
    required this.stockActual,
  });

  final String insumoNombre;
  final String unidad;
  final double cantidad;
  final double stockActual;

  factory CommerceInventoryEntry.fromJson(Map<String, dynamic> json) {
    return CommerceInventoryEntry(
      insumoNombre: json['insumoNombre']?.toString() ?? '',
      unidad: json['unidad']?.toString() ?? '',
      cantidad: (json['cantidad'] as num?)?.toDouble() ?? 0,
      stockActual: (json['stockActual'] as num?)?.toDouble() ?? 0,
    );
  }
}

class CommerceOrderDetail {
  const CommerceOrderDetail({
    required this.id,
    required this.tipo,
    required this.estado,
    required this.estadoWoo,
    required this.wooOrderId,
    required this.conjuntoId,
    required this.conjuntoNombre,
    required this.total,
    required this.moneda,
    required this.pagarAhora,
    required this.fechaServicio,
    required this.turnoServicio,
    required this.opcionPagoServicio,
    required this.whatsappPhone,
    required this.creadoEn,
    required this.entradaInventarioAplicada,
    required this.puntosAplicados,
    required this.transicionesPermitidas,
    required this.items,
    required this.historial,
    required this.entradasInventario,
  });

  final int id;
  final String tipo;
  final String estado;
  final String estadoWoo;
  final String wooOrderId;
  final String? conjuntoId;
  final String? conjuntoNombre;
  final double total;
  final String moneda;
  final double pagarAhora;
  final String? fechaServicio;
  final String? turnoServicio;
  final String? opcionPagoServicio;
  final String whatsappPhone;
  final DateTime? creadoEn;
  final bool entradaInventarioAplicada;
  final bool puntosAplicados;
  final List<String> transicionesPermitidas;
  final List<CommerceOrderDetailItem> items;
  final List<CommerceOrderHistoryItem> historial;
  final List<CommerceInventoryEntry> entradasInventario;

  bool get esConjunto => tipo == 'CONJUNTO';

  factory CommerceOrderDetail.fromJson(Map<String, dynamic> json) {
    return CommerceOrderDetail(
      id: (json['id'] as num?)?.toInt() ?? 0,
      tipo: json['tipo']?.toString() ?? '',
      estado: json['estado']?.toString() ?? '',
      estadoWoo: json['estadoWoo']?.toString() ?? '',
      wooOrderId: json['wooOrderId']?.toString() ?? '',
      conjuntoId: json['conjuntoId']?.toString(),
      conjuntoNombre: json['conjuntoNombre'] == null
          ? null
          : repairCommerceText(json['conjuntoNombre']),
      total: (json['total'] as num?)?.toDouble() ?? 0,
      moneda: json['moneda']?.toString() ?? 'COP',
      pagarAhora: (json['pagarAhora'] as num?)?.toDouble() ?? 0,
      fechaServicio: json['fechaServicio']?.toString(),
      turnoServicio: json['turnoServicio'] == null
          ? null
          : repairCommerceText(json['turnoServicio']),
      opcionPagoServicio: json['opcionPagoServicio']?.toString(),
      whatsappPhone: json['whatsappPhone']?.toString() ?? '',
      creadoEn: DateTime.tryParse(json['creadoEn']?.toString() ?? ''),
      entradaInventarioAplicada:
          json['entradaInventarioAplicada'] as bool? ?? false,
      puntosAplicados: json['puntosAplicados'] as bool? ?? false,
      transicionesPermitidas:
          (json['transicionesPermitidas'] as List<dynamic>? ?? const [])
              .map((value) => value.toString())
              .toList(),
      items: (json['items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(CommerceOrderDetailItem.fromJson)
          .toList(),
      historial: (json['historial'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(CommerceOrderHistoryItem.fromJson)
          .toList(),
      entradasInventario:
          (json['entradasInventario'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(CommerceInventoryEntry.fromJson)
              .toList(),
    );
  }
}

class ReceiptPreviewItem {
  const ReceiptPreviewItem({
    required this.itemId,
    required this.producto,
    required this.sku,
    required this.cantidad,
    required this.insumo,
    required this.origenMapeo,
  });

  final int itemId;
  final String producto;
  final String? sku;
  final double cantidad;
  final CommerceInsumoRef? insumo;
  final String origenMapeo;

  factory ReceiptPreviewItem.fromJson(Map<String, dynamic> json) {
    final rawInsumo = json['insumo'];
    return ReceiptPreviewItem(
      itemId: (json['itemId'] as num?)?.toInt() ?? 0,
      producto: json['producto']?.toString() ?? '',
      sku: json['sku']?.toString(),
      cantidad: (json['cantidad'] as num?)?.toDouble() ?? 0,
      insumo: rawInsumo is Map<String, dynamic>
          ? CommerceInsumoRef.fromJson(rawInsumo)
          : null,
      origenMapeo: json['origenMapeo']?.toString() ?? '',
    );
  }
}

class ReceiptPreview {
  const ReceiptPreview({
    required this.puedeAplicar,
    required this.yaAplicada,
    required this.mensaje,
    required this.items,
    required this.insumosDisponibles,
  });

  final bool puedeAplicar;
  final bool yaAplicada;
  final String mensaje;
  final List<ReceiptPreviewItem> items;
  final List<CommerceInsumoRef> insumosDisponibles;

  factory ReceiptPreview.fromJson(Map<String, dynamic> json) {
    return ReceiptPreview(
      puedeAplicar: json['puedeAplicar'] as bool? ?? false,
      yaAplicada: json['yaAplicada'] as bool? ?? false,
      mensaje: json['mensaje']?.toString() ?? '',
      items: (json['items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ReceiptPreviewItem.fromJson)
          .toList(),
      insumosDisponibles:
          (json['insumosDisponibles'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(CommerceInsumoRef.fromJson)
              .toList(),
    );
  }
}
