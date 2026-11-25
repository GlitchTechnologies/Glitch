import 'package:flutter/widgets.dart';

_WsLifecycleWakeup? _observer;

void bindWsWakeup(void Function(Duration hidden) onWake) {
  if (_observer != null) return;
  final observer = _WsLifecycleWakeup(onWake);
  _observer = observer;
  WidgetsBinding.instance.addObserver(observer);
}

class _WsLifecycleWakeup with WidgetsBindingObserver {
  _WsLifecycleWakeup(this._onWake);

  final void Function(Duration hidden) _onWake;

  DateTime? _pausedAt;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final pausedAt = _pausedAt;
      _pausedAt = null;
      _onWake(pausedAt == null ? Duration.zero : DateTime.now().difference(pausedAt));
    }
  }
}
