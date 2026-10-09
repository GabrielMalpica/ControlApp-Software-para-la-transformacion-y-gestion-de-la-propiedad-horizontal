// Corre en un navegador real (usa su decodificador y canvas):
//   flutter test --platform chrome test/optimizar_imagen_web_test.dart
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:flutter_application_1/model/evidencia_adjunto_model.dart';
import 'package:flutter_application_1/utils/pickers/optimizar_imagen_bridge.dart';
import 'package:flutter_application_1/utils/pickers/selected_upload_file.dart';

/// Foto "de cámara" con ruido (para que pese como una real).
Uint8List fotoDeCamara(int ancho, int alto, {int? orientacion}) {
  final imagen = img.Image(width: ancho, height: alto);
  var semilla = 7;
  for (final p in imagen) {
    semilla = (semilla * 1103515245 + 12345) & 0x7fffffff;
    final v = semilla % 256;
    // Mitad izquierda roja, derecha azul: sirve para ver la orientación.
    p
      ..r = p.x < ancho / 2 ? 200 + v % 50 : v % 50
      ..g = v % 60
      ..b = p.x < ancho / 2 ? v % 50 : 200 + v % 50;
  }
  if (orientacion != null) imagen.exif.imageIfd.orientation = orientacion;
  return img.encodeJpg(imagen, quality: 92);
}

void main() {
  final captura = CapturaEvidencia(
    tomadaEn: DateTime.utc(2026, 10, 8, 20),
  ).conGps(4.14, -73.62);

  test('reduce una foto grande a 1920 px y conserva la captura', () async {
    final original = fotoDeCamara(2100, 1400);
    final salida = await OptimizadorImagen.optimizar(
      SelectedUploadFile(
        name: 'IMG_1234.jpeg',
        mimeType: 'image/jpeg',
        bytes: original,
        captura: captura,
      ),
    );

    final decodificada = img.decodeJpg(salida.bytes!)!;
    expect([decodificada.width, decodificada.height], [1920, 1280]);
    expect(salida.bytes!.length, lessThan(original.length));
    expect(salida.name, 'IMG_1234.jpg');
    expect(salida.mimeType, 'image/jpeg');
    expect(salida.captura?.tomadaEn, captura.tomadaEn);
    expect(salida.captura?.latitud, 4.14);
  });

  test('aplica la orientación EXIF (foto guardada acostada)', () async {
    // Guardada 2100x1400 con orientación 6 (girar 90°): se ve vertical.
    final salida = await OptimizadorImagen.optimizar(
      SelectedUploadFile(
        name: 'foto.jpg',
        bytes: fotoDeCamara(2100, 1400, orientacion: 6),
      ),
    );
    final decodificada = img.decodeJpg(salida.bytes!)!;
    expect([decodificada.width, decodificada.height], [1280, 1920]);
    // Al girar 90° a la derecha, lo rojo (izquierda) queda arriba.
    expect(decodificada.getPixel(640, 100).r, greaterThan(150));
    expect(decodificada.getPixel(640, 1820).b, greaterThan(150));
  });

  test(
    'convierte PNG a JPG y deja intactos los PDF y las fotos ya livianas',
    () async {
      final png = Uint8List.fromList(
        img.encodePng(img.Image(width: 2400, height: 1200)),
      );
      final desdePng = await OptimizadorImagen.optimizar(
        SelectedUploadFile(name: 'captura.png', bytes: png),
      );
      expect(desdePng.name, 'captura.jpg');
      expect(img.decodeJpg(desdePng.bytes!)!.width, 1920);

      final pdf = SelectedUploadFile(
        name: 'acta.pdf',
        bytes: Uint8List.fromList('%PDF-1.4'.codeUnits),
      );
      expect(identical(await OptimizadorImagen.optimizar(pdf), pdf), isTrue);

      final liviana = SelectedUploadFile(
        name: 'ya.jpg',
        bytes: fotoDeCamara(800, 600),
      );
      expect(
        identical(await OptimizadorImagen.optimizar(liviana), liviana),
        isTrue,
      );
    },
  );

  test('si el navegador no puede leerla devuelve el original', () async {
    final rota = SelectedUploadFile(
      name: 'rota.jpg',
      bytes: Uint8List.fromList(List.filled(2000, 7)),
    );
    expect(identical(await OptimizadorImagen.optimizar(rota), rota), isTrue);
  });
}
