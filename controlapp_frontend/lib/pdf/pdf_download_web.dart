import 'dart:html' as html;
import 'dart:typed_data';

Future<void> downloadPdfWeb(List<int> bytes, String filename) async {
  final blob = html.Blob([Uint8List.fromList(bytes)], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);

  final a = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';

  html.document.body!.children.add(a);
  a.click();
  a.remove();

  html.Url.revokeObjectUrl(url);
}
