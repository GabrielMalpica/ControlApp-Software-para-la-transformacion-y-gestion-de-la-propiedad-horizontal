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

/// Convierte horas (double/int/string) a minutos (int)
int? _horasToMin(dynamic v) {
  if (v == null) return null;
  final d = _toDouble(v);
  if (d == null) return null;
  final min = (d * 60).round();
  return min > 0 ? min : null;
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
  final int? maquinariaId;
  final String? tipo;
  final double? cantidad;

  final String? origen; // 'CONJUNTO' | 'EMPRESA'
  final bool?
  preferirConjunto; // si true: intenta conjunto, si no hay -> empresa

  MaquinariaPlanItem({
    this.maquinariaId,
    this.tipo,
    this.cantidad,
    this.origen,
    this.preferirConjunto,
  });

  factory MaquinariaPlanItem.fromJson(Map<String, dynamic> json) {
    return MaquinariaPlanItem(
      maquinariaId: _toInt(json['maquinariaId']),
      tipo: json['tipo'] as String?,
      cantidad: _toDouble(json['cantidad']),
      origen: json['origen']?.toString(),
      preferirConjunto: json['preferirConjunto'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
    if (maquinariaId != null) 'maquinariaId': maquinariaId,
    if (tipo != null) 'tipo': tipo,
    if (cantidad != null) 'cantidad': cantidad,
    if (origen != null) 'origen': origen,
    if (preferirConjunto != null) 'preferirConjunto': preferirConjunto,
  };
}

/// ✅ Plan de herramientas asociadas a la definición / tarea
class HerramientaPlanItem {
  final int herramientaId;
  final double cantidad;
  final String estado; // OPERATIVA | DANADA | PERDIDA | BAJA

  HerramientaPlanItem({
    required this.herramientaId,
    required this.cantidad,
    required this.estado,
  });

  factory HerramientaPlanItem.fromJson(Map<String, dynamic> json) {
    return HerramientaPlanItem(
      herramientaId: _toInt(json['herramientaId']) ?? 0,
      cantidad: _toDouble(json['cantidad']) ?? 0,
      estado: (json['estado']?.toString().trim().isNotEmpty ?? false)
          ? json['estado'].toString()
          : 'OPERATIVA',
    );
  }

  Map<String, dynamic> toJson() => {
    'herramientaId': herramientaId,
    'cantidad': cantidad,
    'estado': estado,
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

  final String? diaSemanaProgramado;
  final int? diaMesProgramado;

  final String? unidadCalculo;
  final double? areaNumerica;
  final double? rendimientoBase;

  final int? duracionMinutosFija;
  final String? rendimientoTiempoBase;

  /// ✅ NUEVO: cuántos días para completar la preventiva (si es larga)
  /// Ej: 10 horas = 600 min y diasParaCompletar=5 => 120 min/día
  final int? diasParaCompletar;

  // Insumo principal
  final int? insumoPrincipalId;
  final double? consumoPrincipalPorUnidad;

  final List<InsumoPlanItem> insumosPlan;
  final List<MaquinariaPlanItem> maquinariaPlan;

  final List<HerramientaPlanItem> herramientasPlan;

  /// Operarios asignados
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
    this.diaSemanaProgramado,
    this.diaMesProgramado,
    this.unidadCalculo,
    this.areaNumerica,
    this.rendimientoBase,
    this.duracionMinutosFija,
    this.rendimientoTiempoBase,

    /// ✅ NUEVO
    this.diasParaCompletar,

    this.insumoPrincipalId,
    this.consumoPrincipalPorUnidad,
    this.insumosPlan = const [],
    this.maquinariaPlan = const [],
    this.herramientasPlan = const [],
    this.operariosIds = const [],
    this.responsableSugeridoId,
    this.supervisorId,
    this.activo = true,
  });

  factory DefinicionPreventiva.fromJson(Map<String, dynamic> json) {
    final insumosJson = (json['insumosPlanJson'] as List?) ?? [];
    final maquinariaJson = (json['maquinariaPlanJson'] as List?) ?? [];
    final herramientasJson = (json['herramientasPlanJson'] as List?) ?? [];

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

    final durMin =
        _toInt(json['duracionMinutosFija']) ??
        _horasToMin(json['duracionHorasFija']);

    return DefinicionPreventiva(
      id: _toInt(json['id']) ?? 0,
      conjuntoId: json['conjuntoId']?.toString() ?? '',
      ubicacionId: _toInt(json['ubicacionId']) ?? 0,
      elementoId: _toInt(json['elementoId']) ?? 0,
      descripcion: json['descripcion']?.toString() ?? '',
      frecuencia: json['frecuencia']?.toString() ?? '',
      prioridad: _toInt(json['prioridad']) ?? 2,

      // programación
      diaSemanaProgramado: json['diaSemanaProgramado']?.toString(),
      diaMesProgramado: _toInt(json['diaMesProgramado']),

      unidadCalculo: json['unidadCalculo']?.toString(),
      areaNumerica: _toDouble(json['areaNumerica']),
      rendimientoBase: _toDouble(json['rendimientoBase']),
      duracionMinutosFija: durMin,
      rendimientoTiempoBase: json['rendimientoTiempoBase']?.toString(),

      /// ✅ NUEVO
      diasParaCompletar: _toInt(json['diasParaCompletar']),

      insumoPrincipalId: _toInt(json['insumoPrincipalId']),
      consumoPrincipalPorUnidad: _toDouble(json['consumoPrincipalPorUnidad']),

      insumosPlan: insumosJson
          .map((e) => InsumoPlanItem.fromJson(e as Map<String, dynamic>))
          .toList(),

      maquinariaPlan: maquinariaJson
          .map((e) => MaquinariaPlanItem.fromJson(e as Map<String, dynamic>))
          .toList(),

      herramientasPlan: herramientasJson
          .map((e) => HerramientaPlanItem.fromJson(e as Map<String, dynamic>))
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

class MaquinariaPlanItemRequest {
  final int maquinariaId;
  final String? tipo;
  final double? cantidad;

  // ✅ NUEVO
  final String? origen; // 'CONJUNTO' | 'EMPRESA'
  final bool? preferirConjunto;

  MaquinariaPlanItemRequest({
    required this.maquinariaId,
    this.tipo,
    this.cantidad,
    this.origen,
    this.preferirConjunto,
  });

  Map<String, dynamic> toJson() => {
    'maquinariaId': maquinariaId,
    if (tipo != null) 'tipo': tipo,
    if (cantidad != null) 'cantidad': cantidad,
    if (origen != null) 'origen': origen,
    if (preferirConjunto != null) 'preferirConjunto': preferirConjunto,
  };
}

class HerramientaPlanItemRequest {
  final int herramientaId;
  final double cantidad;
  final String estado;

  HerramientaPlanItemRequest({
    required this.herramientaId,
    required this.cantidad,
    required this.estado,
  });

  Map<String, dynamic> toJson() => {
    'herramientaId': herramientaId,
    'cantidad': cantidad,
    'estado': estado,
  };
}

class DefinicionPreventivaRequest {
  final int ubicacionId;
  final int elementoId;
  final String descripcion;

  final String frecuencia;
  final int prioridad;

  final String? diaSemanaProgramado;
  final int? diaMesProgramado;

  final String? unidadCalculo;
  final double? areaNumerica;
  final double? rendimientoBase;

  /// estándar backend: minutos
  final int? duracionMinutosFija;
  final String? rendimientoTiempoBase;

  /// ✅ NUEVO: días para completar
  final int? diasParaCompletar;

  /// compat temporal: horas
  final double? duracionHorasFijaCompat;

  final int? insumoPrincipalId;
  final double? consumoPrincipalPorUnidad;

  final List<InsumoPlanItemRequest>? insumosPlan;
  final List<MaquinariaPlanItemRequest>? maquinariaPlan;
  final List<HerramientaPlanItemRequest>? herramientasPlan;

  final int? responsableSugeridoId;
  final int? supervisorId;

  final List<int>? operariosIds;

  final bool? activo;

  DefinicionPreventivaRequest({
    required this.ubicacionId,
    required this.elementoId,
    required this.descripcion,
    required this.frecuencia,
    required this.prioridad,
    this.diaSemanaProgramado,
    this.diaMesProgramado,
    this.unidadCalculo,
    this.areaNumerica,
    this.rendimientoBase,
    this.duracionMinutosFija,
    this.rendimientoTiempoBase,

    /// ✅ NUEVO
    this.diasParaCompletar,

    this.duracionHorasFijaCompat,
    this.insumoPrincipalId,
    this.consumoPrincipalPorUnidad,
    this.insumosPlan,
    this.maquinariaPlan,
    this.herramientasPlan,
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

    // programación
    if (diaSemanaProgramado != null) 'diaSemanaProgramado': diaSemanaProgramado,
    if (diaMesProgramado != null) 'diaMesProgramado': diaMesProgramado,

    // cálculo por rendimiento
    if (unidadCalculo != null) 'unidadCalculo': unidadCalculo,
    if (areaNumerica != null) 'areaNumerica': areaNumerica,
    if (rendimientoBase != null) 'rendimientoBase': rendimientoBase,

    // estándar: minutos
    if (duracionMinutosFija != null) 'duracionMinutosFija': duracionMinutosFija,
    if (rendimientoTiempoBase != null)
      'rendimientoTiempoBase': rendimientoTiempoBase,

    /// ✅ NUEVO
    if (diasParaCompletar != null) 'diasParaCompletar': diasParaCompletar,

    // compat (solo si toca)
    if (duracionHorasFijaCompat != null)
      'duracionHorasFija': duracionHorasFijaCompat,

    if (insumoPrincipalId != null) 'insumoPrincipalId': insumoPrincipalId,
    if (consumoPrincipalPorUnidad != null)
      'consumoPrincipalPorUnidad': consumoPrincipalPorUnidad,

    if (insumosPlan != null && insumosPlan!.isNotEmpty)
      'insumosPlanJson': insumosPlan!.map((e) => e.toJson()).toList(),

    if (maquinariaPlan != null && maquinariaPlan!.isNotEmpty)
      'maquinariaPlanJson': maquinariaPlan!.map((e) => e.toJson()).toList(),

    if (herramientasPlan != null && herramientasPlan!.isNotEmpty)
      'herramientasPlanJson': herramientasPlan!.map((e) => e.toJson()).toList(),

    if (responsableSugeridoId != null)
      'responsableSugeridoId': responsableSugeridoId,
    if (supervisorId != null) 'supervisorId': supervisorId,
    if (operariosIds != null && operariosIds!.isNotEmpty)
      'operariosIds': operariosIds,
    if (activo != null) 'activo': activo,
  };
}
