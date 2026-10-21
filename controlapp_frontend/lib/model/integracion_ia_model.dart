/// Modelos del panel "Integraciones IA" (MCP, solo gerentes).
library;

DateTime? _fecha(dynamic valor) =>
    valor == null ? null : DateTime.tryParse(valor.toString())?.toLocal();

class PermisoIa {
  final String scope;
  final String titulo;
  final String descripcion;
  final String nivel;

  const PermisoIa({
    required this.scope,
    required this.titulo,
    required this.descripcion,
    required this.nivel,
  });

  bool get modificaDatos => nivel != 'lectura';

  factory PermisoIa.fromJson(Map<String, dynamic> json) => PermisoIa(
    scope: json['scope']?.toString() ?? '',
    titulo: json['titulo']?.toString() ?? '',
    descripcion: json['descripcion']?.toString() ?? '',
    nivel: json['nivel']?.toString() ?? 'lectura',
  );
}

class ConfiguracionIntegracionesIa {
  final String? urlServidor;
  final bool habilitadoParaMi;
  final List<PermisoIa> permisos;

  const ConfiguracionIntegracionesIa({
    required this.urlServidor,
    required this.habilitadoParaMi,
    required this.permisos,
  });

  String tituloPermiso(String scope) => permisos
      .firstWhere(
        (p) => p.scope == scope,
        orElse: () => PermisoIa(
          scope: scope,
          titulo: scope,
          descripcion: '',
          nivel: 'lectura',
        ),
      )
      .titulo;

  factory ConfiguracionIntegracionesIa.fromJson(Map<String, dynamic> json) =>
      ConfiguracionIntegracionesIa(
        urlServidor: (json['urlServidor'] as String?)?.trim().isEmpty ?? true
            ? null
            : json['urlServidor'] as String,
        habilitadoParaMi: json['habilitadoParaMi'] == true,
        permisos: (json['permisos'] as List<dynamic>? ?? const [])
            .map((p) => PermisoIa.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}

class ConexionIa {
  final String id;
  final bool propia;
  final String gerente;
  final String cliente;
  final String clienteHost;
  final List<String> permisos;
  final String estado;
  final DateTime? autorizadaEn;
  final DateTime? ultimoUsoEn;
  final DateTime? revocadaEn;
  final String? motivoRevocacion;

  const ConexionIa({
    required this.id,
    required this.propia,
    required this.gerente,
    required this.cliente,
    required this.clienteHost,
    required this.permisos,
    required this.estado,
    this.autorizadaEn,
    this.ultimoUsoEn,
    this.revocadaEn,
    this.motivoRevocacion,
  });

  bool get activa => estado == 'ACTIVA';
  bool get suspendida => estado == 'SUSPENDIDA';

  String get estadoLegible => switch (estado) {
    'ACTIVA' => 'Activa',
    'SUSPENDIDA' => 'Suspendida por seguridad',
    'REVOCADA' => 'Revocada',
    _ => estado,
  };

  factory ConexionIa.fromJson(Map<String, dynamic> json) => ConexionIa(
    id: json['id']?.toString() ?? '',
    propia: json['propia'] == true,
    gerente: json['gerente']?.toString() ?? '',
    cliente: json['cliente']?.toString() ?? '',
    clienteHost: json['clienteHost']?.toString() ?? '',
    permisos: (json['permisos'] as List<dynamic>? ?? const [])
        .map((p) => p.toString())
        .toList(),
    estado: json['estado']?.toString() ?? '',
    autorizadaEn: _fecha(json['autorizadaEn']),
    ultimoUsoEn: _fecha(json['ultimoUsoEn']),
    revocadaEn: _fecha(json['revocadaEn']),
    motivoRevocacion: json['motivoRevocacion']?.toString(),
  );
}

class ActividadIa {
  final String id;
  final String herramienta;
  final String nivelRiesgo;
  final String resultado;
  final String? codigo;
  final String? mensaje;
  final DateTime? creadoEn;

  const ActividadIa({
    required this.id,
    required this.herramienta,
    required this.nivelRiesgo,
    required this.resultado,
    this.codigo,
    this.mensaje,
    this.creadoEn,
  });

  bool get fallo => !const {'OK', 'PREVIEW', 'CONFIRMADO'}.contains(resultado);

  /// "previsualizar_traslado_operario" → "Previsualizar traslado operario".
  String get herramientaLegible {
    final texto = herramienta.replaceAll('_', ' ');
    return texto.isEmpty ? texto : texto[0].toUpperCase() + texto.substring(1);
  }

  factory ActividadIa.fromJson(Map<String, dynamic> json) => ActividadIa(
    id: json['id']?.toString() ?? '',
    herramienta: json['herramienta']?.toString() ?? '',
    nivelRiesgo: json['nivelRiesgo']?.toString() ?? '',
    resultado: json['resultado']?.toString() ?? '',
    codigo: json['codigo']?.toString(),
    mensaje: json['mensaje']?.toString(),
    creadoEn: _fecha(json['creadoEn']),
  );
}

class AprobacionIa {
  final String id;
  final String operacion;
  final String cliente;
  final String resumen;
  final DateTime? creadaEn;
  final DateTime? expiraEn;

  const AprobacionIa({
    required this.id,
    required this.operacion,
    required this.cliente,
    required this.resumen,
    this.creadaEn,
    this.expiraEn,
  });

  factory AprobacionIa.fromJson(Map<String, dynamic> json) => AprobacionIa(
    id: json['id']?.toString() ?? '',
    operacion: json['operacion']?.toString() ?? '',
    cliente: json['cliente']?.toString() ?? '',
    resumen: json['resumen']?.toString() ?? '',
    creadaEn: _fecha(json['creadaEn']),
    expiraEn: _fecha(json['expiraEn']),
  );
}
