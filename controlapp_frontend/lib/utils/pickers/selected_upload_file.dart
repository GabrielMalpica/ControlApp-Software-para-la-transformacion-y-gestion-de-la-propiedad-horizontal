import 'dart:typed_data';

class SelectedUploadFile {
  final String name;
  final String? mimeType;

  /// En WEB siempre viene bytes.
  final Uint8List? bytes;

  /// En IO (Windows/Mac/Linux/Android/iOS) normalmente viene path.
  final String? path;

  const SelectedUploadFile({
    required this.name,
    this.mimeType,
    this.bytes,
    this.path,
  });

  bool get hasBytes => bytes != null && bytes!.isNotEmpty;
  bool get hasPath => path != null && path!.isNotEmpty;
}