import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'package:flutter_application_1/model/evidencia_adjunto_model.dart';
import 'package:flutter_application_1/service/upload_media_type.dart';

/// Agrega las evidencias de cierre al multipart (`files`; web: bytes, móvil y
/// escritorio: ruta) y, alineado con ellas, el campo `evidenciasCaptura` con
/// la hora y el GPS de las fotos tomadas con la cámara de la app, que el
/// backend estampa como marca de agua.
Future<void> adjuntarEvidencias(
  http.MultipartRequest req,
  List<EvidenciaAdjunto> evidencias,
) async {
  final capturas = <CapturaEvidencia?>[];

  for (final evidencia in evidencias) {
    final path = evidencia.path?.trim();
    final bytes = evidencia.bytes;
    final fileName = evidencia.nombre.trim().isNotEmpty
        ? evidencia.nombre.trim()
        : (path?.split(RegExp(r'[\\/]')).last ?? 'evidencia.jpg');
    final contentType = uploadMediaTypeFromName(fileName);

    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (await file.exists()) {
        req.files.add(
          await http.MultipartFile.fromPath(
            'files',
            path,
            filename: fileName,
            contentType: contentType,
          ),
        );
        capturas.add(evidencia.captura);
        continue;
      }
    }

    if (kIsWeb && bytes != null && bytes.isNotEmpty) {
      req.files.add(
        http.MultipartFile.fromBytes(
          'files',
          bytes,
          filename: fileName,
          contentType: contentType,
        ),
      );
      capturas.add(evidencia.captura);
    }
  }

  agregarCampoCapturas(req, capturas);
}

/// [capturas] debe tener una entrada por cada archivo ya agregado a `files`,
/// en el mismo orden.
void agregarCampoCapturas(
  http.MultipartRequest req,
  List<CapturaEvidencia?> capturas,
) {
  final json = evidenciasCapturaJson(capturas);
  if (json != null) req.fields['evidenciasCaptura'] = json;
}
