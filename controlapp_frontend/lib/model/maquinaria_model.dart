// lib/models/maquinaria_model.dart

class Maquinaria {
  final int id;
  final String nombre;
  final String marca;
  final String tipo; // TipoMaquinaria (enum en backend)
  final String estado; // EstadoMaquinaria (enum en backend)
  final bool disponible;
  final String? conjuntoId;
  final int? operarioId;
  final String? empresaId;
  final DateTime? fechaPrestamo;
  final DateTime? fechaDevolucionEstimada;

  Maquinaria({
    required this.id,
    required this.nombre,
    required this.marca,
    required this.tipo,
    required this.estado,
    required this.disponible,
    this.conjuntoId,
    this.operarioId,
    this.empresaId,
    this.fechaPrestamo,
    this.fechaDevolucionEstimada,
  });

  factory Maquinaria.fromJson(Map<String, dynamic> json) {
    return Maquinaria(
      id: json['id'],
      nombre: json['nombre'],
      marca: json['marca'],
      tipo: json['tipo'],
      estado: json['estado'],
      disponible: json['disponible'],
      conjuntoId: json['conjuntoId'],
      operarioId: json['operarioId'],
      empresaId: json['empresaId'],
      fechaPrestamo: json['fechaPrestamo'] != null
          ? DateTime.parse(json['fechaPrestamo'])
          : null,
      fechaDevolucionEstimada: json['fechaDevolucionEstimada'] != null
          ? DateTime.parse(json['fechaDevolucionEstimada'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'marca': marca,
      'tipo': tipo,
      'estado': estado,
      'disponible': disponible,
      'conjuntoId': conjuntoId,
      'operarioId': operarioId,
      'empresaId': empresaId,
      'fechaPrestamo': fechaPrestamo?.toIso8601String(),
      'fechaDevolucionEstimada': fechaDevolucionEstimada?.toIso8601String(),
    };
  }
}
