import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class AnchoredFeed extends SingleChildRenderObjectWidget {
  const AnchoredFeed({
    super.key,
    required this.controller,
    required this.anchors,
    this.onLaidOut,
    required super.child,
  });

  final ScrollController controller;

  final Iterable<GlobalKey> anchors;

  final VoidCallback? onLaidOut;

  @override
  RenderAnchoredFeed createRenderObject(BuildContext context) =>
      RenderAnchoredFeed(controller: controller, anchors: anchors, onLaidOut: onLaidOut);

  @override
  void updateRenderObject(BuildContext context, RenderAnchoredFeed renderObject) {
    renderObject
      ..controller = controller
      ..anchors = anchors
      ..onLaidOut = onLaidOut;
  }
}

const double _kStickToBottom = 0.5;

class RenderAnchoredFeed extends RenderProxyBox {
  RenderAnchoredFeed({
    required this.controller,
    required this.anchors,
    this.onLaidOut,
  });

  ScrollController controller;
  Iterable<GlobalKey> anchors;
  VoidCallback? onLaidOut;

  @override
  bool get isRepaintBoundary => true;

  @override
  void performLayout() {
    final anchor = _pickAnchor();
    super.performLayout();
    if (anchor != null) _restore(anchor);
    onLaidOut?.call();
  }

  ({RenderBox box, double fromBottom})? _pickAnchor() {
    if (!hasSize || !controller.hasClients) return null;
    final position = controller.position;
    if (!position.hasPixels || !position.hasViewportDimension) return null;
    final pixels = position.pixels;
    if (pixels <= _kStickToBottom) return null;
    final visibleBottom = size.height - pixels;
    final visibleTop = visibleBottom - position.viewportDimension;
    RenderBox? best;
    double bestTop = double.infinity;
    for (final key in anchors) {
      final box = _rowBox(key);
      if (box == null || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero, ancestor: this).dy;
      final bottom = top + box.size.height;
      if (bottom <= visibleTop || top >= visibleBottom) continue;
      if (top < bestTop) {
        best = box;
        bestTop = top;
      }
    }
    if (best == null) return null;
    return (box: best, fromBottom: size.height - bestTop);
  }

  void _restore(({RenderBox box, double fromBottom}) anchor) {
    final box = anchor.box;
    if (!box.attached || !box.hasSize || !controller.hasClients) return;
    final top = box.localToGlobal(Offset.zero, ancestor: this).dy;
    final delta = (size.height - top) - anchor.fromBottom;
    if (delta.abs() < 0.01) return;
    controller.position.correctBy(delta);
  }

  RenderBox? _rowBox(GlobalKey key) {
    final object = key.currentContext?.findRenderObject();
    if (object is! RenderBox || !object.attached) return null;
    RenderObject? node = object.parent;
    while (node != null && node != this) {
      node = node.parent;
    }
    return node == this ? object : null;
  }
}

enum FeedRowPlace {
  below,

  shown,

  notYet,
}

FeedRowPlace? feedRowPlace(GlobalKey key) {
  final box = key.currentContext?.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  final Object? viewport = RenderAbstractViewport.maybeOf(box);
  if (viewport is! RenderBox || !viewport.hasSize) return null;
  final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
  final bottom = top + box.size.height;
  final height = viewport.size.height;
  if (top >= height) return FeedRowPlace.below;
  if (bottom > 0 && bottom <= height + 0.5) return FeedRowPlace.shown;
  if (top <= 0 && bottom >= height) return FeedRowPlace.shown;
  return FeedRowPlace.notYet;
}
