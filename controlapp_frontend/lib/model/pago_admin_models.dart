/// Cobro de Factus Pay visto por el equipo (gerente / jefe de operaciones):
/// historial, cobros que necesitan una decisión y conciliación.
class PagoAdminItem {
  const PagoAdminItem({
    required this.id,
    required this.referenceCode,
    required this.canal,
    required this.estado,
    required this.estadoProveedor,
    required this.montoEsperado,
    required this.montoProveedor,
    required this.pedidoAppId,
    required this.wooOrderId,
    required this.conjuntoNombre,
    required this.pagadoDetectadoEn,
    required this.pendienteSincronizarWoo,
    required this.requiereAccion,
    required this.creadoEn,
  });

  final int id;
  final String referenceCode;
  final String canal;
  final String estado;
  final String? estadoProveedor;
  final double montoEsperado;
  final double? montoProveedor;
  final int? pedidoAppId;
  final String? wooOrderId;
  final String? conjuntoNombre;
  final DateTime? pagadoDetectadoEn;
  final bool pendienteSincronizarWoo;
  final bool requiereAccion;
  final DateTime? creadoEn;

  bool get esTienda => canal == 'WOOCOMMERCE';

  /// "Pedido #41", "Orden web #900" o la referencia si no hay ninguno.
  String get origen {
    if (pedidoAppId != null) return 'Pedido #$pedidoAppId';
    if (wooOrderId != null) return 'Orden web #$wooOrderId';
    return referenceCode;
  }

  static DateTime? _fecha(Object? value) =>
      value == null ? null : DateTime.tryParse(value.toString());

  factory PagoAdminItem.fromJson(Map<String, dynamic> json) {
    return PagoAdminItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      referenceCode: json['referenceCode']?.toString() ?? '',
      canal: json['canal']?.toString() ?? '',
      estado: json['estado']?.toString() ?? '',
      estadoProveedor: json['estadoProveedor']?.toString(),
      montoEsperado: (json['montoEsperado'] as num?)?.toDouble() ?? 0,
      montoProveedor: (json['montoProveedor'] as num?)?.toDouble(),
      pedidoAppId: (json['pedidoAppId'] as num?)?.toInt(),
      wooOrderId: json['wooOrderId']?.toString(),
      conjuntoNombre: json['conjuntoNombre']?.toString(),
      pagadoDetectadoEn: _fecha(json['pagadoDetectadoEn']),
      pendienteSincronizarWoo: json['pendienteSincronizarWoo'] as bool? ?? false,
      requiereAccion: json['requiereAccion'] as bool? ?? false,
      creadoEn: _fecha(json['creadoEn']),
    );
  }
}

class PagoAdminEvento {
  const PagoAdminEvento({
    required this.tipo,
    required this.estadoAnterior,
    required this.estadoNuevo,
    required this.detalle,
    required this.creadoEn,
  });

  final String tipo;
  final String? estadoAnterior;
  final String? estadoNuevo;

  /// Motivo / mensaje legible sacado del payload del evento, si lo hay.
  final String? detalle;
  final DateTime? creadoEn;

  factory PagoAdminEvento.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'];
    String? detalle;
    if (payload is Map) {
      detalle = (payload['motivo'] ?? payload['error'] ?? payload['accion'])
          ?.toString();
    }
    return PagoAdminEvento(
      tipo: json['tipo']?.toString() ?? '',
      estadoAnterior: json['estadoAnterior']?.toString(),
      estadoNuevo: json['estadoNuevo']?.toString(),
      detalle: detalle,
      creadoEn: json['creadoEn'] == null
          ? null
          : DateTime.tryParse(json['creadoEn'].toString()),
    );
  }
}

class PagoAdminDetalle {
  const PagoAdminDetalle({required this.item, required this.eventos});

  final PagoAdminItem item;
  final List<PagoAdminEvento> eventos;

  factory PagoAdminDetalle.fromJson(Map<String, dynamic> json) {
    return PagoAdminDetalle(
      item: PagoAdminItem.fromJson(json),
      eventos: (json['eventos'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PagoAdminEvento.fromJson)
          .toList(),
    );
  }
}

class PagoAdminPagina {
  const PagoAdminPagina({
    required this.total,
    required this.pagina,
    required this.porPagina,
    required this.items,
  });

  final int total;
  final int pagina;
  final int porPagina;
  final List<PagoAdminItem> items;

  bool get hayMas => pagina * porPagina < total;

  factory PagoAdminPagina.fromJson(Map<String, dynamic> json) {
    return PagoAdminPagina(
      total: (json['total'] as num?)?.toInt() ?? 0,
      pagina: (json['pagina'] as num?)?.toInt() ?? 1,
      porPagina: (json['porPagina'] as num?)?.toInt() ?? 25,
      items: (json['items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PagoAdminItem.fromJson)
          .toList(),
    );
  }
}

class ConciliacionAnomalia {
  const ConciliacionAnomalia({
    required this.tipo,
    required this.referenceCode,
    required this.detalle,
    required this.corregida,
  });

  final String tipo;
  final String referenceCode;
  final String detalle;
  final bool corregida;

  factory ConciliacionAnomalia.fromJson(Map<String, dynamic> json) {
    return ConciliacionAnomalia(
      tipo: json['tipo']?.toString() ?? '',
      referenceCode: json['referenceCode']?.toString() ?? '',
      detalle: json['detalle']?.toString() ?? '',
      corregida: json['corregida'] as bool? ?? false,
    );
  }
}

class ConciliacionReporte {
  const ConciliacionReporte({
    required this.ejecutadaEn,
    required this.completo,
    required this.remotosPagados,
    required this.anomalias,
  });

  final DateTime? ejecutadaEn;

  /// false = el listado de Factus se cortó en el tope de páginas.
  final bool completo;
  final int remotosPagados;
  final List<ConciliacionAnomalia> anomalias;

  int get sinCorregir => anomalias.where((a) => !a.corregida).length;

  factory ConciliacionReporte.fromJson(Map<String, dynamic> json) {
    return ConciliacionReporte(
      ejecutadaEn: json['ejecutadaEn'] == null
          ? null
          : DateTime.tryParse(json['ejecutadaEn'].toString()),
      completo: json['completo'] as bool? ?? false,
      remotosPagados: (json['remotosPagados'] as num?)?.toInt() ?? 0,
      anomalias: (json['anomalias'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ConciliacionAnomalia.fromJson)
          .toList(),
    );
  }
}

/// Etiqueta legible de cada estado de un cobro.
String pagoEstadoLabel(String estado) {
  switch (estado) {
    case 'CREADO':
    case 'PENDIENTE':
      return 'Pendiente';
    case 'PAGADO':
      return 'Pagado';
    case 'FALLIDO':
    case 'ERROR':
      return 'Fallido';
    case 'VENCIDO':
      return 'Vencido';
    case 'ABANDONADO':
      return 'Abandonado';
    case 'PAGADO_HUERFANO':
      return 'Pagado sin pedido';
    case 'PAGADO_DUPLICADO':
      return 'Pago duplicado';
    case 'DISCREPANCIA':
      return 'Monto distinto';
    case 'DEVUELTO':
      return 'Devuelto';
    case 'RESUELTO':
      return 'Resuelto';
    default:
      return estado;
  }
}
