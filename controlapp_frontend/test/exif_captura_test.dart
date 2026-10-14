import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:flutter_application_1/service/evidencia_camara_service.dart';
import 'package:flutter_application_1/utils/pickers/exif_captura.dart';

/// Tres racionales (grados, minutos, segundos) como los guarda la cámara.
img.IfdValue _gms(List<(int, int)> partes) {
  final datos = ByteData(partes.length * 8);
  for (var i = 0; i < partes.length; i++) {
    datos.setUint32(i * 8, partes[i].$1);
    datos.setUint32(i * 8 + 4, partes[i].$2);
  }
  return img.IfdValueRational.data(
    img.InputBuffer(datos.buffer.asUint8List(), bigEndian: true),
    partes.length,
  );
}

Uint8List _jpg({String? tomada, String? offset, bool conGps = false}) {
  final foto = img.Image(width: 16, height: 16);
  if (tomada != null) foto.exif.exifIfd[0x9003] = img.IfdValueAscii(tomada);
  if (offset != null) foto.exif.exifIfd[0x9011] = img.IfdValueAscii(offset);
  if (conGps) {
    final gps = foto.exif.gpsIfd;
    gps[0x0001] = img.IfdValueAscii('N');
    gps[0x0002] = _gms([(4, 1), (8, 1), (3125, 100)]); // 4° 8' 31,25"
    gps[0x0003] = img.IfdValueAscii('W');
    gps[0x0004] = _gms([(73, 1), (37, 1), (3600, 100)]); // 73° 37' 36"
  }
  return img.encodeJpg(foto);
}

void main() {
  group('capturaDesdeExif', () {
    test('lee la hora de toma como hora local del celular', () {
      final c = capturaDesdeExif(_jpg(tomada: '2026:10:13 18:30:17'))!;
      expect(c.tomadaEn, DateTime(2026, 10, 13, 18, 30, 17));
      expect(c.tieneGps, isFalse);
    });

    test('con OffsetTimeOriginal la hora es exacta', () {
      final c = capturaDesdeExif(
        _jpg(tomada: '2026:10:13 18:30:17', offset: '-05:00'),
      )!;
      expect(c.tomadaEn, DateTime.utc(2026, 10, 13, 23, 30, 17));
    });

    test('convierte el GPS de grados/minutos/segundos con su hemisferio', () {
      final c = capturaDesdeExif(
        _jpg(tomada: '2026:10:13 18:30:17', conGps: true),
      )!;
      expect(c.latitud, closeTo(4.142014, 0.000001));
      expect(c.longitud, closeTo(-73.626667, 0.000001));
    });

    test('sin hora de toma, con hora vacía o sin EXIF devuelve null', () {
      expect(capturaDesdeExif(_jpg()), isNull);
      expect(capturaDesdeExif(_jpg(tomada: '0000:00:00 00:00:00')), isNull);
      expect(
        capturaDesdeExif(img.encodePng(img.Image(width: 4, height: 4))),
        isNull,
      );
      expect(capturaDesdeExif(Uint8List.fromList([1, 2, 3])), isNull);
      expect(capturaDesdeExif(null), isNull);
    });
  });

  test('una foto de galería es "recién tomada" hasta 30 minutos', () {
    final ahora = DateTime(2026, 10, 13, 19);
    bool reciente(Duration hace) =>
        EvidenciaCamara.esRecienTomada(ahora.subtract(hace), ahora);

    expect(reciente(const Duration(minutes: 5)), isTrue);
    expect(reciente(const Duration(minutes: 30)), isTrue);
    expect(reciente(const Duration(minutes: 31)), isFalse);
    expect(reciente(const Duration(hours: 5)), isFalse);
    // Reloj del celular adelantado más de un minuto: no se confía.
    expect(reciente(const Duration(minutes: -5)), isFalse);
  });
}
