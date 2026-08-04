// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'selected_upload_file.dart';

typedef ClipboardImageDispose = void Function();

class ClipboardImageCapture {
  static bool get isSupported => html.window.navigator.clipboard != null;

  static Future<SelectedUploadFile?> readImage() async {
    return null;
  }

  static ClipboardImageDispose? registerPasteListener(
    void Function(SelectedUploadFile file) onImage,
  ) {
    final subscription = html.document.onPaste.listen((event) async {
      final file = await _fileFromPasteEvent(event);
      if (file != null) onImage(file);
    });

    return () {
      subscription.cancel();
    };
  }

  static Future<SelectedUploadFile?> _fileFromPasteEvent(
    html.Event event,
  ) async {
    if (event is! html.ClipboardEvent) return null;
    final data = event.clipboardData;
    if (data == null) return null;

    final items = data.items;
    if (items == null) return null;

    final itemCount = items.length ?? 0;
    for (var i = 0; i < itemCount; i++) {
      final item = items[i];
      final type = (item.type ?? '').toLowerCase();
      if (!type.startsWith('image/')) continue;
      final file = item.getAsFile();
      if (file == null) continue;
      final bytes = await _readFileAsBytes(file);
      if (bytes.isEmpty) continue;
      return SelectedUploadFile(
        name: _defaultName(type),
        mimeType: type,
        bytes: bytes,
      );
    }

    return null;
  }

  static String _defaultName(String mimeType) {
    final extension = mimeType.split('/').last.trim();
    final safeExtension = extension.isEmpty ? 'png' : extension;
    return 'evidencia_portapapeles.$safeExtension';
  }

  static Future<Uint8List> _readBlobAsBytes(html.Blob blob) async {
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

    reader.readAsArrayBuffer(blob);
    return completer.future;
  }

  static Future<Uint8List> _readFileAsBytes(html.File file) {
    return _readBlobAsBytes(file);
  }
}
