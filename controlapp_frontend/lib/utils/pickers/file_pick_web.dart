import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'selected_upload_file.dart';

class UniversalFilePick {
  static Future<List<SelectedUploadFile>> pick({
    bool allowMultiple = true,
    List<String>? allowedExtensions,
  }) async {
    final input = html.FileUploadInputElement();
    input.multiple = allowMultiple;

    // accept: ".jpg,.png,.pdf"
    if (allowedExtensions != null && allowedExtensions.isNotEmpty) {
      final accept = allowedExtensions
          .map((e) => '.${e.toLowerCase()}')
          .join(',');
      input.accept = accept;
    }

    final completer = Completer<List<SelectedUploadFile>>();

    input.onChange.listen((_) async {
      final files = input.files ?? [];
      final out = <SelectedUploadFile>[];

      for (final f in files) {
        final bytes = await _readFileAsBytes(f);
        out.add(
          SelectedUploadFile(
            name: f.name,
            mimeType: f.type.isEmpty ? null : f.type,
            bytes: bytes, // ✅ WEB
          ),
        );
      }

      completer.complete(out);
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
