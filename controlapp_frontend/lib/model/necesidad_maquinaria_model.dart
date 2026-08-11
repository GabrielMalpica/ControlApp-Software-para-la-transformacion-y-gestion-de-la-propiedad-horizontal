import 'maquinaria_model.dart';

/// Tarea publicada que origina una necesidad de maquinaria.
class TareaNecesidadMaquinaria {
  final int tareaId;
  final String descripcion;
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final List<String> operariosNombres;

  const TareaNecesidadMaquinaria({
    required this.tareaId,
    required this.descripcion,
    required this.fechaInicio,
    required this.fechaFin,
    this.operariosNombres = const [],
  });

  factory TareaNecesidadMaquinaria.fromJson(Map<String, dynamic> json) {
    return TareaNecesidadMaquinaria(
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

/// Máquina ya asignada a una necesidad.
class AsignacionMaquinaria {
  final int usoId;
  final int maquinariaId;
  final String maquinariaNombre;
  final String marca;
  final DateTime entrega;
  final DateTime recogida;

  const AsignacionMaquinaria({
    required this.usoId,
    required this.maquinariaId,
    required this.maquinariaNombre,
    required this.marca,
    required this.entrega,
    required this.recogida,
  });

  factory AsignacionMaquinaria.fromJson(Map<String, dynamic> json) {
    return AsignacionMaquinaria(
      usoId: (json['usoId'] as num).toInt(),
      maquinariaId: (json['maquinariaId'] as num).toInt(),
      maquinariaNombre: json['maquinariaNombre']?.toString() ?? '',
      marca: json['marca']?.toString() ?? '',
      entrega:
          DateTime.tryParse(json['entrega']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      recogida:
          DateTime.tryParse(json['recogida']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }
}

/// Necesidad agrupada por tipo de máquina + conjunto + día.
class NecesidadMaquinaria {
  final String clave;
  final TipoMaquinariaFlutter? tipo;
  final String tipoRaw;
  final DateTime fecha;
  final String conjuntoId;
  final String conjuntoNombre;
  final int cantidadRequerida;
  final int pendientes;
  final int? maquinariaSugeridaId;
  final List<TareaNecesidadMaquinaria> tareas;
  final List<AsignacionMaquinaria> asignaciones;

  const NecesidadMaquinaria({
    required this.clave,
    required this.tipo,
    required this.tipoRaw,
    required this.fecha,
    required this.conjuntoId,
    required this.conjuntoNombre,
    required this.cantidadRequerida,
    required this.pendientes,
    this.maquinariaSugeridaId,
    this.tareas = const [],
    this.asignaciones = const [],
  });

  bool get cubierta => pendientes == 0;

  String get tipoLabel => tipo?.label ?? tipoRaw;

  factory NecesidadMaquinaria.fromJson(Map<String, dynamic> json) {
    final tipoRaw = json['tipo']?.toString() ?? '';
    TipoMaquinariaFlutter? tipo;
    for (final valor in TipoMaquinariaFlutter.values) {
      if (valor.name == tipoRaw) {
        tipo = valor;
        break;
      }
    }

    return NecesidadMaquinaria(
      clave: json['clave']?.toString() ?? '',
      tipo: tipo,
      tipoRaw: tipoRaw,
      fecha:
          DateTime.tryParse(json['fecha']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      conjuntoId: json['conjuntoId']?.toString() ?? '',
      conjuntoNombre: json['conjuntoNombre']?.toString() ?? '',
      cantidadRequerida: (json['cantidadRequerida'] as num?)?.toInt() ?? 0,
      pendientes: (json['pendientes'] as num?)?.toInt() ?? 0,
      maquinariaSugeridaId: (json['maquinariaSugeridaId'] as num?)?.toInt(),
      tareas: ((json['tareas'] as List?) ?? const [])
          .map(
            (e) => TareaNecesidadMaquinaria.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(),
      asignaciones: ((json['asignaciones'] as List?) ?? const [])
          .map(
            (e) => AsignacionMaquinaria.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(),
    );
  }
}

/// Máquina candidata para cubrir una necesidad.
class MaquinaCandidata {
  final int id;
  final String nombre;
  final String marca;
  final String tipo;
  final String propietarioTipo;

  const MaquinaCandidata({
    required this.id,
    required this.nombre,
    required this.marca,
    required this.tipo,
    required this.propietarioTipo,
  });

  factory MaquinaCandidata.fromJson(Map<String, dynamic> json) {
    return MaquinaCandidata(
      id: (json['id'] as num).toInt(),
      nombre: json['nombre']?.toString() ?? '',
      marca: json['marca']?.toString() ?? '',
      tipo: json['tipo']?.toString() ?? '',
      propietarioTipo: json['propietarioTipo']?.toString() ?? '',
    );
  }

  String get etiqueta {
    final origen = propietarioTipo == 'CONJUNTO' ? 'Conjunto' : 'Empresa';
    return marca.trim().isEmpty
        ? '[$origen] $nombre'
        : '[$origen] $nombre • $marca';
  }
}

/// Respuesta del cronograma general de maquinaria.
class CronogramaMaquinariaResponse {
  final int anio;
  final int mes;
  final List<NecesidadMaquinaria> necesidades;
  final Map<String, List<MaquinaCandidata>> maquinariasPorTipo;

  const CronogramaMaquinariaResponse({
    required this.anio,
    required this.mes,
    required this.necesidades,
    required this.maquinariasPorTipo,
  });

  factory CronogramaMaquinariaResponse.fromJson(Map<String, dynamic> json) {
    final catalogo = <String, List<MaquinaCandidata>>{};
    final raw = (json['maquinariasPorTipo'] as Map?) ?? const {};
    raw.forEach((key, value) {
      catalogo[key.toString()] = ((value as List?) ?? const [])
          .map(
            (e) =>
                MaquinaCandidata.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    });

    return CronogramaMaquinariaResponse(
      anio: (json['anio'] as num?)?.toInt() ?? DateTime.now().year,
      mes: (json['mes'] as num?)?.toInt() ?? DateTime.now().month,
      necesidades: ((json['necesidades'] as List?) ?? const [])
          .map(
            (e) => NecesidadMaquinaria.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(),
      maquinariasPorTipo: catalogo,
    );
  }
}
