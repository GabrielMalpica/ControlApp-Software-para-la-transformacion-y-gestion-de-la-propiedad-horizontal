import 'package:image_picker/image_picker.dart';

import 'selected_upload_file.dart';

class CameraCapture {
  static Future<SelectedUploadFile?> pickPhoto() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (x == null) return null;

    final name = x.name.trim().isEmpty ? 'foto.jpg' : x.name.trim();
    final path = x.path.trim();
    if (path.isEmpty) return null;

    return SelectedUploadFile(
      name: name,
      mimeType: 'image/jpeg',
      path: path,
    );
  }
}
