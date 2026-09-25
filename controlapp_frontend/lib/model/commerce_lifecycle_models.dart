import 'package:flutter_application_1/model/commerce_models.dart';

class CommerceInsumoRef {
  const CommerceInsumoRef({
    required this.id,
    required this.nombre,
    required this.unidad,
    this.wooFactorConversion = 1,
  });

  final int id;
  final String nombre;
  final String unidad;
  // Cuantas unidades de "unidad" trae cada unidad comprada en la tienda.
  final double wooFactorConversion;

  factory CommerceInsumoRef.fromJson(Map<String, dynamic> json) {
    return CommerceInsumoRef(
      id: (json['id'] as num?)?.toInt() ?? 0,
      nombre: repairCommerceText(json['nombre']),
      unidad: json['unidad']?.toString() ?? '',
      wooFactorConversion:
          (json['wooFactorConversion'] as num?)?.toDouble() ?? 1,
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
    this.cantidadRecibida,
    this.novedadRecepcion,
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
  // Lo que el cliente reportó al recibir (null = pedido anterior al reporte).
  final double? cantidadRecibida;
  final String? novedadRecepcion;

  /// true si al recibir llegó menos de lo pedido.
  bool get llegoIncompleto =>
      cantidadRecibida != null && cantidadRecibida! < cantidad;

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
      cantidadRecibida: (json['cantidadRecibida'] as num?)?.toDouble(),
      novedadRecepcion: json['novedadRecepcion'] == null
          ? null
          : repairCommerceText(json['novedadRecepcion']),
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
    required this.direccionEntrega,
    required this.metodoPago,
    required this.comprobanteUrl,
    required this.comprobanteSubidoEn,
    this.verificacionComprobante,
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
  final String? direccionEntrega;
  final String? metodoPago;
  final String? comprobanteUrl;
  final DateTime? comprobanteSubidoEn;
  // Lectura automática (OCR) del comprobante; solo la recibe quien revisa pagos.
  final ComprobanteVerificacion? verificacionComprobante;
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
      direccionEntrega: json['direccionEntrega']?.toString(),
      metodoPago: json['metodoPago']?.toString(),
      comprobanteUrl: json['comprobanteUrl']?.toString(),
      comprobanteSubidoEn: json['comprobanteSubidoEn'] != null
          ? DateTime.tryParse(json['comprobanteSubidoEn'].toString())
          : null,
      verificacionComprobante: json['verificacionComprobante'] is Map
          ? ComprobanteVerificacion.fromJson(
              Map<String, dynamic>.from(json['verificacionComprobante'] as Map),
            )
          : null,
    );
  }
}

class ComprobanteVerificacionCheck {
  const ComprobanteVerificacionCheck({
    required this.clave,
    required this.ok,
    required this.detalle,
  });

  final String clave;
  // null = no se pudo evaluar.
  final bool? ok;
  final String detalle;

  factory ComprobanteVerificacionCheck.fromJson(Map<String, dynamic> json) {
    return ComprobanteVerificacionCheck(
      clave: json['clave']?.toString() ?? '',
      ok: json['ok'] as bool?,
      detalle: repairCommerceText(json['detalle']),
    );
  }
}

class ComprobanteVerificacion {
  const ComprobanteVerificacion({
    required this.veredicto,
    required this.montoDetectado,
    required this.referencia,
    required this.checks,
    required this.analizadoEn,
  });

  /// COINCIDE, REVISAR, DUPLICADO o ILEGIBLE.
  final String veredicto;
  final double? montoDetectado;
  final String? referencia;
  final List<ComprobanteVerificacionCheck> checks;
  final DateTime? analizadoEn;

  factory ComprobanteVerificacion.fromJson(Map<String, dynamic> json) {
    return ComprobanteVerificacion(
      veredicto: json['veredicto']?.toString() ?? 'REVISAR',
      montoDetectado: (json['montoDetectado'] as num?)?.toDouble(),
      referencia: json['referencia']?.toString(),
      checks: (json['checks'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map(
            (item) => ComprobanteVerificacionCheck.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
      analizadoEn: DateTime.tryParse(json['analizadoEn']?.toString() ?? ''),
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
    required this.cantidadInventario,
    required this.factorDesdeWoo,
  });

  final int itemId;
  final String producto;
  final String? sku;
  final double cantidad;
  final CommerceInsumoRef? insumo;
  final String origenMapeo;
  // cantidad x factor de conversion del insumo: lo que realmente sumara al
  // inventario del conjunto.
  final double cantidadInventario;
  // true = el factor de conversion lo declaro WooCommerce (campo del
  // producto/variacion), no hace falta escribirlo al mapear.
  final bool factorDesdeWoo;

  factory ReceiptPreviewItem.fromJson(Map<String, dynamic> json) {
    final rawInsumo = json['insumo'];
    final cantidad = (json['cantidad'] as num?)?.toDouble() ?? 0;
    return ReceiptPreviewItem(
      itemId: (json['itemId'] as num?)?.toInt() ?? 0,
      producto: json['producto']?.toString() ?? '',
      sku: json['sku']?.toString(),
      cantidad: cantidad,
      insumo: rawInsumo is Map<String, dynamic>
          ? CommerceInsumoRef.fromJson(rawInsumo)
          : null,
      origenMapeo: json['origenMapeo']?.toString() ?? '',
      cantidadInventario:
          (json['cantidadInventario'] as num?)?.toDouble() ?? cantidad,
      factorDesdeWoo: json['factorDesdeWoo'] as bool? ?? false,
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
    this.puedeMapear = false,
  });

  final bool puedeAplicar;
  final bool yaAplicada;
  // Solo el equipo de Control SAS configura insumos; quien recibe solo reporta.
  final bool puedeMapear;
  final String mensaje;
  final List<ReceiptPreviewItem> items;
  final List<CommerceInsumoRef> insumosDisponibles;

  factory ReceiptPreview.fromJson(Map<String, dynamic> json) {
    return ReceiptPreview(
      puedeAplicar: json['puedeAplicar'] as bool? ?? false,
      yaAplicada: json['yaAplicada'] as bool? ?? false,
      puedeMapear: json['puedeMapear'] as bool? ?? false,
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
