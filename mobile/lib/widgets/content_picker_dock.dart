import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_theme.dart';

class ContentPickerDock extends StatefulWidget {
  final double height;

  final double maxHeight;

  final bool instant;

  final ValueNotifier<double> space;

  final VoidCallback onClosed;

  final Widget child;

  const ContentPickerDock({
    super.key,
    required this.height,
    required this.maxHeight,
    required this.instant,
    required this.space,
    required this.onClosed,
    required this.child,
  });

  @override
  State<ContentPickerDock> createState() => ContentPickerDockState();
}

class ContentPickerDockState extends State<ContentPickerDock> with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 220);

  late final AnimationController _h = AnimationController(
    vsync: this,
    lowerBound: 0,
    upperBound: 100000,
    value: widget.instant ? widget.height : 0,
  )..addListener(_onHeight);

  final ValueNotifier<double> _dim = ValueNotifier(0);

  bool _closing = false;

  bool _searchFocused = false;

  bool _pullingDown = false;

  @override
  void initState() {
    super.initState();
    _onHeight();
    if (!widget.instant) _animateTo(widget.height);
  }

  @override
  void didUpdateWidget(ContentPickerDock old) {
    super.didUpdateWidget(old);
    if (_closing || _h.isAnimating) return;
    if (_h.value == old.height && widget.height != old.height) _h.value = widget.height;
    if (_h.value == old.maxHeight && widget.maxHeight != old.maxHeight) _h.value = widget.maxHeight;
  }

  @override
  void dispose() {
    _h.dispose();
    _dim.dispose();
    super.dispose();
  }

  /// Высота поменялась — обновить место под строкой ввода. Посреди сборки
  /// кадра (первое построение, смена высоты в didUpdateWidget) менять его
  /// нельзя: строка ввода уже собрана в этом кадре — тогда после кадра.
  void _onHeight() {
    final span = widget.maxHeight - widget.height;
    _dim.value = span <= 0 ? 0.0 : ((_h.value - widget.height) / span).clamp(0.0, 1.0);
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks || phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.space.value = math.min(_h.value, widget.height);
      });
      return;
    }
    widget.space.value = math.min(_h.value, widget.height);
  }

  void _animateTo(double target) => _h.animateTo(target, duration: _duration, curve: Curves.easeOutCubic);

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    FocusScope.of(context).unfocus();
    await _h.animateTo(0, duration: _duration, curve: Curves.easeOutCubic);
    if (mounted) widget.onClosed();
  }

  bool get expanded => _h.value > widget.height + 1;

  void collapse() => _animateTo(widget.height);

  void _expand() => _animateTo(widget.maxHeight);

  void _onDragUpdate(DragUpdateDetails d) {
    if (_closing) return;
    _h.value = (_h.value - d.delta.dy).clamp(0.0, widget.maxHeight);
  }

  void _onDragEnd(DragEndDetails d) {
    if (_closing) return;
    final v = d.velocity.pixelsPerSecond.dy; // > 0 — вниз
    final h = _h.value;
    final h0 = widget.height;
    if (v < -700) {
      h < h0 ? _animateTo(h0) : _expand();
    } else if (v.abs() <= 700 && h > h0 + (widget.maxHeight - h0) / 2) {
      _expand();
    } else if (h < h0 && (v > 700 || h < h0 * 0.6)) {
      close();
    } else {
      _animateTo(h0);
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (_closing || n.metrics.axis != Axis.vertical) return false;
    if (n is OverscrollNotification && n.dragDetails != null && n.overscroll < 0 && (expanded || _pullingDown)) {
      _pullingDown = true;
      _h.value = (_h.value + n.overscroll).clamp(widget.height, widget.maxHeight);
    } else if (n is ScrollUpdateNotification && _pullingDown && n.dragDetails != null && (n.scrollDelta ?? 0) > 0) {
      _h.value = (_h.value + n.scrollDelta!).clamp(widget.height, widget.maxHeight);
    } else if (n is ScrollEndNotification && _pullingDown) {
      _pullingDown = false;
      final v = n.dragDetails?.velocity.pixelsPerSecond.dy ?? 0;
      final mid = widget.height + (widget.maxHeight - widget.height) / 2;
      if (v > 700 || (v.abs() <= 700 && _h.value < mid)) {
        collapse();
      } else {
        _expand();
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    return StatusBarDimFollow(
      level: _dim,
      child: AnimatedBuilder(
      animation: _h,
      builder: (context, child) {
        final h = _h.value;
        final dim = _dim.value;
        final bottomEdge = _searchFocused ? math.max(keyboard, safeBottom) : safeBottom;
        final lift = bottomEdge - safeBottom;
        return Stack(
          children: [
            if (dim > 0)
              Positioned.fill(
                key: const ValueKey('dim'),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: collapse,
                  child: ColoredBox(color: Colors.black54.withOpacity(Colors.black54.opacity * dim)),
                ),
              ),
            Positioned(
              key: const ValueKey('panel'),
              left: 0,
              right: 0,
              bottom: bottomEdge,
              height: math.min(h, widget.maxHeight - lift).clamp(0.0, double.infinity),
              child: child!,
            ),
          ],
        );
      },
      child: GestureDetector(
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        child: Focus(
          onFocusChange: (has) {
            setState(() => _searchFocused = has);
            if (has && !expanded && !_closing) _expand();
          },
          canRequestFocus: false,
          skipTraversal: true,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: GlitchColors.bgPickerNarrow,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(top: BorderSide(color: GlitchColors.border)),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: widget.child,
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: GlitchColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}
