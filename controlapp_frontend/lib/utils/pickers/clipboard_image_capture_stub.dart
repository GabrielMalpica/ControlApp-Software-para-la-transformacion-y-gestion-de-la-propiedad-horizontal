import 'selected_upload_file.dart';

typedef ClipboardImageDispose = void Function();

class ClipboardImageCapture {
  static bool get isSupported => false;

  static Future<SelectedUploadFile?> readImage() async {
    return null;
  }

  static ClipboardImageDispose? registerPasteListener(
    void Function(SelectedUploadFile file) onImage,
  ) {
    return null;
  }
}
