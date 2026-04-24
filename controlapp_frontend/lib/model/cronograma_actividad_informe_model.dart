class CronogramaActividadInformeModel {
  final String actividad;
  final num horasMes;
  final num semana1;
  final num semana2;
  final num semana3;
  final num semana4;
  final num semana5;

  CronogramaActividadInformeModel({
    required this.actividad,
    required this.horasMes,
    required this.semana1,
    required this.semana2,
    required this.semana3,
    required this.semana4,
    required this.semana5,
  });

  factory CronogramaActividadInformeModel.fromJson(Map<String, dynamic> json) {
    num parseNum(String key) => num.tryParse(json[key]?.toString() ?? '') ?? 0;

    return CronogramaActividadInformeModel(
      actividad: (json['actividad'] ?? '').toString(),
      horasMes: parseNum('horasMes'),
      semana1: parseNum('semana1'),
      semana2: parseNum('semana2'),
      semana3: parseNum('semana3'),
      semana4: parseNum('semana4'),
      semana5: parseNum('semana5'),
    );
  }
}
