class ResidenteCreado {
  final String id;
  final String nombre;
  final String correo;
  final String conjuntoNombre;
  final String credencialUsuario;
  final String credencialTemporal;

  const ResidenteCreado({
    required this.id,
    required this.nombre,
    required this.correo,
    required this.conjuntoNombre,
    required this.credencialUsuario,
    required this.credencialTemporal,
  });

  factory ResidenteCreado.fromJson(Map<String, dynamic> json) {
    final usuario = json['usuario'] as Map<String, dynamic>? ?? const {};
    final conjunto = json['conjunto'] as Map<String, dynamic>? ?? const {};
    final cred = json['credenciales'] as Map<String, dynamic>? ?? const {};
    return ResidenteCreado(
      id: usuario['id']?.toString() ?? '',
      nombre: usuario['nombre']?.toString() ?? '',
      correo: usuario['correo']?.toString() ?? '',
      conjuntoNombre: conjunto['nombre']?.toString() ?? '',
      credencialUsuario: cred['usuario']?.toString() ?? '',
      credencialTemporal: cred['contrasenaTemporal']?.toString() ?? '',
    );
  }
}

class ResidenteAdminItem {
  final String id;
  final String nombre;
  final String correo;
  final bool activo;
  final bool requiereCambioContrasena;
  final String conjuntoNit;
  final String conjuntoNombre;
  final String tipoUnidad;
  final String sector;
  final String unidad;
  final String telefono;

  const ResidenteAdminItem({
    required this.id,
    required this.nombre,
    required this.correo,
    required this.activo,
    required this.requiereCambioContrasena,
    required this.conjuntoNit,
    required this.conjuntoNombre,
    required this.tipoUnidad,
    required this.sector,
    required this.unidad,
    required this.telefono,
  });

  String get ubicacion => sector.isEmpty ? unidad : '$sector - $unidad';

  factory ResidenteAdminItem.fromJson(Map<String, dynamic> json) {
    final usuario = json['usuario'] as Map<String, dynamic>? ?? const {};
    final conjunto = json['conjunto'] as Map<String, dynamic>? ?? const {};
    return ResidenteAdminItem(
      id: usuario['id']?.toString() ?? json['id']?.toString() ?? '',
      nombre: usuario['nombre']?.toString() ?? '',
      correo: usuario['correo']?.toString() ?? '',
      activo: usuario['activo'] == true,
      requiereCambioContrasena: usuario['requiereCambioContrasena'] == true,
      conjuntoNit: conjunto['nit']?.toString() ?? '',
      conjuntoNombre: conjunto['nombre']?.toString() ?? '',
      tipoUnidad: json['tipoUnidad']?.toString() ?? '',
      sector: json['sector']?.toString() ?? '',
      unidad: json['unidad']?.toString() ?? '',
      telefono: json['telefonoContacto']?.toString() ?? '',
    );
  }
}

class CargaResidentesResumen {
  final String archivo;
  final int totalFilas;
  final int creados;
  final int fallidos;

  const CargaResidentesResumen({
    required this.archivo,
    required this.totalFilas,
    required this.creados,
    required this.fallidos,
  });

  factory CargaResidentesResumen.fromJson(Map<String, dynamic> json) {
    return CargaResidentesResumen(
      archivo: json['archivo']?.toString() ?? '',
      totalFilas: (json['totalFilas'] as num?)?.toInt() ?? 0,
      creados: (json['creados'] as num?)?.toInt() ?? 0,
      fallidos: (json['fallidos'] as num?)?.toInt() ?? 0,
    );
  }
}

class CargaResidenteError {
  final int fila;
  final String cedula;
  final String nombre;
  final String correo;
  final String motivo;

  const CargaResidenteError({
    required this.fila,
    required this.cedula,
    required this.nombre,
    required this.correo,
    required this.motivo,
  });

  factory CargaResidenteError.fromJson(Map<String, dynamic> json) {
    return CargaResidenteError(
      fila: (json['fila'] as num?)?.toInt() ?? 0,
      cedula: json['cedula']?.toString() ?? '',
      nombre: json['nombre']?.toString() ?? '',
      correo: json['correo']?.toString() ?? '',
      motivo: json['motivo']?.toString() ?? '',
    );
  }
}

class CargaResidentesResult {
  final String conjuntoNombre;
  final String conjuntoNit;
  final CargaResidentesResumen resumen;
  final List<CargaResidenteError> errores;

  const CargaResidentesResult({
    required this.conjuntoNombre,
    required this.conjuntoNit,
    required this.resumen,
    required this.errores,
  });

  factory CargaResidentesResult.fromJson(Map<String, dynamic> json) {
    final conjunto = json['conjunto'] as Map<String, dynamic>? ?? const {};
    return CargaResidentesResult(
      conjuntoNombre: conjunto['nombre']?.toString() ?? '',
      conjuntoNit: conjunto['nit']?.toString() ?? '',
      resumen: CargaResidentesResumen.fromJson(
        json['resumen'] as Map<String, dynamic>? ?? const {},
      ),
      errores: (json['errores'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(CargaResidenteError.fromJson)
          .toList(),
    );
  }
}
