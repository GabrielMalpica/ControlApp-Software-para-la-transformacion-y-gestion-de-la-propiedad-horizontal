// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:math' as math;
import 'dart:typed_data';

import 'selected_upload_file.dart';

/// Lado máximo y calidad de las fotos de evidencia: lo mismo que ya usa la
/// cola sin conexión. Una foto de cámara pasa de 3-6 MB a ~0,3-0,6 MB.
const int _ladoMaximo = 1920;
const double _calidadJpeg = 0.82;

/// Un JPG que ya es así de liviano y no pasa del lado máximo se deja igual.
const int _bytesSinTocar = 600 * 1024;

const _extensionesImagen = {
  'jpg',
  'jpeg',
  'jfif',
  'png',
  'webp',
  'gif',
  'bmp',
  'heic',
  'heif',
};

class OptimizadorImagen {
  /// Reduce la foto a 1920 px y la recomprime como JPG con el decodificador
  /// nativo del navegador (rápido, no bloquea como hacerlo en Dart). Subirla
  /// pesa 5-10 veces menos, que con datos móviles es lo que más demora un
  /// cierre con varias evidencias.
  ///
  /// El navegador ya aplica la orientación EXIF al dibujarla, así que sale
  /// derecha. La hora y el GPS de la toma viajan aparte ([captura]). Si algo
  /// falla (formato que el navegador no lee, p. ej. HEIC en Chrome) se
  /// devuelve el archivo original: nunca se pierde una evidencia por esto.
  static Future<SelectedUploadFile> optimizar(
    SelectedUploadFile archivo,
  ) async {
    final bytes = archivo.bytes;
    if (bytes == null || bytes.isEmpty || !_esImagen(archivo)) return archivo;

    final url = html.Url.createObjectUrlFromBlob(
      html.Blob([bytes], archivo.mimeType ?? 'image/jpeg'),
    );
    try {
      final img = html.ImageElement();
      final cargada = Future.any([
        img.onLoad.first.then((_) => true),
        img.onError.first.then((_) => false),
      ]);
      img.src = url;
      if (!await cargada.timeout(const Duration(seconds: 15))) return archivo;

      final ancho = img.naturalWidth;
      final alto = img.naturalHeight;
      if (ancho <= 0 || alto <= 0) return archivo;

      final escala = math.min(1.0, _ladoMaximo / math.max(ancho, alto));
      final esJpeg = _esJpeg(archivo);
      if (escala == 1.0 && esJpeg && bytes.length <= _bytesSinTocar) {
        return archivo;
      }

      final anchoFinal = (ancho * escala).round();
      final altoFinal = (alto * escala).round();
      final canvas = html.CanvasElement(width: anchoFinal, height: altoFinal);
      final ctx = canvas.context2D
        ..imageSmoothingQuality = 'high'
        // Fondo blanco: un PNG con transparencia no queda negro en JPG.
        ..fillStyle = '#ffffff'
        ..fillRect(0, 0, anchoFinal, altoFinal);
      ctx.drawImageScaled(img, 0, 0, anchoFinal, altoFinal);

      final salida = await _leerBlob(
        await canvas.toBlob('image/jpeg', _calidadJpeg),
      );
      if (salida.isEmpty || (esJpeg && salida.length >= bytes.length)) {
        return archivo;
      }

      return SelectedUploadFile(
        name: _conExtensionJpg(archivo.name),
        mimeType: 'image/jpeg',
        bytes: salida,
        captura: archivo.captura,
      );
    } catch (_) {
      return archivo;
    } finally {
      html.Url.revokeObjectUrl(url);
    }
  }

  /// Una a la vez: cada foto de cámara descomprimida ocupa decenas de MB.
  static Future<List<SelectedUploadFile>> optimizarTodas(
    Iterable<SelectedUploadFile> archivos,
  ) async {
    final out = <SelectedUploadFile>[];
    for (final a in archivos) {
      out.add(await optimizar(a));
    }
    return out;
  }

  static String _extension(String nombre) {
    final punto = nombre.lastIndexOf('.');
    return punto < 0 ? '' : nombre.substring(punto + 1).toLowerCase();
  }

  static bool _esImagen(SelectedUploadFile a) {
    final mime = (a.mimeType ?? '').toLowerCase();
    return mime.startsWith('image/') ||
        _extensionesImagen.contains(_extension(a.name));
  }

  static bool _esJpeg(SelectedUploadFile a) {
    final mime = (a.mimeType ?? '').toLowerCase();
    return mime == 'image/jpeg' ||
        const {'jpg', 'jpeg', 'jfif'}.contains(_extension(a.name));
  }

  static String _conExtensionJpg(String nombre) {
    final limpio = nombre.trim().isEmpty ? 'foto' : nombre.trim();
    final punto = limpio.lastIndexOf('.');
    final base = punto <= 0 ? limpio : limpio.substring(0, punto);
    return '$base.jpg';
  }

  static Future<Uint8List> _leerBlob(html.Blob blob) {
    final reader = html.FileReader();
    final completer = Completer<Uint8List>();
    reader.onLoadEnd.listen((_) {
      final result = reader.result;
      if (result is ByteBuffer) {
        completer.complete(Uint8List.view(result));
      } else if (result is Uint8List) {
        completer.complete(result);
      } else {
        completer.complete(Uint8List(0));
      }
    });
    reader.readAsArrayBuffer(blob);
    return completer.future;
  }
}
