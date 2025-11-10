class Usuario {
  final int id;
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

  Usuario({
    required this.id,
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
  });

  factory Usuario.fromJson(Map<String, dynamic> json) {
    return Usuario(
      id: json['id'],
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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
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
    };
  }
}
