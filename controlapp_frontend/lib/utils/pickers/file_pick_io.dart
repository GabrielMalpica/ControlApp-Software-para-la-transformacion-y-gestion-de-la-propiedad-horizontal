import 'package:file_picker/file_picker.dart';
import 'selected_upload_file.dart';

class UniversalFilePick {
  /// allowedExtensions ejemplo: ['jpg','png','pdf']
  static Future<List<SelectedUploadFile>> pick({
    bool allowMultiple = true,
    List<String>? allowedExtensions,
  }) async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: allowMultiple,
      withData: false, // en IO basta con path
      type: allowedExtensions == null ? FileType.any : FileType.custom,
      allowedExtensions: allowedExtensions,
    );

    if (res == null) return [];

    return res.files.map((pf) {
      return SelectedUploadFile(
        name: pf.name,
        path: pf.path, // ✅ IO
        // bytes normalmente null aquí, y está bien
      );
    }).toList();
  }
}
