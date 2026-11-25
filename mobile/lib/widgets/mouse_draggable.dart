import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

class MouseDraggable<T extends Object> extends Draggable<T> {
  const MouseDraggable({
    super.key,
    required super.child,
    required super.feedback,
    super.data,
    super.childWhenDragging,
    super.dragAnchorStrategy,
    super.onDragStarted,
    super.onDragEnd,
    super.maxSimultaneousDrags,
  });

  @override
  MultiDragGestureRecognizer createRecognizer(GestureMultiDragStartCallback onStart) =>
      ImmediateMultiDragGestureRecognizer(
        supportedDevices: const {PointerDeviceKind.mouse},
        allowedButtonsFilter: allowedButtonsFilter,
      )..onStart = onStart;
}
