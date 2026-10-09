// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter_application_1/model/evidencia_adjunto_model.dart';

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
      final tomadaEn = _horaDeToma(file.lastModified);
      if (!completer.isCompleted) {
        completer.complete(
          SelectedUploadFile(
            name: name,
            mimeType: file.type.isEmpty ? 'image/jpeg' : file.type,
            bytes: bytes,
            captura: tomadaEn == null
                ? null
                : CapturaEvidencia(tomadaEn: tomadaEn),
          ),
        );
      }
    });

    input.click();
    return completer.future;
  }

  /// En celulares el archivo que devuelve la cámara se crea al tomar la foto,
  /// así que su fecha de modificación es la hora de la toma. En un PC sin
  /// cámara este mismo botón abre un selector de archivos: si el archivo es
  /// viejo no es una foto recién tomada y no se le atribuye hora de toma.
  static DateTime? _horaDeToma(int? lastModifiedMs) {
    if (lastModifiedMs == null || lastModifiedMs <= 0) return null;
    final fecha = DateTime.fromMillisecondsSinceEpoch(lastModifiedMs);
    final diferencia = DateTime.now().difference(fecha);
    if (diferencia > const Duration(minutes: 10) ||
        diferencia < const Duration(minutes: -1)) {
      return null;
    }
    return fecha;
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
