import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:flutter_application_1/service/offline/evidencia_compresion.dart';

import 'selected_upload_file.dart';

/// En la app nativa la cámara y la galería ya entregan la foto reducida a
/// 1920 px como JPG (ver `camera_capture_io.dart` y `galeria_evidencias.dart`).
/// Aquí solo se convierte a JPG lo que no lo es (PNG, WEBP…) o lo que llegó
/// muy pesado por otro camino: el servidor solo acepta JPG, PNG y PDF.
/// El EXIF (hora de toma) ya se leyó antes de llegar aquí.
class OptimizadorImagen {
  static Future<SelectedUploadFile> optimizar(
    SelectedUploadFile archivo,
  ) async {
    final path = archivo.path?.trim() ?? '';
    if (path.isEmpty || !esNombreDeImagenComprimible(archivo.name)) {
      return archivo;
    }
    try {
      final file = File(path);
      if (!await file.exists()) return archivo;
      final tamano = await file.length();
      final yaEsJpg = const {
        '.jpg',
        '.jpeg',
      }.contains(p.extension(archivo.name).toLowerCase());
      if (yaEsJpg && tamano <= bytesMinimosParaComprimir) return archivo;

      final salida = await compute(
        comprimirImagenEvidencia,
        await file.readAsBytes(),
      );
      if (!esJpeg(salida)) return archivo; // no se pudo leer (p. ej. HEIC)
      if (yaEsJpg && salida.length >= tamano) return archivo;

      final dir = await getTemporaryDirectory();
      final nombre = nombreConExtensionJpg(archivo.name);
      final destino = p.join(
        dir.path,
        'evidencia_${DateTime.now().microsecondsSinceEpoch}_$nombre',
      );
      await File(destino).writeAsBytes(salida, flush: true);
      return SelectedUploadFile(
        name: nombre,
        mimeType: 'image/jpeg',
        path: destino,
        captura: archivo.captura,
      );
    } catch (_) {
      // Nunca se pierde una evidencia por no poder optimizarla.
      return archivo;
    }
  }

  /// Una a la vez: cada foto descomprimida ocupa decenas de MB.
  static Future<List<SelectedUploadFile>> optimizarTodas(
    Iterable<SelectedUploadFile> archivos,
  ) async {
    final out = <SelectedUploadFile>[];
    for (final a in archivos) {
      out.add(await optimizar(a));
    }
    return out;
  }
}
