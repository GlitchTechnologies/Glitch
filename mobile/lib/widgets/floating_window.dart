import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/adaptive_open.dart' show isWideLayout;

enum FloatingCorner { topLeft, topRight, bottomLeft, bottomRight }

class FloatingWindow extends StatefulWidget {
  final Size size;

  final double scale;

  final ValueChanged<double>? onScaleChanged;

  final FloatingCorner corner;

  final ValueChanged<FloatingCorner> onCornerChanged;

  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  final Widget Function(BuildContext context, Size size) builder;

  const FloatingWindow({
    super.key,
    required this.size,
    required this.corner,
    required this.onCornerChanged,
    required this.builder,
    this.scale = 1,
    this.onScaleChanged,
    this.onTap,
    this.onDoubleTap,
  });

  static const double minScale = 0.71;
  static const double maxScale = 2.2;

  @override
  State<FloatingWindow> createState() => _FloatingWindowState();
}

class _FloatingWindowState extends State<FloatingWindow> with SingleTickerProviderStateMixin {
  static const _wideInset = 24.0;
  static const _narrowInset = 12.0;
  static const _narrowBottomGap = 120.0;

  static const _resizeGrip = 24.0;

  late final AnimationController _snapCtrl;
  Animation<Offset>? _snapAnim;

  Offset? _dragOffset;

  double? _resizeStartScale;
  Offset _resizeAccum = Offset.zero;

  Size get _size => widget.size * widget.scale;

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))
      ..addListener(() => setState(() {}))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) setState(() => _snapAnim = null);
      });
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  Offset _cornerOffset(FloatingCorner corner, Size screen, EdgeInsets padding, bool wide) {
    final size = _size;
    final side = wide ? _wideInset : _narrowInset;
    final top = padding.top + side;
    final bottom = wide ? padding.bottom + _wideInset : padding.bottom + _narrowBottomGap;
    final left = corner == FloatingCorner.topLeft || corner == FloatingCorner.bottomLeft;
    final up = corner == FloatingCorner.topLeft || corner == FloatingCorner.topRight;
    final x = left ? side : screen.width - size.width - side;
    final y = up ? top : screen.height - size.height - bottom;
    return Offset(math.max(side, x), math.max(top, y));
  }

  FloatingCorner _nearest(Offset o, Size screen) {
    final size = _size;
    final left = o.dx + size.width / 2 < screen.width / 2;
    final up = o.dy + size.height / 2 < screen.height / 2;
    return up
        ? (left ? FloatingCorner.topLeft : FloatingCorner.topRight)
        : (left ? FloatingCorner.bottomLeft : FloatingCorner.bottomRight);
  }

  Offset _clamp(Offset o, Size screen) => Offset(
        o.dx.clamp(0, math.max(0, screen.width - _size.width)),
        o.dy.clamp(0, math.max(0, screen.height - _size.height)),
      );

  void _resize(Offset delta) {
    final start = _resizeStartScale;
    final onScale = widget.onScaleChanged;
    if (start == null || onScale == null) return;
    _resizeAccum += delta;
    final long = math.max(widget.size.width, widget.size.height);
    final next = (start + (_resizeAccum.dy - _resizeAccum.dx) / (2 * long))
        .clamp(FloatingWindow.minScale, FloatingWindow.maxScale);
    onScale(next.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final wide = isWideLayout(context);
    final size = _size;
    final offset = _dragOffset ?? _snapAnim?.value ?? _cornerOffset(widget.corner, screen, padding, wide);
    return Positioned(
      left: offset.dx,
      top: offset.dy,
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        onPanStart: (_) {
          _snapCtrl.stop();
          setState(() {
            _dragOffset = offset;
            _snapAnim = null;
          });
        },
        onPanUpdate: (d) {
          setState(() => _dragOffset = _clamp((_dragOffset ?? offset) + d.delta, screen));
        },
        onPanEnd: (_) {
          final from = _dragOffset ?? offset;
          final corner = _nearest(from, screen);
          final target = _cornerOffset(corner, screen, padding, wide);
          setState(() {
            _dragOffset = null;
            _snapAnim = Tween<Offset>(begin: from, end: target).animate(
              CurvedAnimation(parent: _snapCtrl, curve: Curves.easeOutCubic),
            );
          });
          _snapCtrl.forward(from: 0);
          widget.onCornerChanged(corner);
        },
        child: SizedBox.fromSize(
          size: size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.builder(context, size),
              if (widget.onScaleChanged != null)
                Positioned(
                  left: 0,
                  bottom: 0,
                  width: _resizeGrip,
                  height: _resizeGrip,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeUpRightDownLeft,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (_) {
                        _resizeStartScale = widget.scale;
                        _resizeAccum = Offset.zero;
                      },
                      onPanUpdate: (d) => _resize(d.delta),
                      onPanEnd: (_) => _resizeStartScale = null,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
