import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/notification_settings.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';

class ServerNotifications extends ChangeNotifier {
  final Map<int, ServerNotifSettings> _byServer = {};

  final Map<Object, Set<int>> _snapshotsInFlight = {};

  Timer? _expiry;

  ServerNotifSettings of(int serverId) => _byServer[serverId] ?? const ServerNotifSettings();

  bool isMuted(int serverId) => of(serverId).mutedAt(DateTime.now());

  void attach() {
    wsService.removeListener(_onWsEvent);
    wsService.addListener(_onWsEvent);
  }

  void reset() {
    _byServer.clear();
    _snapshotsInFlight.clear();
    _expiry?.cancel();
    _expiry = null;
    notifyListeners();
  }

  void forgetServer(int serverId) {
    if (_byServer.remove(serverId) != null) notifyListeners();
  }

  Object beginSnapshot() {
    final attempt = Object();
    _snapshotsInFlight[attempt] = <int>{};
    return attempt;
  }

  void dropSnapshot(Object attempt) => _snapshotsInFlight.remove(attempt);

  void applySnapshot(Map<int, ServerNotifSettings?> settings, Object attempt) {
    final fresher = _snapshotsInFlight.remove(attempt) ?? const <int>{};
    for (final e in settings.entries) {
      final value = e.value;
      if (value == null || fresher.contains(e.key)) continue;
      _byServer[e.key] = value;
    }
    _changed();
  }

  Future<ServerNotifSettings> refresh(int serverId) async {
    final settings = await api.getServerNotifications(serverId);
    _set(serverId, settings);
    return settings;
  }

  Future<ServerNotifSettings> update(
    int serverId, {
    NotifLevel? level,
    bool? suppressEveryone,
    bool? suppressRoles,
    bool? muted,
    int? muteMinutes,
  }) async {
    final settings = await api.updateServerNotifications(
      serverId,
      level: level,
      suppressEveryone: suppressEveryone,
      suppressRoles: suppressRoles,
      muted: muted,
      muteMinutes: muteMinutes,
    );
    _set(serverId, settings);
    return settings;
  }

  void _set(int serverId, ServerNotifSettings settings) {
    for (final fresher in _snapshotsInFlight.values) {
      fresher.add(serverId);
    }
    _byServer[serverId] = settings;
    _changed();
  }

  void _changed() {
    _scheduleExpiry();
    notifyListeners();
  }

  void _scheduleExpiry() {
    _expiry?.cancel();
    _expiry = null;
    final now = DateTime.now();
    DateTime? next;
    for (final settings in _byServer.values) {
      final until = settings.mutedUntil;
      if (!settings.muted || until == null || !until.isAfter(now)) continue;
      if (next == null || until.isBefore(next)) next = until;
    }
    if (next == null) return;
    _expiry = Timer(next.difference(now) + const Duration(seconds: 1), _changed);
  }

  void _onWsEvent(Map<String, dynamic> event) {
    if (event['type'] != 'server.notifications.changed') return;
    final serverId = event['server_id'];
    final settings = event['settings'];
    if (serverId is! int || settings is! Map<String, dynamic>) return;
    _set(serverId, ServerNotifSettings.fromJson(settings));
  }
}

final serverNotifications = ServerNotifications();
