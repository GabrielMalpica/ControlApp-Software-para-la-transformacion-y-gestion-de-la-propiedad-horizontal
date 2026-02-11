import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

/// Preview para IO:
/// - XFile (camera/gallery) => Image.file
/// - PlatformFile (file_picker) => si tiene path: Image.file, si no: Image.memory
class PreviewHelper {
  static Widget previewXFile(
    XFile xf, {
    double size = 92,
    BoxFit fit = BoxFit.cover,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.file(File(xf.path), width: size, height: size, fit: fit),
    );
  }

  static Widget previewPlatformFile(
    PlatformFile pf, {
    double size = 92,
    BoxFit fit = BoxFit.cover,
  }) {
    final lower = pf.name.toLowerCase();

    final isImg =
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png');

    if (!isImg) {
      return _fileBox(pf.name, size: size);
    }

    if (pf.path != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(File(pf.path!), width: size, height: size, fit: fit),
      );
    }

    final Uint8List? bytes = pf.bytes;
    if (bytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(bytes, width: size, height: size, fit: fit),
      );
    }

    return _fileBox(pf.name, size: size);
  }

  static Widget _fileBox(String name, {double size = 92}) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        color: Colors.grey.shade50,
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Text(
          name,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
        ),
      ),
    );
  }
}
