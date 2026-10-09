import 'dart:convert';

/// Cuándo (y, si hubo señal GPS, dónde) se tomó una foto con la cámara de la
/// app. El backend lo estampa como marca de agua abajo a la derecha antes de
/// subir la evidencia a Drive. Las fotos adjuntadas desde la galería no lo
/// traen: para esas solo se puede afirmar la hora de subida.
class CapturaEvidencia {
  final DateTime tomadaEn;
  final double? latitud;
  final double? longitud;

  const CapturaEvidencia({required this.tomadaEn, this.latitud, this.longitud});

  bool get tieneGps => latitud != null && longitud != null;

  CapturaEvidencia conGps(double latitud, double longitud) => CapturaEvidencia(
    tomadaEn: tomadaEn,
    latitud: latitud,
    longitud: longitud,
  );

  Map<String, dynamic> toJson() => {
    // En UTC: el backend la muestra en hora de Colombia.
    'tomadaEn': tomadaEn.toUtc().toIso8601String(),
    if (tieneGps) 'latitud': latitud,
    if (tieneGps) 'longitud': longitud,
  };

  static CapturaEvidencia? fromJson(Object? json) {
    if (json is! Map) return null;
    final tomadaEn = DateTime.tryParse(json['tomadaEn']?.toString() ?? '');
    if (tomadaEn == null) return null;
    final lat = json['latitud'];
    final lng = json['longitud'];
    return CapturaEvidencia(
      tomadaEn: tomadaEn,
      latitud: lat is num ? lat.toDouble() : null,
      longitud: lng is num ? lng.toDouble() : null,
    );
  }
}

/// Valor del campo multipart `evidenciasCaptura`: una entrada por archivo
/// enviado en `files`, en el mismo orden (null si no se tomó con la cámara de
/// la app). Devuelve null si ninguna trae datos, para no mandar el campo.
String? evidenciasCapturaJson(List<CapturaEvidencia?> capturas) {
  if (capturas.every((c) => c == null)) return null;
  return jsonEncode(capturas.map((c) => c?.toJson()).toList());
}

class EvidenciaAdjunto {
  final String nombre;
  final String? path;
  final List<int>? bytes;
  final CapturaEvidencia? captura;

  const EvidenciaAdjunto({
    required this.nombre,
    this.path,
    this.bytes,
    this.captura,
  });
}
