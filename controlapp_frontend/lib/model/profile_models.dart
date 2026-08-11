class ProfileConjunto {
  final String nit;
  final String nombre;

  const ProfileConjunto({required this.nit, required this.nombre});

  factory ProfileConjunto.fromJson(Map<String, dynamic> json) {
    return ProfileConjunto(
      nit: json['nit']?.toString() ?? '',
      nombre: json['nombre']?.toString() ?? '',
    );
  }
}

class ProfileUser {
  final String id;
  final String nombre;
  final String correo;
  final String rol;
  final bool activo;
  final bool requiereCambioContrasena;

  const ProfileUser({
    required this.id,
    required this.nombre,
    required this.correo,
    required this.rol,
    required this.activo,
    required this.requiereCambioContrasena,
  });

  factory ProfileUser.fromJson(Map<String, dynamic> json) {
    return ProfileUser(
      id: json['id']?.toString() ?? '',
      nombre: json['nombre']?.toString() ?? '',
      correo: json['correo']?.toString() ?? '',
      rol: json['rol']?.toString() ?? '',
      activo: json['activo'] == true,
      requiereCambioContrasena: json['requiereCambioContrasena'] == true,
    );
  }
}

class ResidentProfile {
  final String tipoUnidad;
  final String sector;
  final String unidad;
  final ProfileConjunto? conjunto;

  const ResidentProfile({
    required this.tipoUnidad,
    required this.sector,
    required this.unidad,
    required this.conjunto,
  });

  factory ResidentProfile.fromJson(Map<String, dynamic> json) {
    return ResidentProfile(
      tipoUnidad: json['tipoUnidad']?.toString() ?? '',
      sector: json['sector']?.toString() ?? '',
      unidad: json['unidad']?.toString() ?? '',
      conjunto: json['conjunto'] is Map<String, dynamic>
          ? ProfileConjunto.fromJson(json['conjunto'] as Map<String, dynamic>)
          : null,
    );
  }
}

class ProfileMetrics {
  final int totalPedidos;
  final int pedidosCompletados;
  final double totalCompras;
  final double comprasCompletadas;
  final int puntos;
  final int beneficiosActivos;

  const ProfileMetrics({
    required this.totalPedidos,
    required this.pedidosCompletados,
    required this.totalCompras,
    required this.comprasCompletadas,
    required this.puntos,
    required this.beneficiosActivos,
  });

  factory ProfileMetrics.fromJson(Map<String, dynamic> json) {
    return ProfileMetrics(
      totalPedidos: (json['totalPedidos'] as num?)?.toInt() ?? 0,
      pedidosCompletados: (json['pedidosCompletados'] as num?)?.toInt() ?? 0,
      totalCompras: (json['totalCompras'] as num?)?.toDouble() ?? 0,
      comprasCompletadas: (json['comprasCompletadas'] as num?)?.toDouble() ?? 0,
      puntos: (json['puntos'] as num?)?.toInt() ?? 0,
      beneficiosActivos: (json['beneficiosActivos'] as num?)?.toInt() ?? 0,
    );
  }
}

class ProfileSummary {
  final ProfileUser user;
  final ResidentProfile? residente;
  final List<ProfileConjunto> conjuntos;
  final ProfileMetrics metricas;

  const ProfileSummary({
    required this.user,
    required this.residente,
    required this.conjuntos,
    required this.metricas,
  });

  factory ProfileSummary.fromJson(Map<String, dynamic> json) {
    return ProfileSummary(
      user: ProfileUser.fromJson(json['user'] as Map<String, dynamic>),
      residente: json['residente'] is Map<String, dynamic>
          ? ResidentProfile.fromJson(json['residente'] as Map<String, dynamic>)
          : null,
      conjuntos: (json['conjuntos'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ProfileConjunto.fromJson)
          .toList(),
      metricas: ProfileMetrics.fromJson(
        json['metricas'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
    );
  }
}
