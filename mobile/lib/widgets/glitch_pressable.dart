import 'package:flutter/material.dart';


class GlitchPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const GlitchPressable({super.key, required this.child, this.onTap});

  @override
  State<GlitchPressable> createState() => _GlitchPressableState();
}

class _GlitchPressableState extends State<GlitchPressable> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween<double>(begin: 1.0, end: 0.96).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _opacity = Tween<double>(begin: 1.0, end: 0.85).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _pressDown() {
    if (widget.onTap != null) _ctrl.forward();
  }

  void _pressUp() {
    if (widget.onTap != null) _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return ClickableCursor(
      enabled: widget.onTap != null,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _pressDown(),
        onPointerUp: (_) => _pressUp(),
        onPointerCancel: (_) => _pressUp(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, child) => Transform.scale(
              scale: _scale.value,
              child: Opacity(opacity: _opacity.value, child: child),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class ClickableCursor extends StatelessWidget {
  final Widget child;
  final bool enabled;

  const ClickableCursor({super.key, required this.child, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: enabled
          ? DefaultSelectionStyle.merge(mouseCursor: SystemMouseCursors.click, child: child)
          : child,
    );
  }
}

class GlitchHoverArea extends StatefulWidget {
  final Widget Function(BuildContext context, bool active) builder;
  final VoidCallback? onTap;

  final bool hoverWhenDisabled;

  final ValueChanged<bool>? onHoverChanged;

  const GlitchHoverArea({
    super.key,
    required this.builder,
    required this.onTap,
    this.hoverWhenDisabled = false,
    this.onHoverChanged,
  });

  @override
  State<GlitchHoverArea> createState() => _GlitchHoverAreaState();
}

class _GlitchHoverAreaState extends State<GlitchHoverArea> {
  bool _active = false;

  void _set(bool v) {
    if (_active == v) return;
    setState(() => _active = v);
    if (widget.onTap != null || widget.hoverWhenDisabled) widget.onHoverChanged?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => _set(true),
      onExit: (_) => _set(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: enabled ? () => _set(false) : null,
        child: enabled
            ? DefaultSelectionStyle.merge(
                mouseCursor: SystemMouseCursors.click,
                child: widget.builder(context, _active),
              )
            : widget.builder(context, widget.hoverWhenDisabled && _active),
      ),
    );
  }
}
