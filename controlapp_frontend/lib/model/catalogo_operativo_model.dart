/// Catálogo operativo de la empresa: categorías de tarea (orden de
/// programación del día) y perfiles (capacidades = categorías permitidas).
/// Espeja CategoriaTarea / PerfilOperativo del backend.
library;

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

List<String> _toStringList(dynamic v) =>
    ((v as List?) ?? const []).map((e) => e.toString()).toList();

/// Etiquetas legibles de los roles de un operario (enum TipoFuncion).
const Map<String, String> kEtiquetaRolFuncion = {
  'TODERO': 'Todero',
  'SALVAVIDAS': 'Salvavidas',
  'ASEO': 'Aseo',
  'PISCINERO': 'Piscinero',
  'JARDINERO': 'Jardinero',
};

class CategoriaTarea {
  final int id;
  final String nombre;

  /// 1 = primero en el día. Solo ordena; no decide qué tareas entran al mes.
  final int ordenProgramacion;
  final String? colorHex;

  /// Clave del ícono (ver utils/cronograma/categoria_iconos.dart); null =
  /// la app sugiere uno por el nombre.
  final String? icono;
  final List<String> palabrasClave;
  final bool activa;

  /// Preventivas que la usan (solo viene al listar el catálogo).
  final int preventivas;

  const CategoriaTarea({
    required this.id,
    required this.nombre,
    required this.ordenProgramacion,
    this.colorHex,
    this.icono,
    this.palabrasClave = const [],
    this.activa = true,
    this.preventivas = 0,
  });

  factory CategoriaTarea.fromJson(Map<String, dynamic> json) {
    return CategoriaTarea(
      id: _toInt(json['id']) ?? 0,
      nombre: json['nombre']?.toString() ?? '',
      ordenProgramacion: _toInt(json['ordenProgramacion']) ?? 100,
      colorHex: json['colorHex']?.toString(),
      icono: json['icono']?.toString(),
      palabrasClave: _toStringList(json['palabrasClave']),
      activa: json['activa'] as bool? ?? true,
      preventivas: _toInt(json['preventivas']) ?? 0,
    );
  }
}

/// Resumen de la categoría que viene embebido en una preventiva.
class CategoriaResumen {
  final int id;
  final String nombre;
  final int ordenProgramacion;
  final String? colorHex;
  final String? icono;
  final bool activa;

  const CategoriaResumen({
    required this.id,
    required this.nombre,
    required this.ordenProgramacion,
    this.colorHex,
    this.icono,
    this.activa = true,
  });

  static CategoriaResumen? tryFromJson(dynamic json) {
    if (json is! Map) return null;
    final id = _toInt(json['id']);
    if (id == null) return null;
    return CategoriaResumen(
      id: id,
      nombre: json['nombre']?.toString() ?? '',
      ordenProgramacion: _toInt(json['ordenProgramacion']) ?? 100,
      colorHex: json['colorHex']?.toString(),
      icono: json['icono']?.toString(),
      activa: json['activa'] as bool? ?? true,
    );
  }
}

class PerfilOperativo {
  final int id;
  final String nombre;
  final List<String> roles;
  final String? descripcion;
  final bool activo;

  /// Capacidades: ids de las categorías que este perfil puede ejecutar.
  final List<int> categoriasIds;

  /// Plazas de conjuntos que usan este perfil.
  final int plazas;

  const PerfilOperativo({
    required this.id,
    required this.nombre,
    required this.roles,
    this.descripcion,
    this.activo = true,
    this.categoriasIds = const [],
    this.plazas = 0,
  });

  factory PerfilOperativo.fromJson(Map<String, dynamic> json) {
    return PerfilOperativo(
      id: _toInt(json['id']) ?? 0,
      nombre: json['nombre']?.toString() ?? '',
      roles: _toStringList(json['roles']),
      descripcion: json['descripcion']?.toString(),
      activo: json['activo'] as bool? ?? true,
      categoriasIds: ((json['categoriasIds'] as List?) ?? const [])
          .map(_toInt)
          .whereType<int>()
          .toList(),
      plazas: _toInt(json['plazas']) ?? 0,
    );
  }

  /// "Todero-Salvavidas" a partir de los roles del perfil.
  String get etiquetaRoles =>
      roles.map((r) => kEtiquetaRolFuncion[r] ?? r).join('-');
}

/// Sugerencia de categoría para una preventiva sin categoría (no se guarda
/// hasta que el usuario la confirma).
class SugerenciaCategoria {
  final int defId;
  final String descripcion;
  final int categoriaId;
  final String categoriaNombre;
  final List<String> coincidencias;

  const SugerenciaCategoria({
    required this.defId,
    required this.descripcion,
    required this.categoriaId,
    required this.categoriaNombre,
    this.coincidencias = const [],
  });

  factory SugerenciaCategoria.fromJson(Map<String, dynamic> json) {
    return SugerenciaCategoria(
      defId: _toInt(json['defId']) ?? 0,
      descripcion: json['descripcion']?.toString() ?? '',
      categoriaId: _toInt(json['categoriaId']) ?? 0,
      categoriaNombre: json['categoriaNombre']?.toString() ?? '',
      coincidencias: _toStringList(json['coincidencias']),
    );
  }
}

class SugerenciasCategoriaResultado {
  final List<SugerenciaCategoria> sugerencias;
  final List<({int defId, String descripcion})> sinSugerencia;

  const SugerenciasCategoriaResultado({
    this.sugerencias = const [],
    this.sinSugerencia = const [],
  });

  factory SugerenciasCategoriaResultado.fromJson(Map<String, dynamic> json) {
    return SugerenciasCategoriaResultado(
      sugerencias: ((json['sugerencias'] as List?) ?? const [])
          .map((e) => SugerenciaCategoria.fromJson(e as Map<String, dynamic>))
          .toList(),
      sinSugerencia: ((json['sinSugerencia'] as List?) ?? const [])
          .map(
            (e) => (
              defId: _toInt((e as Map)['defId']) ?? 0,
              descripcion: e['descripcion']?.toString() ?? '',
            ),
          )
          .toList(),
    );
  }
}

/// Resultado de asignar categoría en lote: lo aplicado y lo omitido por
/// incompatibilidad con el perfil de la plaza.
class AsignacionCategoriaResultado {
  final int actualizadas;
  final List<({int id, String descripcion, String motivo})> omitidas;

  const AsignacionCategoriaResultado({
    this.actualizadas = 0,
    this.omitidas = const [],
  });

  factory AsignacionCategoriaResultado.fromJson(Map<String, dynamic> json) {
    return AsignacionCategoriaResultado(
      actualizadas: _toInt(json['actualizadas']) ?? 0,
      omitidas: ((json['omitidas'] as List?) ?? const [])
          .map(
            (e) => (
              id: _toInt((e as Map)['id']) ?? 0,
              descripcion: e['descripcion']?.toString() ?? '',
              motivo: e['motivo']?.toString() ?? '',
            ),
          )
          .toList(),
    );
  }
}
