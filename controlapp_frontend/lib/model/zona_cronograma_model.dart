class ZonaCronogramaModel {
  final int elementoZonaId;
  final String nombre;
  final int orden;
  final String colorHex;
  final bool configurado;
  final int? ubicacionId;
  final String? ubicacionNombre;

  const ZonaCronogramaModel({
    required this.elementoZonaId,
    required this.nombre,
    required this.orden,
    required this.colorHex,
    this.configurado = false,
    this.ubicacionId,
    this.ubicacionNombre,
  });

  factory ZonaCronogramaModel.fromJson(Map<String, dynamic> json) {
    return ZonaCronogramaModel(
      elementoZonaId:
          int.tryParse(
            (json['elementoZonaId'] ?? json['elementoId'])?.toString() ?? '',
          ) ??
          0,
      nombre: (json['nombre'] ?? 'Sin zona').toString(),
      orden: int.tryParse(json['orden']?.toString() ?? '') ?? 100,
      colorHex: (json['colorHex'] ?? '#2E7D32').toString().toUpperCase(),
      configurado: json['configurado'] == true,
      ubicacionId: int.tryParse(json['ubicacionId']?.toString() ?? ''),
      ubicacionNombre: json['ubicacionNombre']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'elementoZonaId': elementoZonaId,
    'nombre': nombre,
    'orden': orden,
    'colorHex': colorHex,
    'configurado': configurado,
    if (ubicacionId != null) 'ubicacionId': ubicacionId,
    if (ubicacionNombre != null) 'ubicacionNombre': ubicacionNombre,
  };

  ZonaCronogramaModel copyWith({int? orden, String? colorHex}) {
    return ZonaCronogramaModel(
      elementoZonaId: elementoZonaId,
      nombre: nombre,
      orden: orden ?? this.orden,
      colorHex: colorHex ?? this.colorHex,
      configurado: true,
      ubicacionId: ubicacionId,
      ubicacionNombre: ubicacionNombre,
    );
  }
}
