// lib/models/supervisor_model.dart

class SupervisorModel {
  final int id;            // mismo ID que Usuario.id
  final String empresaId;  // NIT de la empresa

  SupervisorModel({
    required this.id,
    required this.empresaId,
  });

  factory SupervisorModel.fromJson(Map<String, dynamic> json) {
    return SupervisorModel(
      id: json['id'] ?? 0,
      empresaId: json['empresaId'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'empresaId': empresaId,
    };
  }
}

/// DTO para crear supervisor
class CrearSupervisorDTO {
  final int id;
  final String empresaId;

  CrearSupervisorDTO({
    required this.id,
    required this.empresaId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'empresaId': empresaId,
      };
}

/// DTO para editar supervisor
class EditarSupervisorDTO {
  final String? empresaId;

  EditarSupervisorDTO({this.empresaId});

  Map<String, dynamic> toJson() => {
        if (empresaId != null) 'empresaId': empresaId,
      };
}
