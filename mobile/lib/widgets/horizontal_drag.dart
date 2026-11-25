import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

enum DragSide { left, right }

const double _kWrongWaySlop = 6.0;

class SideDragRecognizer extends HorizontalDragGestureRecognizer {
  SideDragRecognizer({required this.side});

  DragSide side;

  final Map<int, double> _moved = <int, double>{};
  final Set<int> _accepted = <int>{};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _moved[event.pointer] = 0;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    final pointer = event.pointer;
    if (event is PointerMoveEvent && !_accepted.contains(pointer) && _moved.containsKey(pointer)) {
      final total = _moved[pointer]! + event.delta.dx;
      _moved[pointer] = total;
      final wrongWay = side == DragSide.left ? total > _kWrongWaySlop : total < -_kWrongWaySlop;
      if (wrongWay) {
        _moved.remove(pointer);
        resolvePointer(pointer, GestureDisposition.rejected);
        stopTrackingPointer(pointer);
        return;
      }
    }
    super.handleEvent(event);
  }

  @override
  void acceptGesture(int pointer) {
    _accepted.add(pointer);
    super.acceptGesture(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _moved.clear();
    _accepted.clear();
    super.didStopTrackingLastPointer(pointer);
  }

  @override
  void dispose() {
    _moved.clear();
    _accepted.clear();
    super.dispose();
  }
}

class SideDragDetector extends StatelessWidget {
  const SideDragDetector({
    super.key,
    required this.side,
    this.enabled = true,
    this.onStart,
    this.onUpdate,
    this.onEnd,
    this.onCancel,
    this.behavior = HitTestBehavior.translucent,
    required this.child,
  });

  final DragSide side;

  final bool enabled;
  final GestureDragStartCallback? onStart;
  final GestureDragUpdateCallback? onUpdate;
  final GestureDragEndCallback? onEnd;
  final GestureDragCancelCallback? onCancel;
  final HitTestBehavior behavior;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: behavior,
      gestures: !enabled
          ? const <Type, GestureRecognizerFactory>{}
          : <Type, GestureRecognizerFactory>{
              SideDragRecognizer: GestureRecognizerFactoryWithHandlers<SideDragRecognizer>(
                () => SideDragRecognizer(side: side),
                (SideDragRecognizer r) {
                  r
                    ..side = side
                    ..onStart = onStart
                    ..onUpdate = onUpdate
                    ..onEnd = onEnd
                    ..onCancel = onCancel;
                },
              ),
            },
      child: child,
    );
  }
}

class SwipeBackScope extends StatefulWidget {
  const SwipeBackScope({
    super.key,
    required this.enabled,
    required this.onBack,
    required this.child,
  });

  final bool enabled;

  final VoidCallback onBack;
  final Widget child;

  @override
  State<SwipeBackScope> createState() => _SwipeBackScopeState();
}

const double _kBackFraction = 0.33;

const double _kBackFlingSpeed = 700.0;

const double _kBackFlingMinDistance = 28.0;

const double _kHeldValue = 0.999;

const Duration _kSettleDuration = Duration(milliseconds: 220);

class _SwipeBackScopeState extends State<SwipeBackScope> with SingleTickerProviderStateMixin {
  final ValueNotifier<double> _offset = ValueNotifier<double>(0);

  late final AnimationController _settle = AnimationController(vsync: this, duration: _kSettleDuration);
  double _settleFrom = 0;
  double _settleTarget = 0;
  VoidCallback? _afterSettle;

  ModalRoute<dynamic>? _route;

  NavigatorState? _holdingNavigator;

  double _dragged = 0;

  @override
  void initState() {
    super.initState();
    _settle.addListener(() {
      final t = Curves.easeOutCubic.transform(_settle.value);
      _offset.value = _settleFrom + (_settleTarget - _settleFrom) * t;
    });
    _settle.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      final done = _afterSettle;
      _afterSettle = null;
      done?.call();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    _releaseHold(restore: true);
    _settle.dispose();
    _offset.dispose();
    super.dispose();
  }

  double get _width => MediaQuery.sizeOf(context).width;

  bool _hold() {
    final route = _route;
    final controller = route?.controller;
    if (route == null || controller == null) return false;
    if (!route.isCurrent || route.isFirst || !controller.isCompleted) return false;
    final navigator = route.navigator;
    if (navigator == null) return false;
    navigator.didStartUserGesture();
    controller.value = _kHeldValue;
    _holdingNavigator = navigator;
    return true;
  }

  void _releaseHold({required bool restore}) {
    final navigator = _holdingNavigator;
    if (navigator == null) return;
    _holdingNavigator = null;
    final route = _route;
    final controller = route?.controller;
    if (restore && route != null && route.isActive && controller != null && !controller.isAnimating) {
      controller.value = 1.0;
    }
    navigator.didStopUserGesture();
  }

  void _settleTo(double target, {VoidCallback? then}) {
    _settleFrom = _offset.value;
    _settleTarget = target;
    _afterSettle = then;
    _settle.forward(from: 0);
  }

  void _onStart(DragStartDetails _) {
    _settle.stop();
    _afterSettle = null;
    _dragged = _offset.value;
    if (_holdingNavigator == null) _hold();
  }

  void _onUpdate(DragUpdateDetails d) {
    _dragged = (_dragged + d.delta.dx).clamp(0.0, _width).toDouble();
    if (_holdingNavigator != null) _offset.value = _dragged;
  }

  void _onEnd(DragEndDetails d) {
    final fling = d.velocity.pixelsPerSecond.dx;
    final far = _dragged >= _width * _kBackFraction ||
        (fling >= _kBackFlingSpeed && _dragged >= _kBackFlingMinDistance);
    far ? _commit() : _cancel();
  }

  void _onCancel() => _cancel();

  void _commit() {
    final navigator = _holdingNavigator;
    final controller = _route?.controller;
    _dragged = 0;
    if (navigator == null) {
      widget.onBack();
      return;
    }
    _holdingNavigator = null;
    _settleTo(_width);
    widget.onBack();
    if (controller != null && controller.isAnimating) {
      late AnimationStatusListener onStatus;
      onStatus = (_) {
        controller.removeStatusListener(onStatus);
        navigator.didStopUserGesture();
      };
      controller.addStatusListener(onStatus);
    } else {
      navigator.didStopUserGesture();
    }
  }

  void _cancel() {
    _dragged = 0;
    if (_holdingNavigator == null) return;
    _settleTo(0, then: () => _releaseHold(restore: true));
  }

  @override
  Widget build(BuildContext context) {
    return _SwipeBackHandle(
      enabled: widget.enabled,
      onStart: _onStart,
      onUpdate: _onUpdate,
      onEnd: _onEnd,
      onCancel: _onCancel,
      child: ValueListenableBuilder<double>(
        valueListenable: _offset,
        child: widget.child,
        builder: (_, dx, child) => Transform.translate(offset: Offset(dx, 0), child: child),
      ),
    );
  }
}

class _SwipeBackHandle extends InheritedWidget {
  const _SwipeBackHandle({
    required this.enabled,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
    required super.child,
  });

  final bool enabled;
  final GestureDragStartCallback onStart;
  final GestureDragUpdateCallback onUpdate;
  final GestureDragEndCallback onEnd;
  final GestureDragCancelCallback onCancel;

  @override
  bool updateShouldNotify(_SwipeBackHandle old) => enabled != old.enabled;
}

class SwipeBackArea extends StatelessWidget {
  const SwipeBackArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final handle = context.dependOnInheritedWidgetOfExactType<_SwipeBackHandle>();
    if (handle == null) return child;
    return SideDragDetector(
      enabled: handle.enabled,
      side: DragSide.right,
      onStart: handle.onStart,
      onUpdate: handle.onUpdate,
      onEnd: handle.onEnd,
      onCancel: handle.onCancel,
      child: child,
    );
  }
}
