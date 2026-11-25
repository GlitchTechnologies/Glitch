import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/relationship.dart';
import '../models/presence.dart';
import '../services/api_service.dart';
import '../services/user_activities.dart';
import '../services/user_presences.dart';
import '../services/user_updates.dart';
import '../services/websocket_service.dart';

/// Загружает список с сервера и применяет события дружбы, присутствия и профиля.
/// Пока запрос выполняется, события имеют приоритет над его ответом.
/// После переподключения список загружается заново.
class Friends extends ChangeNotifier {
  final Map<int, Relationship> _byUser = {};

  final Map<Object, Set<int>> _snapshotsInFlight = {};

  int _session = 0;

  final Set<int> _busy = {};

  StreamSubscription<PersonLook>? _looksSub;

  bool _loaded = false;
  String? _error;

  bool get loaded => _loaded;

  String? get error => _loaded ? null : _error;

  Relationship? of(int userId) => _byUser[userId];

  bool isBusy(int userId) => _busy.contains(userId);

  List<Relationship> get friends => _sorted(RelationshipKind.friend);

  List<Relationship> get pending => [
        ..._newestFirst(RelationshipKind.incoming),
        ..._newestFirst(RelationshipKind.outgoing),
      ];

  int get incomingCount => _byUser.values.where((r) => r.kind == RelationshipKind.incoming).length;

  List<Relationship> _sorted(RelationshipKind kind) {
    final list = _byUser.values.where((r) => r.kind == kind).toList();
    list.sort((a, b) => a.user.displayName.toLowerCase().compareTo(b.user.displayName.toLowerCase()));
    return list;
  }

  List<Relationship> _newestFirst(RelationshipKind kind) {
    final list = _byUser.values.where((r) => r.kind == kind).toList();
    list.sort((a, b) => b.since.compareTo(a.since));
    return list;
  }


  void attach() {
    wsService.removeListener(_onWsEvent);
    wsService.addListener(_onWsEvent);
    wsService.removeReconnectListener(_onReconnect);
    wsService.addReconnectListener(_onReconnect);
    _looksSub?.cancel();
    _looksSub = userUpdates.looks.listen(_onLook);
    unawaited(load());
  }

  void reset() {
    _session++;
    wsService.removeListener(_onWsEvent);
    wsService.removeReconnectListener(_onReconnect);
    _looksSub?.cancel();
    _looksSub = null;
    _byUser.clear();
    _snapshotsInFlight.clear();
    _busy.clear();
    _loaded = false;
    _error = null;
    notifyListeners();
  }

  void _onReconnect() => unawaited(load());

  Future<void> load() async {
    final session = _session;
    final activitySnapshot = userActivities.beginSnapshot();
    final presenceSnapshot = userPresences.beginSnapshot();
    final attempt = Object();
    _snapshotsInFlight[attempt] = <int>{};
    try {
      final list = await api.getRelationships();
      if (session != _session) return;
      userPresences.seedAll([for (final r in list) (r.user.id, r.presenceStatus)], snapshot: presenceSnapshot);
      userActivities.seedAll([for (final r in list) (r.user.id, r.activities)], snapshot: activitySnapshot);
      final fresher = _snapshotsInFlight.remove(attempt) ?? const <int>{};
      final keep = {
        for (final id in fresher)
          if (_byUser[id] case final r?) id: r,
      };
      _byUser
        ..clear()
        ..addAll({for (final r in list) if (!fresher.contains(r.user.id)) r.user.id: _livePresence(r)})
        ..addAll(keep);
      _loaded = true;
      _error = null;
      notifyListeners();
    } catch (e) {
      _snapshotsInFlight.remove(attempt);
      if (session != _session) return;
      _error = errorMessage(e);
      notifyListeners();
    }
  }


  Future<Relationship?> addByNickname(String nickname) async {
    final session = _session;
    final rel = await api.requestFriendByNickname(nickname);
    if (rel != null && session == _session) _put(rel);
    return rel;
  }

  Future<void> request(int userId) => _act(userId, () => api.requestFriend(userId));

  Future<void> remove(int userId) => _act(userId, () async {
        await api.removeRelationship(userId);
        _drop(userId);
        return null;
      });

  Future<void> _act(int userId, Future<Relationship?> Function() call) async {
    if (!_busy.add(userId)) return;
    final session = _session;
    notifyListeners();
    try {
      final rel = await call();
      if (rel != null && session == _session) _put(rel);
    } finally {
      if (session == _session && _busy.remove(userId)) notifyListeners();
    }
  }


  void _touch(int userId) {
    for (final fresher in _snapshotsInFlight.values) {
      fresher.add(userId);
    }
  }

  Relationship _livePresence(Relationship rel) {
    final status = userPresences.statusOf(rel.user.id, rel.presenceStatus);
    return rel.copyWith(isOnline: status.isOnline, presenceStatus: status);
  }

  void _put(Relationship rel) {
    _touch(rel.user.id);
    _byUser[rel.user.id] = rel;
    notifyListeners();
  }

  void _drop(int userId) {
    _touch(userId);
    if (_byUser.remove(userId) != null) notifyListeners();
  }

  void _onWsEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'relationship.add':
        final raw = event['relationship'];
        if (raw is! Map<String, dynamic>) return;
        final rel = Relationship.fromJson(raw);
        if (rel != null) _put(rel);
      case 'relationship.remove':
        final userId = event['user_id'];
        if (userId is int) _drop(userId);
      case 'presence.online' || 'presence.offline':
        final userId = event['user_id'];
        if (userId is! int) return;
        final rel = _byUser[userId];
        final online = event['type'] == 'presence.online';
        final status = presenceStatusFrom(event['status'], online: online);
        if (rel == null) return;
        _touch(userId);
        if (rel.isOnline == online && rel.presenceStatus == status) return;
        _byUser[userId] = rel.copyWith(isOnline: online, presenceStatus: status);
        notifyListeners();
    }
  }

  void _onLook(PersonLook change) {
    final person = change.person;
    final rel = _byUser[change.userId];
    if (change.serverId != null || person == null || rel == null) return;
    _byUser[change.userId] = rel.copyWith(user: person);
    notifyListeners();
  }
}

final friends = Friends();
