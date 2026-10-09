import 'package:image_picker/image_picker.dart';

import 'package:flutter_application_1/model/evidencia_adjunto_model.dart';

import 'selected_upload_file.dart';

class CameraCapture {
  static Future<SelectedUploadFile?> pickPhoto() async {
    // 1920 px como la cola sin conexión: la foto pesa ~10 veces menos y el
    // cierre sube mucho más rápido con datos móviles.
    final x = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 82,
    );
    if (x == null) return null;

    final name = x.name.trim().isEmpty ? 'foto.jpg' : x.name.trim();
    final path = x.path.trim();
    if (path.isEmpty) return null;

    return SelectedUploadFile(
      name: name,
      mimeType: 'image/jpeg',
      path: path,
      // La fuente es siempre la cámara: la foto se acaba de tomar.
      captura: CapturaEvidencia(tomadaEn: DateTime.now()),
    );
  }
}
