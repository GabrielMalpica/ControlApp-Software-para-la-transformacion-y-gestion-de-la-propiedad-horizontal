class SolicitudInsumoItemRequest {
  final int insumoId;
  final num cantidad;

  SolicitudInsumoItemRequest({required this.insumoId, required this.cantidad});

  Map<String, dynamic> toJson() => {"insumoId": insumoId, "cantidad": cantidad};
}

class SolicitudInsumoRequest {
  final String conjuntoId; // NIT conjunto
  final String? empresaId; // opcional
  final List<SolicitudInsumoItemRequest> items;

  SolicitudInsumoRequest({
    required this.conjuntoId,
    this.empresaId,
    required this.items,
  });

  Map<String, dynamic> toJson() => {
    "conjuntoId": conjuntoId,
    if (empresaId != null) "empresaId": empresaId,
    "items": items.map((e) => e.toJson()).toList(),
  };
}
