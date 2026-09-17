import 'conjunto_model.dart';

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
  final bool activo;
  final String? observaciones;
  final String? operarioId;
  final String? operarioNombre;
  final List<HorarioConjunto> horarios;

  NecesidadOperario({
    required this.id,
    required this.conjuntoId,
    required this.roles,
    required this.etiqueta,
    required this.orden,
    required this.horarioEspecial,
    required this.activo,
    this.observaciones,
    this.operarioId,
    this.operarioNombre,
    this.horarios = const [],
  });

  bool get ocupada => operarioId != null;

  factory NecesidadOperario.fromJson(Map<String, dynamic> json) {
    final operarioJson = json['operario'] as Map<String, dynamic>?;
    final usuarioJson = operarioJson?['usuario'] as Map<String, dynamic>?;
    final horariosJson = (json['horarios'] as List?) ?? const [];
    final rolesJson = (json['roles'] as List?) ?? const [];

    return NecesidadOperario(
      id: json['id'] as int,
      conjuntoId: json['conjuntoId'] as String,
      roles: rolesJson.map((r) => r.toString()).toList(),
      etiqueta: json['etiqueta'] as String,
      orden: json['orden'] as int? ?? 0,
      horarioEspecial: json['horarioEspecial'] as bool? ?? false,
      activo: json['activo'] as bool? ?? true,
      observaciones: json['observaciones'] as String?,
      operarioId: json['operarioId'] as String? ?? operarioJson?['id'] as String?,
      operarioNombre: usuarioJson?['nombre'] as String?,
      horarios: horariosJson
          .map((h) => HorarioConjunto.fromJson(h as Map<String, dynamic>))
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
    };
  }
}
