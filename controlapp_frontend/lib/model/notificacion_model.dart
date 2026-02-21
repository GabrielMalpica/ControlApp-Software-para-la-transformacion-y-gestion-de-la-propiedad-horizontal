class NotificacionModel {
  final int id;
  final String tipo;
  final String titulo;
  final String mensaje;
  final String? referenciaTipo;
  final int? referenciaId;
  final Map<String, dynamic>? data;
  final bool leida;
  final DateTime creadaEn;
  final DateTime? leidaEn;

  NotificacionModel({
    required this.id,
    required this.tipo,
    required this.titulo,
    required this.mensaje,
    required this.leida,
    required this.creadaEn,
    this.referenciaTipo,
    this.referenciaId,
    this.data,
    this.leidaEn,
  });

  factory NotificacionModel.fromJson(Map<String, dynamic> json) {
    final dataRaw = json['data'];
    Map<String, dynamic>? parsedData;
    if (dataRaw is Map<String, dynamic>) {
      parsedData = dataRaw;
    } else if (dataRaw is Map) {
      parsedData = dataRaw.cast<String, dynamic>();
    }

    return NotificacionModel(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      tipo: (json['tipo'] ?? '').toString(),
      titulo: (json['titulo'] ?? '').toString(),
      mensaje: (json['mensaje'] ?? '').toString(),
      referenciaTipo: json['referenciaTipo']?.toString(),
      referenciaId: json['referenciaId'] != null
          ? int.tryParse(json['referenciaId'].toString())
          : null,
      data: parsedData,
      leida: json['leida'] == true,
      creadaEn:
          DateTime.tryParse(json['creadaEn']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      leidaEn: json['leidaEn'] != null
          ? DateTime.tryParse(json['leidaEn'].toString())?.toLocal()
          : null,
    );
  }
}
