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
    );
  }
}
