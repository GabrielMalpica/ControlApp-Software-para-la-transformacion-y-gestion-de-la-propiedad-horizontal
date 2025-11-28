class UsuarioEnums {
  final List<String> roles;
  final List<String> estadosCiviles;
  final List<String> eps;
  final List<String> fondosPensiones;
  final List<String> jornadasLaborales;
  final List<String> tiposSangre;
  final List<String> tallasCamisa;
  final List<String> tallasPantalon;
  final List<String> tallasCalzado;
  final List<String> tiposContrato;
  final List<String> tiposFuncion;

  UsuarioEnums({
    required this.roles,
    required this.estadosCiviles,
    required this.eps,
    required this.fondosPensiones,
    required this.jornadasLaborales,
    required this.tiposSangre,
    required this.tallasCamisa,
    required this.tallasPantalon,
    required this.tallasCalzado,
    required this.tiposContrato,
    required this.tiposFuncion,
  });

  factory UsuarioEnums.fromJson(Map<String, dynamic> json) {
    List<String> list(dynamic v) =>
        (v as List<dynamic>).map((e) => e.toString()).toList();

    return UsuarioEnums(
      roles: list(json['rol']),
      estadosCiviles: list(json['estadoCivil']),
      eps: list(json['eps']),
      fondosPensiones: list(json['fondoPensiones']),
      jornadasLaborales: list(json['jornadaLaboral']),
      tiposSangre: list(json['tipoSangre']),
      tallasCamisa: list(json['tallaCamisa']),
      tallasPantalon: list(json['tallaPantalon']),
      tallasCalzado: list(json['tallaCalzado']),
      tiposContrato: list(json['tipoContrato']),
      tiposFuncion: list(json['tipoFuncion']),
    );
  }
}
