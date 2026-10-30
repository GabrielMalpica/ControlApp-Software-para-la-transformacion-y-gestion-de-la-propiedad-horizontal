/// Respuesta de POST /gerente/tareas/reemplazo/impacto: qué pasaría al
/// programar una correctiva (actividad especial) en un horario.
class ImpactoCorrectiva {
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final int duracionMinutos;
  final int prioridad;

  /// Nadie tiene nada a esa hora.
  final bool libre;

  /// Se puede programar (con o sin reemplazos).
  final bool puedeProgramar;
  final List<int> reemplazarIds;
  final List<TareaImpactada> reemplazos;
  final List<TareaImpactada> bloqueos;
  final List<OperarioImpactado> operarios;
  final bool hayHuecoGrande;
  final int? prioridadMasAltaReemplazada;

  /// Reglas que impiden programar (festivo, límite semanal...).
  final List<AvisoImpacto> bloqueosGenerales;

  /// Avisos que no impiden programar (p. ej. fuera de la jornada).
  final List<AvisoImpacto> avisos;

  /// Primer horario del día libre para todos, sin reemplazar nada.
  final DateTime? sugerenciaInicio;
  final DateTime? sugerenciaFin;

  const ImpactoCorrectiva({
    required this.fechaInicio,
    required this.fechaFin,
    required this.duracionMinutos,
    required this.prioridad,
    required this.libre,
    required this.puedeProgramar,
    this.reemplazarIds = const [],
    this.reemplazos = const [],
    this.bloqueos = const [],
    this.operarios = const [],
    this.hayHuecoGrande = false,
    this.prioridadMasAltaReemplazada,
    this.bloqueosGenerales = const [],
    this.avisos = const [],
    this.sugerenciaInicio,
    this.sugerenciaFin,
  });

  /// Se programa sin preguntar nada: libre, sin avisos ni bloqueos.
  bool get directo =>
      libre && puedeProgramar && avisos.isEmpty && bloqueosGenerales.isEmpty;

  /// Personas que no están en la actividad pero pierden una tarea compartida.
  List<OperarioImpactado> get afectadosFuera =>
      operarios.where((o) => !o.enLaActividad).toList(growable: false);

  factory ImpactoCorrectiva.fromJson(Map<String, dynamic> json) {
    final sugerencia = json['sugerencia'];
    return ImpactoCorrectiva(
      fechaInicio: _fecha(json['fechaInicio']) ?? DateTime.now(),
      fechaFin: _fecha(json['fechaFin']) ?? DateTime.now(),
      duracionMinutos: _entero(json['duracionMinutos']) ?? 0,
      prioridad: _entero(json['prioridad']) ?? 2,
      libre: json['libre'] == true,
      puedeProgramar: json['puedeProgramar'] == true,
      reemplazarIds: _ids(json['reemplazarIds']),
      reemplazos: _lista(
        json['reemplazos'],
      ).map(TareaImpactada.fromJson).toList(),
      bloqueos: _lista(json['bloqueos']).map(TareaImpactada.fromJson).toList(),
      operarios: _lista(
        json['operarios'],
      ).map(OperarioImpactado.fromJson).toList(),
      hayHuecoGrande: json['hayHuecoGrande'] == true,
      prioridadMasAltaReemplazada: _entero(json['prioridadMasAltaReemplazada']),
      bloqueosGenerales: _lista(
        json['bloqueosGenerales'],
      ).map(AvisoImpacto.fromJson).toList(),
      avisos: _lista(json['avisos']).map(AvisoImpacto.fromJson).toList(),
      sugerenciaInicio: sugerencia is Map
          ? _fecha(sugerencia['fechaInicio'])
          : null,
      sugerenciaFin: sugerencia is Map ? _fecha(sugerencia['fechaFin']) : null,
    );
  }
}

class TareaImpactada {
  final int tareaId;
  final String descripcion;
  final String tipo;
  final String estado;
  final int prioridad;
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final int minutosSolapados;

  /// AUTO (P3) | CONFIRM_WARN (P2) | CONFIRM_DANGER (P1), en reemplazos.
  final String? tipoConfirmacion;

  /// NO_ES_PREVENTIVA | PRIORIDAD | ESTADO, en bloqueos.
  final String? motivo;
  final String? mensaje;
  final List<OperarioDeTarea> operarios;

  const TareaImpactada({
    required this.tareaId,
    required this.descripcion,
    required this.tipo,
    required this.estado,
    required this.prioridad,
    required this.fechaInicio,
    required this.fechaFin,
    this.minutosSolapados = 0,
    this.tipoConfirmacion,
    this.motivo,
    this.mensaje,
    this.operarios = const [],
  });

  int get duracionMinutos => fechaFin.difference(fechaInicio).inMinutes;

  factory TareaImpactada.fromJson(Map<String, dynamic> json) => TareaImpactada(
    tareaId: _entero(json['tareaId']) ?? 0,
    descripcion: (json['descripcion'] ?? '').toString(),
    tipo: (json['tipo'] ?? '').toString(),
    estado: (json['estado'] ?? '').toString(),
    prioridad: _entero(json['prioridad']) ?? 2,
    fechaInicio: _fecha(json['fechaInicio']) ?? DateTime.now(),
    fechaFin: _fecha(json['fechaFin']) ?? DateTime.now(),
    minutosSolapados: _entero(json['minutosSolapados']) ?? 0,
    tipoConfirmacion: json['tipoConfirmacion']?.toString(),
    motivo: json['motivo']?.toString(),
    mensaje: json['mensaje']?.toString(),
    operarios: _lista(json['operarios']).map(OperarioDeTarea.fromJson).toList(),
  );
}

class OperarioDeTarea {
  final String id;
  final String nombre;
  final bool enLaActividad;

  const OperarioDeTarea({
    required this.id,
    required this.nombre,
    required this.enLaActividad,
  });

  factory OperarioDeTarea.fromJson(Map<String, dynamic> json) =>
      OperarioDeTarea(
        id: (json['id'] ?? '').toString(),
        nombre: (json['nombre'] ?? '').toString(),
        enLaActividad: json['enLaActividad'] == true,
      );
}

class HuecoImpacto {
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final int minutos;
  final bool grande;

  const HuecoImpacto({
    required this.fechaInicio,
    required this.fechaFin,
    required this.minutos,
    required this.grande,
  });

  factory HuecoImpacto.fromJson(Map<String, dynamic> json) => HuecoImpacto(
    fechaInicio: _fecha(json['fechaInicio']) ?? DateTime.now(),
    fechaFin: _fecha(json['fechaFin']) ?? DateTime.now(),
    minutos: _entero(json['minutos']) ?? 0,
    grande: json['grande'] == true,
  );
}

class OperarioImpactado {
  final String operarioId;
  final String nombre;
  final bool enLaActividad;
  final List<int> reemplazadasIds;
  final List<int> bloqueosIds;
  final int minutosReemplazados;
  final List<HuecoImpacto> huecos;
  final int minutosHueco;
  final bool huecoGrande;

  const OperarioImpactado({
    required this.operarioId,
    required this.nombre,
    required this.enLaActividad,
    this.reemplazadasIds = const [],
    this.bloqueosIds = const [],
    this.minutosReemplazados = 0,
    this.huecos = const [],
    this.minutosHueco = 0,
    this.huecoGrande = false,
  });

  factory OperarioImpactado.fromJson(Map<String, dynamic> json) =>
      OperarioImpactado(
        operarioId: (json['operarioId'] ?? '').toString(),
        nombre: (json['nombre'] ?? '').toString(),
        enLaActividad: json['enLaActividad'] == true,
        reemplazadasIds: _ids(json['reemplazadasIds']),
        bloqueosIds: _ids(json['bloqueosIds']),
        minutosReemplazados: _entero(json['minutosReemplazados']) ?? 0,
        huecos: _lista(json['huecos']).map(HuecoImpacto.fromJson).toList(),
        minutosHueco: _entero(json['minutosHueco']) ?? 0,
        huecoGrande: json['huecoGrande'] == true,
      );
}

class AvisoImpacto {
  final String codigo;
  final String mensaje;

  const AvisoImpacto({required this.codigo, required this.mensaje});

  factory AvisoImpacto.fromJson(Map<String, dynamic> json) => AvisoImpacto(
    codigo: (json['codigo'] ?? '').toString(),
    mensaje: (json['mensaje'] ?? '').toString(),
  );
}

DateTime? _fecha(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString())?.toLocal();
}

int? _entero(dynamic v) {
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '');
}

List<int> _ids(dynamic v) =>
    v is List ? v.map(_entero).whereType<int>().toList() : const [];

List<Map<String, dynamic>> _lista(dynamic v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : const [];
