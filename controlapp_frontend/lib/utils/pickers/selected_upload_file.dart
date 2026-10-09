import 'dart:typed_data';

import 'package:flutter_application_1/model/evidencia_adjunto_model.dart';

class SelectedUploadFile {
  final String name;
  final String? mimeType;

  /// En WEB siempre viene bytes.
  final Uint8List? bytes;

  /// En IO (Windows/Mac/Linux/Android/iOS) normalmente viene path.
  final String? path;

  /// Solo en fotos recién tomadas con la cámara: hora (y GPS) de la toma,
  /// para la marca de agua de auditoría.
  final CapturaEvidencia? captura;

  const SelectedUploadFile({
    required this.name,
    this.mimeType,
    this.bytes,
    this.path,
    this.captura,
  });

  bool get hasBytes => bytes != null && bytes!.isNotEmpty;
  bool get hasPath => path != null && path!.isNotEmpty;

  SelectedUploadFile conCaptura(CapturaEvidencia? captura) =>
      SelectedUploadFile(
        name: name,
        mimeType: mimeType,
        bytes: bytes,
        path: path,
        captura: captura,
      );
}
