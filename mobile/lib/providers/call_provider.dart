import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import '../services/chat_viewing.dart';
import '../services/call_platform_web.dart' if (dart.library.io) '../services/call_platform_native.dart';

import '../core/avatar_color.dart';
import '../core/call_constants.dart';
import '../core/l10n.dart';
import '../main.dart' show navigatorKey;
import '../models/incoming_call_payload.dart';
import '../models/voice_pass.dart';
import '../services/api_service.dart';
import '../services/app_sounds.dart';
import '../services/auth_service.dart';
import '../services/call_screen_capture_web.dart'
    if (dart.library.io) '../services/call_screen_capture_native.dart';
import '../services/error_reporter.dart';
import '../services/push_service.dart';
import '../services/voice_connection.dart';
import '../services/voice_cue.dart';
import '../services/voice_resume.dart';
import '../services/websocket_service.dart';

enum CallState {
  idle,        // звонка нет
  outgoing,    // мы позвонили и сидим в комнате, у остальных звенит
  incoming,    // нам звонят, ждём решения
  connecting,  // трубку взяли, входим в комнату
  active,      // в комнате есть кто-то ещё — разговор идёт
}

enum CallFailure {
  busy,
  blocked,
  noAccess,
  alreadyInCall,
  tooOften,
  noMicrophone,
  notConnected,
  gone,
  otherDevice,
  internal,
}

class WaitingCall {
  final int callId;
  final int chatId;
  final String title;
  final bool group;
  final String? avatar;
  final Color? avatarColor;
  final int? fromId;

  final CallMember? caller;
  const WaitingCall({
    required this.callId,
    required this.chatId,
    required this.title,
    required this.group,
    this.avatar,
    this.avatarColor,
    this.fromId,
    this.caller,
  });
}

class CallProvider extends ChangeNotifier with WidgetsBindingObserver {
  CallState state = CallState.idle;
  int? callId;
  int? chatId;
  bool isGroup = false;

  int? peerId;
  String peerName = '';
  String? peerAvatar;
  Color? peerAvatarColor;
  bool isVideo = false;

  bool get muted => !voiceConnection.micEnabled;
  bool speaker = false;

  WaitingCall? waitingCall;

  List<CallMember> roster = const [];

  int _rosterVersion = -1;

  DateTime? _connectedAt;
  Duration elapsed = Duration.zero;
  Timer? _ticker;

  CallFailure? _failure;
  bool _attached = false;

  Timer? _ringTimeout;
  static const _ringTimeoutDuration = Duration(seconds: 60);

  Timer? _connectTimeout;
  static const _connectTimeoutDuration = Duration(seconds: 30);

  StreamSubscription<({String action, IncomingCallPayload payload})>? _callActionSub;
  StreamSubscription<VoiceDrop>? _dropSub;

  String? _callRoom;

  bool get _inOurRoom => _callRoom != null && voiceConnection.roomName == _callRoom;

  bool get isBusy => state != CallState.idle;

  bool get canControlAudio =>
      state == CallState.active || state == CallState.connecting || state == CallState.outgoing;

  bool get canSwitchSpeaker => callSupportsSpeaker;


  List<VoiceMember> get members => _inOurRoom ? voiceConnection.members : const [];

  bool get cameraOn => voiceConnection.cameraOn;
  bool get sharingScreen => voiceConnection.screenOn;
  bool get frontCamera => voiceConnection.frontCamera;

  bool get peerSharingScreen => members.any((m) => !m.isLocal && m.screen != null);

  bool get showsScreenShare => screenCaptureSupported;
  bool get canShareScreen => screenCaptureSupported && canUseCamera;
  bool get canUseCamera => canControlAudio && _inOurRoom && voiceConnection.canStream;


  CallFailure? consumeFailure() {
    final f = _failure;
    _failure = null;
    return f;
  }

  bool get isAttached => _attached;


  /// Подписка на сокет, уведомления и телефонию. Зовётся из AccountSession.start
  /// (после выхода из аккаунта сокет чистит всех слушателей). Идемпотентна.
  void attach() {
    wsService.removeListener(_onWsEvent);
    wsService.addListener(_onWsEvent);
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.addObserver(this);
    bindCallServiceData(_onServiceData);
    _callActionSub?.cancel();
    _callActionSub = pushService.onCallAction.listen(_onNotificationCallAction);
    unawaited(GlitchTelecom.register());
    GlitchTelecom.listen(_onTelecomEvent);
    voiceConnection.removeListener(_onVoiceChanged);
    voiceConnection.addListener(_onVoiceChanged);
    _dropSub?.cancel();
    _dropSub = voiceConnection.onDropped.listen(_onVoiceDropped);
    _attached = true;
  }

  /// Кнопка «Завершить» на карточке активного звонка (сервисный изолят).
  void _onServiceData(Object data) {
    if (data == callServiceHangupSignal) hangup();
  }

  void _onNotificationCallAction(({String action, IncomingCallPayload payload}) event) {
    if (callId != event.payload.callId) return;
    if (event.action == callActionAccept) {
      unawaited(_acceptWhenOnScreen(event.payload.callId));
    } else {
      decline();
      if (_cameFromBackground) unawaited(_moveAppToBackground());
    }
  }

  void _onTelecomEvent(TelecomEvent event) {
    switch (event) {
      case TelecomEvent.answer:
        if (state == CallState.incoming) unawaited(accept());
      case TelecomEvent.reject:
        if (state == CallState.incoming) decline();
      case TelecomEvent.disconnect:
        if (isBusy) hangup(reason: 'telecom');
      case TelecomEvent.rejectedBySystem:
        if (isBusy) {
          _failure = CallFailure.busy;
          hangup(reason: 'cellular_busy');
        }
      case TelecomEvent.muted:
      case TelecomEvent.unmuted:
        final nowMuted = event == TelecomEvent.muted;
        if (canControlAudio && muted != nowMuted) unawaited(_applyMute(nowMuted));
      case TelecomEvent.showIncomingUi:
        break;
    }
  }

  /// Звонок приняли кнопкой на уведомлении при ЗАКРЫТОМ приложении — сервер
  /// дослал его по сокету после запуска. Читается здесь, а не при старте:
  /// фоновый изолят пишет «записку» примерно тогда же, когда система поднимает
  /// приложение.
  Future<void> _acceptPendingIfMatches() async {
    final id = callId;
    if (id == null || state != CallState.incoming) return;
    final pending = await PushService.consumePendingAcceptedCall();
    if (pending != id) return;
    await _acceptWhenOnScreen(id);
  }

  Future<void> _acceptWhenOnScreen(int id) async {
    if (callId != id || state != CallState.incoming) return;
    if (!await _waitUntilResumed()) return;
    if (callId != id || state != CallState.incoming) return;
    await accept();
  }

  static const _appControl = MethodChannel('glitch/app_control');

  Future<void> _setOverLockScreen(bool show) async {
    try {
      await _appControl.invokeMethod(show ? 'showOverLockScreen' : 'hideOverLockScreen');
    } catch (_) {
    }
  }

  Future<void> _moveAppToBackground() async {
    try {
      await _appControl.invokeMethod('moveToBackground');
    } catch (_) {}
  }

  bool _inBackground = false;
  DateTime? _leftBackgroundAt;

  bool get _cameFromBackground {
    if (_inBackground) return true;
    final left = _leftBackgroundAt;
    return left != null && DateTime.now().difference(left) < const Duration(seconds: 2);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.paused || lifecycle == AppLifecycleState.detached) {
      _inBackground = true;
    } else if (lifecycle == AppLifecycleState.resumed) {
      if (_inBackground) _leftBackgroundAt = DateTime.now();
      _inBackground = false;
    }
  }

  Future<bool> _waitUntilResumed({Duration timeout = const Duration(seconds: 30)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) return true;
      await Future.delayed(const Duration(milliseconds: 150));
      if (state != CallState.incoming) return false;
    }
    return false;
  }


  Future<void> startCall({
    required int chat,
    required String name,
    String? avatar,
    bool group = false,
  }) async {
    if (isBusy) return; // второй тап по кнопке
    if (!await ensureMicrophonePermission()) {
      _failure = CallFailure.noMicrophone;
      notifyListeners();
      return;
    }
    if (isBusy) return; // пока спрашивали разрешение, мог прийти входящий

    chatId = chat;
    isGroup = group;
    peerId = null;
    peerName = name;
    peerAvatar = avatar;
    peerAvatarColor = null;
    isVideo = false;
    speaker = false;
    elapsed = Duration.zero;
    state = CallState.outgoing;
    _provisional([
      _me(CallMemberState.joining),
      if (!group) CallMember(userId: 0, state: CallMemberState.ringing, displayName: name, avatar: avatar),
    ]);
    unawaited(GlitchTelecom.reportOutgoing(name));
    _startRingTimeout();
    notifyListeners();
    await _prepareFlags();

    final CallPass pass;
    try {
      pass = await api.startCall(chat, voiceConnection.selfFlags);
    } on ApiException catch (e) {
      if (chatId != chat || state != CallState.outgoing) return;
      _failure = switch (e.message) {
        'blocked' => CallFailure.blocked,
        'too_often' => CallFailure.tooOften,
        _ => e.statusCode == 403 ? CallFailure.noAccess : CallFailure.internal,
      };
      _reset();
      return;
    } catch (e, s) {
      if (chatId != chat || state != CallState.outgoing) return;
      errorReporter.report(e, stack: s, screen: 'call:start');
      _failure = CallFailure.internal;
      _reset();
      return;
    }
    if (chatId != chat || state != CallState.outgoing) {
      unawaited(api.leaveCall(pass.chatId, pass.callId).catchError((Object _) {}));
      return;
    }
    callId = pass.callId;
    isGroup = pass.isGroup;
    _applyCall(pass.call);
    if (pass.created) {
      if (appSounds.isOn(VoiceCue.ringback)) unawaited(GlitchRingtone.playOutgoing());
    } else {
      _enterConnecting();
    }
    notifyListeners();
    await _enterRoom(pass);
  }

  Future<void> joinOngoing({
    required int chat,
    required int call,
    required String name,
    bool group = true,
  }) async {
    if (isBusy && callId == call) return; // уже в нём или входим — второй тап
    if (!await ensureMicrophonePermission()) {
      _failure = CallFailure.noMicrophone;
      notifyListeners();
      return;
    }
    if (isBusy && callId == call) return;
    if (isBusy) hangup(reason: 'switched');
    callId = call;
    chatId = chat;
    isGroup = group;
    peerId = null;
    peerName = name;
    peerAvatar = null;
    peerAvatarColor = null;
    isVideo = false;
    speaker = false;
    elapsed = Duration.zero;
    _provisional([_me(CallMemberState.joining)]);
    unawaited(GlitchTelecom.reportOutgoing(name));
    _enterConnecting();
    await _prepareFlags();

    final CallPass pass;
    try {
      pass = await api.joinCall(chat, call, voiceConnection.selfFlags);
    } on ApiException catch (e) {
      if (callId != call) return;
      _failure = e.statusCode == 404 ? CallFailure.gone : CallFailure.notConnected;
      _reset();
      return;
    } catch (e, s) {
      if (callId != call) return;
      errorReporter.report(e, stack: s, screen: 'call:joinOngoing');
      _failure = CallFailure.notConnected;
      _reset();
      return;
    }
    if (callId != call) return;
    isGroup = pass.isGroup;
    _applyCall(pass.call);
    await _enterRoom(pass);
  }

  Future<void> _prepareFlags() async {
    if (voiceConnection.deafened) await voiceConnection.clearDeafen();
  }

  Future<void> accept() async {
    if (state != CallState.incoming) return;
    final id = callId;
    final chat = chatId;
    if (id == null || chat == null) return;

    if (!await ensureMicrophonePermission()) {
      _failure = CallFailure.noMicrophone;
      decline();
      return;
    }
    if (callId != id) return;

    // Уведомление о входящем гасим сразу: иначе в шторке висели бы два —
    // «Входящий вызов» (несмахиваемое) и «Активный звонок».
    unawaited(pushService.clearIncomingCall(id));
    _setMine(CallMemberState.joining);
    _enterConnecting();
    await _prepareFlags();

    final CallPass pass;
    try {
      pass = await api.joinCall(chat, id, voiceConnection.selfFlags);
    } on ApiException catch (e) {
      if (callId != id) return;
      _failure = e.statusCode == 404 ? CallFailure.gone : CallFailure.notConnected;
      _reset();
      return;
    } catch (e, s) {
      if (callId != id) return;
      errorReporter.report(e, stack: s, screen: 'call:join');
      _failure = CallFailure.notConnected;
      _reset();
      return;
    }
    if (callId != id) return;
    _applyCall(pass.call);
    await _enterRoom(pass);
  }

  Future<void> acceptWaiting() async {
    final w = waitingCall;
    if (w == null) return;
    waitingCall = null;
    hangup(reason: 'switched');
    _presentIncoming(callId: w.callId, chatId: w.chatId, title: w.title,
        group: w.group, avatar: w.avatar, avatarColor: w.avatarColor,
        fromId: w.fromId, caller: w.caller, video: false, ring: false);
    await accept();
  }

  void declineWaiting() {
    final w = waitingCall;
    if (w == null) return;
    waitingCall = null;
    unawaited(api.declineCall(w.chatId, w.callId).catchError((Object _) {}));
    notifyListeners();
  }

  void decline() {
    final id = callId;
    final chat = chatId;
    if (id != null && chat != null) {
      unawaited(api.declineCall(chat, id).catchError((Object e, StackTrace s) {
        errorReporter.report(e, stack: s, screen: 'call:decline');
      }));
    }
    _reset();
  }

  void hangup({String? reason}) {
    final id = callId;
    final chat = chatId;
    Future<void>? leaving;
    if (id != null && chat != null && state != CallState.incoming) {
      leaving = api.leaveCall(chat, id).catchError((Object e, StackTrace s) {
        errorReporter.report(e, stack: s, screen: 'call:leave');
      });
    } else if (id != null && chat != null && state == CallState.incoming) {
      unawaited(api.declineCall(chat, id).catchError((Object _) {}));
    }
    _reset(leaving: leaving);
  }

  void endForAccountChange() {
    if (state == CallState.idle) return;
    hangup(reason: 'logout');
  }


  Future<void> _applyMute(bool value) async {
    if (!canControlAudio) return;
    await voiceConnection.setMicEnabled(!value);
  }

  Future<void> toggleSpeaker() async {
    if (!canControlAudio || !canSwitchSpeaker) return;
    speaker = !speaker;
    notifyListeners();
    await setSpeakerphone(speaker);
  }



  void _onWsEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'call.incoming':
        _onIncoming(event);
      case 'call.ring_ended':
        final id = event['call_id'];
        if (waitingCall?.callId == id) {
          waitingCall = null;
          notifyListeners();
        }
        if (state == CallState.incoming && callId == id) _reset();
      case 'call.ended':
        final id = event['call_id'];
        if (waitingCall?.callId == id) {
          waitingCall = null;
          notifyListeners();
        }
        if (callId == id && isBusy) _reset();
      case 'call.updated':
        if (event['call_id'] == callId) _applyCall(CurrentCall.fromJson(event));
    }
  }

  void _onIncoming(Map<String, dynamic> event) {
    final incomingId = event['call_id'];
    final chat = event['chat_id'];
    if (incomingId is! int || chat is! int) return;

    final declined = PushService.consumePendingDeclinedCall();
    if (declined != null && declined == incomingId) {
      unawaited(api.declineCall(chat, incomingId).catchError((Object _) {}));
      unawaited(pushService.clearIncomingCall(incomingId));
      unawaited(_moveAppToBackground());
      return;
    }

    final group = event['is_group'] == true;
    final from = event['from'];
    final fromMap = from is Map ? from : const {};
    final callerName = (fromMap['display_name'] as String?) ?? '';
    final callerId = fromMap['id'];
    final caller = callerId is int
        ? CallMember(
            userId: callerId,
            state: CallMemberState.connected,
            displayName: callerName,
            nickname: fromMap['nickname'] as String?,
            avatar: fromMap['avatar'] as String?,
            avatarColor: fromMap['avatar_color'] as String?,
          )
        : null;
    final title = group ? ((event['chat_name'] as String?) ?? callerName) : callerName;

    // Этот же звонок уже известен — досылка после переподключения сокета.
    if (incomingId == callId || incomingId == waitingCall?.callId) {
      _ackIncoming(incomingId);
      return;
    }

    if (isBusy) {
      waitingCall = WaitingCall(
        callId: incomingId,
        chatId: chat,
        title: title,
        group: group,
        avatar: group ? null : fromMap['avatar'] as String?,
        avatarColor: group ? null : parseAvatarColor(fromMap['avatar_color']),
        fromId: fromMap['id'] as int?,
        caller: caller,
      );
      _ackIncoming(incomingId);
      notifyListeners();
      return;
    }

    _presentIncoming(
      callId: incomingId,
      chatId: chat,
      title: title,
      group: group,
      avatar: group ? null : fromMap['avatar'] as String?,
      avatarColor: group ? null : parseAvatarColor(fromMap['avatar_color']),
      fromId: fromMap['id'] as int?,
      caller: caller,
      video: event['is_video'] == true,
    );

    if (!chatViewing.appInFront) {
      unawaited(pushService.showIncomingCall(
        callId: incomingId,
        chatId: chat,
        callerName: title,
        callerAvatar: group ? null : fromMap['avatar'] as String?,
      ));
    } else {
      unawaited(pushService.clearIncomingCall(incomingId));
    }
    _ackIncoming(incomingId);
    unawaited(_acceptPendingIfMatches());
  }

  void _presentIncoming({
    required int callId,
    required int chatId,
    required String title,
    required bool group,
    required String? avatar,
    required Color? avatarColor,
    required int? fromId,
    required CallMember? caller,
    required bool video,
    bool ring = true,
  }) {
    this.callId = callId;
    _provisional([if (caller != null) caller, _me(CallMemberState.ringing)]);
    this.chatId = chatId;
    isGroup = group;
    isVideo = video;
    peerId = fromId;
    peerName = title;
    peerAvatar = avatar;
    peerAvatarColor = avatarColor;
    speaker = false;
    elapsed = Duration.zero;
    state = CallState.incoming;
    if (ring) {
      unawaited(GlitchRingtone.playIncoming(callId: callId, silent: !appSounds.isOn(VoiceCue.ringtone)));
    }
    unawaited(GlitchTelecom.reportIncoming(title));
    unawaited(_setOverLockScreen(true));
    _startRingTimeout();
    notifyListeners();
  }

  void _ackIncoming(int id) =>
      wsService.send({'type': 'call.incoming.ack', 'call_id': id});


  CallMember _me(CallMemberState state) =>
      CallMember(userId: authService.currentUser?.id ?? 0, state: state);

  void _provisional(List<CallMember> members) {
    roster = members;
    _rosterVersion = -1;
  }

  void _setMine(CallMemberState state) {
    final me = authService.currentUser?.id;
    roster = [
      for (final m in roster)
        m.userId == me
            ? CallMember(userId: m.userId, state: state, displayName: m.displayName,
                nickname: m.nickname, avatar: m.avatar, avatarColor: m.avatarColor)
            : m,
    ];
    notifyListeners();
  }

  void _applyCall(CurrentCall? call) {
    if (call == null || call.callId != callId || call.members.isEmpty) return;
    if (call.version < _rosterVersion) return;
    _rosterVersion = call.version;
    roster = call.members;
    notifyListeners();
  }


  Future<void> _enterRoom(CallPass pass) async {
    final id = pass.callId;
    _callRoom = pass.pass.room;
    _startForegroundService();
    await setSpeakerphone(false);
    if (callId != id) return;
    try {
      await voiceConnection.connect(pass.pass);
    } on VoiceMicUnavailable {
      if (callId != id) return;
      _failure = CallFailure.noMicrophone;
      notifyListeners();
    } catch (e) {
      if (callId != id) return;
      _failure = CallFailure.notConnected;
      hangup(reason: 'connect_failed');
      return;
    }
    if (callId != id) return;
    final chat = chatId;
    if (chat != null) {
      voiceResume.rememberCall(
          room: pass.pass.room, chatId: chat, callId: id, title: peerName, isGroup: isGroup);
    }
    _onVoiceChanged();
  }

  void _onVoiceChanged() {
    if (!isBusy) return;
    if ((state == CallState.outgoing || state == CallState.connecting) &&
        voiceConnection.isConnected &&
        voiceConnection.othersCount > 0) {
      _startTalking();
    }
    notifyListeners();
  }

  void _onVoiceDropped(VoiceDrop drop) {
    if (!isBusy || state == CallState.incoming || drop.room != _callRoom) return;
    switch (drop.reason) {
      case VoiceDropReason.replaced:
        hangup(reason: 'switched_to_channel');
      case VoiceDropReason.removed:
      case VoiceDropReason.roomClosed:
        if (drop.cause == 'other_device') _failure = CallFailure.otherDevice;
        _reset();
      case VoiceDropReason.roomLost:
      case VoiceDropReason.lost:
        if (state == CallState.active) {
          unawaited(_rejoinRoom());
        } else {
          _failure = CallFailure.notConnected;
          hangup(reason: 'connection_lost');
        }
    }
  }

  /// Новый пропуск в тот же звонок и вход в комнату — сервер заведёт её на
  /// живой копии медиасервера (`call_pass` → `ensure_room`). Сам звонок
  /// (состояние, телефония, служба, таймер разговора, громкая связь) не
  /// сбрасывается: для человека это «Переподключение…», а не новый звонок.
  /// Сервер держит место в звонке `LEAVE_GRACE_SECONDS` — успели, и для
  /// собеседников он просто переподключился. Не вышло — звонок для нас
  /// кончился, как при обрыве связи.
  Future<void> _rejoinRoom() async {
    final id = callId;
    final chat = chatId;
    if (id == null || chat == null) return;
    try {
      final pass = await api.joinCall(chat, id, voiceConnection.selfFlags);
      if (callId != id || !isBusy) return;
      _callRoom = pass.pass.room;
      await voiceConnection.connect(pass.pass);
      if (callId != id) return;
      await setSpeakerphone(speaker);
      _onVoiceChanged();
    } on VoiceMicUnavailable {
      if (callId != id) return;
      _failure = CallFailure.noMicrophone;
      notifyListeners();
    } on ApiException catch (e) {
      if (callId != id) return;
      _failure = e.statusCode == 404 ? CallFailure.gone : CallFailure.notConnected;
      hangup(reason: 'connection_lost');
    } catch (e, s) {
      if (callId != id) return;
      errorReporter.report(e, stack: s, screen: 'call:rejoinRoom');
      _failure = CallFailure.notConnected;
      hangup(reason: 'connection_lost');
    }
  }

  void _startForegroundService() {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    final s = S.of(ctx);
    unawaited(CallForegroundService.start(
      peerName: peerName,
      ongoingText: s.callOngoing,
      hangUpText: s.callEndConversation,
    ));
  }

  void _startRingTimeout() {
    _ringTimeout?.cancel();
    _ringTimeout = Timer(_ringTimeoutDuration, () {
      if (state == CallState.incoming) _reset();
      if (state == CallState.outgoing) hangup(reason: 'ring_timeout');
    });
  }

  void _enterConnecting() {
    state = CallState.connecting;
    _ringTimeout?.cancel();
    _ringTimeout = null;
    unawaited(GlitchRingtone.stop());
    _connectTimeout?.cancel();
    _connectTimeout = Timer(_connectTimeoutDuration, () {
      if (state != CallState.connecting) return;
      _failure = CallFailure.notConnected;
      hangup(reason: 'connect_timeout');
    });
    notifyListeners();
  }

  void _startTalking() {
    if (state == CallState.active) return;
    state = CallState.active;
    unawaited(GlitchRingtone.stop());
    unawaited(GlitchTelecom.setActive().then((_) => setSpeakerphone(speaker)));
    _connectTimeout?.cancel();
    _connectTimeout = null;
    _ringTimeout?.cancel();
    _ringTimeout = null;
    _connectedAt = DateTime.now();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final since = _connectedAt;
      if (since == null) return;
      elapsed = DateTime.now().difference(since);
      notifyListeners();
    });
    notifyListeners();
  }

  /// Полный сброс. Идемпотентен: сюда приходят и по своему отбою, и по
  /// событию с сервера, и по отключению медиасервером. [leaving] — запрос
  /// «положил трубку», если сброс — свой отбой (см. `disconnectFrom`).
  void _reset({Future<void>? leaving}) {
    _connectTimeout?.cancel();
    _connectTimeout = null;
    _ringTimeout?.cancel();
    _ringTimeout = null;
    _ticker?.cancel();
    _ticker = null;
    _connectedAt = null;
    elapsed = Duration.zero;

    final id = callId;
    if (id != null) unawaited(pushService.clearIncomingCall(id));
    final room = _callRoom;
    _callRoom = null;
    voiceResume.forget(room);
    final channelHoldsVoice = voiceConnection.roomName != null && voiceConnection.roomName != room;
    if (!channelHoldsVoice) unawaited(CallForegroundService.stop());
    unawaited(GlitchRingtone.stop());
    unawaited(GlitchTelecom.setEnded().then((_) async {
      if (room != null) await setSpeakerphone(false);
    }));
    unawaited(_setOverLockScreen(false));
    if (room != null && voiceConnection.roomName == room) {
      unawaited(voiceConnection.disconnectFrom(room, after: leaving));
    }

    state = CallState.idle;
    callId = null;
    chatId = null;
    isGroup = false;
    peerId = null;
    peerName = '';
    peerAvatar = null;
    peerAvatarColor = null;
    speaker = false;
    waitingCall = null;
    roster = const [];
    _rosterVersion = -1;
    notifyListeners();
  }
}

final callProvider = CallProvider();
