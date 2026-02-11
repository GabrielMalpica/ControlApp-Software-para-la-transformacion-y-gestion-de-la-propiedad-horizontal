class Usuario {
  final String cedula;
  final String nombre;
  final String correo;
  final String rol;
  final BigInt telefono;
  final DateTime fechaNacimiento;
  final String? direccion;
  final String? estadoCivil;
  final int? numeroHijos;
  final bool? padresVivos;
  final String? tipoSangre;
  final String? eps;
  final String? fondoPensiones;
  final String? tallaCamisa;
  final String? tallaPantalon;
  final String? tallaCalzado;
  final String? tipoContrato;
  final String? jornadaLaboral;
  final List<String>? tipoFunciones;
  final bool activo;
  final String? patronJornada;

  Usuario({
    required this.cedula,
    required this.nombre,
    required this.correo,
    required this.rol,
    required this.telefono,
    required this.fechaNacimiento,
    this.direccion,
    this.estadoCivil,
    this.numeroHijos,
    this.padresVivos,
    this.tipoSangre,
    this.eps,
    this.fondoPensiones,
    this.tallaCamisa,
    this.tallaPantalon,
    this.tallaCalzado,
    this.tipoContrato,
    this.jornadaLaboral,
    this.tipoFunciones,
    this.activo = true,
    this.patronJornada,
  });

  factory Usuario.fromJson(Map<String, dynamic> json) {
    return Usuario(
      // el backend devuelve `id`, que es la cédula
      cedula: json['id']?.toString() ?? json['cedula']?.toString() ?? '',
      nombre: json['nombre'],
      correo: json['correo'],
      rol: json['rol'],
      telefono: BigInt.parse(json['telefono'].toString()),
      fechaNacimiento: DateTime.parse(json['fechaNacimiento']),
      direccion: json['direccion'],
      estadoCivil: json['estadoCivil'],
      numeroHijos: json['numeroHijos'],
      padresVivos: json['padresVivos'],
      tipoSangre: json['tipoSangre'],
      eps: json['eps'],
      fondoPensiones: json['fondoPensiones'],
      tallaCamisa: json['tallaCamisa'],
      tallaPantalon: json['tallaPantalon'],
      tallaCalzado: json['tallaCalzado'],
      tipoContrato: json['tipoContrato'],
      jornadaLaboral: json['jornadaLaboral'],
      tipoFunciones: (json['tipoFunciones'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      activo: json['activo'] ?? true,
      patronJornada: json['patronJornada'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': cedula, // 👈 así lo espera el DTO (id = cédula)
      'nombre': nombre,
      'correo': correo,
      'rol': rol,
      'telefono': telefono.toString(),
      'fechaNacimiento': fechaNacimiento.toIso8601String(),
      'direccion': direccion,
      'estadoCivil': estadoCivil,
      'numeroHijos': numeroHijos,
      'padresVivos': padresVivos,
      'tipoSangre': tipoSangre,
      'eps': eps,
      'fondoPensiones': fondoPensiones,
      'tallaCamisa': tallaCamisa,
      'tallaPantalon': tallaPantalon,
      'tallaCalzado': tallaCalzado,
      'tipoContrato': tipoContrato,
      'jornadaLaboral': jornadaLaboral,
      'activo': activo,
      'patronJornada': patronJornada,
      if (tipoFunciones != null && tipoFunciones!.isNotEmpty)
        'tipoFunciones': tipoFunciones,
    };
  }
}
