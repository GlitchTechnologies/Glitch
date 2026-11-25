import 'package:flutter/material.dart';

import '../models/server.dart';
import '../models/voice_pass.dart';
import '../theme/app_theme.dart';
import 'glitch_hover_row.dart';
import 'mouse_draggable.dart';



class LayoutDrag {
  final Room? room;
  final RoomCategory? category;

  const LayoutDrag.room(Room this.room) : category = null;
  const LayoutDrag.category(RoomCategory this.category) : room = null;
}

Widget _rowFeedback(double width, Widget row) => Material(
  type: MaterialType.transparency,
  child: SizedBox(width: width, child: row),
);


class LayoutDraggable extends StatelessWidget {
  final LayoutDrag data;
  final bool enabled;
  final VoidCallback? onStarted;

  final VoidCallback? onEnded;
  final Widget child;

  const LayoutDraggable({
    super.key,
    required this.data,
    required this.enabled,
    this.onStarted,
    this.onEnded,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return LayoutBuilder(
      builder: (context, constraints) => MouseDraggable<LayoutDrag>(
        data: data,
        dragAnchorStrategy: childDragAnchorStrategy,
        onDragStarted: onStarted,
        onDragEnd: (_) => onEnded?.call(),
        feedback: _rowFeedback(constraints.maxWidth, child),
        childWhenDragging: Opacity(opacity: 0.4, child: child),
        child: child,
      ),
    );
  }
}


class LayoutDropZone extends StatefulWidget {
  final bool Function(LayoutDrag drag, bool before) accepts;
  final void Function(LayoutDrag drag, bool before) onDrop;

  final double indent;
  final Widget child;

  const LayoutDropZone({
    super.key,
    required this.accepts,
    required this.onDrop,
    required this.indent,
    required this.child,
  });

  @override
  State<LayoutDropZone> createState() => _LayoutDropZoneState();
}

class _LayoutDropZoneState extends State<LayoutDropZone> {
  bool? _before;

  bool? _upperHalf(Offset pointer) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.globalToLocal(pointer).dy < box.size.height / 2;
  }

  void _set(bool? before) {
    if (before != _before) setState(() => _before = before);
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<LayoutDrag>(
      onWillAcceptWithDetails: (_) => true,
      onMove: (d) {
        final upper = _upperHalf(d.offset);
        _set(upper != null && widget.accepts(d.data, upper) ? upper : null);
      },
      onLeave: (_) => _set(null),
      onAcceptWithDetails: (d) {
        final before = _before;
        _set(null);
        if (before != null) widget.onDrop(d.data, before);
      },
      builder: (context, candidate, rejected) => Stack(
        children: [
          KeyedSubtree(key: const ValueKey('row'), child: widget.child),
          if (_before != null)
            Positioned(
              key: const ValueKey('line'),
              left: widget.indent,
              right: 8,
              top: _before! ? 0 : null,
              bottom: _before! ? null : 0,
              child: IgnorePointer(
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: GlitchColors.accentBlue,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}


class VoiceMemberDrag {
  final VoiceStateInfo member;
  final int fromRoomId;

  const VoiceMemberDrag(this.member, this.fromRoomId);
}

class VoiceMemberDraggable extends StatelessWidget {
  final VoiceMemberDrag data;
  final bool enabled;
  final Widget feedback;
  final Widget child;

  const VoiceMemberDraggable({
    super.key,
    required this.data,
    required this.enabled,
    required this.feedback,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return LayoutBuilder(
      builder: (context, constraints) => MouseDraggable<VoiceMemberDrag>(
        data: data,
        dragAnchorStrategy: childDragAnchorStrategy,
        feedback: _rowFeedback(constraints.maxWidth, feedback),
        childWhenDragging: Opacity(opacity: 0.4, child: child),
        child: child,
      ),
    );
  }
}

class VoiceMemberDropZone extends StatelessWidget {
  final bool Function(VoiceMemberDrag drag) accepts;
  final void Function(VoiceMemberDrag drag) onDrop;
  final Widget child;

  const VoiceMemberDropZone({
    super.key,
    required this.accepts,
    required this.onDrop,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<VoiceMemberDrag>(
      onWillAcceptWithDetails: (d) => accepts(d.data),
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, candidate, rejected) {
        final highlighted = candidate.isNotEmpty;
        final radius = BorderRadius.circular(GlitchHoverRow.radius);
        return Stack(
          children: [
            Positioned.fill(
              key: const ValueKey('fill'),
              child: IgnorePointer(
                child: Padding(
                  padding: GlitchHoverRow.defaultHighlightInset,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: highlighted ? GlitchColors.accentBlue.withOpacity(0.05) : Colors.transparent,
                      borderRadius: radius,
                    ),
                  ),
                ),
              ),
            ),
            KeyedSubtree(key: const ValueKey('content'), child: child),
            Positioned.fill(
              key: const ValueKey('outline'),
              child: IgnorePointer(
                child: Padding(
                  padding: GlitchHoverRow.defaultHighlightInset,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      border: highlighted ? Border.all(color: GlitchColors.accentBlue, width: 2) : null,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
