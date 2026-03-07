import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'selected_upload_file.dart';

class CameraCapture {
  static Future<SelectedUploadFile?> pickPhoto() async {
    final input = html.FileUploadInputElement()
      ..accept = 'image/*'
      ..multiple = false;
    input.attributes['capture'] = 'environment';

    final completer = Completer<SelectedUploadFile?>();

    input.onChange.listen((_) async {
      final file = input.files?.isNotEmpty == true ? input.files!.first : null;
      if (file == null) {
        if (!completer.isCompleted) completer.complete(null);
        return;
      }

      final bytes = await _readFileAsBytes(file);
      final name = file.name.trim().isEmpty ? 'foto.jpg' : file.name.trim();
      if (!completer.isCompleted) {
        completer.complete(
          SelectedUploadFile(
            name: name,
            mimeType: file.type.isEmpty ? 'image/jpeg' : file.type,
            bytes: bytes,
          ),
        );
      }
    });

    input.click();
    return completer.future;
  }

  static Future<Uint8List> _readFileAsBytes(html.File file) async {
    final reader = html.FileReader();
    final completer = Completer<Uint8List>();

    reader.onLoadEnd.listen((_) {
      final result = reader.result;
      if (result is ByteBuffer) {
        completer.complete(Uint8List.view(result));
      } else if (result is Uint8List) {
        completer.complete(result);
      } else {
        completer.complete(Uint8List(0));
      }
    });

    reader.readAsArrayBuffer(file);
    return completer.future;
  }
}
