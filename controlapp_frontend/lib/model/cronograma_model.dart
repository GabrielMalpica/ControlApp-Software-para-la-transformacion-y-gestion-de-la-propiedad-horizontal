enum EstadoTarea { PENDIENTE, EN_PROCESO, COMPLETADA, CANCELADA }
enum TipoTarea { CORRECTIVA, PREVENTIVA }
enum Frecuencia { DIARIA, SEMANAL, MENSUAL, TRIMESTRAL, ANUAL }

class TareaModel {
  final int? id;
  final String descripcion;
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final int duracionHoras;
  final int ubicacionId;
  final int elementoId;
  final int? operarioId;
  final int? supervisorId;
  final TipoTarea tipo;
  final Frecuencia? frecuencia;
  final String? grupoPlanId;
  final int? bloqueIndex;
  final int? bloquesTotales;
  final String? observaciones;
  final EstadoTarea? estado;

  TareaModel({
    this.id,
    required this.descripcion,
    required this.fechaInicio,
    required this.fechaFin,
    required this.duracionHoras,
    required this.ubicacionId,
    required this.elementoId,
    this.operarioId,
    this.supervisorId,
    this.tipo = TipoTarea.CORRECTIVA,
    this.frecuencia,
    this.grupoPlanId,
    this.bloqueIndex,
    this.bloquesTotales,
    this.observaciones,
    this.estado,
  });

  factory TareaModel.fromJson(Map<String, dynamic> json) {
    return TareaModel(
      id: json['id'],
      descripcion: json['descripcion'] ?? '',
      fechaInicio: DateTime.parse(json['fechaInicio']),
      fechaFin: DateTime.parse(json['fechaFin']),
      duracionHoras: json['duracionHoras'],
      ubicacionId: json['ubicacionId'],
      elementoId: json['elementoId'],
      operarioId: json['operarioId'],
      supervisorId: json['supervisorId'],
      tipo: TipoTarea.values.firstWhere(
        (e) => e.name == json['tipo'],
        orElse: () => TipoTarea.CORRECTIVA,
      ),
      frecuencia: json['frecuencia'] != null
          ? Frecuencia.values.firstWhere(
              (e) => e.name == json['frecuencia'],
              orElse: () => Frecuencia.MENSUAL,
            )
          : null,
      grupoPlanId: json['grupoPlanId'],
      bloqueIndex: json['bloqueIndex'],
      bloquesTotales: json['bloquesTotales'],
      observaciones: json['observaciones'],
      estado: json['estado'] != null
          ? EstadoTarea.values.firstWhere(
              (e) => e.name == json['estado'],
              orElse: () => EstadoTarea.PENDIENTE,
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'descripcion': descripcion,
      'fechaInicio': fechaInicio.toIso8601String(),
      'fechaFin': fechaFin.toIso8601String(),
      'duracionHoras': duracionHoras,
      'ubicacionId': ubicacionId,
      'elementoId': elementoId,
      if (operarioId != null) 'operarioId': operarioId,
      if (supervisorId != null) 'supervisorId': supervisorId,
      'tipo': tipo.name,
      if (frecuencia != null) 'frecuencia': frecuencia!.name,
      if (grupoPlanId != null) 'grupoPlanId': grupoPlanId,
      if (bloqueIndex != null) 'bloqueIndex': bloqueIndex,
      if (bloquesTotales != null) 'bloquesTotales': bloquesTotales,
      if (observaciones != null) 'observaciones': observaciones,
      if (estado != null) 'estado': estado!.name,
    };
  }
}

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
