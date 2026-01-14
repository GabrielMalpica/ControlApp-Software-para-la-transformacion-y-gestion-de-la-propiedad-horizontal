enum TipoSolicitud { INSUMOS, MAQUINARIA }

enum EstadoSolicitudUi { PENDIENTE, APROBADA, RECHAZADA }

extension EstadoSolicitudUiExt on EstadoSolicitudUi {
  String get label {
    switch (this) {
      case EstadoSolicitudUi.PENDIENTE:
        return 'Pendiente';
      case EstadoSolicitudUi.APROBADA:
        return 'Aprobada';
      case EstadoSolicitudUi.RECHAZADA:
        return 'Rechazada';
    }
  }
}

class SolicitudUnificada {
  final TipoSolicitud tipo;
  final int id;
  final EstadoSolicitudUi estado;
  final DateTime fecha;
  final String? descripcion; // maquinaria puede traer nombre/desc
  final List<Map<String, dynamic>>?
  items; // insumos: [{nombre, cantidad, unidad}]
  final String? conjuntoNombre; // opcional si lo devuelves
  final String? maquinaNombre; // opcional

  SolicitudUnificada({
    required this.tipo,
    required this.id,
    required this.estado,
    required this.fecha,
    this.descripcion,
    this.items,
    this.conjuntoNombre,
    this.maquinaNombre,
  });
}
