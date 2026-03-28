class CumpleaneroModel {
  final String id;
  final String nombre;
  final String correo;
  final String rol;
  final DateTime fechaNacimiento;
  final int dia;
  final int mes;
  final bool esHoy;

  CumpleaneroModel({
    required this.id,
    required this.nombre,
    required this.correo,
    required this.rol,
    required this.fechaNacimiento,
    required this.dia,
    required this.mes,
    required this.esHoy,
  });

  factory CumpleaneroModel.fromJson(Map<String, dynamic> json) {
    return CumpleaneroModel(
      id: (json['id'] ?? '').toString(),
      nombre: (json['nombre'] ?? '').toString(),
      correo: (json['correo'] ?? '').toString(),
      rol: (json['rol'] ?? '').toString(),
      fechaNacimiento: DateTime.parse(json['fechaNacimiento'].toString()),
      dia: (json['dia'] as num).toInt(),
      mes: (json['mes'] as num).toInt(),
      esHoy: json['esHoy'] == true,
    );
  }
}

class CumpleanosHoyModel {
  final bool esCumpleanosHoy;
  final String nombre;
  final String? mensaje;
  final DateTime? fechaNacimiento;

  CumpleanosHoyModel({
    required this.esCumpleanosHoy,
    required this.nombre,
    this.mensaje,
    this.fechaNacimiento,
  });

  factory CumpleanosHoyModel.fromJson(Map<String, dynamic> json) {
    return CumpleanosHoyModel(
      esCumpleanosHoy: json['esCumpleanosHoy'] == true,
      nombre: (json['nombre'] ?? '').toString(),
      mensaje: json['mensaje']?.toString(),
      fechaNacimiento: json['fechaNacimiento'] == null
          ? null
          : DateTime.tryParse(json['fechaNacimiento'].toString()),
    );
  }
}
