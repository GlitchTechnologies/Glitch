import 'package:flutter/foundation.dart';

import '../models/activity.dart';
import 'websocket_service.dart';

/// Кто кладёт:
///  * загрузчики мест показа — что пришло в поле `activities` ответа
///    ([seed]/[seedAll]): список участников сообщества, карточка участника,
///    профиль, список друзей. Ответ — срез на момент запроса;
///  * событие сокета `presence.activity` — весь список активностей человека
///    (сервер шлёт его тем, кому сообщает «в сети», и самому человеку);
///  * `presence.offline` — ушёл из сети, активностей нет.
/// Последнее пришедшее — правда. Кто событий о человеке не получает (не друг
/// и не собеседник), видит срез, как и «в сети» в панели участников.
class UserActivities extends ChangeNotifier {
  final Map<int, List<UserActivity>> _byUser = {};
  final Map<int, int> _eventVersions = {};
  int _version = 0;
  int _resetVersion = 0;

  int beginSnapshot() => _version;

  bool acceptsSnapshot(int userId, int snapshot) =>
      snapshot >= _resetVersion && (_eventVersions[userId] ?? 0) <= snapshot;

  List<UserActivity> of(int userId) => _byUser[userId] ?? const [];

  void seed(int userId, List<UserActivity> activities, {required int snapshot}) {
    if (!acceptsSnapshot(userId, snapshot)) return;
    if (_put(userId, activities)) notifyListeners();
  }

  void seedAll(Iterable<(int, List<UserActivity>)> entries, {required int snapshot}) {
    var changed = false;
    for (final (userId, activities) in entries) {
      if (acceptsSnapshot(userId, snapshot)) changed = _put(userId, activities) || changed;
    }
    if (changed) notifyListeners();
  }

  bool _put(int userId, List<UserActivity> activities) {
    final before = _byUser[userId] ?? const <UserActivity>[];
    final same = before.length == activities.length &&
        [for (var i = 0; i < before.length; i++) before[i].sameAs(activities[i])].every((x) => x);
    if (same) return false;
    if (activities.isEmpty) {
      _byUser.remove(userId);
    } else {
      _byUser[userId] = List.unmodifiable(activities);
    }
    return true;
  }

  /// Подписаться на сокет. Идемпотентно (remove перед add).
  void attach() {
    wsService.removeListener(_onWsEvent);
    wsService.addListener(_onWsEvent);
  }

  void reset() {
    wsService.removeListener(_onWsEvent);
    _resetVersion = ++_version;
    _eventVersions.clear();
    if (_byUser.isEmpty) return;
    _byUser.clear();
    notifyListeners();
  }

  void _onWsEvent(Map<String, dynamic> event) {
    final userId = event['user_id'];
    if (userId is! int) return;
    switch (event['type']) {
      case 'presence.activity':
        _eventVersions[userId] = ++_version;
        if (_put(userId, UserActivity.listFromJson(event['activities']))) notifyListeners();
      case 'presence.offline':
        _eventVersions[userId] = ++_version;
        if (_put(userId, const [])) notifyListeners();
    }
  }
}

final userActivities = UserActivities();
