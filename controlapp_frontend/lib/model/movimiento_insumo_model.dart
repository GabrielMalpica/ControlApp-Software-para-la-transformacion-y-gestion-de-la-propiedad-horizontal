class MovimientoInsumoResponse {
  final int id;

  /// "ENTRADA" o "SALIDA"
  final String tipo;
  final num cantidad;

  /// Saldo acumulado después de este movimiento.
  final num saldo;
  final DateTime fecha;
  final String? observacion;
  final String? operario;
  final int? tareaId;
  final String? tareaDescripcion;

  /// Nombre de quien registró el movimiento cuando NO es un operario
  /// cerrando su propia tarea (ej. administrador/gerente/supervisor
  /// haciendo un ingreso/salida manual, o recibiendo una compra).
  final String? registradoPorNombre;

  /// operario ?? registradoPorNombre: a quién mostrarle como responsable.
  final String? responsableNombre;

  /// "COMPRA", "TAREA" o "MANUAL": de dónde vino el movimiento, para elegir
  /// la frase correcta al mostrarlo.
  final String origen;

  MovimientoInsumoResponse({
    required this.id,
    required this.tipo,
    required this.cantidad,
    required this.saldo,
    required this.fecha,
    this.observacion,
    this.operario,
    this.tareaId,
    this.tareaDescripcion,
    this.registradoPorNombre,
    this.responsableNombre,
    this.origen = 'MANUAL',
  });

  bool get esEntrada => tipo.toUpperCase() == 'ENTRADA';

  /// Frase lista para mostrar en el kardex, ej. "María González compró" /
  /// "Se usó en la tarea #12 (Limpieza de fachada)" / "Registrado
  /// manualmente por Juan Pérez".
  String get resumenResponsable {
    final nombre = responsableNombre;
    switch (origen) {
      case 'COMPRA':
        return nombre == null ? 'Compra registrada' : '$nombre compró';
      case 'TAREA':
        final desc = tareaDescripcion?.trim();
        final tareaTxt = tareaId == null
            ? 'una tarea'
            : 'la tarea #$tareaId${desc?.isNotEmpty == true ? ' ($desc)' : ''}';
        return nombre == null
            ? 'Se usó en $tareaTxt'
            : 'Se usó en $tareaTxt · $nombre';
      default:
        return nombre == null
            ? 'Registrado manualmente'
            : 'Registrado manualmente por $nombre';
    }
  }

  static num _parseNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }

  static int? _parseIntNullable(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  factory MovimientoInsumoResponse.fromJson(Map<String, dynamic> json) {
    return MovimientoInsumoResponse(
      id: _parseIntNullable(json['id']) ?? 0,
      tipo: (json['tipo'] ?? '').toString(),
      cantidad: _parseNum(json['cantidad']),
      saldo: _parseNum(json['saldo']),
      fecha:
          DateTime.tryParse(json['fecha']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      observacion: json['observacion']?.toString(),
      operario: json['operario']?.toString(),
      tareaId: _parseIntNullable(json['tareaId']),
      tareaDescripcion: json['tareaDescripcion']?.toString(),
      registradoPorNombre: json['registradoPorNombre']?.toString(),
      responsableNombre: json['responsableNombre']?.toString(),
      origen: (json['origen'] ?? 'MANUAL').toString(),
    );
  }
}
