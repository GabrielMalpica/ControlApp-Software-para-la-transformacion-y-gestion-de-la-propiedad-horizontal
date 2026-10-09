import 'selected_upload_file.dart';

/// En la app nativa la cámara ya entrega la foto reducida (ver
/// `camera_capture_io.dart`) y la cola sin conexión comprime en un isolate,
/// así que aquí no se hace nada.
class OptimizadorImagen {
  static Future<SelectedUploadFile> optimizar(
    SelectedUploadFile archivo,
  ) async => archivo;

  static Future<List<SelectedUploadFile>> optimizarTodas(
    Iterable<SelectedUploadFile> archivos,
  ) async => archivos.toList();
}
