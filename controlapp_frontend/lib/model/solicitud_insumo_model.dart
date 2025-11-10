// lib/models/solicitud_insumo_model.dart

class SolicitudInsumoItem {
  final int insumoId;
  final int cantidad;

  SolicitudInsumoItem({
    required this.insumoId,
    required this.cantidad,
  });

  factory SolicitudInsumoItem.fromJson(Map<String, dynamic> json) {
    return SolicitudInsumoItem(
      insumoId: json['insumoId'],
      cantidad: json['cantidad'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'insumoId': insumoId,
      'cantidad': cantidad,
    };
  }
}

class SolicitudInsumoModel {
  final String conjuntoId;
  final String? empresaId;
  final List<SolicitudInsumoItem> items;
  final bool? aprobado;
  final DateTime? fechaAprobacion;
  final DateTime? fechaCreacion;

  SolicitudInsumoModel({
    required this.conjuntoId,
    this.empresaId,
    required this.items,
    this.aprobado,
    this.fechaAprobacion,
    this.fechaCreacion,
  });

  factory SolicitudInsumoModel.fromJson(Map<String, dynamic> json) {
    return SolicitudInsumoModel(
      conjuntoId: json['conjuntoId'],
      empresaId: json['empresaId'],
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => SolicitudInsumoItem.fromJson(e))
              .toList() ??
          [],
      aprobado: json['aprobado'],
      fechaAprobacion: json['fechaAprobacion'] != null
          ? DateTime.parse(json['fechaAprobacion'])
          : null,
      fechaCreacion: json['fechaCreacion'] != null
          ? DateTime.parse(json['fechaCreacion'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'conjuntoId': conjuntoId,
      'empresaId': empresaId,
      'items': items.map((e) => e.toJson()).toList(),
    };
  }
}
