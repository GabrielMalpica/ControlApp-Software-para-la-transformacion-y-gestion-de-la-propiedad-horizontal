import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';

Future<Uint8List> renderWidgetToPngBytes({
  required Widget widget,
  required Size logicalSize,
  double pixelRatio = 2.0,
}) async {
  final repaintBoundary = RenderRepaintBoundary();
  final flutterView = WidgetsBinding.instance.platformDispatcher.views.first;

  // ✅ ESTA ES LA CLAVE
  final renderView = RenderView(
    view: flutterView,
    configuration: ViewConfiguration.fromView(flutterView),
    child: RenderPositionedBox(
      alignment: Alignment.center,
      child: repaintBoundary,
    ),
  );

  final pipelineOwner = PipelineOwner();
  final buildOwner = BuildOwner(focusManager: FocusManager());

  pipelineOwner.rootNode = renderView;
  renderView.prepareInitialFrame();

  final rootElement = RenderObjectToWidgetAdapter<RenderBox>(
    container: repaintBoundary,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: logicalSize.width,
        height: logicalSize.height,
        child: Material(color: Colors.transparent, child: widget),
      ),
    ),
  ).attachToRenderTree(buildOwner);

  buildOwner.buildScope(rootElement);
  buildOwner.finalizeTree();

  pipelineOwner.flushLayout();
  pipelineOwner.flushCompositingBits();
  pipelineOwner.flushPaint();

  final image = await repaintBoundary.toImage(pixelRatio: pixelRatio);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

  return byteData!.buffer.asUint8List();
}
