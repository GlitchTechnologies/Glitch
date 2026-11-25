import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/presence.dart';
import '../core/presence.dart' show unhideLastSeen;
import '../core/time_json.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'error_reporter.dart';
import 'websocket_service.dart';

class UserPresences extends ChangeNotifier {
  final Map<int, PresenceStatus> _byUser = {};
  final Map<int, DateTime?> _lastSeen = {};
  final Map<int, bool> _blocked = {};
  final Map<int, int> _versions = {};
  int _clock = 0;
  int _resetClock = 0;
  final _changes = StreamController<int>.broadcast();
  Stream<int> get changes => _changes.stream;
  AccountPresence _own = const AccountPresence();
  AccountPresence get own => _own;
  List<int> durationsMinutes = const [];
  bool ready = false;
  bool ownKnown = false;
  bool loading = false;
  bool saving = false;
  int _session = 0;
  int _ownGeneration = 0;
  int _loadGeneration = 0;

  int beginSnapshot() => ++_clock;

  bool _seed(int userId, PresenceStatus status, int snapshot, bool blocked, DateTime? lastSeen) {
    if (blocked || userId == authService.currentUser?.id || snapshot < _resetClock || (_versions[userId] ?? 0) > snapshot) return false;
    _versions[userId] = snapshot;
    final seen = lastSeen == null ? null : unhideLastSeen(lastSeen);
    final changed = _byUser[userId] != status ||
        (lastSeen != null && (!_lastSeen.containsKey(userId) || _lastSeen[userId] != seen));
    _byUser[userId] = status;
    if (lastSeen != null) _lastSeen[userId] = seen;
    return changed;
  }

  void seed(int userId, PresenceStatus status, {required int snapshot, bool blocked = false, DateTime? lastSeen}) {
    if (_seed(userId, status, snapshot, blocked, lastSeen)) notifyListeners();
  }

  void seedAll(Iterable<(int, PresenceStatus)> entries, {required int snapshot}) {
    var changed = false;
    for (final (id, status) in entries) {
      changed = _seed(id, status, snapshot, false, null) || changed;
    }
    if (changed) notifyListeners();
  }

  void _clearVisible() {
    _byUser.clear();
    _lastSeen.clear();
    _blocked.clear();
    _versions.clear();
    _resetClock = ++_clock;
  }

  PresenceStatus statusOf(int userId, PresenceStatus fallback) =>
      userId == authService.currentUser?.id ? (ownKnown ? _own.status : PresenceStatus.offline) : _byUser[userId] ?? fallback;

  DateTime? lastSeenOf(int userId, DateTime? fallback) => _lastSeen.containsKey(userId) ? _lastSeen[userId] : fallback;
  bool blockedFor(int userId, bool fallback) => fallback || _blocked[userId] == true;

  bool _hiddenInPersonal(int userId, DateTime? serverLastSeen, bool blocked) =>
      blockedFor(userId, blocked) ||
      (serverLastSeen != null && unhideLastSeen(serverLastSeen) == null);

  PresenceStatus personalStatusOf(int userId, PresenceStatus fallback,
          {required DateTime? serverLastSeen, bool blocked = false}) =>
      _hiddenInPersonal(userId, serverLastSeen, blocked) ? PresenceStatus.offline : statusOf(userId, fallback);

  DateTime? personalLastSeenOf(int userId, DateTime? serverLastSeen, {bool blocked = false}) =>
      _hiddenInPersonal(userId, serverLastSeen, blocked)
          ? null : lastSeenOf(userId, serverLastSeen == null ? null : unhideLastSeen(serverLastSeen));

  bool personalActivityVisible(int userId, DateTime serverLastSeen, {bool blocked = false}) =>
      userId == authService.currentUser?.id ||
      (!_hiddenInPersonal(userId, serverLastSeen, blocked) && lastSeenOf(userId, unhideLastSeen(serverLastSeen)) != null);

  void _setOwn(AccountPresence value) {
    final changed = _own.status != value.status;
    _own = value;
    ownKnown = true;
    final id = authService.currentUser?.id;
    if (changed && id != null) _changes.add(id);
  }

  void attach() {
    wsService.removeListener(_onEvent);
    wsService.addListener(_onEvent);
    wsService.removeConnectListener(_connected);
    wsService.addConnectListener(_connected);
  }

  void reset() {
    _session++;
    _loadGeneration++;
    wsService.removeListener(_onEvent);
    wsService.removeConnectListener(_connected);
    _clearVisible();
    _own = const AccountPresence();
    durationsMinutes = const [];
    ready = false;
    ownKnown = false;
    loading = false;
    saving = false;
    notifyListeners();
  }

  void _connected() {
    _clearVisible();
    _loadGeneration++;
    loading = false;
    notifyListeners();
    unawaited(load().catchError((Object e, StackTrace s) {
      errorReporter.report(e, stack: s, screen: 'presence:load');
    }));
  }

  Future<void> load() async {
    if (loading) return;
    final session = _session;
    final generation = ++_loadGeneration;
    final ownGeneration = _ownGeneration;
    loading = true;
    notifyListeners();
    try {
      final result = await api.getMyPresence();
      if (session != _session || generation != _loadGeneration) return;
      durationsMinutes = result.durationsMinutes;
      if (ownGeneration == _ownGeneration) _setOwn(result.account);
      ready = true;
    } catch (_) {
      if (session != _session || generation != _loadGeneration) return;
      rethrow;
    } finally {
      if (session == _session && generation == _loadGeneration) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> choose(PresenceStatus status, int? minutes) async {
    if (saving) return;
    final session = _session;
    final generation = _ownGeneration;
    saving = true;
    notifyListeners();
    try {
      final result = await api.updateMyPresence(status, minutes);
      if (session != _session) return;
      if (generation == _ownGeneration) {
        _ownGeneration++;
        _setOwn(result);
      }
    } finally {
      if (session == _session) {
        saving = false;
        notifyListeners();
      }
    }
  }

  void _onEvent(Map<String, dynamic> event) {
    final id = event['user_id'];
    if (id is! int) return;
    if (event['type'] == 'block.changed') {
      _blocked[id] = event['blocked'] == true;
      notifyListeners();
      _changes.add(id);
      return;
    }
    if (event['type'] == 'presence.self' && id == authService.currentUser?.id) {
      final settings = event['settings'];
      if (settings is! Map<String, dynamic>) return;
      _ownGeneration++;
      _setOwn(AccountPresence.fromJson(settings));
      notifyListeners();
    } else if (event['type'] == 'presence.online' || event['type'] == 'presence.offline') {
      _versions[id] = ++_clock;
      final status = presenceStatusFrom(event['status'], online: event['type'] == 'presence.online');
      final rawLastSeen = event['last_seen'];
      final seen = rawLastSeen is String ? unhideLastSeen(parseUtcLocal(rawLastSeen)) : null;
      if (_byUser[id] == status && _lastSeen[id] == seen) return;
      _byUser[id] = status;
      _lastSeen[id] = seen;
      notifyListeners();
      _changes.add(id);
    }
  }
}

final userPresences = UserPresences();
