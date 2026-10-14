import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:flutter_application_1/model/evidencia_adjunto_model.dart';

/// Hora de toma (y GPS, si el archivo lo trae) del EXIF de una foto JPG
/// elegida de la galería. Se lee antes de reducir la foto, porque el
/// navegador descarta el EXIF al recomprimirla.
///
/// Las fotos de la cámara del celular casi siempre traen la hora; el GPS casi
/// nunca llega: Android e iPhone lo quitan al compartir la foto con una
/// página web. Las de WhatsApp no traen ninguno de los dos. Sin hora de toma
/// devuelve null.
CapturaEvidencia? capturaDesdeExif(Uint8List? bytes) {
  // Solo JPG (FF D8): es lo que guarda la cámara y lo único con EXIF aquí.
  if (bytes == null || bytes.length < 4) return null;
  if (bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
  try {
    final exif = img.decodeJpgExif(bytes);
    if (exif == null) return null;
    final tomadaEn = _fechaToma(exif.exifIfd);
    if (tomadaEn == null) return null;
    final gps = _gps(exif.gpsIfd);
    return CapturaEvidencia(
      tomadaEn: tomadaEn,
      latitud: gps?.latitud,
      longitud: gps?.longitud,
    );
  } catch (_) {
    return null;
  }
}

final _formatoFecha = RegExp(
  r'^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})',
);
final _formatoOffset = RegExp(r'^([+-])(\d{2}):(\d{2})$');

DateTime? _fechaToma(img.IfdDirectory exif) {
  // DateTimeOriginal, o DateTimeDigitized si la cámara no puso la primera.
  final texto = (exif[0x9003] ?? exif[0x9004])?.toString().trim() ?? '';
  final m = _formatoFecha.firstMatch(texto);
  if (m == null) return null;
  final p = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
  // Cámaras sin hora configurada guardan 0000:00:00 o fechas imposibles.
  if (p[0] < 2000 || p[1] < 1 || p[1] > 12 || p[2] < 1 || p[2] > 31) {
    return null;
  }
  if (p[3] > 23 || p[4] > 59 || p[5] > 59) return null;

  // OffsetTimeOriginal ("-05:00"): con él la hora es exacta; sin él se toma
  // como hora local del celular, que es donde se tomó la foto.
  final offset = _formatoOffset.firstMatch(
    exif[0x9011]?.toString().trim() ?? '',
  );
  if (offset == null) return DateTime(p[0], p[1], p[2], p[3], p[4], p[5]);
  final minutos =
      (int.parse(offset.group(2)!) * 60 + int.parse(offset.group(3)!)) *
      (offset.group(1) == '-' ? -1 : 1);
  return DateTime.utc(
    p[0],
    p[1],
    p[2],
    p[3],
    p[4],
    p[5],
  ).subtract(Duration(minutes: minutos));
}

({double latitud, double longitud})? _gps(img.IfdDirectory gps) {
  final lat = _grados(gps[0x0002]);
  final lng = _grados(gps[0x0004]);
  if (lat == null || lng == null) return null;
  final latitud = gps[0x0001]?.toString().trim().toUpperCase() == 'S'
      ? -lat
      : lat;
  final longitud = gps[0x0003]?.toString().trim().toUpperCase() == 'W'
      ? -lng
      : lng;
  if (latitud.abs() > 90 || longitud.abs() > 180) return null;
  // 0,0 es lo que dejan algunos celulares cuando no tenían señal.
  if (latitud == 0 && longitud == 0) return null;
  return (latitud: latitud, longitud: longitud);
}

/// Grados, minutos y segundos (tres racionales) a grados decimales.
double? _grados(img.IfdValue? valor) {
  if (valor == null || valor.length < 3) return null;
  final grados =
      valor.toDouble(0) + valor.toDouble(1) / 60 + valor.toDouble(2) / 3600;
  return grados.isFinite ? grados : null;
}
