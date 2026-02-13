import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

Future<Uint8List> capturePngFromKey(
  GlobalKey key, {
  double pixelRatio = 2,
  int maxFrames = 180,
  Duration retryDelay = const Duration(milliseconds: 16),
}) async {
  final ctx = key.currentContext;
  if (ctx == null) {
    throw StateError('capturePngFromKey: key no montado (currentContext=null)');
  }

  final ro = ctx.findRenderObject();
  if (ro is! RenderRepaintBoundary) {
    throw StateError(
      'capturePngFromKey: RenderObject no es RenderRepaintBoundary',
    );
  }

  final boundary = ro;

  for (int i = 0; i < maxFrames; i++) {
    await WidgetsBinding.instance.endOfFrame;

    final attached = boundary.attached;
    final hasSize =
        boundary.hasSize && boundary.size.width > 0 && boundary.size.height > 0;

    final hasLayer = boundary.layer != null;

    if (!attached || !hasSize || !hasLayer) {
      await Future.delayed(retryDelay);
      continue;
    }

    try {
      final ui.Image img = await boundary.toImage(pixelRatio: pixelRatio);
      final bd = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bd == null) {
        await Future.delayed(retryDelay);
        continue;
      }

      final bytes = bd.buffer.asUint8List();

      if (bytes.length < 800) {
        await Future.delayed(retryDelay);
        continue;
      }

      return bytes;
    } catch (_) {
      await Future.delayed(retryDelay);
      continue;
    }
  }

  throw StateError(
    'capturePngFromKey: No se pudo capturar PNG. '
    'boundary(attached=${boundary.attached}, size=${boundary.hasSize ? boundary.size : "no-size"}, layer=${boundary.layer != null})',
  );
}
