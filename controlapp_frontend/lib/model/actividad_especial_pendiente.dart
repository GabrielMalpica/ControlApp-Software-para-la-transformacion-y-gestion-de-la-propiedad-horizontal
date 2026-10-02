import '../api/tarea_api.dart';

/// Una correctiva ("actividad especial" para el rol administrador) creada
/// sin fecha ni hora, pendiente de arrastrarse a una franja del cronograma
/// semanal. Vive solo en memoria de [CronogramaPage]: no se persiste en el
/// backend hasta que se ubica en el cronograma.
class ActividadEspecialPendiente {
  final String localId;
  final String descripcion;
  final int prioridad;
  final int duracionMinutos;

  final int ubicacionId;
  final String ubicacionNombre;
  final int elementoId;
  final String elementoNombre;

  final List<String> operariosIds;
  final List<String> operariosNombres;
  final String? supervisorId;

  final String? observaciones;
  final List<int> maquinariaIds;
  final List<Map<String, dynamic>> herramientas;

  ActividadEspecialPendiente({
    required this.localId,
    required this.descripcion,
    required this.prioridad,
    required this.duracionMinutos,
    required this.ubicacionId,
    required this.ubicacionNombre,
    required this.elementoId,
    required this.elementoNombre,
    required this.operariosIds,
    required this.operariosNombres,
    this.supervisorId,
    this.observaciones,
    this.maquinariaIds = const [],
    this.herramientas = const [],
  });

  String get duracionLabel {
    final horas = duracionMinutos ~/ 60;
    final minutos = duracionMinutos % 60;
    if (horas <= 0) return '${duracionMinutos}min';
    if (minutos == 0) return '${horas}h';
    return '${horas}h ${minutos}min';
  }

  TareaRequest toRequest({
    required String conjuntoId,
    required DateTime inicio,
    required DateTime fin,
  }) {
    return TareaRequest(
      descripcion: descripcion,
      fechaInicio: inicio,
      fechaFin: fin,
      duracionMinutos: duracionMinutos,
      prioridad: prioridad,
      tipo: 'CORRECTIVA',
      ubicacionId: ubicacionId,
      elementoId: elementoId,
      conjuntoId: conjuntoId,
      supervisorId: supervisorId,
      operariosIds: operariosIds,
      observaciones: observaciones,
      maquinariaIds: maquinariaIds,
      herramientas: herramientas,
    );
  }
}
