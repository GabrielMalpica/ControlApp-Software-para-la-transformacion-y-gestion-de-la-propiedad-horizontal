import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_application_1/pdf/pdf_download.dart';
import 'package:printing/printing.dart';

Future<void> openOrDownloadPdf(Uint8List bytes, String filename) async {
  if (kIsWeb) {
    await downloadPdfWeb(bytes, filename);
  } else {
    await Printing.layoutPdf(name: filename, onLayout: (_) async => bytes);
  }
}
