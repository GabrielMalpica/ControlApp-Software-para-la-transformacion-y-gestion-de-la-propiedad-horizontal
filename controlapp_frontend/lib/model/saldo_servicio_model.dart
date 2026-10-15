import 'package:flutter_application_1/model/commerce_lifecycle_models.dart';

double _num(dynamic valor) => valor is num ? valor.toDouble() : 0;

DateTime? _fecha(dynamic valor) =>
    valor == null ? null : DateTime.tryParse(valor.toString());

String? _texto(dynamic valor) {
  final t = valor?.toString().trim();
  return t == null || t.isEmpty ? null : t;
}

/// Lo que falta pagar de un servicio pagado con anticipo. Nace cuando el
/// servicio termina; mientras esté pendiente, quien lo debe no puede hacer
/// pedidos nuevos (lo decide el backend). Ver GET /commerce/saldos.
class SaldoServicio {
  const SaldoServicio({
    required this.id,
    required this.wooOrderId,
    required this.estado,
    required this.totalOrden,
    required this.pagadoAntes,
    required this.montoSaldo,
    required this.servicios,
    this.servicioTerminadoEn,
    this.pedidoAppId,
    this.pagadoEn,
    this.cobro,
  });

  final int id;
  final String wooOrderId;

  /// PENDIENTE, PAGADO o PAGADO_POR_FUERA.
  final String estado;
  final double totalOrden;
  final double pagadoAntes;
  final double montoSaldo;
  final String servicios;
  final DateTime? servicioTerminadoEn;
  final int? pedidoAppId;
  final DateTime? pagadoEn;

  /// Último código de pago (QR) generado para este saldo.
  final PagoCobroInfo? cobro;

  bool get pendiente => estado == 'PENDIENTE';

  /// El código actual todavía se puede pagar (no venció ni falló).
  bool get tieneCodigoVigente {
    final c = cobro;
    return c != null && c.estaActivo && !c.vencidoLocal && !c.fallo;
  }

  factory SaldoServicio.fromJson(Map<String, dynamic> json) {
    final cobro = json['cobro'];
    return SaldoServicio(
      id: (json['id'] as num?)?.toInt() ?? 0,
      wooOrderId: json['wooOrderId']?.toString() ?? '',
      estado: json['estado']?.toString() ?? '',
      totalOrden: _num(json['totalOrden']),
      pagadoAntes: _num(json['pagadoAntes']),
      montoSaldo: _num(json['montoSaldo']),
      servicios: json['servicios']?.toString() ?? 'Servicio',
      servicioTerminadoEn: _fecha(json['servicioTerminadoEn']),
      pedidoAppId: (json['pedidoAppId'] as num?)?.toInt(),
      pagadoEn: _fecha(json['pagadoEn']),
      cobro: cobro is Map<String, dynamic>
          ? PagoCobroInfo.fromJson(cobro)
          : null,
    );
  }
}

/// Un cliente en la lista "Clientes en mora" (gerente / jefe de operaciones).
class MoraCliente {
  const MoraCliente({
    required this.id,
    required this.estado,
    required this.canal,
    required this.wooOrderId,
    required this.nombre,
    required this.servicios,
    required this.totalOrden,
    required this.pagadoAntes,
    required this.montoSaldo,
    this.pedidoAppId,
    this.documento,
    this.correo,
    this.telefono,
    this.direccion,
    this.servicioTerminadoEn,
    this.diasEnMora,
    this.pagadoEn,
    this.resueltoPorNombre,
    this.resolucionMotivo,
    this.pedidosEnMora = const <String>[],
  });

  final int id;
  final String estado;

  /// "app" o "tienda": dónde se hizo el pedido.
  final String canal;
  final String wooOrderId;
  final int? pedidoAppId;
  final String nombre;
  final String? documento;
  final String? correo;
  final String? telefono;
  final String? direccion;
  final String servicios;
  final double totalOrden;
  final double pagadoAntes;
  final double montoSaldo;
  final DateTime? servicioTerminadoEn;
  final int? diasEnMora;
  final DateTime? pagadoEn;
  final String? resueltoPorNombre;
  final String? resolucionMotivo;

  /// Órdenes de la tienda que hizo estando en mora (sin que se pudiera
  /// verificar en el momento).
  final List<String> pedidosEnMora;

  bool get pendiente => estado == 'PENDIENTE';

  factory MoraCliente.fromJson(Map<String, dynamic> json) {
    final incidencias = json['pedidosEnMora'];
    return MoraCliente(
      id: (json['id'] as num?)?.toInt() ?? 0,
      estado: json['estado']?.toString() ?? '',
      canal: json['canal']?.toString() ?? 'tienda',
      wooOrderId: json['wooOrderId']?.toString() ?? '',
      pedidoAppId: (json['pedidoAppId'] as num?)?.toInt(),
      nombre: json['nombre']?.toString() ?? 'Cliente',
      documento: _texto(json['documento']),
      correo: _texto(json['correo']),
      telefono: _texto(json['telefono']),
      direccion: _texto(json['direccion']),
      servicios: json['servicios']?.toString() ?? 'Servicio',
      totalOrden: _num(json['totalOrden']),
      pagadoAntes: _num(json['pagadoAntes']),
      montoSaldo: _num(json['montoSaldo']),
      servicioTerminadoEn: _fecha(json['servicioTerminadoEn']),
      diasEnMora: (json['diasEnMora'] as num?)?.toInt(),
      pagadoEn: _fecha(json['pagadoEn']),
      resueltoPorNombre: _texto(json['resueltoPorNombre']),
      resolucionMotivo: _texto(json['resolucionMotivo']),
      pedidosEnMora: incidencias is List
          ? incidencias
                .whereType<Map<String, dynamic>>()
                .map((i) => i['wooOrderId']?.toString() ?? '')
                .where((id) => id.isNotEmpty)
                .toList()
          : const <String>[],
    );
  }
}

class MoraListado {
  const MoraListado({
    required this.total,
    required this.clientesEnMora,
    required this.montoPendiente,
    required this.items,
  });

  final int total;
  final int clientesEnMora;
  final double montoPendiente;
  final List<MoraCliente> items;

  factory MoraListado.fromJson(Map<String, dynamic> json) {
    final resumen = json['resumen'] is Map<String, dynamic>
        ? json['resumen'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final items = json['items'];
    return MoraListado(
      total: (json['total'] as num?)?.toInt() ?? 0,
      clientesEnMora: (resumen['clientesEnMora'] as num?)?.toInt() ?? 0,
      montoPendiente: _num(resumen['montoPendiente']),
      items: items is List
          ? items
                .whereType<Map<String, dynamic>>()
                .map(MoraCliente.fromJson)
                .toList()
          : const <MoraCliente>[],
    );
  }
}
