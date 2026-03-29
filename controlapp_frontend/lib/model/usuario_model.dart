import 'package:intl/intl.dart';

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
  final List<DisponibilidadOperarioPeriodo> disponibilidadPeriodos;

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
    this.disponibilidadPeriodos = const [],
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
      disponibilidadPeriodos:
          ((json['operario']?['disponibilidadPeriodos'] as List?) ??
                  (json['disponibilidadPeriodos'] as List?) ??
                  const [])
              .whereType<Map>()
              .map(
                (e) => DisponibilidadOperarioPeriodo.fromJson(
                  e.cast<String, dynamic>(),
                ),
              )
              .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': cedula, // 👈 así lo espera el DTO (id = cédula)
      'nombre': nombre,
      'correo': correo,
      'rol': rol,
      'telefono': telefono.toString(),
      'fechaNacimiento': DateFormat('yyyy-MM-dd').format(fechaNacimiento),
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
      'disponibilidadPeriodos': disponibilidadPeriodos
          .map((e) => e.toJson())
          .toList(),
      if (tipoFunciones != null && tipoFunciones!.isNotEmpty)
        'tipoFunciones': tipoFunciones,
    };
  }
}

class DisponibilidadOperarioPeriodo {
  final int? id;
  final DateTime fechaInicio;
  final DateTime? fechaFin;
  final bool trabajaDomingo;
  final String? diaDescanso;
  final String? observaciones;

  const DisponibilidadOperarioPeriodo({
    this.id,
    required this.fechaInicio,
    this.fechaFin,
    this.trabajaDomingo = false,
    this.diaDescanso,
    this.observaciones,
  });

  factory DisponibilidadOperarioPeriodo.fromJson(Map<String, dynamic> json) {
    return DisponibilidadOperarioPeriodo(
      id: json['id'] is num
          ? (json['id'] as num).toInt()
          : int.tryParse('${json['id']}'),
      fechaInicio: DateTime.parse(json['fechaInicio'].toString()),
      fechaFin: json['fechaFin'] == null
          ? null
          : DateTime.tryParse(json['fechaFin'].toString()),
      trabajaDomingo: json['trabajaDomingo'] == true,
      diaDescanso: json['diaDescanso']?.toString(),
      observaciones: json['observaciones']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'fechaInicio': fechaInicio.toIso8601String(),
      'fechaFin': fechaFin?.toIso8601String(),
      'trabajaDomingo': trabajaDomingo,
      'diaDescanso': diaDescanso,
      'observaciones': observaciones,
    };
  }
}
