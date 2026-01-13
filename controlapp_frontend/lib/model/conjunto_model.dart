import 'usuario_model.dart';

class HorarioConjunto {
  final String dia;
  final String horaApertura;
  final String horaCierre;
  final String? descansoInicio;
  final String? descansoFin;

  HorarioConjunto({
    required this.dia,
    required this.horaApertura,
    required this.horaCierre,
    this.descansoInicio,
    this.descansoFin,
  });

  factory HorarioConjunto.fromJson(Map<String, dynamic> json) {
    return HorarioConjunto(
      dia: json['dia'] as String,
      horaApertura: json['horaApertura'] as String,
      horaCierre: json['horaCierre'] as String,
      descansoInicio: json['descansoInicio'] as String?,
      descansoFin: json['descansoFin'] as String?,
    );
  }
}

class Elemento {
  final int id;
  final String nombre;

  Elemento({required this.id, required this.nombre});

  factory Elemento.fromJson(Map<String, dynamic> json) {
    return Elemento(id: json['id'] as int, nombre: json['nombre'] as String);
  }
}

class UbicacionConElementos {
  final int id;
  final String nombre;
  final List<Elemento> elementos;

  UbicacionConElementos({
    required this.id,
    required this.nombre,
    required this.elementos,
  });

  factory UbicacionConElementos.fromJson(Map<String, dynamic> json) {
    final elemsJson = (json['elementos'] as List?) ?? [];
    return UbicacionConElementos(
      id: json['id'] as int,
      nombre: json['nombre'] as String,
      elementos: elemsJson
          .map((e) => Elemento.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class Conjunto {
  final String nit;
  final String nombre;
  final String direccion;
  final String correo;
  final bool activo;
  final double? valorMensual;
  final List<String> tipoServicio;
  final DateTime? fechaInicioContrato;
  final DateTime? fechaFinContrato;
  final List<String> consignasEspeciales;
  final List<String> valorAgregado;

  final String? administradorId;
  final String? administradorNombre;

  final List<Usuario> operarios;
  final List<HorarioConjunto> horarios;
  final List<UbicacionConElementos> ubicaciones;

  Conjunto({
    required this.nit,
    required this.nombre,
    required this.direccion,
    required this.correo,
    required this.activo,
    required this.tipoServicio,
    required this.consignasEspeciales,
    required this.valorAgregado,
    this.valorMensual,
    this.fechaInicioContrato,
    this.fechaFinContrato,
    this.administradorId,
    this.administradorNombre,
    this.operarios = const [],
    this.horarios = const [],
    this.ubicaciones = const [],
  });

  factory Conjunto.fromJson(Map<String, dynamic> json) {
    // admin viene como { id, usuario: {...} } si hiciste el include en Prisma
    String? adminId;
    String? adminNombre;

    if (json['administrador'] != null) {
      final admin = json['administrador'] as Map<String, dynamic>;
      adminId = admin['id'] as String?;
      final userJson = admin['usuario'] as Map<String, dynamic>?;
      if (userJson != null) {
        adminNombre = userJson['nombre'] as String?;
      }
    }

    final operariosJson = (json['operarios'] as List?) ?? [];
    final horariosJson = (json['horarios'] as List?) ?? [];
    final ubicacionesJson = (json['ubicaciones'] as List?) ?? [];

    return Conjunto(
      nit: json['nit'] as String,
      nombre: json['nombre'] as String,
      direccion: json['direccion'] as String,
      correo: json['correo'] as String,
      activo: json['activo'] as bool? ?? true,
      tipoServicio: (json['tipoServicio'] as List? ?? [])
          .map((e) => e.toString())
          .toList(),
      valorMensual: json['valorMensual'] != null
          ? double.tryParse(json['valorMensual'].toString())
          : null,
      fechaInicioContrato: json['fechaInicioContrato'] != null
          ? DateTime.parse(json['fechaInicioContrato'] as String)
          : null,
      fechaFinContrato: json['fechaFinContrato'] != null
          ? DateTime.parse(json['fechaFinContrato'] as String)
          : null,
      consignasEspeciales: (json['consignasEspeciales'] as List? ?? [])
          .map((e) => e.toString())
          .toList(),
      valorAgregado: (json['valorAgregado'] as List? ?? [])
          .map((e) => e.toString())
          .toList(),
      administradorId: adminId,
      administradorNombre: adminNombre,
      operarios: operariosJson
          .map((o) {
            final uJson =
                (o as Map<String, dynamic>)['usuario'] as Map<String, dynamic>?;
            return uJson != null ? Usuario.fromJson(uJson) : null;
          })
          .whereType<Usuario>()
          .toList(),
      horarios: horariosJson
          .map((h) => HorarioConjunto.fromJson(h as Map<String, dynamic>))
          .toList(),
      ubicaciones: ubicacionesJson
          .map((u) => UbicacionConElementos.fromJson(u as Map<String, dynamic>))
          .toList(),
    );
  }
}
