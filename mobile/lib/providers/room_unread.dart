import 'package:flutter/foundation.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/websocket_service.dart';
import 'server_notifications.dart';

/// УПОМИНАНИЯ (2026-10-17, как у Discord) — красные числа у канала и у
/// значка сообщества: сколько непрочитанных сообщений упомянули меня. Правило
/// тоже только на сервере (read_state_service.mentions_for_rooms /
/// mentions_by_server), здесь — показ тем же приёмом:
///   * снимок по каналам — с сообществом (`ServerDetail.mentionCounts`), сумма
///     по каждому сообществу — со списком сообществ
///     (`ServerListItem.mentionCount`);
///   * `mention.new` канала — +1 каналу и сообществу;
///   * `chat.read.self` канала — точный остаток канала и сообщества;
///   * удалили или поправили сообщение в канале, где есть упоминания, —
///     счётчики сообщества перечитываются (`GET /servers/{id}/mentions`):
///     было ли в нём упоминание меня, отсюда не видно;
///   * мои настройки уведомлений сообщества поменялись
///     (`server.notifications.changed`) — тоже перечитываются: заглушённые
///     @everyone/@here и роли упоминаниями меня не считаются.
class RoomUnread extends ChangeNotifier {
  final Set<int> _unread = {};

  final Set<int> _unreadServers = {};

  final Map<int, int> _mentions = {};
  final Map<int, int> _serverMentions = {};

  final Map<int, int> _roomServer = {};

  final Map<Object, ({Set<int> rooms, Set<int> servers})> _snapshotsInFlight = {};

  final Map<int, int> _refetchSeq = {};

  bool isUnread(int roomId) => _unread.contains(roomId);

  int mentionsIn(int roomId) => _mentions[roomId] ?? 0;

  int mentionsInServer(int serverId) => _serverMentions[serverId] ?? 0;

  bool serverUnreadShown(int serverId) =>
      _unreadServers.contains(serverId) && !serverNotifications.isMuted(serverId);

  void attach() {
    wsService.removeListener(_onWsEvent);
    wsService.addListener(_onWsEvent);
  }

  void reset() {
    _unread.clear();
    _unreadServers.clear();
    _mentions.clear();
    _serverMentions.clear();
    _roomServer.clear();
    _snapshotsInFlight.clear();
    _refetchSeq.clear();
    notifyListeners();
  }

  void forgetServer(int serverId) {
    _serverMentions.remove(serverId);
    _unreadServers.remove(serverId);
    final rooms = [for (final e in _roomServer.entries) if (e.value == serverId) e.key];
    for (final id in rooms) {
      _roomServer.remove(id);
      _mentions.remove(id);
      _unread.remove(id);
    }
    notifyListeners();
  }

  Object beginSnapshot() {
    final attempt = Object();
    _snapshotsInFlight[attempt] = (rooms: <int>{}, servers: <int>{});
    return attempt;
  }

  void dropSnapshot(Object attempt) => _snapshotsInFlight.remove(attempt);

  void applySnapshot(int serverId, Iterable<int> roomIds, Iterable<int> unread,
      Map<int, int> mentions, Object attempt) {
    final fresher = _snapshotsInFlight.remove(attempt);
    final unreadSet = unread.toSet();
    for (final id in roomIds) {
      _roomServer[id] = serverId;
      if (fresher?.rooms.contains(id) ?? false) continue;
      if (unreadSet.contains(id)) {
        _unread.add(id);
      } else {
        _unread.remove(id);
      }
      _setMentions(id, mentions[id] ?? 0);
    }
    if (!(fresher?.servers.contains(serverId) ?? false)) {
      _sumServer(serverId);
      _setServerUnread(serverId, roomIds.any(_unread.contains));
    }
    notifyListeners();
  }

  void applyServerTotals(Map<int, int> totals, Set<int> unread, Object attempt) {
    final fresher = _snapshotsInFlight.remove(attempt);
    for (final e in totals.entries) {
      if (fresher?.servers.contains(e.key) ?? false) continue;
      _setServerMentions(e.key, e.value);
      _setServerUnread(e.key, unread.contains(e.key));
    }
    notifyListeners();
  }

  void _touch({int? roomId, int? serverId}) {
    for (final fresher in _snapshotsInFlight.values) {
      if (roomId != null) fresher.rooms.add(roomId);
      if (serverId != null) fresher.servers.add(serverId);
    }
  }

  void _set(int roomId, bool unread) {
    _touch(roomId: roomId);
    final changed = unread ? _unread.add(roomId) : _unread.remove(roomId);
    if (changed) notifyListeners();
  }

  void _setMentions(int roomId, int n) {
    if (n > 0) {
      _mentions[roomId] = n;
    } else {
      _mentions.remove(roomId);
    }
  }

  void _setServerUnread(int serverId, bool unread) {
    if (unread) {
      _unreadServers.add(serverId);
    } else {
      _unreadServers.remove(serverId);
    }
  }

  void _setServerMentions(int serverId, int n) {
    if (n > 0) {
      _serverMentions[serverId] = n;
    } else {
      _serverMentions.remove(serverId);
    }
  }

  void _sumServer(int serverId) {
    var sum = 0;
    for (final e in _roomServer.entries) {
      if (e.value == serverId) sum += _mentions[e.key] ?? 0;
    }
    _setServerMentions(serverId, sum);
  }

  Future<void> _refetch(int serverId) async {
    final seq = (_refetchSeq[serverId] ?? 0) + 1;
    _refetchSeq[serverId] = seq;
    try {
      final counts = await api.getMentionCounts(serverId);
      if (_refetchSeq[serverId] != seq) return;
      for (final e in _roomServer.entries.where((e) => e.value == serverId).toList()) {
        _setMentions(e.key, counts.rooms[e.key] ?? 0);
      }
      for (final e in counts.rooms.entries) {
        _roomServer[e.key] = serverId;
        _setMentions(e.key, e.value);
      }
      _setServerMentions(serverId, counts.total);
      notifyListeners();
    } catch (_) {
    }
  }

  void _onWsEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'message.new':
        if (event['in_room'] != true) return;
        final message = event['message'];
        if (message is! Map) return;
        final roomId = message['chat_id'];
        if (roomId is! int) return;
        if (message['sender_id'] == authService.currentUser?.id) return;
        final serverId = event['server_id'] ?? _roomServer[roomId];
        if (serverId is int) {
          _touch(serverId: serverId);
          _roomServer[roomId] = serverId;
          _setServerUnread(serverId, true);
        }
        _set(roomId, true);
        notifyListeners();
      case 'chat.read.self':
        if (event['in_room'] != true) return;
        final roomId = event['chat_id'];
        final left = event['unread_count'];
        if (roomId is! int || left is! int) return;
        _set(roomId, left > 0);
        final serverId = event['server_id'];
        final mentions = event['mention_count'];
        final serverMentions = event['server_mention_count'];
        if (serverId is int && mentions is int && serverMentions is int) {
          _touch(roomId: roomId, serverId: serverId);
          _roomServer[roomId] = serverId;
          _setMentions(roomId, mentions);
          _setServerMentions(serverId, serverMentions);
          final serverUnread = event['server_unread'];
          if (serverUnread is bool) _setServerUnread(serverId, serverUnread);
          notifyListeners();
        }
      case 'mention.new':
        if (event['in_room'] != true) return;
        final roomId = event['chat_id'];
        final serverId = event['server_id'];
        if (roomId is! int || serverId is! int) return;
        _touch(roomId: roomId, serverId: serverId);
        _roomServer[roomId] = serverId;
        _setMentions(roomId, mentionsIn(roomId) + 1);
        _setServerMentions(serverId, mentionsInServer(serverId) + 1);
        notifyListeners();
      case 'message.deleted' || 'message.edited':
        if (event['in_room'] != true) return;
        final roomId = event['chat_id'];
        final serverId = _roomServer[roomId];
        if (roomId is int && serverId != null && mentionsIn(roomId) > 0) _refetch(serverId);
      case 'server.notifications.changed':
        final serverId = event['server_id'];
        if (serverId is int) _refetch(serverId);
      case 'server.room.deleted':
        final roomId = event['chat_id'];
        if (roomId is int) {
          _set(roomId, false);
          final serverId = _roomServer.remove(roomId);
          final gone = _mentions.remove(roomId);
          if (gone != null && serverId != null) {
            _touch(serverId: serverId);
            _setServerMentions(serverId, mentionsInServer(serverId) - gone);
            notifyListeners();
          }
        }
    }
  }
}

final roomUnread = RoomUnread();
