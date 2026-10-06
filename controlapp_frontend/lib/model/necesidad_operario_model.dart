import 'conjunto_model.dart';

/// Franja horaria sin día (a diferencia de [HorarioConjunto]): la usa el
/// horario festivo de una necesidad, que no depende del día de la semana.
/// Espeja HorarioFranjaDTO del backend (Conjunto.ts).
class HorarioFranja {
  final String horaApertura;
  final String horaCierre;
  final String? descansoInicio;
  final String? descansoFin;

  HorarioFranja({
    required this.horaApertura,
    required this.horaCierre,
    this.descansoInicio,
    this.descansoFin,
  });

  factory HorarioFranja.fromJson(Map<String, dynamic> json) {
    return HorarioFranja(
      horaApertura: json['horaApertura'] as String,
      horaCierre: json['horaCierre'] as String,
      descansoInicio: json['descansoInicio'] as String?,
      descansoFin: json['descansoFin'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'horaApertura': horaApertura,
      'horaCierre': horaCierre,
    };
    if (descansoInicio != null) map['descansoInicio'] = descansoInicio;
    if (descansoFin != null) map['descansoFin'] = descansoFin;
    return map;
  }
}

/// Necesidad operativa (plaza/cargo) de un conjunto, p.ej. "Todero #1" o
/// una plaza combinada "Todero-Salvavidas #1". Espeja
/// ConjuntoNecesidadOperario del backend: pertenece al conjunto, y
/// [operarioId] es quien la ocupa actualmente (puede estar vacante).
class NecesidadOperario {
  final int id;
  final String conjuntoId;
  // TODERO | SALVAVIDAS | ASEO | PISCINERO | JARDINERO. Casi siempre uno
  // solo, pero admite combinaciones: quien ocupe la plaza debe tener
  // TODOS los roles de esta lista (lo valida el backend).
  final List<String> roles;
  final String etiqueta;
  final int orden;
  final bool horarioEspecial;
  // Festivos: independiente de horarioEspecial/horarios (por día de
  // semana). Cualquier rol puede trabajar festivos si se configura aquí
  // -reemplaza la regla fija anterior de que solo Salvavidas trabajaba
  // festivos-.
  final bool trabajaFestivos;
  final HorarioFranja? horarioFestivo;
  // Descanso compensatorio: si está activo, trabajar un festivo que cae en
  // el día de descanso semanal de la plaza genera un día de descanso
  // [diasDescansoCompensatorio] días después (un festivo en un día que igual
  // trabaja no genera nada).
  final bool descansoCompensatorio;
  final int diasDescansoCompensatorio;
  final bool activo;
  final String? observaciones;
  final String? operarioId;
  final String? operarioNombre;
  final List<HorarioConjunto> horarios;

  /// Perfil operativo del catálogo de la empresa (null en datos antiguos sin
  /// perfil). Define las categorías de tarea que la plaza puede ejecutar.
  final int? perfilId;
  final String? perfilNombre;
  final bool perfilActivo;

  /// Ids de las categorías habilitadas en el perfil de la plaza.
  final List<int> perfilCategoriasIds;

  NecesidadOperario({
    required this.id,
    required this.conjuntoId,
    required this.roles,
    required this.etiqueta,
    required this.orden,
    required this.horarioEspecial,
    this.trabajaFestivos = false,
    this.horarioFestivo,
    this.descansoCompensatorio = false,
    this.diasDescansoCompensatorio = 1,
    required this.activo,
    this.observaciones,
    this.operarioId,
    this.operarioNombre,
    this.horarios = const [],
    this.perfilId,
    this.perfilNombre,
    this.perfilActivo = true,
    this.perfilCategoriasIds = const [],
  });

  bool get ocupada => operarioId != null;

  /// ¿La plaza puede ejecutar esa categoría? Un perfil sin categorías
  /// configuradas no bloquea (se configura después en el catálogo), igual que
  /// valida el backend al crear/editar una preventiva.
  bool admiteCategoria(int categoriaId) =>
      perfilCategoriasIds.isEmpty || perfilCategoriasIds.contains(categoriaId);

  factory NecesidadOperario.fromJson(Map<String, dynamic> json) {
    final operarioJson = json['operario'] as Map<String, dynamic>?;
    final usuarioJson = operarioJson?['usuario'] as Map<String, dynamic>?;
    final horariosJson = (json['horarios'] as List?) ?? const [];
    final rolesJson = (json['roles'] as List?) ?? const [];
    final festivoHoraApertura = json['festivoHoraApertura'] as String?;
    final festivoHoraCierre = json['festivoHoraCierre'] as String?;
    final perfilJson = json['perfil'] is Map
        ? Map<String, dynamic>.from(json['perfil'] as Map)
        : null;

    return NecesidadOperario(
      id: json['id'] as int,
      conjuntoId: json['conjuntoId'] as String,
      roles: rolesJson.map((r) => r.toString()).toList(),
      etiqueta: json['etiqueta'] as String,
      orden: json['orden'] as int? ?? 0,
      horarioEspecial: json['horarioEspecial'] as bool? ?? false,
      trabajaFestivos: json['trabajaFestivos'] as bool? ?? false,
      horarioFestivo: (festivoHoraApertura != null && festivoHoraCierre != null)
          ? HorarioFranja(
              horaApertura: festivoHoraApertura,
              horaCierre: festivoHoraCierre,
              descansoInicio: json['festivoDescansoInicio'] as String?,
              descansoFin: json['festivoDescansoFin'] as String?,
            )
          : null,
      descansoCompensatorio: json['descansoCompensatorio'] as bool? ?? false,
      diasDescansoCompensatorio: json['diasDescansoCompensatorio'] as int? ?? 1,
      activo: json['activo'] as bool? ?? true,
      observaciones: json['observaciones'] as String?,
      operarioId:
          json['operarioId'] as String? ?? operarioJson?['id'] as String?,
      operarioNombre: usuarioJson?['nombre'] as String?,
      horarios: horariosJson
          .map((h) => HorarioConjunto.fromJson(h as Map<String, dynamic>))
          .toList(),
      perfilId: json['perfilId'] as int? ?? perfilJson?['id'] as int?,
      perfilNombre: perfilJson?['nombre'] as String?,
      perfilActivo: perfilJson?['activo'] as bool? ?? true,
      perfilCategoriasIds: ((perfilJson?['categorias'] as List?) ?? const [])
          .map((c) => (c as Map)['categoriaId'])
          .whereType<int>()
          .toList(),
    );
  }

  /// Payload para crear/editar la plaza (POST/PATCH
  /// /conjuntos/:nit/necesidades). La asignación de operario va por un
  /// endpoint aparte (asignarOperarioNecesidad/liberarNecesidad).
  Map<String, dynamic> toJson() {
    return {
      'roles': roles,
      'etiqueta': etiqueta,
      'orden': orden,
      'horarioEspecial': horarioEspecial,
      if (observaciones != null) 'observaciones': observaciones,
      'horarios': horarios.map((h) => h.toJson()).toList(),
      'trabajaFestivos': trabajaFestivos,
      'horarioFestivo': horarioFestivo?.toJson(),
      'descansoCompensatorio': descansoCompensatorio,
      'diasDescansoCompensatorio': diasDescansoCompensatorio,
    };
  }
}

/// Un día "interesante" (festivo trabajado o descanso compensatorio) del calendario de una plaza. Espeja lo que devuelve
/// GET /conjuntos/:nit/necesidades/calendario.
class NecesidadCalendarioDia {
  final String fecha; // yyyy-MM-dd
  final String tipo; // FESTIVO | DESCANSO
  final String? origen; // Para DESCANSO: fecha (yyyy-MM-dd) que lo originó.

  NecesidadCalendarioDia({
    required this.fecha,
    required this.tipo,
    this.origen,
  });

  factory NecesidadCalendarioDia.fromJson(Map<String, dynamic> json) {
    return NecesidadCalendarioDia(
      fecha: json['fecha'] as String,
      tipo: json['tipo'] as String,
      origen: json['origen'] as String?,
    );
  }
}

class NecesidadCalendarioPlaza {
  final int necesidadId;
  final String etiqueta;
  final String operarioId;
  final List<NecesidadCalendarioDia> dias;

  NecesidadCalendarioPlaza({
    required this.necesidadId,
    required this.etiqueta,
    required this.operarioId,
    required this.dias,
  });

  factory NecesidadCalendarioPlaza.fromJson(Map<String, dynamic> json) {
    final diasJson = (json['dias'] as List?) ?? const [];
    return NecesidadCalendarioPlaza(
      necesidadId: json['necesidadId'] as int,
      etiqueta: json['etiqueta'] as String,
      operarioId: json['operarioId'] as String,
      dias: diasJson
          .map(
            (d) => NecesidadCalendarioDia.fromJson(d as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}
