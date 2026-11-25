import 'package:flutter/material.dart';

class ResizeHandle extends StatefulWidget {
  final Axis axis;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDrag;
  final VoidCallback? onDragEnd;

  final VoidCallback? onReset;

  const ResizeHandle({
    super.key,
    required this.axis,
    required this.onDragStart,
    required this.onDrag,
    this.onDragEnd,
    this.onReset,
  });

  @override
  State<ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<ResizeHandle> {
  Offset? _origin;

  OverlayEntry? _shield;

  MouseCursor get _cursor =>
      widget.axis == Axis.horizontal ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow;

  void _start(Offset position) {
    _origin = position;
    _removeShield();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay != null) {
      final cursor = _cursor;
      _shield = OverlayEntry(
        builder: (_) => Positioned.fill(child: MouseRegion(cursor: cursor, opaque: true)),
      );
      overlay.insert(_shield!);
    }
    widget.onDragStart();
  }

  void _update(Offset position) {
    final origin = _origin;
    if (origin == null) return;
    final shift = position - origin;
    widget.onDrag(widget.axis == Axis.horizontal ? shift.dx : shift.dy);
  }

  void _finish() {
    final wasDragging = _origin != null;
    _origin = null;
    _removeShield();
    if (wasDragging) widget.onDragEnd?.call();
  }

  void _removeShield() {
    _shield?.remove();
    _shield = null;
  }

  @override
  void dispose() {
    _removeShield();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.axis == Axis.horizontal;
    return MouseRegion(
      cursor: _cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: widget.onReset,
        onHorizontalDragStart: horizontal ? (d) => _start(d.globalPosition) : null,
        onHorizontalDragUpdate: horizontal ? (d) => _update(d.globalPosition) : null,
        onHorizontalDragEnd: horizontal ? (_) => _finish() : null,
        onHorizontalDragCancel: horizontal ? _finish : null,
        onVerticalDragStart: horizontal ? null : (d) => _start(d.globalPosition),
        onVerticalDragUpdate: horizontal ? null : (d) => _update(d.globalPosition),
        onVerticalDragEnd: horizontal ? null : (_) => _finish(),
        onVerticalDragCancel: horizontal ? null : _finish,
      ),
    );
  }
}
