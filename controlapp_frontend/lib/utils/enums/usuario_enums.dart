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
  final List<String> patronesJornada;

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
    required this.patronesJornada,
  });

  factory UsuarioEnums.fromJson(Map<String, dynamic> json) {
    List<String> listOfStrings(dynamic v) {
      if (v == null) return [];
      if (v is List) return v.map((e) => e.toString()).toList();
      return [];
    }

    return UsuarioEnums(
      roles: listOfStrings(json['rol']),
      estadosCiviles: listOfStrings(json['estadoCivil']),
      eps: listOfStrings(json['eps']),
      fondosPensiones: listOfStrings(json['fondoPensiones']),
      jornadasLaborales: listOfStrings(json['jornadaLaboral']),
      tiposSangre: listOfStrings(json['tipoSangre']),
      tallasCamisa: listOfStrings(json['tallaCamisa']),
      tallasPantalon: listOfStrings(json['tallaPantalon']),
      tallasCalzado: listOfStrings(json['tallaCalzado']),
      tiposContrato: listOfStrings(json['tipoContrato']),
      tiposFuncion: listOfStrings(json['tipoFuncion']),
      patronesJornada: listOfStrings(json['patronesJornada']),
    );
  }
}
