import 'dart:typed_data';

import 'package:image/image.dart' as img;

const int maxLadoEvidencia = 1920;
const int calidadJpegEvidencia = 80;

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

bool esNombreDeImagenComprimible(String nombre) {
  final n = nombre.toLowerCase();
  return n.endsWith('.jpg') ||
      n.endsWith('.jpeg') ||
      n.endsWith('.png') ||
      n.endsWith('.webp') ||
      n.endsWith('.bmp');
}
