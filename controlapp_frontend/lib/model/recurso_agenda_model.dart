// lib/model/recurso_agenda_model.dart
//
// Modelos de la agenda de recursos (maquinaria + herramientas). Reflejan el
// contrato de `/recursos/...` del backend (ver docs/agenda-recursos.md).

/// MAQUINARIA | HERRAMIENTA
enum ClaseRecurso {
  maquinaria('MAQUINARIA', 'Maquinaria'),
  herramienta('HERRAMIENTA', 'Herramienta');

  const ClaseRecurso(this.api, this.etiqueta);
  final String api;
  final String etiqueta;

  static ClaseRecurso fromApi(Object? raw) =>
      raw?.toString().toUpperCase() == 'HERRAMIENTA'
          ? ClaseRecurso.herramienta
          : ClaseRecurso.maquinaria;
}

/// Estado de una unidad en un día (derivado por el backend).
enum EstadoDiaRecurso {
  disponible('DISPONIBLE', 'Disponible'),
  reservado('RESERVADO', 'Reservado'),
  enTraslado('EN_TRASLADO', 'Entrega / recogida'),
  prestado('PRESTADO', 'Prestado'),
  mantenimiento('MANTENIMIENTO', 'Mantenimiento'),
  noOperativa('NO_OPERATIVA', 'No operativa');

  const EstadoDiaRecurso(this.api, this.etiqueta);
  final String api;
  final String etiqueta;

  static EstadoDiaRecurso fromApi(Object? raw) {
    final v = raw?.toString().toUpperCase();
    return EstadoDiaRecurso.values.firstWhere(
      (e) => e.api == v,
      orElse: () => EstadoDiaRecurso.disponible,
    );
  }
}

/// Estado "ahora mismo" de una unidad.
enum EstadoActualRecurso {
  disponible('DISPONIBLE', 'Disponible'),
  enUso('EN_USO', 'En uso'),
  reservado('RESERVADO', 'Reservado'),
  enTraslado('EN_TRASLADO', 'En traslado'),
  prestado('PRESTADO', 'Prestado'),
  mantenimiento('MANTENIMIENTO', 'Mantenimiento'),
  noOperativa('NO_OPERATIVA', 'No operativa');

  const EstadoActualRecurso(this.api, this.etiqueta);
  final String api;
  final String etiqueta;

  static EstadoActualRecurso fromApi(Object? raw) {
    final v = raw?.toString().toUpperCase();
    return EstadoActualRecurso.values.firstWhere(
      (e) => e.api == v,
      orElse: () => EstadoActualRecurso.disponible,
    );
  }
}

DateTime _fecha(Object? raw) =>
    DateTime.tryParse(raw?.toString() ?? '')?.toLocal() ??
    DateTime.fromMillisecondsSinceEpoch(0);

DateTime? _fechaOpt(Object? raw) {
  if (raw == null) return null;
  return DateTime.tryParse(raw.toString())?.toLocal();
}

/// 'YYYY-MM-DD' (clave de día del backend) a DateTime local a medianoche.
DateTime fechaDeClave(String clave) {
  final p = clave.split('-');
  if (p.length != 3) return DateTime.now();
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

String claveDeFecha(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

int _int(Object? raw, [int fallback = 0]) =>
    raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '') ?? fallback;

int? _intOpt(Object? raw) =>
    raw == null ? null : (raw is num ? raw.toInt() : int.tryParse(raw.toString()));

String? _str(Object? raw) {
  final s = raw?.toString();
  return (s == null || s.trim().isEmpty) ? null : s;
}

List<Map<String, dynamic>> _lista(Object? raw) => raw is List
    ? raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList()
    : const [];

class ReservaRecursoModel {
  final int id;
  final ClaseRecurso clase;
  final int unidadId;
  final String recursoEtiqueta;

  /// TAREA | PRESTAMO | MANTENIMIENTO
  final String tipo;

  /// RESERVADA | FINALIZADA | CANCELADA
  final String estado;

  /// CONJUNTO | EMPRESA
  final String origen;
  final String? conjuntoId;
  final String? conjuntoNombre;
  final int? tareaId;
  final String? tareaDescripcion;
  final String? tareaEstado;
  final int? necesidadId;
  final DateTime usoInicio;
  final DateTime usoFin;
  final DateTime bloqueoInicio;
  final DateTime bloqueoFin;
  final List<String> responsables;
  final String? supervisor;
  final String? observacion;
  final String? motivoCancelacion;
  final int duracionMinutos;
  final DateTime? canceladoEn;
  final DateTime? finalizadaEn;

  const ReservaRecursoModel({
    required this.id,
    required this.clase,
    required this.unidadId,
    required this.recursoEtiqueta,
    required this.tipo,
    required this.estado,
    required this.origen,
    required this.conjuntoId,
    required this.conjuntoNombre,
    required this.tareaId,
    required this.tareaDescripcion,
    required this.tareaEstado,
    required this.necesidadId,
    required this.usoInicio,
    required this.usoFin,
    required this.bloqueoInicio,
    required this.bloqueoFin,
    required this.responsables,
    required this.supervisor,
    required this.observacion,
    required this.motivoCancelacion,
    required this.duracionMinutos,
    required this.canceladoEn,
    required this.finalizadaEn,
  });

  bool get esMantenimiento => tipo == 'MANTENIMIENTO';
  bool get esPrestamo => tipo == 'PRESTAMO';
  bool get esTarea => tipo == 'TAREA';
  bool get vigente => estado == 'RESERVADA';
  bool get cancelada => estado == 'CANCELADA';
  bool get finalizada => estado == 'FINALIZADA';
  bool get deEmpresa => origen == 'EMPRESA';

  /// Hay ventana logística (entrega/recogida o traslado) además del uso.
  bool get tieneVentanaLogistica =>
      bloqueoInicio.isBefore(usoInicio) || bloqueoFin.isAfter(usoFin);

  factory ReservaRecursoModel.fromJson(Map<String, dynamic> json) {
    return ReservaRecursoModel(
      id: _int(json['id']),
      clase: ClaseRecurso.fromApi(json['clase']),
      unidadId: _int(json['unidadId']),
      recursoEtiqueta: json['recursoEtiqueta']?.toString() ?? 'Recurso',
      tipo: json['tipo']?.toString() ?? 'TAREA',
      estado: json['estado']?.toString() ?? 'RESERVADA',
      origen: json['origen']?.toString() ?? 'EMPRESA',
      conjuntoId: _str(json['conjuntoId']),
      conjuntoNombre: _str(json['conjuntoNombre']),
      tareaId: _intOpt(json['tareaId']),
      tareaDescripcion: _str(json['tareaDescripcion']),
      tareaEstado: _str(json['tareaEstado']),
      necesidadId: _intOpt(json['necesidadId']),
      usoInicio: _fecha(json['usoInicio']),
      usoFin: _fecha(json['usoFin']),
      bloqueoInicio: _fecha(json['bloqueoInicio']),
      bloqueoFin: _fecha(json['bloqueoFin']),
      responsables: (json['responsables'] as List? ?? const [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList(),
      supervisor: _str(json['supervisor']),
      observacion: _str(json['observacion']),
      motivoCancelacion: _str(json['motivoCancelacion']),
      duracionMinutos: _int(json['duracionMinutos']),
      canceladoEn: _fechaOpt(json['canceladoEn']),
      finalizadaEn: _fechaOpt(json['finalizadaEn']),
    );
  }
}

class DiaRecursoModel {
  final DateTime fecha;
  final EstadoDiaRecurso estado;
  final String? conjuntoId;
  final String? conjuntoNombre;

  const DiaRecursoModel({
    required this.fecha,
    required this.estado,
    required this.conjuntoId,
    required this.conjuntoNombre,
  });

  factory DiaRecursoModel.fromJson(Map<String, dynamic> json) => DiaRecursoModel(
        fecha: fechaDeClave(json['fecha']?.toString() ?? ''),
        estado: EstadoDiaRecurso.fromApi(json['estado']),
        conjuntoId: _str(json['conjuntoId']),
        conjuntoNombre: _str(json['conjuntoNombre']),
      );
}

class UnidadAgendaModel {
  final ClaseRecurso clase;
  final int id;
  final String? codigo;
  final String nombre;
  final String etiqueta;
  final String? marca;
  final String? modelo;
  final String? serial;
  final int? tipoId;
  final String tipoNombre;

  /// Estado del inventario (OPERATIVA, DANADA, ...).
  final String estado;
  final bool reservable;

  /// EMPRESA | CONJUNTO
  final String propietarioTipo;
  final String? conjuntoPropietarioId;
  final String? conjuntoPropietarioNombre;
  final String ubicacionBase;
  final EstadoActualRecurso estadoActual;
  final String ubicacionActual;
  final DateTime? libreDesde;
  final List<DiaRecursoModel> dias;
  final List<ReservaRecursoModel> reservas;

  const UnidadAgendaModel({
    required this.clase,
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.etiqueta,
    required this.marca,
    required this.modelo,
    required this.serial,
    required this.tipoId,
    required this.tipoNombre,
    required this.estado,
    required this.reservable,
    required this.propietarioTipo,
    required this.conjuntoPropietarioId,
    required this.conjuntoPropietarioNombre,
    required this.ubicacionBase,
    required this.estadoActual,
    required this.ubicacionActual,
    required this.libreDesde,
    required this.dias,
    required this.reservas,
  });

  bool get esDeEmpresa => propietarioTipo == 'EMPRESA';

  factory UnidadAgendaModel.fromJson(Map<String, dynamic> json) {
    final ubic = json['ubicacionActual'];
    return UnidadAgendaModel(
      clase: ClaseRecurso.fromApi(json['clase']),
      id: _int(json['id']),
      codigo: _str(json['codigo']),
      nombre: json['nombre']?.toString() ?? '',
      etiqueta: json['etiqueta']?.toString() ?? '',
      marca: _str(json['marca']),
      modelo: _str(json['modelo']),
      serial: _str(json['serial']),
      tipoId: _intOpt(json['tipoId']),
      tipoNombre: json['tipoNombre']?.toString() ?? '',
      estado: json['estado']?.toString() ?? 'OPERATIVA',
      reservable: json['reservable'] != false,
      propietarioTipo: json['propietarioTipo']?.toString() ?? 'EMPRESA',
      conjuntoPropietarioId: _str(json['conjuntoPropietarioId']),
      conjuntoPropietarioNombre: _str(json['conjuntoPropietarioNombre']),
      ubicacionBase: json['ubicacionBase']?.toString() ?? '',
      estadoActual: EstadoActualRecurso.fromApi(json['estadoActual']),
      ubicacionActual: ubic is Map ? (ubic['nombre']?.toString() ?? '') : '',
      libreDesde: _fechaOpt(json['libreDesde']),
      dias: _lista(json['dias']).map(DiaRecursoModel.fromJson).toList(),
      reservas: _lista(json['reservas']).map(ReservaRecursoModel.fromJson).toList(),
    );
  }
}

class GrupoAgendaModel {
  final ClaseRecurso clase;
  final int? tipoId;
  final String tipoNombre;
  final int total;
  final int disponiblesHoy;
  final List<UnidadAgendaModel> unidades;

  const GrupoAgendaModel({
    required this.clase,
    required this.tipoId,
    required this.tipoNombre,
    required this.total,
    required this.disponiblesHoy,
    required this.unidades,
  });

  factory GrupoAgendaModel.fromJson(Map<String, dynamic> json) => GrupoAgendaModel(
        clase: ClaseRecurso.fromApi(json['clase']),
        tipoId: _intOpt(json['tipoId']),
        tipoNombre: json['tipoNombre']?.toString() ?? '',
        total: _int(json['total']),
        disponiblesHoy: _int(json['disponiblesHoy']),
        unidades: _lista(json['unidades']).map(UnidadAgendaModel.fromJson).toList(),
      );
}

class AgendaRecursosResponse {
  final DateTime desde;
  final DateTime hasta;
  final List<DateTime> dias;
  final int totalUnidades;
  final List<GrupoAgendaModel> grupos;

  const AgendaRecursosResponse({
    required this.desde,
    required this.hasta,
    required this.dias,
    required this.totalUnidades,
    required this.grupos,
  });

  factory AgendaRecursosResponse.fromJson(Map<String, dynamic> json) => AgendaRecursosResponse(
        desde: fechaDeClave(json['desde']?.toString() ?? ''),
        hasta: fechaDeClave(json['hasta']?.toString() ?? ''),
        dias: (json['dias'] as List? ?? const []).map((e) => fechaDeClave(e.toString())).toList(),
        totalUnidades: _int(json['totalUnidades']),
        grupos: _lista(json['grupos']).map(GrupoAgendaModel.fromJson).toList(),
      );
}

class TareaNecesidadModel {
  final int id;
  final String descripcion;
  final String estado;
  final String tipo;
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final String? grupoPlanId;
  final String? conjuntoId;
  final String conjuntoNombre;
  final String? ubicacion;
  final List<String> operarios;

  const TareaNecesidadModel({
    required this.id,
    required this.descripcion,
    required this.estado,
    required this.tipo,
    required this.fechaInicio,
    required this.fechaFin,
    required this.grupoPlanId,
    required this.conjuntoId,
    required this.conjuntoNombre,
    required this.ubicacion,
    required this.operarios,
  });

  factory TareaNecesidadModel.fromJson(Map<String, dynamic> json) => TareaNecesidadModel(
        id: _int(json['id']),
        descripcion: json['descripcion']?.toString() ?? '',
        estado: json['estado']?.toString() ?? '',
        tipo: json['tipo']?.toString() ?? '',
        fechaInicio: _fecha(json['fechaInicio']),
        fechaFin: _fecha(json['fechaFin']),
        grupoPlanId: _str(json['grupoPlanId']),
        conjuntoId: _str(json['conjuntoId']),
        conjuntoNombre: json['conjuntoNombre']?.toString() ?? '',
        ubicacion: _str(json['ubicacion']),
        operarios: (json['operarios'] as List? ?? const []).map((e) => e.toString()).toList(),
      );
}

enum CoberturaNecesidad {
  pendiente('PENDIENTE', 'Sin asignar'),
  parcial('PARCIAL', 'Parcial'),
  cubierta('CUBIERTA', 'Cubierta');

  const CoberturaNecesidad(this.api, this.etiqueta);
  final String api;
  final String etiqueta;

  static CoberturaNecesidad fromApi(Object? raw) {
    final v = raw?.toString().toUpperCase();
    return CoberturaNecesidad.values.firstWhere(
      (e) => e.api == v,
      orElse: () => CoberturaNecesidad.pendiente,
    );
  }
}

class NecesidadRecursoModel {
  final int id;
  final ClaseRecurso clase;
  final int tipoId;
  final String tipoNombre;
  final int cantidad;
  final bool obligatorio;

  /// PLAN_PREVENTIVA | MANUAL
  final String origen;
  final int asignadas;
  final int pendientes;
  final CoberturaNecesidad cobertura;
  final bool asignable;
  final List<String> conflictos;
  final TareaNecesidadModel tarea;
  final List<ReservaRecursoModel> reservas;

  const NecesidadRecursoModel({
    required this.id,
    required this.clase,
    required this.tipoId,
    required this.tipoNombre,
    required this.cantidad,
    required this.obligatorio,
    required this.origen,
    required this.asignadas,
    required this.pendientes,
    required this.cobertura,
    required this.asignable,
    required this.conflictos,
    required this.tarea,
    required this.reservas,
  });

  bool get tieneConflicto => conflictos.isNotEmpty;

  factory NecesidadRecursoModel.fromJson(Map<String, dynamic> json) => NecesidadRecursoModel(
        id: _int(json['id']),
        clase: ClaseRecurso.fromApi(json['clase']),
        tipoId: _int(json['tipoId']),
        tipoNombre: json['tipoNombre']?.toString() ?? '',
        cantidad: _int(json['cantidad'], 1),
        obligatorio: json['obligatorio'] != false,
        origen: json['origen']?.toString() ?? 'PLAN_PREVENTIVA',
        asignadas: _int(json['asignadas']),
        pendientes: _int(json['pendientes']),
        cobertura: CoberturaNecesidad.fromApi(json['cobertura']),
        asignable: json['asignable'] == true,
        conflictos: _lista(json['conflictos']).map((c) => c['motivo']?.toString() ?? '').toList(),
        tarea: TareaNecesidadModel.fromJson(Map<String, dynamic>.from(json['tarea'] as Map? ?? const {})),
        reservas: _lista(json['reservas']).map(ReservaRecursoModel.fromJson).toList(),
      );
}

class ResumenNecesidades {
  final int total;
  final int pendientes;
  final int parciales;
  final int cubiertas;
  final int conConflicto;

  const ResumenNecesidades({
    this.total = 0,
    this.pendientes = 0,
    this.parciales = 0,
    this.cubiertas = 0,
    this.conConflicto = 0,
  });

  factory ResumenNecesidades.fromJson(Map<String, dynamic>? json) => ResumenNecesidades(
        total: _int(json?['total']),
        pendientes: _int(json?['pendientes']),
        parciales: _int(json?['parciales']),
        cubiertas: _int(json?['cubiertas']),
        conConflicto: _int(json?['conConflicto']),
      );
}

class NecesidadesResponse {
  final ResumenNecesidades resumen;
  final List<NecesidadRecursoModel> necesidades;

  const NecesidadesResponse({required this.resumen, required this.necesidades});

  factory NecesidadesResponse.fromJson(Map<String, dynamic> json) => NecesidadesResponse(
        resumen: ResumenNecesidades.fromJson(
          json['resumen'] is Map ? Map<String, dynamic>.from(json['resumen'] as Map) : null,
        ),
        necesidades: _lista(json['necesidades']).map(NecesidadRecursoModel.fromJson).toList(),
      );
}

class ContextoReservaModel {
  final int reservaId;
  final String tipo;
  final String? conjuntoNombre;
  final String? tareaDescripcion;
  final DateTime usoInicio;
  final DateTime usoFin;

  const ContextoReservaModel({
    required this.reservaId,
    required this.tipo,
    required this.conjuntoNombre,
    required this.tareaDescripcion,
    required this.usoInicio,
    required this.usoFin,
  });

  static ContextoReservaModel? fromJsonOpt(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    return ContextoReservaModel(
      reservaId: _int(json['reservaId']),
      tipo: json['tipo']?.toString() ?? 'TAREA',
      conjuntoNombre: _str(json['conjuntoNombre']),
      tareaDescripcion: _str(json['tareaDescripcion']),
      usoInicio: _fecha(json['usoInicio']),
      usoFin: _fecha(json['usoFin']),
    );
  }
}

/// CONJUNTO (propia) | CUSTODIA (prestada y ya en el conjunto) | EMPRESA
enum GrupoCandidato {
  conjunto('CONJUNTO', 'Del conjunto'),
  custodia('CUSTODIA', 'Ya prestada al conjunto'),
  empresa('EMPRESA', 'Préstamo de la empresa');

  const GrupoCandidato(this.api, this.etiqueta);
  final String api;
  final String etiqueta;

  static GrupoCandidato fromApi(Object? raw) {
    final v = raw?.toString().toUpperCase();
    return GrupoCandidato.values.firstWhere(
      (e) => e.api == v,
      orElse: () => GrupoCandidato.empresa,
    );
  }
}

class CandidatoRecursoModel {
  final ClaseRecurso clase;
  final int unidadId;
  final String etiqueta;
  final String? codigo;
  final String tipoNombre;
  final String? marca;
  final String estado;
  final GrupoCandidato grupo;
  final String origen;
  final bool disponible;
  final String? motivo;
  final bool sugerida;
  final bool yaAsignada;
  final bool cercaDelConjunto;
  final int usosEnPeriodo;
  final DateTime? bloqueoInicio;
  final DateTime? bloqueoFin;
  final ContextoReservaModel? reservaAnterior;
  final ContextoReservaModel? reservaSiguiente;

  const CandidatoRecursoModel({
    required this.clase,
    required this.unidadId,
    required this.etiqueta,
    required this.codigo,
    required this.tipoNombre,
    required this.marca,
    required this.estado,
    required this.grupo,
    required this.origen,
    required this.disponible,
    required this.motivo,
    required this.sugerida,
    required this.yaAsignada,
    required this.cercaDelConjunto,
    required this.usosEnPeriodo,
    required this.bloqueoInicio,
    required this.bloqueoFin,
    required this.reservaAnterior,
    required this.reservaSiguiente,
  });

  factory CandidatoRecursoModel.fromJson(Map<String, dynamic> json) {
    final ventana = json['ventana'] is Map ? Map<String, dynamic>.from(json['ventana'] as Map) : null;
    return CandidatoRecursoModel(
      clase: ClaseRecurso.fromApi(json['clase']),
      unidadId: _int(json['unidadId']),
      etiqueta: json['etiqueta']?.toString() ?? '',
      codigo: _str(json['codigo']),
      tipoNombre: json['tipoNombre']?.toString() ?? '',
      marca: _str(json['marca']),
      estado: json['estado']?.toString() ?? '',
      grupo: GrupoCandidato.fromApi(json['grupo']),
      origen: json['origen']?.toString() ?? 'EMPRESA',
      disponible: json['disponible'] == true,
      motivo: _str(json['motivo']),
      sugerida: json['sugerida'] == true,
      yaAsignada: json['yaAsignada'] == true,
      cercaDelConjunto: json['cercaDelConjunto'] == true,
      usosEnPeriodo: _int(json['usosEnPeriodo']),
      bloqueoInicio: _fechaOpt(ventana?['bloqueoInicio']),
      bloqueoFin: _fechaOpt(ventana?['bloqueoFin']),
      reservaAnterior: ContextoReservaModel.fromJsonOpt(json['reservaAnterior']),
      reservaSiguiente: ContextoReservaModel.fromJsonOpt(json['reservaSiguiente']),
    );
  }
}

class CandidatosResponse {
  final int necesidadId;
  final ClaseRecurso clase;
  final String tipoNombre;
  final int cantidad;
  final bool obligatorio;
  final int asignadas;
  final int pendientes;
  final TareaNecesidadModel tarea;
  final int tareasDelGrupoConPendiente;
  final List<CandidatoRecursoModel> candidatos;

  const CandidatosResponse({
    required this.necesidadId,
    required this.clase,
    required this.tipoNombre,
    required this.cantidad,
    required this.obligatorio,
    required this.asignadas,
    required this.pendientes,
    required this.tarea,
    required this.tareasDelGrupoConPendiente,
    required this.candidatos,
  });

  factory CandidatosResponse.fromJson(Map<String, dynamic> json) {
    final n = Map<String, dynamic>.from(json['necesidad'] as Map? ?? const {});
    final t = Map<String, dynamic>.from(json['tarea'] as Map? ?? const {});
    final g = Map<String, dynamic>.from(json['grupo'] as Map? ?? const {});
    return CandidatosResponse(
      necesidadId: _int(n['id']),
      clase: ClaseRecurso.fromApi(n['clase']),
      tipoNombre: n['tipoNombre']?.toString() ?? '',
      cantidad: _int(n['cantidad'], 1),
      obligatorio: n['obligatorio'] != false,
      asignadas: _int(n['asignadas']),
      pendientes: _int(n['pendientes']),
      tarea: TareaNecesidadModel.fromJson(t),
      tareasDelGrupoConPendiente: _int(g['tareasConPendiente']),
      candidatos: _lista(json['candidatos']).map(CandidatoRecursoModel.fromJson).toList(),
    );
  }
}

class AlertaRecursoModel {
  /// NECESIDAD_SIN_CUBRIR | NECESIDAD_PARCIAL | NECESIDAD_OPCIONAL_PENDIENTE |
  /// RECURSO_NO_OPERATIVO | RESERVA_TAREA_INACTIVA | RESERVA_FUERA_DE_HORARIO
  final String tipo;

  /// ALTA | MEDIA | BAJA
  final String severidad;
  final String mensaje;
  final DateTime fecha;
  final String? conjuntoId;
  final String? conjuntoNombre;
  final int? tareaId;
  final int? necesidadId;
  final int? reservaId;

  const AlertaRecursoModel({
    required this.tipo,
    required this.severidad,
    required this.mensaje,
    required this.fecha,
    required this.conjuntoId,
    required this.conjuntoNombre,
    required this.tareaId,
    required this.necesidadId,
    required this.reservaId,
  });

  bool get esNecesidad => tipo.startsWith('NECESIDAD_');

  factory AlertaRecursoModel.fromJson(Map<String, dynamic> json) => AlertaRecursoModel(
        tipo: json['tipo']?.toString() ?? '',
        severidad: json['severidad']?.toString() ?? 'MEDIA',
        mensaje: json['mensaje']?.toString() ?? '',
        fecha: _fecha(json['fecha']),
        conjuntoId: _str(json['conjuntoId']),
        conjuntoNombre: _str(json['conjuntoNombre']),
        tareaId: _intOpt(json['tareaId']),
        necesidadId: _intOpt(json['necesidadId']),
        reservaId: _intOpt(json['reservaId']),
      );
}

class AlertasResponse {
  final int total;
  final int alta;
  final List<AlertaRecursoModel> alertas;

  const AlertasResponse({required this.total, required this.alta, required this.alertas});

  factory AlertasResponse.fromJson(Map<String, dynamic> json) {
    final r = json['resumen'] is Map ? Map<String, dynamic>.from(json['resumen'] as Map) : const {};
    return AlertasResponse(
      total: _int(r['total']),
      alta: _int(r['alta']),
      alertas: _lista(json['alertas']).map(AlertaRecursoModel.fromJson).toList(),
    );
  }
}

class LlegadaRecursosDia {
  final DateTime fecha;
  final List<ReservaRecursoModel> reservas;

  const LlegadaRecursosDia({required this.fecha, required this.reservas});
}

class SemanaConjuntoResponse {
  final String conjuntoId;
  final String conjuntoNombre;
  final DateTime desde;
  final DateTime hasta;
  final List<DateTime> dias;
  final List<NecesidadRecursoModel> necesidades;
  final ResumenNecesidades resumenNecesidades;
  final List<UnidadAgendaModel> recursosPropios;
  final List<LlegadaRecursosDia> recursosEmpresa;

  const SemanaConjuntoResponse({
    required this.conjuntoId,
    required this.conjuntoNombre,
    required this.desde,
    required this.hasta,
    required this.dias,
    required this.necesidades,
    required this.resumenNecesidades,
    required this.recursosPropios,
    required this.recursosEmpresa,
  });

  factory SemanaConjuntoResponse.fromJson(Map<String, dynamic> json) {
    final c = Map<String, dynamic>.from(json['conjunto'] as Map? ?? const {});
    return SemanaConjuntoResponse(
      conjuntoId: c['nit']?.toString() ?? '',
      conjuntoNombre: c['nombre']?.toString() ?? '',
      desde: fechaDeClave(json['desde']?.toString() ?? ''),
      hasta: fechaDeClave(json['hasta']?.toString() ?? ''),
      dias: (json['dias'] as List? ?? const []).map((e) => fechaDeClave(e.toString())).toList(),
      necesidades: _lista(json['necesidades']).map(NecesidadRecursoModel.fromJson).toList(),
      resumenNecesidades: ResumenNecesidades.fromJson(
        json['resumenNecesidades'] is Map ? Map<String, dynamic>.from(json['resumenNecesidades'] as Map) : null,
      ),
      recursosPropios: _lista(json['recursosPropios']).map(UnidadAgendaModel.fromJson).toList(),
      recursosEmpresa: _lista(json['recursosEmpresa'])
          .map(
            (d) => LlegadaRecursosDia(
              fecha: fechaDeClave(d['fecha']?.toString() ?? ''),
              reservas: _lista(d['reservas']).map(ReservaRecursoModel.fromJson).toList(),
            ),
          )
          .toList(),
    );
  }
}

class HistorialUnidadResponse {
  final String etiqueta;
  final String tipoNombre;
  final String estado;
  final bool reservable;
  final EstadoActualRecurso estadoActual;
  final String ubicacionActual;
  final DateTime? libreDesde;
  final int totalReservas;
  final int finalizadas;
  final int canceladas;
  final int minutosDeUso;
  final int conjuntosDistintos;
  final List<ReservaRecursoModel> reservas;

  const HistorialUnidadResponse({
    required this.etiqueta,
    required this.tipoNombre,
    required this.estado,
    required this.reservable,
    required this.estadoActual,
    required this.ubicacionActual,
    required this.libreDesde,
    required this.totalReservas,
    required this.finalizadas,
    required this.canceladas,
    required this.minutosDeUso,
    required this.conjuntosDistintos,
    required this.reservas,
  });

  factory HistorialUnidadResponse.fromJson(Map<String, dynamic> json) {
    final u = Map<String, dynamic>.from(json['unidad'] as Map? ?? const {});
    final e = Map<String, dynamic>.from(json['estadoActual'] as Map? ?? const {});
    final r = Map<String, dynamic>.from(json['resumen'] as Map? ?? const {});
    final ubic = e['ubicacion'];
    return HistorialUnidadResponse(
      etiqueta: u['etiqueta']?.toString() ?? '',
      tipoNombre: u['tipoNombre']?.toString() ?? '',
      estado: u['estado']?.toString() ?? '',
      reservable: u['reservable'] != false,
      estadoActual: EstadoActualRecurso.fromApi(e['estado']),
      ubicacionActual: ubic is Map ? (ubic['nombre']?.toString() ?? '') : '',
      libreDesde: _fechaOpt(e['libreDesde']),
      totalReservas: _int(r['reservas']),
      finalizadas: _int(r['finalizadas']),
      canceladas: _int(r['canceladas']),
      minutosDeUso: _int(r['minutosDeUso']),
      conjuntosDistintos: _int(r['conjuntosDistintos']),
      reservas: _lista(json['reservas']).map(ReservaRecursoModel.fromJson).toList(),
    );
  }
}

class ConfigLogisticaRecursos {
  /// 0=domingo..6=sábado. Vacío = la empresa trabaja por horas.
  final List<int> diasEntregaRecursos;
  final int margenTrasladoMinutos;

  const ConfigLogisticaRecursos({
    required this.diasEntregaRecursos,
    required this.margenTrasladoMinutos,
  });

  bool get porHoras => diasEntregaRecursos.isEmpty;

  factory ConfigLogisticaRecursos.fromJson(Map<String, dynamic> json) => ConfigLogisticaRecursos(
        diasEntregaRecursos: (json['diasEntregaRecursos'] as List? ?? const [])
            .map((e) => _int(e))
            .toList(),
        margenTrasladoMinutos: _int(json['margenTrasladoMinutos']),
      );

  Map<String, dynamic> toJson() => {
        'diasEntregaRecursos': diasEntregaRecursos,
        'margenTrasladoMinutos': margenTrasladoMinutos,
      };
}

class CapacidadBorradorDia {
  final DateTime fecha;
  final ClaseRecurso clase;
  final String tipoNombre;
  final int requeridas;
  final int capacidad;
  final bool insuficiente;

  const CapacidadBorradorDia({
    required this.fecha,
    required this.clase,
    required this.tipoNombre,
    required this.requeridas,
    required this.capacidad,
    required this.insuficiente,
  });

  factory CapacidadBorradorDia.fromJson(Map<String, dynamic> json) => CapacidadBorradorDia(
        fecha: fechaDeClave(json['fecha']?.toString() ?? ''),
        clase: ClaseRecurso.fromApi(json['clase']),
        tipoNombre: json['tipoNombre']?.toString() ?? '',
        requeridas: _int(json['requeridas']),
        capacidad: _int(json['capacidad']),
        insuficiente: json['insuficiente'] == true,
      );
}

/// Un conflicto de un 409 RECURSO_OCUPADO (al reservar o al reprogramar).
class ConflictoRecursoModel {
  final String unidadEtiqueta;
  final String motivo;
  final String? ocupadoConjunto;
  final String? ocupadoTarea;
  final DateTime? ocupadoDesde;
  final DateTime? ocupadoHasta;

  const ConflictoRecursoModel({
    required this.unidadEtiqueta,
    required this.motivo,
    this.ocupadoConjunto,
    this.ocupadoTarea,
    this.ocupadoDesde,
    this.ocupadoHasta,
  });

  factory ConflictoRecursoModel.fromJson(Map<String, dynamic> json) {
    final o = json['ocupadoPor'] is Map ? Map<String, dynamic>.from(json['ocupadoPor'] as Map) : null;
    return ConflictoRecursoModel(
      unidadEtiqueta: json['unidadEtiqueta']?.toString() ?? '',
      motivo: json['motivo']?.toString() ?? '',
      ocupadoConjunto: _str(o?['conjuntoNombre']),
      ocupadoTarea: _str(o?['tareaDescripcion']),
      ocupadoDesde: _fechaOpt(o?['bloqueoInicio']),
      ocupadoHasta: _fechaOpt(o?['bloqueoFin']),
    );
  }

  /// Extrae los conflictos de un cuerpo de error del backend (si es RECURSO_OCUPADO).
  static List<ConflictoRecursoModel> desdeError(Object? details) {
    if (details is! Map) return const [];
    final reason = (details['reason'] ?? details['code'])?.toString();
    if (reason != 'RECURSO_OCUPADO') return const [];
    return _lista(details['conflictos']).map(ConflictoRecursoModel.fromJson).toList();
  }
}
