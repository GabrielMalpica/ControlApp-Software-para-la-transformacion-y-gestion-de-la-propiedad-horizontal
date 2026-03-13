import 'package:http_parser/http_parser.dart';

MediaType? uploadMediaTypeFromName(
  String filename, {
  String? fallbackMimeType,
}) {
  final lower = filename.toLowerCase().trim();

  if (lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.jfif')) {
    return MediaType('image', 'jpeg');
  }
  if (lower.endsWith('.png')) {
    return MediaType('image', 'png');
  }
  if (lower.endsWith('.webp')) {
    return MediaType('image', 'webp');
  }
  if (lower.endsWith('.gif')) {
    return MediaType('image', 'gif');
  }
  if (lower.endsWith('.bmp')) {
    return MediaType('image', 'bmp');
  }
  if (lower.endsWith('.heic')) {
    return MediaType('image', 'heic');
  }
  if (lower.endsWith('.heif')) {
    return MediaType('image', 'heif');
  }
  if (lower.endsWith('.pdf')) {
    return MediaType('application', 'pdf');
  }

  if (fallbackMimeType != null && fallbackMimeType.contains('/')) {
    final parts = fallbackMimeType.split('/');
    if (parts.length >= 2) {
      return MediaType(parts.first, parts.sublist(1).join('/'));
    }
  }

  return null;
}
