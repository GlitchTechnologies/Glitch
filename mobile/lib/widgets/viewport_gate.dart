import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class ViewportGate extends StatefulWidget {
  const ViewportGate({super.key, required this.placeholder, required this.builder});

  final Widget placeholder;
  final WidgetBuilder builder;

  @override
  State<ViewportGate> createState() => _ViewportGateState();
}

const double _kShowWithin = 1.0;

const double _kHideBeyond = 2.0;

class _ViewportGateState extends State<ViewportGate> {
  ScrollPosition? _position;
  Listenable? _relayout;
  bool _shown = false;
  bool _checkScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _position) {
      _position?.removeListener(_check);
      _position = position;
      _position?.addListener(_check);
    }
    final relayout = context.dependOnInheritedWidgetOfExactType<ViewportGateScope>()?.relayout;
    if (relayout != _relayout) {
      _relayout?.removeListener(_scheduleCheck);
      _relayout = relayout;
      _relayout?.addListener(_scheduleCheck);
    }
    if (_position == null) {
      _shown = true;
    } else {
      _scheduleCheck();
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_check);
    _relayout?.removeListener(_scheduleCheck);
    super.dispose();
  }

  void _scheduleCheck() {
    if (_checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      _check();
    });
  }

  void _check() {
    if (!mounted) return;
    final position = _position;
    final box = context.findRenderObject();
    if (position == null || box is! RenderBox || !box.attached || !box.hasSize) return;
    if (!position.hasPixels || !position.hasViewportDimension) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    final a = viewport.getOffsetToReveal(box, 0.0).offset;
    final b = viewport.getOffsetToReveal(box, 1.0).offset;
    final from = a < b ? a : b;
    final to = a < b ? b : a;
    final pixels = position.pixels;
    final screen = position.viewportDimension;
    final margin = screen * (_shown ? _kHideBeyond : _kShowWithin);
    final near = pixels >= from - margin && pixels <= to + margin;
    if (near != _shown) setState(() => _shown = near);
  }

  @override
  Widget build(BuildContext context) => _shown ? widget.builder(context) : widget.placeholder;
}

class ViewportGateScope extends InheritedWidget {
  const ViewportGateScope({super.key, required this.relayout, required super.child});

  final Listenable relayout;

  @override
  bool updateShouldNotify(ViewportGateScope old) => relayout != old.relayout;
}
