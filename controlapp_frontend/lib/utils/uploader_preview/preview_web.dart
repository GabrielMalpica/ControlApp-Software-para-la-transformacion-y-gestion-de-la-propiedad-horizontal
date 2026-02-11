import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

/// Preview para WEB:
/// - NO usamos Image.file (no existe dart:io)
/// - XFile => Image.memory (readAsBytes)
/// - PlatformFile => Image.memory (bytes)
class PreviewHelper {
  static Widget previewXFile(
    XFile xf, {
    double size = 92,
    BoxFit fit = BoxFit.cover,
  }) {
    return FutureBuilder<Uint8List>(
      future: xf.readAsBytes(),
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return _loadingBox(size);
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(snap.data!, width: size, height: size, fit: fit),
        );
      },
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

    final Uint8List? bytes = pf.bytes;
    if (bytes == null) {
      // En web DEBE venir con bytes (withData:true)
      return _fileBox('Sin bytes\n${pf.name}', size: size);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.memory(bytes, width: size, height: size, fit: fit),
    );
  }

  static Widget _loadingBox(double size) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        color: Colors.grey.shade50,
      ),
      child: const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
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
