import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../core/adaptive_open.dart';
import '../core/shell_controller.dart';

class CenterPlace extends ChangeNotifier {
  final List<Route<dynamic>> _routes = [];

  late final NavigatorObserver observer = _CenterRouteObserver(this);

  List<({Object? slotKey, Object? scope})> layers({required bool wide}) => [
        if (_routes.isNotEmpty)
          (
            slotKey: (_routes.last.settings.arguments as CenterRouteTag).slotKey,
            scope: (_routes.last.settings.arguments as CenterRouteTag).scope,
          ),
        if (wide && shellController.mainKey != null)
          (slotKey: shellController.mainKey, scope: shellController.mainScope),
      ];

  void _changed() {
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => notifyListeners());
    } else {
      notifyListeners();
    }
  }
}

class _CenterRouteObserver extends NavigatorObserver {
  final CenterPlace _place;

  _CenterRouteObserver(this._place);

  bool _isCenter(Route<dynamic>? route) => route?.settings.arguments is CenterRouteTag;

  void _add(Route<dynamic>? route) {
    if (!_isCenter(route)) return;
    _place._routes.add(route!);
    _place._changed();
  }

  void _remove(Route<dynamic>? route) {
    if (!_isCenter(route)) return;
    _place._routes.remove(route);
    _place._changed();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _remove(oldRoute);
    _add(newRoute);
  }
}

final centerPlace = CenterPlace();
