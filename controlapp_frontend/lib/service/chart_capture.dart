import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

Future<void> _waitPaint(RenderRepaintBoundary boundary) async {
  for (int i = 0; i < 20; i++) {
    await WidgetsBinding.instance.endOfFrame;
    if (!boundary.debugNeedsPaint) return;
  }
  throw StateError(
    'RepaintBoundary no alcanzó a pintar (debugNeedsPaint=true)',
  );
}

Future<Uint8List> capturePngFromKey(
  GlobalKey key, {
  double pixelRatio = 2,
}) async {
  final ctx = key.currentContext;
  if (ctx == null) throw StateError('capturePngFromKey: key no montado');

  final ro = ctx.findRenderObject();
  if (ro is! RenderRepaintBoundary) {
    throw StateError(
      'capturePngFromKey: RenderObject no es RenderRepaintBoundary',
    );
  }

  await _waitPaint(ro);

  final ui.Image img = await ro.toImage(pixelRatio: pixelRatio);
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  return bd!.buffer.asUint8List();
}
