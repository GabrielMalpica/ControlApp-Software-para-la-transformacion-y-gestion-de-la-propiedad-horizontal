import 'dart:convert';

/// Enum de días de la semana (alineado con Prisma)
enum DiaSemana {
  LUNES,
  MARTES,
  MIERCOLES,
  JUEVES,
  VIERNES,
  SABADO,
  DOMINGO,
}

/// Enum de tipo de servicio (alineado con Prisma)
enum TipoServicio {
  VIGILANCIA,
  LIMPIEZA,
  MANTENIMIENTO,
  ADMINISTRACION,
  OTRO,
}

/// Modelo de horario
class HorarioDTO {
  final DiaSemana dia;
  final String horaApertura;
  final String horaCierre;

  HorarioDTO({
    required this.dia,
    required this.horaApertura,
    required this.horaCierre,
  });

  factory HorarioDTO.fromJson(Map<String, dynamic> json) {
    return HorarioDTO(
      dia: DiaSemana.values.firstWhere(
        (e) => e.name == json['dia'],
        orElse: () => DiaSemana.LUNES,
      ),
      horaApertura: json['horaApertura'] ?? '',
      horaCierre: json['horaCierre'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'dia': dia.name,
        'horaApertura': horaApertura,
        'horaCierre': horaCierre,
      };
}

/// Modelo principal de Conjunto
class ConjuntoModel {
  final String nit;
  final String nombre;
  final String direccion;
  final String correo;
  final int? administradorId;
  final String? empresaId;
  final DateTime? fechaInicioContrato;
  final DateTime? fechaFinContrato;
  final bool activo;
  final List<TipoServicio> tipoServicio;
  final double? valorMensual;
  final List<String> consignasEspeciales;
  final List<String> valorAgregado;
  final List<HorarioDTO>? horarios;

  ConjuntoModel({
    required this.nit,
    required this.nombre,
    required this.direccion,
    required this.correo,
    this.administradorId,
    this.empresaId,
    this.fechaInicioContrato,
    this.fechaFinContrato,
    this.activo = true,
    this.tipoServicio = const [],
    this.valorMensual,
    this.consignasEspeciales = const [],
    this.valorAgregado = const [],
    this.horarios,
  });

  factory ConjuntoModel.fromJson(Map<String, dynamic> json) {
    return ConjuntoModel(
      nit: json['nit'] ?? '',
      nombre: json['nombre'] ?? '',
      direccion: json['direccion'] ?? '',
      correo: json['correo'] ?? '',
      administradorId: json['administradorId'],
      empresaId: json['empresaId'],
      fechaInicioContrato: json['fechaInicioContrato'] != null
          ? DateTime.parse(json['fechaInicioContrato'])
          : null,
      fechaFinContrato: json['fechaFinContrato'] != null
          ? DateTime.parse(json['fechaFinContrato'])
          : null,
      activo: json['activo'] ?? true,
      tipoServicio: (json['tipoServicio'] as List?)
              ?.map((e) => TipoServicio.values.firstWhere(
                    (v) => v.name == e,
                    orElse: () => TipoServicio.OTRO,
                  ))
              .toList() ??
          [],
      valorMensual: json['valorMensual'] != null
          ? (json['valorMensual'] as num).toDouble()
          : null,
      consignasEspeciales: List<String>.from(json['consignasEspeciales'] ?? []),
      valorAgregado: List<String>.from(json['valorAgregado'] ?? []),
      horarios: (json['horarios'] as List?)
          ?.map((h) => HorarioDTO.fromJson(h))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'nit': nit,
      'nombre': nombre,
      'direccion': direccion,
      'correo': correo,
      'administradorId': administradorId,
      'empresaId': empresaId,
      'fechaInicioContrato': fechaInicioContrato?.toIso8601String(),
      'fechaFinContrato': fechaFinContrato?.toIso8601String(),
      'activo': activo,
      'tipoServicio': tipoServicio.map((e) => e.name).toList(),
      'valorMensual': valorMensual,
      'consignasEspeciales': consignasEspeciales,
      'valorAgregado': valorAgregado,
      if (horarios != null)
        'horarios': horarios!.map((h) => h.toJson()).toList(),
    };
  }

  /// Convierte a JSON string (útil para debugging o envíos directos)
  String toRawJson() => jsonEncode(toJson());

  /// Crea un ConjuntoModel desde un JSON string
  factory ConjuntoModel.fromRawJson(String str) =>
      ConjuntoModel.fromJson(jsonDecode(str));
}
