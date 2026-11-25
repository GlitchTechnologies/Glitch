import 'dart:async';

import 'package:flutter/gestures.dart' show PointerDeviceKind, PointerEnterEvent, PointerExitEvent;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../core/platform_info.dart';
import '../theme/app_theme.dart';
import 'glitch_dialog.dart' show GlitchWindowArrow, glitchWindowShape;
import 'glitch_menu.dart' show glitchOverlayOf, glitchOverlayPoint;

class GlitchTooltip extends StatefulWidget {
  final String? message;
  final GlitchTooltipSide side;
  final Widget child;

  final Widget? extra;

  final Widget? content;

  final Rect Function(Size size)? target;

  const GlitchTooltip({
    super.key,
    required this.message,
    this.side = GlitchTooltipSide.top,
    this.extra,
    this.target,
    required this.child,
  }) : content = null;

  const GlitchTooltip.rich({
    super.key,
    required Widget content,
    this.side = GlitchTooltipSide.top,
    this.target,
    required this.child,
  }) : content = content, message = null, extra = null;

  static void hide() => _GlitchTooltipState._shown?._hide();

  @override
  State<GlitchTooltip> createState() => _GlitchTooltipState();
}

enum GlitchTooltipSide { top, bottom, left, right }

const Duration _kDelay = Duration(milliseconds: 100);
const Duration _kHandoff = Duration(milliseconds: 400);
const double _kGap = 4;
const double _kScreenMargin = 8;

const double kTooltipScale = 1.1;

const double _kMaxTextWidth = 216 * kTooltipScale;
const double _kRadius = 7 * kTooltipScale;
const EdgeInsets _kPadding = EdgeInsets.symmetric(horizontal: 11 * kTooltipScale, vertical: 7 * kTooltipScale);

class _GlitchTooltipState extends State<GlitchTooltip> {
  static _GlitchTooltipState? _shown;
  static DateTime? _lastHidden;

  Timer? _timer;
  OverlayEntry? _entry;
  ScrollPosition? _scroll;

  bool get _hasMessage => widget.content != null || (widget.message?.isNotEmpty ?? false);

  @override
  void didUpdateWidget(GlitchTooltip old) {
    super.didUpdateWidget(old);
    if (!_hasMessage) {
      _hide();
    } else if (widget.message != old.message ||
        widget.side != old.side ||
        widget.extra != old.extra ||
        widget.content != old.content ||
        widget.target != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _entry?.markNeedsBuild());
    }
  }

  @override
  void deactivate() {
    _hide();
    super.deactivate();
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  void _onEnter(PointerEnterEvent e) {
    if (e.kind != PointerDeviceKind.mouse || !_hasMessage) return;
    final last = _lastHidden;
    final quick = _shown != null || (last != null && DateTime.now().difference(last) < _kHandoff);
    _timer?.cancel();
    if (quick) {
      _show();
    } else {
      _timer = Timer(_kDelay, _show);
    }
  }

  void _onExit(PointerExitEvent e) => _hide();

  void _show() {
    _timer = null;
    if (!mounted || !_hasMessage || _entry != null) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return;
    _shown?._hide();
    final overlay = glitchOverlayOf(context);
    var anchor = _anchorIn(overlay, box);
    _scroll = Scrollable.maybeOf(context)?.position?..addListener(_hide);
    _entry = OverlayEntry(
      builder: (_) {
        // Подпись, сторона и место читаются при каждой сборке плашки — смена
        // подписи или места у видимой подсказки (didUpdateWidget) доходит до
        // неё. Элемент на миг без раскладки — остаётся прежнее место.
        final now = context.findRenderObject();
        if (mounted && now is RenderBox && now.hasSize && now.attached) anchor = _anchorIn(overlay, now);
        return IgnorePointer(
          child: _TooltipBubble(
              anchor: anchor, side: widget.side, message: widget.message ?? '', extra: widget.extra,
              content: widget.content),
        );
      },
    );
    overlay.insert(_entry!);
    _shown = this;
  }

  Rect _anchorIn(OverlayState overlay, RenderBox box) {
    final part = widget.target?.call(box.size) ?? Offset.zero & box.size;
    return glitchOverlayPoint(overlay, box.localToGlobal(part.topLeft)) & part.size;
  }

  void _hide() {
    _timer?.cancel();
    _timer = null;
    _scroll?.removeListener(_hide);
    _scroll = null;
    final entry = _entry;
    if (entry == null) return;
    _entry = null;
    entry.remove();
    if (identical(_shown, this)) _shown = null;
    _lastHidden = DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    if (!hasPointerInput) return widget.child;
    return MouseRegion(
      opaque: false,
      onEnter: _onEnter,
      onExit: _onExit,
      child: widget.child,
    );
  }
}

class _TooltipBubble extends StatefulWidget {
  final Rect anchor;
  final GlitchTooltipSide side;
  final String message;
  final Widget? extra;
  final Widget? content;
  const _TooltipBubble({required this.anchor, required this.side, required this.message, this.extra, this.content});

  @override
  State<_TooltipBubble> createState() => _TooltipBubbleState();
}

class _TooltipBubbleState extends State<_TooltipBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 120))..forward();
  late final Animation<double> _progress = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium!.merge(TextStyle(
          color: GlitchColors.textPrimary,
          fontSize: 12.6 * kTooltipScale,
          fontWeight: FontWeight.w600,
          height: 1.25,
        ));
    final extra = widget.extra;
    return _BubbleLayout(
      anchor: widget.anchor,
      side: widget.side,
      color: GlitchColors.bgMenu,
      progress: _progress,
      child: Padding(
        padding: _kPadding,
        child: DefaultTextStyle(
          style: style,
          textAlign: extra == null ? TextAlign.center : TextAlign.start,
          child: widget.content == null ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: extra == null ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _kMaxTextWidth),
                child: Text(widget.message),
              ),
              if (extra != null) extra,
            ],
          ) : ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kMaxTextWidth),
            child: widget.content!,
          ),
        ),
      ),
    );
  }
}

class _BubbleLayout extends SingleChildRenderObjectWidget {
  final Rect anchor;
  final GlitchTooltipSide side;
  final Color color;
  final Animation<double> progress;

  const _BubbleLayout({
    required this.anchor,
    required this.side,
    required this.color,
    required this.progress,
    required super.child,
  });

  @override
  _RenderBubble createRenderObject(BuildContext context) =>
      _RenderBubble(anchor: anchor, side: side, color: color, progress: progress);

  @override
  void updateRenderObject(BuildContext context, _RenderBubble r) => r
    ..anchor = anchor
    ..side = side
    ..color = color;
}

class _RenderBubble extends RenderProxyBox {
  _RenderBubble({
    required Rect anchor,
    required GlitchTooltipSide side,
    required Color color,
    required this.progress,
  })  : _anchor = anchor,
        _side = side,
        _color = color;

  final Animation<double> progress;

  Rect _anchor;
  set anchor(Rect v) {
    if (v == _anchor) return;
    _anchor = v;
    markNeedsLayout();
  }

  GlitchTooltipSide _side;
  set side(GlitchTooltipSide v) {
    if (v == _side) return;
    _side = v;
    markNeedsLayout();
  }

  Color _color;
  set color(Color v) {
    if (v == _color) return;
    _color = v;
    markNeedsPaint();
  }

  _Placement? _geo;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    progress.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    progress.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void performLayout() {
    size = constraints.biggest;
    final c = child;
    if (c == null) return;
    c.layout(
      BoxConstraints(
        maxWidth: (size.width - _kScreenMargin * 2).clamp(0.0, double.infinity),
        maxHeight: (size.height - _kScreenMargin * 2).clamp(0.0, double.infinity),
      ),
      parentUsesSize: true,
    );
    _geo = _place(_anchor, _side, c.size, size);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) => false;

  @override
  void paint(PaintingContext context, Offset offset) {
    final c = child;
    final g = _geo;
    if (c == null || g == null) return;
    final t = progress.value;
    final pivot = offset + g.towardAnchor.withinRect(g.rect);
    final scale = 0.94 + 0.06 * t;
    final matrix = Matrix4.translationValues(pivot.dx, pivot.dy, 0)
      ..multiply(Matrix4.diagonal3Values(scale, scale, 1))
      ..multiply(Matrix4.translationValues(-pivot.dx, -pivot.dy, 0));
    context.pushOpacity(offset, (t * 255).round(), (context, offset) {
      context.pushTransform(needsCompositing, offset, matrix, (context, offset) {
        final rect = g.rect.shift(offset);
        final shape = glitchWindowShape(radius: _kRadius, arrow: g.arrow);
        final path = shape.getOuterPath(rect);
        context.canvas.drawShadow(path, const Color(0xFF000000), 8, false);
        context.canvas.drawPath(path, Paint()..color = _color);
        shape.paint(context.canvas, rect);
        context.paintChild(c, rect.topLeft + g.arrowRoom.topLeft);
      });
    });
  }
}

typedef _Placement = ({Rect rect, GlitchWindowArrow arrow, EdgeInsets arrowRoom, Alignment towardAnchor});

_Placement _place(
  Rect anchor,
  GlitchTooltipSide wanted,
  Size body,
  Size screen,
) {
  const h = GlitchWindowArrow.height;
  final vertical = wanted == GlitchTooltipSide.top || wanted == GlitchTooltipSide.bottom;
  final along = vertical ? body.height + h + _kGap : body.width + h + _kGap;
  final room = switch (wanted) {
    GlitchTooltipSide.top => (anchor.top - _kScreenMargin, screen.height - anchor.bottom - _kScreenMargin),
    GlitchTooltipSide.bottom => (screen.height - anchor.bottom - _kScreenMargin, anchor.top - _kScreenMargin),
    GlitchTooltipSide.left => (anchor.left - _kScreenMargin, screen.width - anchor.right - _kScreenMargin),
    GlitchTooltipSide.right => (screen.width - anchor.right - _kScreenMargin, anchor.left - _kScreenMargin),
  };
  final side = room.$1 >= along || room.$2 < along
      ? wanted
      : switch (wanted) {
          GlitchTooltipSide.top => GlitchTooltipSide.bottom,
          GlitchTooltipSide.bottom => GlitchTooltipSide.top,
          GlitchTooltipSide.left => GlitchTooltipSide.right,
          GlitchTooltipSide.right => GlitchTooltipSide.left,
        };

  double clampStart(double centered, double length, double limit) =>
      centered.clamp(_kScreenMargin, (limit - _kScreenMargin - length).clamp(_kScreenMargin, double.infinity));
  double arrowAt(double center, double start, double length) => (center - start)
      .clamp(_kRadius + GlitchWindowArrow.width / 2, (length - _kRadius - GlitchWindowArrow.width / 2).clamp(_kRadius + GlitchWindowArrow.width / 2, double.infinity));

  switch (side) {
    case GlitchTooltipSide.top:
    case GlitchTooltipSide.bottom:
      final left = clampStart(anchor.center.dx - body.width / 2, body.width, screen.width);
      final wantedTop = side == GlitchTooltipSide.top ? anchor.top - _kGap - body.height - h : anchor.bottom + _kGap;
      final top = clampStart(wantedTop, body.height + h, screen.height);
      final up = side == GlitchTooltipSide.bottom;
      return (
        rect: Rect.fromLTWH(left, top, body.width, body.height + h),
        arrow: GlitchWindowArrow(edge: up ? AxisDirection.up : AxisDirection.down, at: arrowAt(anchor.center.dx, left, body.width)),
        arrowRoom: EdgeInsets.only(top: up ? h : 0, bottom: up ? 0 : h),
        towardAnchor: up ? Alignment.topCenter : Alignment.bottomCenter,
      );
    case GlitchTooltipSide.left:
    case GlitchTooltipSide.right:
      final top = clampStart(anchor.center.dy - body.height / 2, body.height, screen.height);
      final wantedLeft = side == GlitchTooltipSide.left ? anchor.left - _kGap - body.width - h : anchor.right + _kGap;
      final left = clampStart(wantedLeft, body.width + h, screen.width);
      final pointsLeft = side == GlitchTooltipSide.right;
      return (
        rect: Rect.fromLTWH(left, top, body.width + h, body.height),
        arrow: GlitchWindowArrow(
            edge: pointsLeft ? AxisDirection.left : AxisDirection.right, at: arrowAt(anchor.center.dy, top, body.height)),
        arrowRoom: EdgeInsets.only(left: pointsLeft ? h : 0, right: pointsLeft ? 0 : h),
        towardAnchor: pointsLeft ? Alignment.centerLeft : Alignment.centerRight,
      );
  }
}
