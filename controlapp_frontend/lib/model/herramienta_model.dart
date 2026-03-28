// lib/model/herramienta_model.dart

// =========================
// ENUMS
// =========================

/// Modo de control según Prisma
enum ModoControlHerramienta { PRESTAMO, CONSUMO, VIDA_CORTA }

enum CategoriaHerramienta { LIMPIEZA, JARDINERIA, PISCINA, OTROS }

extension CategoriaHerramientaExt on CategoriaHerramienta {
  String get label {
    switch (this) {
      case CategoriaHerramienta.LIMPIEZA:
        return 'Limpieza';
      case CategoriaHerramienta.JARDINERIA:
        return 'Jardineria';
      case CategoriaHerramienta.PISCINA:
        return 'Piscina';
      case CategoriaHerramienta.OTROS:
        return 'Otros';
    }
  }

  String get backendValue => name;
}

extension ModoControlHerramientaExt on ModoControlHerramienta {
  /// Label para UI
  String get label {
    switch (this) {
      case ModoControlHerramienta.PRESTAMO:
        return 'Préstamo';
      case ModoControlHerramienta.CONSUMO:
        return 'Consumo';
      case ModoControlHerramienta.VIDA_CORTA:
        return 'Vida corta';
    }
  }

  /// Valor que espera el backend (Prisma enum)
  String get backendValue => name; // PRESTAMO | CONSUMO | VIDA_CORTA
}

/// Estado del stock por conjunto
enum EstadoHerramientaStock { OPERATIVA, DANADA, PERDIDA, BAJA }

enum TipoTenenciaHerramienta { PROPIA, PRESTADA }

extension EstadoHerramientaStockExt on EstadoHerramientaStock {
  String get label {
    switch (this) {
      case EstadoHerramientaStock.OPERATIVA:
        return 'Operativa';
      case EstadoHerramientaStock.DANADA:
        return 'Dañada';
      case EstadoHerramientaStock.PERDIDA:
        return 'Perdida';
      case EstadoHerramientaStock.BAJA:
        return 'Baja';
    }
  }

  String get backendValue => name;
}

// =========================
// HELPERS
// =========================

int _asInt(dynamic v, {int fallback = 0}) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? fallback;
}

num _asNum(dynamic v, {num fallback = 0}) {
  if (v == null) return fallback;
  if (v is num) return v;
  return num.tryParse(v.toString()) ?? fallback;
}

String _asString(dynamic v, {String fallback = ""}) {
  if (v == null) return fallback;
  return v.toString();
}

ModoControlHerramienta _parseModo(dynamic v) {
  final s = _asString(v, fallback: "PRESTAMO");
  return ModoControlHerramienta.values.firstWhere(
    (e) => e.name == s,
    orElse: () => ModoControlHerramienta.PRESTAMO,
  );
}

EstadoHerramientaStock _parseEstadoStock(dynamic v) {
  final s = _asString(v, fallback: "OPERATIVA");
  return EstadoHerramientaStock.values.firstWhere(
    (e) => e.name == s,
    orElse: () => EstadoHerramientaStock.OPERATIVA,
  );
}

CategoriaHerramienta _parseCategoria(dynamic v) {
  final s = _asString(v, fallback: 'OTROS');
  return CategoriaHerramienta.values.firstWhere(
    (e) => e.name == s,
    orElse: () => CategoriaHerramienta.OTROS,
  );
}

// =========================
// REQUESTS (para POST / PATCH)
// =========================

/// Crear / editar herramienta (catálogo empresa)
class HerramientaRequest {
  final String nombre;
  final String unidad;
  final CategoriaHerramienta categoria;
  final ModoControlHerramienta modoControl;
  final int? vidaUtilDias;
  final int? umbralBajo;

  HerramientaRequest({
    required this.nombre,
    required this.unidad,
    this.categoria = CategoriaHerramienta.OTROS,
    required this.modoControl,
    this.vidaUtilDias,
    this.umbralBajo,
  });

  Map<String, dynamic> toJson() {
    return {
      'nombre': nombre,
      'unidad': unidad,
      'categoria': categoria.backendValue,
      'modoControl': modoControl.backendValue,
      if (vidaUtilDias != null) 'vidaUtilDias': vidaUtilDias,
      if (umbralBajo != null) 'umbralBajo': umbralBajo,
    };
  }
}

/// Cargar / ajustar stock de herramientas del conjunto
class HerramientaStockRequest {
  final int herramientaId;
  final num cantidad;
  final EstadoHerramientaStock estado;

  HerramientaStockRequest({
    required this.herramientaId,
    required this.cantidad,
    this.estado = EstadoHerramientaStock.OPERATIVA,
  });

  Map<String, dynamic> toJson() {
    return {
      'herramientaId': herramientaId,
      'cantidad': cantidad,
      'estado': estado.backendValue,
    };
  }
}

/// Solicitud de herramientas (admin → gerente)
class SolicitudHerramientaRequest {
  final String conjuntoId;
  final List<SolicitudHerramientaItemRequest> items;

  SolicitudHerramientaRequest({required this.conjuntoId, required this.items});

  Map<String, dynamic> toJson() {
    return {
      'conjuntoId': conjuntoId,
      'items': items.map((e) => e.toJson()).toList(),
    };
  }
}

class SolicitudHerramientaItemRequest {
  final int herramientaId;
  final num cantidad;

  SolicitudHerramientaItemRequest({
    required this.herramientaId,
    required this.cantidad,
  });

  Map<String, dynamic> toJson() {
    return {'herramientaId': herramientaId, 'cantidad': cantidad};
  }
}

// =========================
// RESPONSES (desde backend)
// =========================

/// Herramienta del catálogo (empresa)
class HerramientaResponse {
  final int id;
  final String nombre;
  final String unidad;
  final CategoriaHerramienta categoria;
  final ModoControlHerramienta modoControl;
  final int? vidaUtilDias;
  final int? umbralBajo;
  final num? stockEmpresa;

  HerramientaResponse({
    required this.id,
    required this.nombre,
    required this.unidad,
    required this.categoria,
    required this.modoControl,
    this.vidaUtilDias,
    this.umbralBajo,
    this.stockEmpresa,
  });

  factory HerramientaResponse.fromJson(Map<String, dynamic> json) {
    return HerramientaResponse(
      id: _asInt(json['id']),
      nombre: _asString(json['nombre'], fallback: "-"),
      unidad: _asString(json['unidad'], fallback: "-"),
      categoria: _parseCategoria(json['categoria']),
      modoControl: _parseModo(json['modoControl']),
      vidaUtilDias: json['vidaUtilDias'] == null
          ? null
          : _asInt(json['vidaUtilDias']),
      umbralBajo: json['umbralBajo'] == null
          ? null
          : _asInt(json['umbralBajo']),
      stockEmpresa: json['stockEmpresa'] == null
          ? null
          : _asNum(json['stockEmpresa']),
    );
  }
}

/// Stock de herramienta por conjunto (inventario).
/// ✅ Soporta:
/// - Formato anidado: { herramientaId, estado, cantidad, herramienta: { nombre, unidad, modoControl, umbralBajo } }
/// - Formato plano:   { herramientaId, estado, cantidad, nombre, unidad, modoControl, umbralBajo }
class HerramientaStockResponse {
  final int herramientaId;
  final String nombre;
  final String unidad;
  final CategoriaHerramienta categoria;
  final ModoControlHerramienta modoControl;
  final num cantidad;
  final EstadoHerramientaStock estado;
  final TipoTenenciaHerramienta tipoTenencia;
  final String? empresaIdFuente;
  final DateTime? fechaDevolucionEstimada;
  final int? umbralBajo;

  HerramientaStockResponse({
    required this.herramientaId,
    required this.nombre,
    required this.unidad,
    required this.categoria,
    required this.modoControl,
    required this.cantidad,
    required this.estado,
    required this.tipoTenencia,
    this.empresaIdFuente,
    this.fechaDevolucionEstimada,
    this.umbralBajo,
  });

  factory HerramientaStockResponse.fromJson(Map<String, dynamic> json) {
    final herramienta = (json['herramienta'] is Map)
        ? (json['herramienta'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};

    final nombre = _asString(
      json['nombre'] ?? herramienta['nombre'],
      fallback: "-",
    );
    final unidad = _asString(
      json['unidad'] ?? herramienta['unidad'],
      fallback: "-",
    );

    final modo = _parseModo(json['modoControl'] ?? herramienta['modoControl']);
    final estado = _parseEstadoStock(json['estado']);
    final tenenciaRaw = _asString(
      json['tipoTenencia'] ?? json['origen'],
      fallback: 'PROPIA',
    );
    final tenencia = TipoTenenciaHerramienta.values.firstWhere(
      (e) => e.name == tenenciaRaw,
      orElse: () => TipoTenenciaHerramienta.PROPIA,
    );

    final umbral = (json['umbralBajo'] ?? herramienta['umbralBajo']) == null
        ? null
        : _asInt(json['umbralBajo'] ?? herramienta['umbralBajo']);

    return HerramientaStockResponse(
      herramientaId: _asInt(json['herramientaId']),
      nombre: nombre,
      unidad: unidad,
      categoria: _parseCategoria(json['categoria'] ?? herramienta['categoria']),
      modoControl: modo,
      cantidad: _asNum(json['cantidad']),
      estado: estado,
      tipoTenencia: tenencia,
      empresaIdFuente: json['empresaIdFuente']?.toString(),
      fechaDevolucionEstimada: json['fechaDevolucionEstimada'] == null
          ? null
          : DateTime.tryParse(json['fechaDevolucionEstimada'].toString()),
      umbralBajo: umbral,
    );
  }
}

class HerramientaDisponibilidadResponse {
  final int herramientaId;
  final String nombre;
  final String unidad;
  final CategoriaHerramienta categoria;
  final ModoControlHerramienta modoControl;
  final num stockConjunto;
  final num stockEmpresa;
  final num reservadoConjunto;
  final num reservadoEmpresa;
  final num disponibleConjunto;
  final num disponibleEmpresa;
  final num totalDisponible;

  HerramientaDisponibilidadResponse({
    required this.herramientaId,
    required this.nombre,
    required this.unidad,
    required this.categoria,
    required this.modoControl,
    required this.stockConjunto,
    required this.stockEmpresa,
    required this.reservadoConjunto,
    required this.reservadoEmpresa,
    required this.disponibleConjunto,
    required this.disponibleEmpresa,
    required this.totalDisponible,
  });

  factory HerramientaDisponibilidadResponse.fromJson(Map<String, dynamic> json) {
    return HerramientaDisponibilidadResponse(
      herramientaId: _asInt(json['herramientaId']),
      nombre: _asString(json['nombre'], fallback: '-'),
      unidad: _asString(json['unidad'], fallback: '-'),
      categoria: _parseCategoria(json['categoria']),
      modoControl: _parseModo(json['modoControl']),
      stockConjunto: _asNum(json['stockConjunto']),
      stockEmpresa: _asNum(json['stockEmpresa']),
      reservadoConjunto: _asNum(json['reservadoConjunto']),
      reservadoEmpresa: _asNum(json['reservadoEmpresa']),
      disponibleConjunto: _asNum(json['disponibleConjunto']),
      disponibleEmpresa: _asNum(json['disponibleEmpresa']),
      totalDisponible: _asNum(json['totalDisponible']),
    );
  }
}

/// Solicitud de herramientas (listado / detalle)
class SolicitudHerramientaResponse {
  final int id;
  final String conjuntoId;
  final String estado;
  final DateTime fechaSolicitud;
  final DateTime? fechaAprobacion;
  final List<SolicitudHerramientaItemResponse> items;

  SolicitudHerramientaResponse({
    required this.id,
    required this.conjuntoId,
    required this.estado,
    required this.fechaSolicitud,
    this.fechaAprobacion,
    required this.items,
  });

  factory SolicitudHerramientaResponse.fromJson(Map<String, dynamic> json) {
    return SolicitudHerramientaResponse(
      id: _asInt(json['id']),
      conjuntoId: _asString(json['conjuntoId'], fallback: ""),
      estado: _asString(json['estado'], fallback: "PENDIENTE"),
      fechaSolicitud: DateTime.parse(_asString(json['fechaSolicitud'])),
      fechaAprobacion: json['fechaAprobacion'] != null
          ? DateTime.parse(_asString(json['fechaAprobacion']))
          : null,
      items: (json['items'] as List? ?? [])
          .whereType<Map>()
          .map(
            (e) => SolicitudHerramientaItemResponse.fromJson(
              e.cast<String, dynamic>(),
            ),
          )
          .toList(),
    );
  }
}

class SolicitudHerramientaItemResponse {
  final int herramientaId;
  final String nombre;
  final String unidad;
  final num cantidad;

  SolicitudHerramientaItemResponse({
    required this.herramientaId,
    required this.nombre,
    required this.unidad,
    required this.cantidad,
  });

  factory SolicitudHerramientaItemResponse.fromJson(Map<String, dynamic> json) {
    final herramienta = (json['herramienta'] is Map)
        ? (json['herramienta'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};

    return SolicitudHerramientaItemResponse(
      herramientaId: _asInt(json['herramientaId']),
      nombre: _asString(herramienta['nombre'], fallback: "-"),
      unidad: _asString(herramienta['unidad'], fallback: "-"),
      cantidad: _asNum(json['cantidad']),
    );
  }
}
// ignore_for_file: constant_identifier_names
