// lib/model/gerente_model.dart

class GerenteModel {
  final int id;
  final String? empresaId;

  GerenteModel({
    required this.id,
    this.empresaId,
  });

  /// Crear instancia desde JSON
  factory GerenteModel.fromJson(Map<String, dynamic> json) {
    return GerenteModel(
      id: json['id'] as int,
      empresaId: json['empresaId'] as String?,
    );
  }

  /// Convertir a JSON para envío al backend
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'empresaId': empresaId,
    };
  }
}
