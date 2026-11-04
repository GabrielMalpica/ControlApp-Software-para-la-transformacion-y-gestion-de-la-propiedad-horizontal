import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';

import 'package:flutter_application_1/service/offline/evidencia_compresion.dart';

import 'selected_upload_file.dart';

/// Elegir evidencias de la galería.
///
/// - App nativa: `image_picker` (galería de fotos de Android), reducidas a
///   1920 px y recomprimidas como JPG de calidad 82 por el propio selector,
///   que conserva la hora de toma del EXIF. Solo fotos.
/// - Web: el selector de archivos del navegador (fotos y PDF), con bytes.
///
/// Después hay que pasarlas por `EvidenciaCamara.prepararDeGaleria`, que lee
/// la hora y el GPS del EXIF.
class GaleriaEvidencias {
  GaleriaEvidencias._();

  static const extensionesWeb = [
    'jpg',
    'jpeg',
    'jfif',
    'png',
    'webp',
    'gif',
    'bmp',
    'heic',
    'heif',
    'pdf',
  ];

  /// Hasta [maximo] archivos (0 o menos: no abre nada).
  static Future<List<SelectedUploadFile>> elegir({required int maximo}) async {
    if (maximo <= 0) return const [];
    if (kIsWeb) return _elegirWeb(maximo);

    final picker = ImagePicker();
    final List<XFile> fotos;
    if (maximo == 1) {
      final una = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: maxLadoEvidencia.toDouble(),
        maxHeight: maxLadoEvidencia.toDouble(),
        imageQuality: calidadJpegEvidencia,
      );
      fotos = una == null ? const [] : [una];
    } else {
      fotos = await picker.pickMultiImage(
        maxWidth: maxLadoEvidencia.toDouble(),
        maxHeight: maxLadoEvidencia.toDouble(),
        imageQuality: calidadJpegEvidencia,
        limit: maximo,
      );
    }

    return [
      for (final f in fotos.take(maximo))
        if (f.path.trim().isNotEmpty)
          SelectedUploadFile(
            name: _nombre(f),
            path: f.path,
            mimeType: _esPng(f) ? 'image/png' : 'image/jpeg',
          ),
    ];
  }

  static Future<List<SelectedUploadFile>> _elegirWeb(int maximo) async {
    final elegidos = await FilePicker.platform.pickFiles(
      allowMultiple: maximo > 1,
      withData: true,
      type: FileType.custom,
      allowedExtensions: extensionesWeb,
    );
    if (elegidos == null) return const [];
    return [
      for (final f in elegidos.files.take(maximo))
        SelectedUploadFile(name: f.name, bytes: f.bytes),
    ];
  }

  static bool _esPng(XFile f) => f.path.toLowerCase().endsWith('.png');

  /// El selector devuelve JPG salvo fotos con transparencia (PNG); el nombre
  /// sigue a lo que hay dentro.
  static String _nombre(XFile f) {
    final base = f.name.trim().isEmpty ? 'foto.jpg' : f.name.trim();
    if (_esPng(f)) return base;
    final n = base.toLowerCase();
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return base;
    return nombreConExtensionJpg(base);
  }
}
