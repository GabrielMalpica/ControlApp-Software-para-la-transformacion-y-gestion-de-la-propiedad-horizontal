import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;

import '../../model/cierre_tarea_pendiente_model.dart';
import '../../model/evidencia_adjunto_model.dart';
import 'evidencia_compresion.dart';

class EvidenciaPersistencia {
  static Future<List<EvidenciaPendiente>> persistir({
    required String clienteCierreId,
    required List<EvidenciaAdjunto> evidencias,
  }) async {
    final out = <EvidenciaPendiente>[];
    var indice = 0;

    for (final e in evidencias) {
      indice++;
      final nombre = e.nombre.trim().isNotEmpty
          ? e.nombre.trim()
          : 'evidencia_$indice.jpg';

      final bytes = e.bytes;
      if (bytes == null || bytes.isEmpty) continue;

      var finalBytes = bytes;
      if (esNombreDeImagenComprimible(nombre)) {
        try {
          finalBytes = await compute(comprimirImagenEvidencia, bytes);
        } catch (_) {
          finalBytes = bytes;
        }
      }

      out.add(
        EvidenciaPendiente(
          nombre: nombre,
          bytesBase64: base64Encode(finalBytes),
        ),
      );
    }

    return out;
  }

  /// En web las evidencias viven dentro del documento del store (no hay
  /// archivos sueltos que borrar); el store las elimina junto con el
  /// registro del cierre.
  static Future<void> eliminar(String clienteCierreId) async {}
}
