import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/server.dart';
import '../services/api_service.dart';
import 'server_provider.dart';

/// Заводит тот, у кого есть право «Управлять ролями» (иначе сервер список не
/// отдаст — 403), и освобождает в своём `dispose`. Какие роли МНЕ можно
/// выдавать и снимать, решает сервер (`ServerRole.canEdit`, иерархия) —
/// здесь это не пересчитывается.
class AssignableRoles extends ChangeNotifier {
  final int serverId;

  List<ServerRole> roles = const [];

  String? error;

  StreamSubscription<int>? _sub;
  bool _disposed = false;

  int _seq = 0;

  AssignableRoles(this.serverId) {
    _sub = serverRail.roleChanges.listen((id) {
      if (id == serverId) load();
    });
    load();
  }

  bool canEdit(int roleId) => roles.any((r) => r.id == roleId && r.canEdit);

  Future<void> load() async {
    final seq = ++_seq;
    try {
      final page = await api.getServerRoles(serverId);
      if (_disposed || seq != _seq) return;
      roles = page.roles.where((r) => !r.isDefault).toList();
      error = null;
    } catch (e) {
      if (_disposed || seq != _seq) return;
      error = errorMessage(e);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}
