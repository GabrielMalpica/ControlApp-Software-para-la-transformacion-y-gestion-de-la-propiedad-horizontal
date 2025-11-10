// lib/models/ubicacion_model.dart

class UbicacionModel {
  final int id;
  final String nombre;
  final String conjuntoId;

  UbicacionModel({
    required this.id,
    required this.nombre,
    required this.conjuntoId,
  });

  factory UbicacionModel.fromJson(Map<String, dynamic> json) {
    return UbicacionModel(
      id: json['id'],
      nombre: json['nombre'],
      conjuntoId: json['conjuntoId'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'conjuntoId': conjuntoId,
    };
  }
}
