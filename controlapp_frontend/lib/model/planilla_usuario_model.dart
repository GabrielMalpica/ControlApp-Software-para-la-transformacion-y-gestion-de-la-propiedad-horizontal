/// Una fila de la planilla de personal (`GET /gerente/usuarios/planilla`):
/// todos los datos de una persona para la vista de tabla de "Gestión de
/// usuarios". Las fechas llegan como día puro (`yyyy-MM-dd`).
class PlanillaUsuario {
  final String cedula;
  final String nombre;
  final String correo;
  final String rol;
  final bool activo;
  final String telefono;
  final DateTime? fechaNacimiento;
  final String? direccion;
  final String? estadoCivil;
  final int? numeroHijos;
  final bool? padresVivos;
  final String? contactoEmergenciaNombre;
  final String? contactoEmergenciaParentesco;
  final String? contactoEmergenciaTelefono;
  final String? tipoSangre;
  final String? eps;
  final String? fondoPensiones;
  final String? arl;
  final String? cajaCompensacion;
  final String? tallaCamisa;
  final String? tallaPantalon;
  final String? tallaCalzado;
  final String? tipoContrato;
  final String? jornadaLaboral;
  final String? patronJornada;
  final List<String> funciones;
  final List<ConjuntoPlanilla> conjuntos;
  final List<PlazaPlanilla> plazas;
  final DateTime? fechaIngreso;
  final DateTime? fechaSalida;
  final DateTime? fechaUltimasVacaciones;
  final bool? cursoAlturas;
  final bool? cursoSalvamentoAcuatico;
  final bool? examenIngreso;
  final String? observaciones;
  final String? diaDescanso;
  final bool? trabajaDomingo;

  /// Rangos marcados como vacaciones en Asistencia (último año y lo
  /// programado), ordenados.
  final List<BloqueVacaciones> vacaciones;

  const PlanillaUsuario({
    required this.cedula,
    required this.nombre,
    this.correo = '',
    required this.rol,
    this.activo = true,
    this.telefono = '',
    this.fechaNacimiento,
    this.direccion,
    this.estadoCivil,
    this.numeroHijos,
    this.padresVivos,
    this.contactoEmergenciaNombre,
    this.contactoEmergenciaParentesco,
    this.contactoEmergenciaTelefono,
    this.tipoSangre,
    this.eps,
    this.fondoPensiones,
    this.arl,
    this.cajaCompensacion,
    this.tallaCamisa,
    this.tallaPantalon,
    this.tallaCalzado,
    this.tipoContrato,
    this.jornadaLaboral,
    this.patronJornada,
    this.funciones = const [],
    this.conjuntos = const [],
    this.plazas = const [],
    this.fechaIngreso,
    this.fechaSalida,
    this.fechaUltimasVacaciones,
    this.cursoAlturas,
    this.cursoSalvamentoAcuatico,
    this.examenIngreso,
    this.observaciones,
    this.diaDescanso,
    this.trabajaDomingo,
    this.vacaciones = const [],
  });

  /// Conjuntos de la persona: los vinculados y los de sus plazas, sin repetir.
  List<ConjuntoPlanilla> get conjuntosTodos {
    final porNit = <String, ConjuntoPlanilla>{
      for (final c in conjuntos) c.nit: c,
    };
    for (final p in plazas) {
      porNit.putIfAbsent(
        p.conjuntoNit,
        () => ConjuntoPlanilla(nit: p.conjuntoNit, nombre: p.conjuntoNombre),
      );
    }
    return porNit.values.toList();
  }

  factory PlanillaUsuario.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> mapas(dynamic v) => (v is List ? v : const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();

    return PlanillaUsuario(
      cedula: json['cedula']?.toString() ?? '',
      nombre: json['nombre']?.toString() ?? '',
      correo: json['correo']?.toString() ?? '',
      rol: json['rol']?.toString() ?? '',
      activo: json['activo'] != false,
      telefono: json['telefono']?.toString() ?? '',
      fechaNacimiento: diaDesdeJson(json['fechaNacimiento']),
      direccion: _texto(json['direccion']),
      estadoCivil: _texto(json['estadoCivil']),
      numeroHijos: json['numeroHijos'] is num
          ? (json['numeroHijos'] as num).toInt()
          : null,
      padresVivos: json['padresVivos'] is bool
          ? json['padresVivos'] as bool
          : null,
      contactoEmergenciaNombre: _texto(json['contactoEmergenciaNombre']),
      contactoEmergenciaParentesco: _texto(
        json['contactoEmergenciaParentesco'],
      ),
      contactoEmergenciaTelefono: _texto(json['contactoEmergenciaTelefono']),
      tipoSangre: _texto(json['tipoSangre']),
      eps: _texto(json['eps']),
      fondoPensiones: _texto(json['fondoPensiones']),
      arl: _texto(json['arl']),
      cajaCompensacion: _texto(json['cajaCompensacion']),
      tallaCamisa: _texto(json['tallaCamisa']),
      tallaPantalon: _texto(json['tallaPantalon']),
      tallaCalzado: _texto(json['tallaCalzado']),
      tipoContrato: _texto(json['tipoContrato']),
      jornadaLaboral: _texto(json['jornadaLaboral']),
      patronJornada: _texto(json['patronJornada']),
      funciones: (json['funciones'] is List ? json['funciones'] as List : [])
          .map((e) => e.toString())
          .toList(),
      conjuntos: mapas(
        json['conjuntos'],
      ).map(ConjuntoPlanilla.fromJson).toList(),
      plazas: mapas(json['plazas']).map(PlazaPlanilla.fromJson).toList(),
      fechaIngreso: diaDesdeJson(json['fechaIngreso']),
      fechaSalida: diaDesdeJson(json['fechaSalida']),
      fechaUltimasVacaciones: diaDesdeJson(json['fechaUltimasVacaciones']),
      cursoAlturas: json['cursoAlturas'] is bool
          ? json['cursoAlturas'] as bool
          : null,
      cursoSalvamentoAcuatico: json['cursoSalvamentoAcuatico'] is bool
          ? json['cursoSalvamentoAcuatico'] as bool
          : null,
      examenIngreso: json['examenIngreso'] is bool
          ? json['examenIngreso'] as bool
          : null,
      observaciones: _texto(json['observaciones']),
      diaDescanso: _texto(json['diaDescanso']),
      trabajaDomingo: json['trabajaDomingo'] is bool
          ? json['trabajaDomingo'] as bool
          : null,
      vacaciones:
          mapas(json['vacaciones'])
              .map(BloqueVacaciones.tryParse)
              .whereType<BloqueVacaciones>()
              .toList()
            ..sort((a, b) => a.desde.compareTo(b.desde)),
    );
  }
}

class ConjuntoPlanilla {
  final String nit;
  final String nombre;

  const ConjuntoPlanilla({required this.nit, required this.nombre});

  factory ConjuntoPlanilla.fromJson(Map<String, dynamic> json) =>
      ConjuntoPlanilla(
        nit: json['nit']?.toString() ?? '',
        nombre: json['nombre']?.toString() ?? '',
      );
}

class PlazaPlanilla {
  final String etiqueta;
  final String conjuntoNit;
  final String conjuntoNombre;
  final String? perfil;

  const PlazaPlanilla({
    required this.etiqueta,
    required this.conjuntoNit,
    required this.conjuntoNombre,
    this.perfil,
  });

  factory PlazaPlanilla.fromJson(Map<String, dynamic> json) => PlazaPlanilla(
    etiqueta: json['etiqueta']?.toString() ?? '',
    conjuntoNit: json['conjuntoNit']?.toString() ?? '',
    conjuntoNombre: json['conjuntoNombre']?.toString() ?? '',
    perfil: _texto(json['perfil']),
  );
}

/// Días seguidos marcados como vacaciones en Asistencia (ambos incluidos).
class BloqueVacaciones {
  final DateTime desde;
  final DateTime hasta;

  const BloqueVacaciones({required this.desde, required this.hasta});

  static BloqueVacaciones? tryParse(Map<String, dynamic> json) {
    final desde = diaDesdeJson(json['desde']);
    final hasta = diaDesdeJson(json['hasta']);
    if (desde == null || hasta == null) return null;
    return BloqueVacaciones(desde: desde, hasta: hasta);
  }
}

/// `yyyy-MM-dd` (o un ISO completo) como día calendario, sin corrimiento
/// por huso horario: se toman el año, mes y día tal como vienen.
DateTime? diaDesdeJson(dynamic valor) {
  final texto = valor?.toString().trim() ?? '';
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(texto);
  if (m == null) return null;
  return DateTime(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
  );
}

String? _texto(dynamic valor) {
  final texto = valor?.toString().trim() ?? '';
  return texto.isEmpty ? null : texto;
}
