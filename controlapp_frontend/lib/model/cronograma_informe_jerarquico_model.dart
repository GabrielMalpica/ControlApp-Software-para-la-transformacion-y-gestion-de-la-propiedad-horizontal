import 'package:flutter_application_1/utils/text_encoding.dart';

class CronogramaInformeResumen {
  final int esperadas;
  final int conProgramacion;
  final int completas;
  final int parciales;
  final int sinProgramar;
  final int minutosEsperados;
  final int minutosProgramados;

  const CronogramaInformeResumen({
    required this.esperadas,
    required this.conProgramacion,
    required this.completas,
    required this.parciales,
    required this.sinProgramar,
    required this.minutosEsperados,
    required this.minutosProgramados,
  });

  factory CronogramaInformeResumen.fromJson(Map<String, dynamic> json) {
    int value(String key) => (json[key] as num?)?.toInt() ?? 0;
    return CronogramaInformeResumen(
      esperadas: value('esperadas'),
      conProgramacion: value('conProgramacion'),
      completas: value('completas'),
      parciales: value('parciales'),
      sinProgramar: value('sinProgramar'),
      minutosEsperados: value('minutosEsperados'),
      minutosProgramados: value('minutosProgramados'),
    );
  }
}

class CronogramaInformeOperario {
  final String id;
  final String nombre;

  const CronogramaInformeOperario({required this.id, required this.nombre});

  factory CronogramaInformeOperario.fromJson(Map<String, dynamic> json) =>
      CronogramaInformeOperario(
        id: (json['id'] ?? '').toString(),
        nombre: repairMojibake(json['nombre'] ?? json['id']),
      );
}

class CronogramaInformeBloque {
  final int tareaId;
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final int duracionMinutos;
  final String estado;
  final List<CronogramaInformeOperario> operarios;

  const CronogramaInformeBloque({
    required this.tareaId,
    required this.fechaInicio,
    required this.fechaFin,
    required this.duracionMinutos,
    required this.estado,
    required this.operarios,
  });

  factory CronogramaInformeBloque.fromJson(
    Map<String, dynamic> json,
  ) => CronogramaInformeBloque(
    tareaId: (json['tareaId'] as num?)?.toInt() ?? 0,
    fechaInicio: DateTime.parse(json['fechaInicio'].toString()).toLocal(),
    fechaFin: DateTime.parse(json['fechaFin'].toString()).toLocal(),
    duracionMinutos: (json['duracionMinutos'] as num?)?.toInt() ?? 0,
    estado: repairMojibake(json['estado']),
    operarios: (json['operarios'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              CronogramaInformeOperario.fromJson(item.cast<String, dynamic>()),
        )
        .toList(),
  );
}

class CronogramaInformeOcurrencia {
  final String id;
  final DateTime fechaObjetivo;
  final int duracionEsperadaMin;
  final int minutosProgramados;
  final String estado;
  final bool reubicada;
  final DateTime? fechaRealInicio;
  final DateTime? fechaRealFin;
  final String? motivoCodigo;
  final String? motivoMensaje;
  final List<CronogramaInformeOperario> operariosEsperados;
  final List<CronogramaInformeBloque> bloques;

  const CronogramaInformeOcurrencia({
    required this.id,
    required this.fechaObjetivo,
    required this.duracionEsperadaMin,
    required this.minutosProgramados,
    required this.estado,
    required this.reubicada,
    required this.fechaRealInicio,
    required this.fechaRealFin,
    required this.motivoCodigo,
    required this.motivoMensaje,
    required this.operariosEsperados,
    required this.bloques,
  });

  factory CronogramaInformeOcurrencia.fromJson(Map<String, dynamic> json) {
    DateTime? optionalDate(dynamic value) =>
        value == null ? null : DateTime.tryParse(value.toString())?.toLocal();
    return CronogramaInformeOcurrencia(
      id: (json['id'] ?? '').toString(),
      fechaObjetivo: DateTime.parse(json['fechaObjetivo'].toString()).toLocal(),
      duracionEsperadaMin: (json['duracionEsperadaMin'] as num?)?.toInt() ?? 0,
      minutosProgramados: (json['minutosProgramados'] as num?)?.toInt() ?? 0,
      estado: (json['estado'] ?? 'SIN_PROGRAMAR').toString(),
      reubicada: json['reubicada'] == true,
      fechaRealInicio: optionalDate(json['fechaRealInicio']),
      fechaRealFin: optionalDate(json['fechaRealFin']),
      motivoCodigo: json['motivoCodigo'] == null
          ? null
          : repairMojibake(json['motivoCodigo']),
      motivoMensaje: json['motivoMensaje'] == null
          ? null
          : repairMojibake(json['motivoMensaje']),
      operariosEsperados: (json['operariosEsperados'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) => CronogramaInformeOperario.fromJson(
              item.cast<String, dynamic>(),
            ),
          )
          .toList(),
      bloques: (json['bloques'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                CronogramaInformeBloque.fromJson(item.cast<String, dynamic>()),
          )
          .toList(),
    );
  }
}

class CronogramaInformeDefinicion {
  final String id;
  final int? definicionId;
  final String descripcion;
  final String? frecuencia;
  final int prioridad;
  final int elementoId;
  final String? elementoNombre;
  final CronogramaInformeResumen resumen;
  final List<CronogramaInformeOcurrencia> ocurrencias;

  const CronogramaInformeDefinicion({
    required this.id,
    required this.definicionId,
    required this.descripcion,
    required this.frecuencia,
    required this.prioridad,
    required this.elementoId,
    required this.elementoNombre,
    required this.resumen,
    required this.ocurrencias,
  });

  factory CronogramaInformeDefinicion.fromJson(Map<String, dynamic> json) =>
      CronogramaInformeDefinicion(
        id: (json['id'] ?? '').toString(),
        definicionId: (json['definicionId'] as num?)?.toInt(),
        descripcion: repairMojibake(json['descripcion']),
        frecuencia: json['frecuencia'] == null
            ? null
            : repairMojibake(json['frecuencia']),
        prioridad: (json['prioridad'] as num?)?.toInt() ?? 2,
        elementoId: (json['elementoId'] as num?)?.toInt() ?? 0,
        elementoNombre: json['elementoNombre'] == null
            ? null
            : repairMojibake(json['elementoNombre']),
        resumen: CronogramaInformeResumen.fromJson(
          (json['resumen'] as Map? ?? const {}).cast<String, dynamic>(),
        ),
        ocurrencias: (json['ocurrencias'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (item) => CronogramaInformeOcurrencia.fromJson(
                item.cast<String, dynamic>(),
              ),
            )
            .toList(),
      );
}

class CronogramaInformeUbicacion {
  final int id;
  final String nombre;
  final CronogramaInformeResumen resumen;
  final List<CronogramaInformeDefinicion> definiciones;

  const CronogramaInformeUbicacion({
    required this.id,
    required this.nombre,
    required this.resumen,
    required this.definiciones,
  });

  factory CronogramaInformeUbicacion.fromJson(Map<String, dynamic> json) =>
      CronogramaInformeUbicacion(
        id: (json['id'] as num?)?.toInt() ?? 0,
        nombre: repairMojibake(json['nombre'] ?? 'Sin ubicación'),
        resumen: CronogramaInformeResumen.fromJson(
          (json['resumen'] as Map? ?? const {}).cast<String, dynamic>(),
        ),
        definiciones: (json['definiciones'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (item) => CronogramaInformeDefinicion.fromJson(
                item.cast<String, dynamic>(),
              ),
            )
            .toList(),
      );
}

class CronogramaInformeJerarquicoModel {
  final int anio;
  final int mes;
  final DateTime? semanaInicio;
  final DateTime? semanaFin;
  final bool trazabilidadDisponible;
  final CronogramaInformeResumen resumen;
  final List<CronogramaInformeOperario> operarios;
  final List<CronogramaInformeUbicacion> ubicaciones;

  const CronogramaInformeJerarquicoModel({
    required this.anio,
    required this.mes,
    required this.semanaInicio,
    required this.semanaFin,
    required this.trazabilidadDisponible,
    required this.resumen,
    required this.operarios,
    required this.ubicaciones,
  });

  factory CronogramaInformeJerarquicoModel.fromJson(Map<String, dynamic> json) {
    final periodo = (json['periodo'] as Map? ?? const {})
        .cast<String, dynamic>();
    DateTime? optionalDate(dynamic value) =>
        value == null ? null : DateTime.tryParse(value.toString())?.toLocal();
    return CronogramaInformeJerarquicoModel(
      anio: (periodo['anio'] as num?)?.toInt() ?? 0,
      mes: (periodo['mes'] as num?)?.toInt() ?? 0,
      semanaInicio: optionalDate(periodo['semanaInicio']),
      semanaFin: optionalDate(periodo['semanaFin']),
      trazabilidadDisponible: json['trazabilidadDisponible'] == true,
      resumen: CronogramaInformeResumen.fromJson(
        (json['resumen'] as Map? ?? const {}).cast<String, dynamic>(),
      ),
      operarios: (json['operarios'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) => CronogramaInformeOperario.fromJson(
              item.cast<String, dynamic>(),
            ),
          )
          .toList(),
      ubicaciones: (json['ubicaciones'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) => CronogramaInformeUbicacion.fromJson(
              item.cast<String, dynamic>(),
            ),
          )
          .toList(),
    );
  }
}
