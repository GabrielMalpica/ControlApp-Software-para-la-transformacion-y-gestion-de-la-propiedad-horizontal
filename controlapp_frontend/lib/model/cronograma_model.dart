import 'package:flutter_application_1/model/tarea_model.dart';

enum EstadoTarea { PENDIENTE, EN_PROCESO, COMPLETADA, CANCELADA }
enum TipoTarea { CORRECTIVA, PREVENTIVA }
enum Frecuencia { DIARIA, SEMANAL, MENSUAL, TRIMESTRAL, ANUAL }

class CronogramaModel {
  final String conjuntoId;
  final bool borrador;
  final int? periodoAnio;
  final int? periodoMes;
  final List<TareaModel> tareas;

  CronogramaModel({
    required this.conjuntoId,
    this.borrador = true,
    this.periodoAnio,
    this.periodoMes,
    required this.tareas,
  });

  factory CronogramaModel.fromJson(Map<String, dynamic> json) {
    return CronogramaModel(
      conjuntoId: json['conjuntoId'],
      borrador: json['borrador'] ?? true,
      periodoAnio: json['periodoAnio'],
      periodoMes: json['periodoMes'],
      tareas: (json['tareas'] as List<dynamic>)
          .map((e) => TareaModel.fromJson(e))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'conjuntoId': conjuntoId,
      'borrador': borrador,
      if (periodoAnio != null) 'periodoAnio': periodoAnio,
      if (periodoMes != null) 'periodoMes': periodoMes,
      'tareas': tareas.map((t) => t.toJson()).toList(),
    };
  }
}
