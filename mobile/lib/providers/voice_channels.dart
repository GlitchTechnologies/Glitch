import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/call_constants.dart';
import '../core/l10n.dart';
import '../main.dart' show navigatorKey;
import '../models/server.dart';
import '../models/voice_pass.dart';
import '../services/api_service.dart';
import '../services/call_platform_web.dart' if (dart.library.io) '../services/call_platform_native.dart';
import '../services/error_reporter.dart';
import '../services/voice_connection.dart';
import '../services/voice_resume.dart';
import '../services/websocket_service.dart';
import 'call_provider.dart';

enum VoiceChannelLink { idle, connecting, connected }

enum VoiceChannelFailure {
  full,
  disconnectedByModerator,
  unavailable,
  noAccess,
  noMicrophone,
  otherDevice,
  removed,
  lost,
}

/// Глобальный, как `callProvider`: голос переживает переходы между экранами и
/// сообществами. Сбрасывается при выходе из аккаунта (`reset`).
class VoiceChannels extends ChangeNotifier {
  final Map<int, Map<int, VoiceStateInfo>> _byServer = {};
  final Map<int, VoiceChannelElapsed> _channelTimers = {};

  VoiceChannelElapsed? channelTimer(int chatId) => _channelTimers[chatId];

  void _refreshChannelStarts() {
    final occupied = <int>{};
    for (final members in _byServer.values) {
      for (final member in members.values) {
        final chatId = member.chatId;
        if (chatId == null) continue;
        occupied.add(chatId);
        final timer = member.channelElapsed;
        final previous = _channelTimers[chatId];
        if (timer != null &&
            (previous == null ||
                timer.startedAt.isBefore(previous.startedAt) ||
                (timer.startedAt == previous.startedAt && timer.fromServer && !previous.fromServer))) {
          _channelTimers[chatId] = timer;
        }
      }
    }
    _channelTimers.removeWhere((chatId, _) => !occupied.contains(chatId));
  }

  _ChannelPlace? _current;
  _ChannelPlace? _joining;

  bool _holdsService = false;

  _ChannelPlace? get _shown => _joining ?? _current;

  VoiceChannelLink get link => _joining != null
      ? VoiceChannelLink.connecting
      : _current != null
          ? VoiceChannelLink.connected
          : VoiceChannelLink.idle;
  int? get serverId => _shown?.serverId;
  int? get roomId => _shown?.roomId;
  String get roomName => _shown?.name ?? '';

  bool get muted => !voiceConnection.micEnabled;
  bool get deafened => voiceConnection.deafened;

  VoiceChannelFailure? _failure;
  StreamSubscription<VoiceDrop>? _dropSub;

  List<VoiceMember> get members {
    final room = _current?.room;
    return room != null && voiceConnection.roomName == room ? voiceConnection.members : const [];
  }

  ({int serverId, int roomId})? get connectedChannel {
    final c = _current;
    final room = c?.room;
    if (c == null || room == null || voiceConnection.roomName != room) return null;
    return (serverId: c.serverId, roomId: c.roomId);
  }

  List<VoiceStateInfo> inServer(int serverId) => [
        for (final s in (_byServer[serverId] ?? const {}).values)
          if (s.callId == null) s,
      ];

  List<VoiceStateInfo> inRoom(int serverId, int chatId) => [
        for (final s in (_byServer[serverId] ?? const {}).values)
          if (s.chatId == chatId && s.callId == null) s,
      ];

  bool get speakBlocked => _current != null && !voiceConnection.micAllowed;

  bool get hearBlocked => _current != null && !voiceConnection.hearAllowed;

  VoiceChannelFailure? consumeFailure() {
    final f = _failure;
    _failure = null;
    return f;
  }

  /// Подписка на сокет и подключение. Как `callProvider.attach` — из
  /// AccountSession.start (services/account_session.dart), идемпотентно.
  void attach() {
    wsService.removeListener(_onWsEvent);
    wsService.addListener(_onWsEvent);
    voiceConnection.removeListener(_onVoiceChanged);
    voiceConnection.addListener(_onVoiceChanged);
    _dropSub?.cancel();
    _dropSub = voiceConnection.onDropped.listen(_onDropped);
    bindCallServiceData(_onServiceData);
  }

  void _onServiceData(Object data) {
    if (data == callServiceHangupSignal && link != VoiceChannelLink.idle) unawaited(leave());
  }

  // Правило — «снимок плюс события с момента запроса», как у любого клиента,
  // который сводит HTTP-снимок с потоком событий: всё, что сокет сообщил о
  // человеке ПОСЛЕ отправки запроса, новее снимка или совпадает с ним (сокет
  // доставляет события по порядку), — поэтому о таких людях снимку не
  // верим. Пропуск событий при разрыве сокета этим не прикрывается и не
  // должен: после переподключения сообщество перезапрашивается целиком.

  final Map<Object, Set<int>> _snapshotsInFlight = {};

  Object beginSnapshot() {
    final attempt = Object();
    _snapshotsInFlight[attempt] = <int>{};
    return attempt;
  }

  void dropSnapshot(Object attempt) => _snapshotsInFlight.remove(attempt);

  void applySnapshot(int serverId, List<VoiceStateInfo> states, Object attempt) =>
      applySnapshots({serverId: states}, attempt);

  void applySnapshots(Map<int, List<VoiceStateInfo>> byServer, Object attempt) {
    final fresher = _snapshotsInFlight.remove(attempt) ?? const <int>{};
    for (final entry in byServer.entries) {
      // Снимок заново подтверждает разговор после пропущенных событий.
      for (final member in (_byServer[entry.key] ?? const <int, VoiceStateInfo>{}).values) {
        _channelTimers.remove(member.chatId);
      }
      final room = _byServer.putIfAbsent(entry.key, () => {});
      room.removeWhere((userId, _) => !fresher.contains(userId));
      for (final s in entry.value) {
        if (s.callId != null || fresher.contains(s.userId)) continue;
        for (final m in _byServer.values) {
          m.remove(s.userId);
        }
        room[s.userId] = s;
      }
    }
    _refreshChannelStarts();
    notifyListeners();
  }

  void _onWsEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'voice.state':
        final state = VoiceStateInfo.fromJson(event);
        if (state.callId != null) return; // звонки ведёт callProvider
        for (final fresher in _snapshotsInFlight.values) {
          fresher.add(state.userId);
        }
        final server = state.serverId;
        if (state.left || server == null) {
          for (final m in _byServer.values) {
            m.remove(state.userId);
          }
        } else {
          for (final m in _byServer.values) {
            m.remove(state.userId);
          }
          (_byServer[server] ??= {})[state.userId] = state;
        }
        _refreshChannelStarts();
        notifyListeners();
      case 'server.room.deleted':
        final server = event['server_id'];
        final chat = event['chat_id'];
        if (server is int && chat is int) {
          _byServer[server]?.removeWhere((_, s) => s.chatId == chat);
          _refreshChannelStarts();
          notifyListeners();
        }
    }
  }


  Future<void> join(Room room) => joinRoom(room.serverId, room.id, room.name);

  Future<void> joinRoom(int serverIdArg, int roomIdArg, String name, {bool afterDrop = false}) async {
    final unavailable = afterDrop ? VoiceChannelFailure.lost : VoiceChannelFailure.unavailable;
    if (_joining?.roomId == roomIdArg) return; // уже входим туда
    if (_current?.roomId == roomIdArg) {
      if (_joining != null) {
        _joining = null;
        _settle();
      }
      return;
    }
    if (callProvider.isBusy) callProvider.hangup(reason: 'switched_to_channel');

    final place = _ChannelPlace(serverIdArg, roomIdArg, name);
    _joining = place;
    notifyListeners();

    if (!await ensureMicrophonePermission()) {
      await voiceConnection.setMicEnabled(false);
      _failure = VoiceChannelFailure.noMicrophone;
    }
    if (!identical(_joining, place)) return;

    final VoicePass pass;
    try {
      pass = await api.joinVoiceChannel(place.serverId, place.roomId, voiceConnection.selfFlags);
    } on ApiException catch (e) {
      if (!identical(_joining, place)) return;
      _failure = switch (e.statusCode) {
        409 => VoiceChannelFailure.full,
        503 => unavailable,
        _ => VoiceChannelFailure.noAccess,
      };
      _joining = null;
      _settle();
      return;
    } catch (e, s) {
      if (!identical(_joining, place)) return;
      errorReporter.report(e, stack: s, screen: 'voice:joinChannel');
      _failure = unavailable;
      _joining = null;
      _settle();
      return;
    }
    if (!identical(_joining, place)) return;
    place.room = pass.room;
    _holdsService = true;
    _startForegroundService(place.name);
    await setSpeakerphone(true);
    if (!identical(_joining, place)) return;
    try {
      await voiceConnection.connect(pass);
    } on VoiceMicUnavailable {
      _failure = VoiceChannelFailure.noMicrophone;
    } catch (e) {
      if (identical(_joining, place)) {
        _joining = null;
        _failure = unavailable;
      }
      _settle();
      return;
    }
    if (voiceConnection.roomName == pass.room) {
      _current = place;
      voiceResume.rememberChannel(
          room: pass.room, serverId: place.serverId, roomId: place.roomId, name: place.name);
    }
    if (identical(_joining, place)) _joining = null;
    _settle();
  }

  Future<void> leave() async {
    final rooms = [_current?.room, _joining?.room];
    _forgetCurrent();
    _joining = null;
    _settle();
    for (final room in rooms) {
      if (room != null) await voiceConnection.disconnectFrom(room);
    }
  }

  Future<void> reset() async {
    await leave();
    _byServer.clear();
    _channelTimers.clear();
    _snapshotsInFlight.clear();
    notifyListeners();
  }

  void _forgetCurrent() {
    voiceResume.forget(_current?.room);
    _current = null;
  }

  void _settle() {
    if (_current == null && _joining == null && _holdsService) {
      _holdsService = false;
      if (!callProvider.isBusy) unawaited(CallForegroundService.stop());
    }
    notifyListeners();
  }

  void _onVoiceChanged() {
    if (link != VoiceChannelLink.idle) notifyListeners();
  }

  void _onDropped(VoiceDrop drop) {
    final wasCurrent = _current?.room == drop.room;
    final wasJoining = _joining?.room == drop.room;
    if (!wasCurrent && !wasJoining) return;
    final place = (wasCurrent ? _current : _joining)!;
    final serverOf = place.serverId;
    if (wasCurrent) {
      _forgetCurrent();
    } else {
      _joining = null;
    }
    if (drop.reason == VoiceDropReason.replaced) {
      _settle();
      return;
    }
    final to = drop.moveToChatId;
    if (drop.cause == 'moved' && to != null) {
      unawaited(joinRoom(serverOf, to, drop.moveToName));
      _settle();
      return;
    }
    if (wasCurrent &&
        (drop.reason == VoiceDropReason.roomLost || drop.reason == VoiceDropReason.lost)) {
      unawaited(joinRoom(serverOf, place.roomId, place.name, afterDrop: true));
      _settle();
      return;
    }
    _failure = switch ((drop.reason, drop.cause)) {
      (VoiceDropReason.lost, _) => VoiceChannelFailure.lost,
      (_, 'other_device') => VoiceChannelFailure.otherDevice,
      (_, 'disconnected') => VoiceChannelFailure.disconnectedByModerator,
      _ => VoiceChannelFailure.removed,
    };
    _settle();
  }


  void _startForegroundService(String channelName) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    final s = S.of(ctx);
    unawaited(CallForegroundService.start(
      peerName: channelName,
      ongoingText: s.voiceConnected,
      hangUpText: s.voiceDisconnect,
    ));
  }
}

class _ChannelPlace {
  final int serverId;
  final int roomId;
  final String name;

  String? room;

  _ChannelPlace(this.serverId, this.roomId, this.name);
}

final voiceChannels = VoiceChannels();
