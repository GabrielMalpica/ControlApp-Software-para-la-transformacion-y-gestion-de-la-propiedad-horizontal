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

      final origenPath = e.path?.trim();
      if (origenPath == null || origenPath.isEmpty) continue;

      final origenFile = File(origenPath);
      if (!await origenFile.exists()) continue;

      final destinoPath = p.join(
        destinoDir,
        '${indice.toString().padLeft(2, '0')}_$nombre',
      );

      if (esNombreDeImagenComprimible(nombre)) {
        try {
          final bytes = await origenFile.readAsBytes();
          final comprimido = await compute(comprimirImagenEvidencia, bytes);
          await File(destinoPath).writeAsBytes(comprimido);
        } catch (_) {
          await origenFile.copy(destinoPath);
        }
      } else {
        await origenFile.copy(destinoPath);
      }

      out.add(EvidenciaPendiente(nombre: nombre, path: destinoPath));
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
