// lib/models/operario_model.dart
class OperarioModel {
  final int id;
  final List<String> funciones;
  final bool cursoSalvamentoAcuatico;
  final String? urlEvidenciaSalvamento;
  final bool cursoAlturas;
  final String? urlEvidenciaAlturas;
  final bool examenIngreso;
  final String? urlEvidenciaExamenIngreso;
  final DateTime fechaIngreso;
  final DateTime? fechaSalida;
  final DateTime? fechaUltimasVacaciones;
  final String? observaciones;
  final String empresaId;

  OperarioModel({
    required this.id,
    required this.funciones,
    required this.cursoSalvamentoAcuatico,
    this.urlEvidenciaSalvamento,
    required this.cursoAlturas,
    this.urlEvidenciaAlturas,
    required this.examenIngreso,
    this.urlEvidenciaExamenIngreso,
    required this.fechaIngreso,
    this.fechaSalida,
    this.fechaUltimasVacaciones,
    this.observaciones,
    required this.empresaId,
  });

  factory OperarioModel.fromJson(Map<String, dynamic> json) {
    return OperarioModel(
      id: json['id'],
      funciones: List<String>.from(json['funciones'] ?? []),
      cursoSalvamentoAcuatico: json['cursoSalvamentoAcuatico'] ?? false,
      urlEvidenciaSalvamento: json['urlEvidenciaSalvamento'],
      cursoAlturas: json['cursoAlturas'] ?? false,
      urlEvidenciaAlturas: json['urlEvidenciaAlturas'],
      examenIngreso: json['examenIngreso'] ?? false,
      urlEvidenciaExamenIngreso: json['urlEvidenciaExamenIngreso'],
      fechaIngreso: DateTime.parse(json['fechaIngreso']),
      fechaSalida: json['fechaSalida'] != null
          ? DateTime.parse(json['fechaSalida'])
          : null,
      fechaUltimasVacaciones: json['fechaUltimasVacaciones'] != null
          ? DateTime.parse(json['fechaUltimasVacaciones'])
          : null,
      observaciones: json['observaciones'],
      empresaId: json['empresaId'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'funciones': funciones,
      'cursoSalvamentoAcuatico': cursoSalvamentoAcuatico,
      'urlEvidenciaSalvamento': urlEvidenciaSalvamento,
      'cursoAlturas': cursoAlturas,
      'urlEvidenciaAlturas': urlEvidenciaAlturas,
      'examenIngreso': examenIngreso,
      'urlEvidenciaExamenIngreso': urlEvidenciaExamenIngreso,
      'fechaIngreso': fechaIngreso.toIso8601String(),
      'fechaSalida': fechaSalida?.toIso8601String(),
      'fechaUltimasVacaciones': fechaUltimasVacaciones?.toIso8601String(),
      'observaciones': observaciones,
      'empresaId': empresaId,
    };
  }
}
