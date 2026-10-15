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
    this.origenConfirmacion,
    this.webhooksRecibidos = 0,
    this.webhookPrimeroEn,
    this.ultimaVerificacionEn,
    this.ultimaVerificacionOrigen,
    this.qrExpiraEn,
    this.pagadorNombre,
    this.pagadorTipoDocumento,
    this.pagadorDocumentoUltimos4,
    this.verificable = false,
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

  /// Qué disparó la consulta que confirmó el pago (WEBHOOK, USUARIO, WORKER,
  /// CONCILIACION o ADMIN). Toda confirmación la decide la API de Factus.
  final String? origenConfirmacion;

  /// Avisos del webhook de Factus recibidos para este cobro.
  final int webhooksRecibidos;
  final DateTime? webhookPrimeroEn;
  final DateTime? ultimaVerificacionEn;
  final String? ultimaVerificacionOrigen;
  final DateTime? qrExpiraEn;

  /// Pagador según Factus: solo nombre y los últimos 4 del documento.
  final String? pagadorNombre;
  final String? pagadorTipoDocumento;
  final String? pagadorDocumentoUltimos4;

  /// Se puede pedir "Verificar con Factus" (pendiente o cerrado sin pago).
  final bool verificable;

  bool get esTienda => canal == 'WOOCOMMERCE';

  /// Dónde se originó el cobro: tienda web, app o el saldo de un servicio.
  String get canalLabel => switch (canal) {
    'WOOCOMMERCE' => 'Tienda web',
    'SALDO_SERVICIO' => 'Saldo de servicio',
    _ => 'App',
  };

  /// "Juan Pérez · CC ···7890", o null si Factus no informó el pagador.
  String? get pagador {
    if (pagadorNombre == null || pagadorNombre!.isEmpty) return null;
    final doc = pagadorDocumentoUltimos4 == null
        ? ''
        : ' · ${pagadorTipoDocumento ?? 'Doc.'} ···$pagadorDocumentoUltimos4';
    return '$pagadorNombre$doc';
  }

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
      pendienteSincronizarWoo:
          json['pendienteSincronizarWoo'] as bool? ?? false,
      requiereAccion: json['requiereAccion'] as bool? ?? false,
      creadoEn: _fecha(json['creadoEn']),
      origenConfirmacion: json['origenConfirmacion']?.toString(),
      webhooksRecibidos: (json['webhooksRecibidos'] as num?)?.toInt() ?? 0,
      webhookPrimeroEn: _fecha(json['webhookPrimeroEn']),
      ultimaVerificacionEn: _fecha(json['ultimaVerificacionEn']),
      ultimaVerificacionOrigen: json['ultimaVerificacionOrigen']?.toString(),
      qrExpiraEn: _fecha(json['qrExpiraEn']),
      pagadorNombre: json['pagadorNombre']?.toString(),
      pagadorTipoDocumento: json['pagadorTipoDocumento']?.toString(),
      pagadorDocumentoUltimos4: json['pagadorDocumentoUltimos4']?.toString(),
      verificable: json['verificable'] as bool? ?? false,
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
    this.origen,
  });

  final String tipo;
  final String? estadoAnterior;
  final String? estadoNuevo;

  /// Motivo / mensaje legible sacado del payload del evento, si lo hay.
  final String? detalle;
  final DateTime? creadoEn;

  /// Qué disparó la consulta (WEBHOOK, USUARIO, WORKER, CONCILIACION, ADMIN).
  final String? origen;

  factory PagoAdminEvento.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'];
    String? detalle;
    String? origen;
    if (payload is Map) {
      if (payload['accion'] == 'VERIFICAR_CON_FACTUS') {
        detalle =
            'Verificación con Factus pedida por ${payload['nombre'] ?? 'el equipo'}';
      } else {
        detalle = (payload['motivo'] ?? payload['error'] ?? payload['accion'])
            ?.toString();
      }
      origen = payload['origen']?.toString();
    }
    return PagoAdminEvento(
      tipo: json['tipo']?.toString() ?? '',
      estadoAnterior: json['estadoAnterior']?.toString(),
      estadoNuevo: json['estadoNuevo']?.toString(),
      detalle: detalle,
      origen: origen,
      creadoEn: json['creadoEn'] == null
          ? null
          : DateTime.tryParse(json['creadoEn'].toString()),
    );
  }
}

/// Una entrega del webhook de Factus para un cobro y qué pasó con ella.
class PagoAdminWebhook {
  const PagoAdminWebhook({
    required this.id,
    required this.recibidoEn,
    required this.estado,
    required this.resultado,
    required this.detalle,
    required this.montoReportado,
  });

  final int id;
  final DateTime? recibidoEn;

  /// RECIBIDO (en proceso) o PROCESADO.
  final String estado;
  final String? resultado;
  final String? detalle;
  final double? montoReportado;

  factory PagoAdminWebhook.fromJson(Map<String, dynamic> json) {
    return PagoAdminWebhook(
      id: (json['id'] as num?)?.toInt() ?? 0,
      recibidoEn: json['recibidoEn'] == null
          ? null
          : DateTime.tryParse(json['recibidoEn'].toString()),
      estado: json['estado']?.toString() ?? '',
      resultado: json['resultado']?.toString(),
      detalle: json['detalle']?.toString(),
      montoReportado: (json['montoReportado'] as num?)?.toDouble(),
    );
  }
}

class PagoAdminDetalle {
  const PagoAdminDetalle({
    required this.item,
    required this.eventos,
    this.webhooks = const [],
  });

  final PagoAdminItem item;
  final List<PagoAdminEvento> eventos;
  final List<PagoAdminWebhook> webhooks;

  factory PagoAdminDetalle.fromJson(Map<String, dynamic> json) {
    return PagoAdminDetalle(
      item: PagoAdminItem.fromJson(json),
      eventos: (json['eventos'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PagoAdminEvento.fromJson)
          .toList(),
      webhooks: (json['webhooks'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PagoAdminWebhook.fromJson)
          .toList(),
    );
  }
}

/// Salud del webhook de Factus y modo de confirmación
/// (GET /commerce/pagos/salud).
class SaludPagos {
  const SaludPagos({
    required this.modoConfigurado,
    required this.modoEfectivo,
    required this.motivo,
    required this.webhookConfigurado,
    required this.ultimoWebhookEn,
    required this.avisos24h,
    required this.avisosSinProcesar,
    required this.confirmados7d,
    required this.confirmadosPorWebhook7d,
    required this.pagosSinWebhook24h,
    required this.cobrosPendientes,
  });

  /// "polling" o "webhook".
  final String modoConfigurado;
  final String modoEfectivo;

  /// Por qué el modo efectivo no es el configurado (modo degradado).
  final String? motivo;
  final bool webhookConfigurado;
  final DateTime? ultimoWebhookEn;
  final int avisos24h;
  final int avisosSinProcesar;
  final int confirmados7d;
  final int confirmadosPorWebhook7d;
  final int pagosSinWebhook24h;
  final int cobrosPendientes;

  bool get usaWebhook => modoEfectivo == 'webhook';

  /// Hay algo que mirar: el aviso de Factus no está llegando o hay avisos
  /// atascados.
  bool get conNovedades =>
      motivo != null || pagosSinWebhook24h > 0 || avisosSinProcesar > 5;

  factory SaludPagos.fromJson(Map<String, dynamic> json) {
    final confirmados = json['confirmados7d'];
    final porOrigen = confirmados is Map ? confirmados['porOrigen'] : null;
    return SaludPagos(
      modoConfigurado: json['modoConfigurado']?.toString() ?? 'polling',
      modoEfectivo: json['modoEfectivo']?.toString() ?? 'polling',
      motivo: json['motivo']?.toString(),
      webhookConfigurado: json['webhookConfigurado'] as bool? ?? false,
      ultimoWebhookEn: json['ultimoWebhookEn'] == null
          ? null
          : DateTime.tryParse(json['ultimoWebhookEn'].toString()),
      avisos24h: (json['avisos24h'] as num?)?.toInt() ?? 0,
      avisosSinProcesar: (json['avisosSinProcesar'] as num?)?.toInt() ?? 0,
      confirmados7d: confirmados is Map
          ? (confirmados['total'] as num?)?.toInt() ?? 0
          : 0,
      confirmadosPorWebhook7d: porOrigen is Map
          ? (porOrigen['WEBHOOK'] as num?)?.toInt() ?? 0
          : 0,
      pagosSinWebhook24h: (json['pagosSinWebhook24h'] as num?)?.toInt() ?? 0,
      cobrosPendientes: (json['cobrosPendientes'] as num?)?.toInt() ?? 0,
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

/// Quién disparó una consulta a Factus.
String pagoOrigenLabel(String? origen) {
  switch (origen) {
    case 'WEBHOOK':
      return 'aviso de Factus (webhook)';
    case 'USUARIO':
      return 'el cliente ("Ya pagué")';
    case 'WORKER':
      return 'verificación automática';
    case 'CONCILIACION':
      return 'conciliación';
    case 'ADMIN':
      return 'el equipo ("Verificar con Factus")';
    default:
      return 'sin dato';
  }
}

/// Qué pasó con un aviso del webhook.
String webhookResultadoLabel(String? resultado) {
  switch (resultado) {
    case null:
      return 'En proceso';
    case 'CONFIRMADO':
      return 'Confirmó el pago';
    case 'YA_PROCESADO':
      return 'Repetido (ya estaba resuelto)';
    case 'NO_CONFIRMADO_POR_API':
      return 'Factus no lo confirmó';
    case 'DISCREPANCIA':
      return 'Monto distinto';
    case 'PAGADO_DUPLICADO':
      return 'Pago duplicado';
    case 'PAGADO_HUERFANO':
      return 'Pagado sin pedido';
    case 'REFERENCIA_DESCONOCIDA':
      return 'Referencia desconocida';
    case 'PAYLOAD_INVALIDO':
      return 'Aviso ilegible';
    case 'ERROR':
      return 'Error al procesarlo';
    default:
      return resultado;
  }
}

/// Etiqueta legible del tipo de evento de la bitácora de un cobro.
String pagoEventoLabel(String tipo) {
  switch (tipo) {
    case 'CREADO':
      return 'Cobro creado';
    case 'CONSULTA':
      return 'Consulta a Factus';
    case 'CAMBIO_ESTADO':
      return 'Cambio de estado';
    case 'CONFIRMACION_PEDIDO':
      return 'Pedido marcado como pagado';
    case 'SYNC_WOO':
      return 'Tienda actualizada';
    case 'ERROR':
      return 'Factus no respondió';
    case 'ACCION_MANUAL':
      return 'Acción del equipo';
    case 'WEBHOOK_RECIBIDO':
      return 'Aviso de Factus recibido';
    default:
      return tipo;
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
