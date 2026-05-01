class PreventivaExcluidaBloqueModel {
  final String id;
  final int orden;
  final int duracionMinutos;
  final String estado;
  final int? tareaProgramadaId;
  final DateTime? fechaInicio;
  final DateTime? fechaFin;

  const PreventivaExcluidaBloqueModel({
    required this.id,
    required this.orden,
    required this.duracionMinutos,
    required this.estado,
    this.tareaProgramadaId,
    this.fechaInicio,
    this.fechaFin,
  });

  String get duracionLabel => '${(duracionMinutos / 60).toStringAsFixed(1)} h';
  bool get agendado => estado.toUpperCase() == 'AGENDADO';

  factory PreventivaExcluidaBloqueModel.fromJson(Map<String, dynamic> json) {
    return PreventivaExcluidaBloqueModel(
      id: (json['id'] ?? '').toString(),
      orden: int.tryParse(json['orden']?.toString() ?? '') ?? 0,
      duracionMinutos:
          int.tryParse(json['duracionMinutos']?.toString() ?? '') ?? 0,
      estado: (json['estado'] ?? 'PENDIENTE').toString(),
      tareaProgramadaId: int.tryParse(
        json['tareaProgramadaId']?.toString() ?? '',
      ),
      fechaInicio: json['fechaInicio'] == null
          ? null
          : DateTime.tryParse(json['fechaInicio'].toString())?.toLocal(),
      fechaFin: json['fechaFin'] == null
          ? null
          : DateTime.tryParse(json['fechaFin'].toString())?.toLocal(),
    );
  }
}

class PreventivaExcluidaDivisionManualModel {
  final bool activa;
  final List<PreventivaExcluidaBloqueModel> bloques;

  const PreventivaExcluidaDivisionManualModel({
    required this.activa,
    required this.bloques,
  });

  bool get tienePendientes => bloques.any((item) => !item.agendado);

  factory PreventivaExcluidaDivisionManualModel.fromJson(
    Map<String, dynamic> json,
  ) {
    final rawBloques = (json['bloques'] as List?) ?? const [];
    return PreventivaExcluidaDivisionManualModel(
      activa: json['activa'] != false,
      bloques:
          rawBloques
              .map(
                (e) => PreventivaExcluidaBloqueModel.fromJson(
                  e as Map<String, dynamic>,
                ),
              )
              .toList()
            ..sort((a, b) => a.orden.compareTo(b.orden)),
    );
  }
}

class PreventivaExcluidaBorradorModel {
  final int id;
  final String descripcion;
  final String? frecuencia;
  final int prioridad;
  final int duracionMinutos;
  final DateTime fechaObjetivo;
  final int ubicacionId;
  final String? ubicacionNombre;
  final int elementoId;
  final String? elementoNombre;
  final String? supervisorNombre;
  final List<String> operariosIds;
  final List<String> operariosNombres;
  final String motivoTipo;
  final String? motivoMensaje;
  final String estado;
  final PreventivaExcluidaDivisionManualModel? divisionManual;

  PreventivaExcluidaBorradorModel({
    required this.id,
    required this.descripcion,
    this.frecuencia,
    required this.prioridad,
    required this.duracionMinutos,
    required this.fechaObjetivo,
    required this.ubicacionId,
    this.ubicacionNombre,
    required this.elementoId,
    this.elementoNombre,
    this.supervisorNombre,
    this.operariosIds = const [],
    this.operariosNombres = const [],
    required this.motivoTipo,
    this.motivoMensaje,
    required this.estado,
    this.divisionManual,
  });

  String get duracionLabel => '${(duracionMinutos / 60).toStringAsFixed(1)} h';

  factory PreventivaExcluidaBorradorModel.fromJson(Map<String, dynamic> json) {
    List<String> parseStringList(dynamic raw) {
      if (raw is List) {
        return raw.map((e) => e.toString()).toList();
      }
      return const [];
    }

    return PreventivaExcluidaBorradorModel(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      descripcion: (json['descripcion'] ?? '').toString(),
      frecuencia: json['frecuencia']?.toString(),
      prioridad: int.tryParse(json['prioridad']?.toString() ?? '') ?? 2,
      duracionMinutos:
          int.tryParse(json['duracionMinutos']?.toString() ?? '') ?? 0,
      fechaObjetivo: DateTime.parse(json['fechaObjetivo'].toString()).toLocal(),
      ubicacionId: int.tryParse(json['ubicacionId']?.toString() ?? '') ?? 0,
      ubicacionNombre: json['ubicacionNombre']?.toString(),
      elementoId: int.tryParse(json['elementoId']?.toString() ?? '') ?? 0,
      elementoNombre: json['elementoNombre']?.toString(),
      supervisorNombre: json['supervisorNombre']?.toString(),
      operariosIds: parseStringList(json['operariosIds']),
      operariosNombres: parseStringList(json['operariosNombres']),
      motivoTipo: (json['motivoTipo'] ?? '').toString(),
      motivoMensaje: json['motivoMensaje']?.toString(),
      estado: (json['estado'] ?? '').toString(),
      divisionManual: _parseDivisionManual(json['metadataJson']),
    );
  }

  static PreventivaExcluidaDivisionManualModel? _parseDivisionManual(
    dynamic metadata,
  ) {
    if (metadata is! Map<String, dynamic>) return null;
    final raw = metadata['divisionManual'];
    if (raw is! Map<String, dynamic>) return null;
    final parsed = PreventivaExcluidaDivisionManualModel.fromJson(raw);
    return parsed.bloques.isEmpty ? null : parsed;
  }

  bool get tieneDivisionManual => divisionManual?.activa == true;
}
