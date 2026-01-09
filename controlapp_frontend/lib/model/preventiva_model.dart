// lib/model/preventiva_model.dart

double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

/* ===================== MODELOS ===================== */

class InsumoPlanItem {
  final int insumoId;
  final double consumoPorUnidad;

  InsumoPlanItem({required this.insumoId, required this.consumoPorUnidad});

  factory InsumoPlanItem.fromJson(Map<String, dynamic> json) {
    return InsumoPlanItem(
      insumoId: _toInt(json['insumoId']) ?? 0,
      consumoPorUnidad: _toDouble(json['consumoPorUnidad']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'insumoId': insumoId,
    'consumoPorUnidad': consumoPorUnidad,
  };
}

/// 🔹 Plan de maquinaria asociada a la definición / tarea
class MaquinariaPlanItem {
  final int? maquinariaId; // id en el catálogo de la empresa
  final String? tipo; // ej: "guadaña", "hidrolavadora"
  final double? cantidad; // ej: horas de uso, unidades, etc.

  MaquinariaPlanItem({this.maquinariaId, this.tipo, this.cantidad});

  factory MaquinariaPlanItem.fromJson(Map<String, dynamic> json) {
    return MaquinariaPlanItem(
      maquinariaId: _toInt(json['maquinariaId']),
      tipo: json['tipo'] as String?,
      cantidad: _toDouble(json['cantidad']),
    );
  }

  Map<String, dynamic> toJson() => {
    if (maquinariaId != null) 'maquinariaId': maquinariaId,
    if (tipo != null) 'tipo': tipo,
    if (cantidad != null) 'cantidad': cantidad,
  };
}

class DefinicionPreventiva {
  final int id;
  final String conjuntoId;

  final int ubicacionId;
  final int elementoId;

  final String descripcion;
  final String frecuencia;
  final int prioridad;

  // Duración / cálculo
  final String? unidadCalculo;
  final double? areaNumerica;
  final double? rendimientoBase;
  final int? duracionHorasFija;

  // Insumo principal
  final int? insumoPrincipalId;
  final double? consumoPrincipalPorUnidad;

  final List<InsumoPlanItem> insumosPlan;
  final List<MaquinariaPlanItem> maquinariaPlan;

  /// 🔹 Operarios asignados a la definición (IDs de la tabla Operario)
  final List<int> operariosIds;

  // Responsable sugerido (principal)
  final int? responsableSugeridoId;

  // Supervisor responsable
  final int? supervisorId;

  final bool activo;

  DefinicionPreventiva({
    required this.id,
    required this.conjuntoId,
    required this.ubicacionId,
    required this.elementoId,
    required this.descripcion,
    required this.frecuencia,
    required this.prioridad,
    this.unidadCalculo,
    this.areaNumerica,
    this.rendimientoBase,
    this.duracionHorasFija,
    this.insumoPrincipalId,
    this.consumoPrincipalPorUnidad,
    this.insumosPlan = const [],
    this.maquinariaPlan = const [],
    this.operariosIds = const [],
    this.responsableSugeridoId,
    this.supervisorId,
    this.activo = true,
  });

  factory DefinicionPreventiva.fromJson(Map<String, dynamic> json) {
    final insumosJson = (json['insumosPlanJson'] as List?) ?? [];
    final maquinariaJson = (json['maquinariaPlanJson'] as List?) ?? [];

    // 👇 soporta tanto "operariosIds" como "operarios"
    List<int> opIds = [];
    if (json['operariosIds'] != null) {
      opIds = (json['operariosIds'] as List)
          .map((e) => _toInt(e))
          .whereType<int>()
          .toList();
    } else if (json['operarios'] != null) {
      opIds = (json['operarios'] as List)
          .map((e) => _toInt((e as Map)['id']))
          .whereType<int>()
          .toList();
    }

    return DefinicionPreventiva(
      id: _toInt(json['id']) ?? 0,
      conjuntoId: json['conjuntoId']?.toString() ?? '',
      ubicacionId: _toInt(json['ubicacionId']) ?? 0,
      elementoId: _toInt(json['elementoId']) ?? 0,
      descripcion: json['descripcion']?.toString() ?? '',
      frecuencia: json['frecuencia']?.toString() ?? '',
      prioridad: _toInt(json['prioridad']) ?? 5,
      unidadCalculo: json['unidadCalculo']?.toString(),
      areaNumerica: _toDouble(json['areaNumerica']),
      rendimientoBase: _toDouble(json['rendimientoBase']),
      duracionHorasFija: _toInt(json['duracionHorasFija']),
      insumoPrincipalId: _toInt(json['insumoPrincipalId']),
      consumoPrincipalPorUnidad: _toDouble(json['consumoPrincipalPorUnidad']),
      insumosPlan: insumosJson
          .map((e) => InsumoPlanItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      maquinariaPlan: maquinariaJson
          .map((e) => MaquinariaPlanItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      operariosIds: opIds,
      responsableSugeridoId: _toInt(json['responsableSugeridoId']),
      supervisorId: _toInt(json['supervisorId']),
      activo: json['activo'] as bool? ?? true,
    );
  }
}

/* ===================== REQUESTS (para enviar al backend) ===================== */

class InsumoPlanItemRequest {
  final int insumoId;
  final double consumoPorUnidad;

  InsumoPlanItemRequest({
    required this.insumoId,
    required this.consumoPorUnidad,
  });

  Map<String, dynamic> toJson() => {
    'insumoId': insumoId,
    'consumoPorUnidad': consumoPorUnidad,
  };
}

/// 🔹 Request para maquinaria planificada
class MaquinariaPlanItemRequest {
  final int maquinariaId;
  final String? tipo;
  final double? cantidad;

  MaquinariaPlanItemRequest({
    required this.maquinariaId,
    this.tipo,
    this.cantidad,
  });

  Map<String, dynamic> toJson() => {
    'maquinariaId': maquinariaId,
    if (tipo != null) 'tipo': tipo,
    if (cantidad != null) 'cantidad': cantidad,
  };
}

class DefinicionPreventivaRequest {
  final int ubicacionId;
  final int elementoId;
  final String descripcion;
  final String frecuencia;
  final int prioridad;

  final String? unidadCalculo;
  final double? areaNumerica;
  final double? rendimientoBase;
  final int? duracionHorasFija;

  final int? insumoPrincipalId;
  final double? consumoPrincipalPorUnidad;
  final List<InsumoPlanItemRequest>? insumosPlan;
  final List<MaquinariaPlanItemRequest>? maquinariaPlan;

  final int? responsableSugeridoId;
  final int? supervisorId;

  /// 🔹 NUEVO: operarios asignados
  final List<int>? operariosIds;

  final bool? activo;

  DefinicionPreventivaRequest({
    required this.ubicacionId,
    required this.elementoId,
    required this.descripcion,
    required this.frecuencia,
    required this.prioridad,
    this.unidadCalculo,
    this.areaNumerica,
    this.rendimientoBase,
    this.duracionHorasFija,
    this.insumoPrincipalId,
    this.consumoPrincipalPorUnidad,
    this.insumosPlan,
    this.maquinariaPlan,
    this.responsableSugeridoId,
    this.supervisorId,
    this.operariosIds,
    this.activo,
  });

  Map<String, dynamic> toJson() => {
    'ubicacionId': ubicacionId,
    'elementoId': elementoId,
    'descripcion': descripcion,
    'frecuencia': frecuencia,
    'prioridad': prioridad,
    if (unidadCalculo != null) 'unidadCalculo': unidadCalculo,
    if (areaNumerica != null) 'areaNumerica': areaNumerica,
    if (rendimientoBase != null) 'rendimientoBase': rendimientoBase,
    if (duracionHorasFija != null) 'duracionHorasFija': duracionHorasFija,
    if (insumoPrincipalId != null) 'insumoPrincipalId': insumoPrincipalId,
    if (consumoPrincipalPorUnidad != null)
      'consumoPrincipalPorUnidad': consumoPrincipalPorUnidad,
    if (insumosPlan != null && insumosPlan!.isNotEmpty)
      'insumosPlanJson': insumosPlan!.map((e) => e.toJson()).toList(),
    if (maquinariaPlan != null && maquinariaPlan!.isNotEmpty)
      'maquinariaPlanJson': maquinariaPlan!.map((e) => e.toJson()).toList(),
    if (responsableSugeridoId != null)
      'responsableSugeridoId': responsableSugeridoId,
    if (supervisorId != null) 'supervisorId': supervisorId,
    if (operariosIds != null && operariosIds!.isNotEmpty)
      'operariosIds': operariosIds,
    if (activo != null) 'activo': activo,
  };
}
