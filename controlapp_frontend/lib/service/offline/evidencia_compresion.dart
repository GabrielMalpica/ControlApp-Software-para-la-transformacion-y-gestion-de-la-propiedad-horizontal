import 'dart:typed_data';

import 'package:image/image.dart' as img;

const int maxLadoEvidencia = 1920;
const int calidadJpegEvidencia = 82;

/// Por debajo de esto la foto ya viene reducida (la cámara y los adjuntos se
/// optimizan al agregarse) y recomprimirla solo gasta tiempo: en web esto
/// corre en el hilo principal y congela la pantalla.
const int bytesMinimosParaComprimir = 900 * 1024;

/// Redimensiona y reencodea una imagen para que ocupe menos espacio en la
/// cola offline. Pensado para correr dentro de `compute()` (isolate aparte)
/// ya que decodificar/reencodear fotos de cámara puede tardar cientos de ms.
///
/// Si los bytes no se pueden decodificar (p.ej. HEIC, que el paquete `image`
/// no soporta), se devuelven sin cambios: nunca se bloquea el cierre de la
/// tarea por no poder comprimir una evidencia.
List<int> comprimirImagenEvidencia(List<int> bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(Uint8List.fromList(bytes));
  } catch (_) {
    decoded = null;
  }
  if (decoded == null) return bytes;

  var resized = decoded;
  if (decoded.width > maxLadoEvidencia || decoded.height > maxLadoEvidencia) {
    resized = decoded.width >= decoded.height
        ? img.copyResize(decoded, width: maxLadoEvidencia)
        : img.copyResize(decoded, height: maxLadoEvidencia);
  }

  try {
    return img.encodeJpg(resized, quality: calidadJpegEvidencia);
  } catch (_) {
    return bytes;
  }
}

/// true si los bytes son un JPEG (FF D8 FF).
bool esJpeg(List<int> bytes) =>
    bytes.length > 3 &&
    bytes[0] == 0xFF &&
    bytes[1] == 0xD8 &&
    bytes[2] == 0xFF;

/// Nombre con extensión `.jpg` (el contenido ya se recomprimió como JPEG: un
/// `.png` con contenido JPEG confunde al servidor y a Drive).
String nombreConExtensionJpg(String nombre) {
  final limpio = nombre.trim().isEmpty ? 'foto' : nombre.trim();
  final punto = limpio.lastIndexOf('.');
  final base = punto <= 0 ? limpio : limpio.substring(0, punto);
  return '$base.jpg';
}

/// Nombre final de una evidencia tras [comprimirImagenEvidencia]: si salió
/// un JPEG, con extensión `.jpg`; si no se pudo comprimir, el mismo.
String nombreTrasComprimir(String nombre, List<int> salida) {
  if (!esJpeg(salida)) return nombre;
  final n = nombre.toLowerCase();
  if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return nombre;
  return nombreConExtensionJpg(nombre);
}

bool esNombreDeImagenComprimible(String nombre) {
  final n = nombre.toLowerCase();
  return n.endsWith('.jpg') ||
      n.endsWith('.jpeg') ||
      n.endsWith('.png') ||
      n.endsWith('.webp') ||
      n.endsWith('.bmp');
}
