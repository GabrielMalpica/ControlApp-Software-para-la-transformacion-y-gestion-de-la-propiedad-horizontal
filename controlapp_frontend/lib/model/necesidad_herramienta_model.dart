/// Tarea publicada que origina una necesidad de herramienta.
class TareaNecesidadHerramienta {
  final int tareaId;
  final String descripcion;
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final List<String> operariosNombres;

  const TareaNecesidadHerramienta({
    required this.tareaId,
    required this.descripcion,
    required this.fechaInicio,
    required this.fechaFin,
    this.operariosNombres = const [],
  });

  factory TareaNecesidadHerramienta.fromJson(Map<String, dynamic> json) {
    return TareaNecesidadHerramienta(
      tareaId: (json['tareaId'] as num).toInt(),
      descripcion: json['descripcion']?.toString() ?? '',
      fechaInicio:
          DateTime.tryParse(json['fechaInicio']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      fechaFin:
          DateTime.tryParse(json['fechaFin']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      operariosNombres: ((json['operariosNombres'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// Herramienta ya asignada (por cantidad) a una necesidad.
class AsignacionHerramienta {
  final int usoId;
  final double cantidad;
  final String origenStock; // CONJUNTO | EMPRESA
  final DateTime entrega;
  final DateTime recogida;

  const AsignacionHerramienta({
    required this.usoId,
    required this.cantidad,
    required this.origenStock,
    required this.entrega,
    required this.recogida,
  });

  bool get esPrestamoEmpresa => origenStock == 'EMPRESA';

  factory AsignacionHerramienta.fromJson(Map<String, dynamic> json) {
    return AsignacionHerramienta(
      usoId: (json['usoId'] as num).toInt(),
      cantidad: (json['cantidad'] as num?)?.toDouble() ?? 0,
      origenStock: json['origenStock']?.toString() ?? 'CONJUNTO',
      entrega:
          DateTime.tryParse(json['entrega']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      recogida:
          DateTime.tryParse(json['recogida']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }
}

/// Necesidad agrupada por herramienta + conjunto + día.
class NecesidadHerramienta {
  final String clave;
  final int herramientaId;
  final String herramientaNombre;
  final String herramientaUnidad;
  final String? modoControl;
  final DateTime fecha;
  final String conjuntoId;
  final String conjuntoNombre;
  final double cantidadRequerida;
  final double asignadas;
  final double pendientes;
  final double capacidadConjunto;
  final double capacidadEmpresa;
  final List<TareaNecesidadHerramienta> tareas;
  final List<AsignacionHerramienta> asignaciones;

  const NecesidadHerramienta({
    required this.clave,
    required this.herramientaId,
    required this.herramientaNombre,
    required this.herramientaUnidad,
    required this.modoControl,
    required this.fecha,
    required this.conjuntoId,
    required this.conjuntoNombre,
    required this.cantidadRequerida,
    required this.asignadas,
    required this.pendientes,
    required this.capacidadConjunto,
    required this.capacidadEmpresa,
    this.tareas = const [],
    this.asignaciones = const [],
  });

  bool get cubierta => pendientes <= 0;

  factory NecesidadHerramienta.fromJson(Map<String, dynamic> json) {
    return NecesidadHerramienta(
      clave: json['clave']?.toString() ?? '',
      herramientaId: (json['herramientaId'] as num?)?.toInt() ?? 0,
      herramientaNombre: json['herramientaNombre']?.toString() ?? '',
      herramientaUnidad: json['herramientaUnidad']?.toString() ?? 'UNIDAD',
      modoControl: json['modoControl']?.toString(),
      fecha:
          DateTime.tryParse(json['fecha']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      conjuntoId: json['conjuntoId']?.toString() ?? '',
      conjuntoNombre: json['conjuntoNombre']?.toString() ?? '',
      cantidadRequerida: (json['cantidadRequerida'] as num?)?.toDouble() ?? 0,
      asignadas: (json['asignadas'] as num?)?.toDouble() ?? 0,
      pendientes: (json['pendientes'] as num?)?.toDouble() ?? 0,
      capacidadConjunto: (json['capacidadConjunto'] as num?)?.toDouble() ?? 0,
      capacidadEmpresa: (json['capacidadEmpresa'] as num?)?.toDouble() ?? 0,
      tareas: ((json['tareas'] as List?) ?? const [])
          .map(
            (e) => TareaNecesidadHerramienta.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(),
      asignaciones: ((json['asignaciones'] as List?) ?? const [])
          .map(
            (e) => AsignacionHerramienta.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(),
    );
  }
}

/// Respuesta del cronograma general de herramientas.
class CronogramaHerramientaResponse {
  final int anio;
  final int mes;
  final List<NecesidadHerramienta> necesidades;

  const CronogramaHerramientaResponse({
    required this.anio,
    required this.mes,
    required this.necesidades,
  });

  factory CronogramaHerramientaResponse.fromJson(Map<String, dynamic> json) {
    return CronogramaHerramientaResponse(
      anio: (json['anio'] as num?)?.toInt() ?? DateTime.now().year,
      mes: (json['mes'] as num?)?.toInt() ?? DateTime.now().month,
      necesidades: ((json['necesidades'] as List?) ?? const [])
          .map(
            (e) => NecesidadHerramienta.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(),
    );
  }
}
