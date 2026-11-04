import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:path/path.dart' as p;

import '../../model/cierre_tarea_pendiente_model.dart';
import '../../model/evidencia_adjunto_model.dart';
import 'evidencia_compresion.dart';
import 'sembast_factory_provider.dart';

class EvidenciaPersistencia {
  static Future<List<EvidenciaPendiente>> persistir({
    required String clienteCierreId,
    required List<EvidenciaAdjunto> evidencias,
  }) async {
    final destinoDir = await directorioEvidenciasPendientes(clienteCierreId);
    await Directory(destinoDir).create(recursive: true);

    final out = <EvidenciaPendiente>[];
    var indice = 0;

    for (final e in evidencias) {
      indice++;
      final nombre = e.nombre.trim().isNotEmpty
          ? e.nombre.trim()
          : 'evidencia_$indice.jpg';

      // Origen: el archivo que dejó la cámara o la galería (temporal) o, si
      // la evidencia solo trae bytes, esos bytes. Ninguna se descarta.
      List<int>? bytes;
      File? origenFile;
      final origenPath = e.path?.trim();
      if (origenPath != null && origenPath.isNotEmpty) {
        final f = File(origenPath);
        if (await f.exists()) origenFile = f;
      }
      if (origenFile == null) {
        final b = e.bytes;
        if (b == null || b.isEmpty) continue;
        bytes = b;
      }

      final tamano = origenFile != null
          ? await origenFile.length()
          : bytes!.length;
      var nombreFinal = nombre;
      List<int>? salida;
      if (esNombreDeImagenComprimible(nombre) &&
          tamano > bytesMinimosParaComprimir) {
        try {
          final entrada = bytes ?? await origenFile!.readAsBytes();
          final comprimido = await compute(comprimirImagenEvidencia, entrada);
          salida = comprimido;
          nombreFinal = nombreTrasComprimir(nombre, comprimido);
        } catch (_) {
          salida = null;
        }
      }

      final destinoPath = p.join(
        destinoDir,
        '${indice.toString().padLeft(2, '0')}_$nombreFinal',
      );
      if (salida != null) {
        await File(destinoPath).writeAsBytes(salida, flush: true);
      } else if (origenFile != null) {
        await origenFile.copy(destinoPath);
      } else {
        await File(destinoPath).writeAsBytes(bytes!, flush: true);
      }

      out.add(
        EvidenciaPendiente(
          nombre: nombreFinal,
          path: destinoPath,
          captura: e.captura,
        ),
      );
    }

    return out;
  }

  /// Borra los archivos locales de un cierre ya sincronizado.
  static Future<void> eliminar(String clienteCierreId) async {
    try {
      final dir = Directory(
        await directorioEvidenciasPendientes(clienteCierreId),
      );
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // No es crítico: el archivo huérfano no afecta la integridad de datos,
      // solo ocupa espacio. Se puede limpiar en una pasada futura.
    }
  }
}
