import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/achievement.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/user_updates.dart';
import '../services/websocket_service.dart';

class AchievementCollection extends ChangeNotifier {
  final int userId;
  final int? _accountId;
  StreamSubscription<int>? _changes;
  int _sequence = 0;
  bool _disposed = false;
  bool loading = true;
  bool failed = false;
  List<Achievement>? items;

  AchievementCollection(this.userId) : _accountId = authService.currentUser?.id {
    _changes = userUpdates.changes.listen((id) {
      if (id == userId) _reload();
    });
    wsService.addReconnectListener(_reload);
    authService.currentUserListenable.addListener(_accountChanged);
    unawaited(load());
  }

  void _reload() => unawaited(load());

  void acceptOrder(List<int>? order) {
    if (_disposed || order == null || items == null) return;
    final byId = {for (final item in items!) item.id: item};
    items = List.unmodifiable([
      for (final id in order) if (byId.containsKey(id)) byId.remove(id)!,
      ...byId.values,
    ]);
    notifyListeners();
  }

  void _accountChanged() {
    if (_accountId == authService.currentUser?.id) return;
    _sequence++;
    items = null;
    loading = false;
    failed = true;
    notifyListeners();
  }

  Future<void> load() async {
    if (_disposed || _accountId == null || _accountId != authService.currentUser?.id) return;
    final sequence = ++_sequence;
    loading = true;
    failed = false;
    notifyListeners();
    try {
      final result = userId == _accountId
          ? await api.getMyAchievements()
          : await api.getProfileAchievements(userId);
      if (_disposed || sequence != _sequence || _accountId != authService.currentUser?.id) return;
      items = List.unmodifiable(result);
    } catch (error, stack) {
      if (_disposed || sequence != _sequence || _accountId != authService.currentUser?.id) return;
      failed = true;
      if (error is ApiException && const [401, 403, 404].contains(error.statusCode)) items = null;
      debugPrint('AchievementCollection: $error\n$stack');
    } finally {
      if (!_disposed && sequence == _sequence && _accountId == authService.currentUser?.id) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _sequence++;
    _changes?.cancel();
    wsService.removeReconnectListener(_reload);
    authService.currentUserListenable.removeListener(_accountChanged);
    super.dispose();
  }
}
