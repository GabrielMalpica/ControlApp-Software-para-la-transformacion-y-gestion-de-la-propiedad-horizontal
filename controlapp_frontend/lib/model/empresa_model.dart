class EmpresaModel {
  final int id;
  final String nombre;
  final String nit;
  final int limiteHorasSemana;

  EmpresaModel({
    required this.id,
    required this.nombre,
    required this.nit,
    required this.limiteHorasSemana,
  });

  factory EmpresaModel.fromJson(Map<String, dynamic> json) {
    return EmpresaModel(
      id: json['id'],
      nombre: json['nombre'],
      nit: json['nit'],
      limiteHorasSemana: json['limiteHorasSemana'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'nit': nit,
      'limiteHorasSemana': limiteHorasSemana,
    };
  }
}
