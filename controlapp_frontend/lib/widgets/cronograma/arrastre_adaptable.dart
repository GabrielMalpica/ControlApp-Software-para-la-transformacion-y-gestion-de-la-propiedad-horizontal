import 'package:flutter/material.dart';

/// Arrastre que se siente natural con mouse y con el dedo: con mouse o
/// trackpad se arrastra apenas se mueve (clic y arrastrar, como en cualquier
/// calendario de escritorio); con el dedo hay que mantener presionado, para
/// no quitarle el desplazamiento a la lista o a la cuadrícula.
///
/// El tipo se decide al pasar el puntero por encima (solo el mouse "pasa por
/// encima"), así ya está listo antes de presionar y no cambia en pleno arrastre.
class ArrastreAdaptable<T extends Object> extends StatefulWidget {
  final T data;
  final Widget child;
  final Widget feedback;
  final Widget? childWhenDragging;
  final DragAnchorStrategy dragAnchorStrategy;
  final int? maxSimultaneousDrags;
  final VoidCallback? onDragStarted;
  final DragEndCallback? onDragEnd;
  final DraggableCanceledCallback? onDraggableCanceled;

  const ArrastreAdaptable({
    super.key,
    required this.data,
    required this.child,
    required this.feedback,
    this.childWhenDragging,
    this.dragAnchorStrategy = childDragAnchorStrategy,
    this.maxSimultaneousDrags,
    this.onDragStarted,
    this.onDragEnd,
    this.onDraggableCanceled,
  });

  @override
  State<ArrastreAdaptable<T>> createState() => _ArrastreAdaptableState<T>();
}

class _ArrastreAdaptableState<T extends Object>
    extends State<ArrastreAdaptable<T>> {
  /// Una vez que se ve un mouse en la página, todas las tarjetas lo usan.
  static bool _hayMouse = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final Widget arrastrable = _hayMouse
        ? Draggable<T>(
            data: w.data,
            dragAnchorStrategy: w.dragAnchorStrategy,
            maxSimultaneousDrags: w.maxSimultaneousDrags,
            onDragStarted: w.onDragStarted,
            onDragEnd: w.onDragEnd,
            onDraggableCanceled: w.onDraggableCanceled,
            feedback: w.feedback,
            childWhenDragging: w.childWhenDragging,
            child: w.child,
          )
        : LongPressDraggable<T>(
            data: w.data,
            dragAnchorStrategy: w.dragAnchorStrategy,
            maxSimultaneousDrags: w.maxSimultaneousDrags,
            onDragStarted: w.onDragStarted,
            onDragEnd: w.onDragEnd,
            onDraggableCanceled: w.onDraggableCanceled,
            feedback: w.feedback,
            childWhenDragging: w.childWhenDragging,
            child: w.child,
          );

    return MouseRegion(
      cursor: _hayMouse ? SystemMouseCursors.grab : MouseCursor.defer,
      onHover: (_) {
        if (!_hayMouse) setState(() => _hayMouse = true);
      },
      child: arrastrable,
    );
  }
}
