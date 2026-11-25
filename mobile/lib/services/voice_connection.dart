import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:livekit_client/src/proto/livekit_models.pb.dart' as lk_pb show TrackSource;

import '../core/avatar_color.dart';
import '../core/call_audio_quality.dart';
import '../core/call_video_quality.dart';
import '../core/platform_info.dart';
import '../models/voice_pass.dart';
import 'app_sounds.dart';
import 'error_reporter.dart';
import 'keybinds.dart';
import 'voice_cue.dart';
import 'voice_debug.dart' show screenCaptureDebug, voiceDebugExchange;
import 'voice_ping.dart';
import 'websocket_service.dart';
import 'voice_audio_web.dart' if (dart.library.io) 'voice_audio_native.dart';
import 'call_screen_capture_web.dart' if (dart.library.io) 'call_screen_capture_native.dart';
import 'call_platform_web.dart' if (dart.library.io) 'call_platform_native.dart'
    show bindPageHide, callSupportsAudioInputSelection, callSupportsCameraSelection, ensureCameraPermission,
        unbindPageHide;
import 'call_audio_prefs.dart';
import 'mic_options.dart';
import 'mic_chain_web.dart' if (dart.library.io) 'mic_chain_native.dart';
import 'mic_test.dart';
import 'mic_test_web.dart' if (dart.library.io) 'mic_test_native.dart';

/// Глобальный одиночка, как `callProvider`: голос не принадлежит ни одному
/// экрану и обязан переживать любые переходы. Сбрасывается при выходе из
/// аккаунта (`reset`).
class VoiceConnection extends ChangeNotifier {
  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _events;

  VoiceLinkState state = VoiceLinkState.idle;

  String? roomName;

  bool micEnabled = true;
  bool deafened = false;

  Map<String, bool> get selfFlags => {'self_mute': !micEnabled, 'self_deaf': deafened};

  bool get cameraOn => _room?.localParticipant?.isCameraEnabled() ?? false;
  bool get screenOn => _room?.localParticipant?.isScreenShareEnabled() ?? false;
  bool frontCamera = true;

  bool micAllowed = true;
  bool hearAllowed = true;

  bool streamAllowed = true;

  final StreamController<VoiceDrop> _drops = StreamController.broadcast();
  Stream<VoiceDrop> get onDropped => _drops.stream;

  bool _leaving = false;

  _PendingDrop? _pendingDrop;
  static const _causeWait = Duration(seconds: 2);

  /// Подписка на сокет: причины отключения от сервера. Из AccountSession.start,
  /// как у остальных глобальных слушателей (сокет чистит их при выходе из
  /// аккаунта). Идемпотентно.
  void attach() {
    wsService.removeListener(_onWsEvent);
    wsService.addListener(_onWsEvent);
    wsService.removeReconnectListener(_onWsReconnected);
    wsService.addReconnectListener(_onWsReconnected);
    unawaited(callAudioPrefs.load().then((_) => personAudio.value++));
  }

  bool get isConnected => state == VoiceLinkState.connected || state == VoiceLinkState.reconnecting;

  String? get localIdentity => _identity;
  String? _identity;


  Future<void> connect(VoicePass pass) async {
    final pending = _pendingDrop;
    if (pending != null) {
      pending.timer.cancel();
      _pendingDrop = null;
      _drops.add(VoiceDrop(pending.room, pending.reason));
    }
    final previous = roomName;
    if (_room != null) {
      await disconnect();
      if (previous != null && previous != pass.room) {
        _drops.add(VoiceDrop(previous, VoiceDropReason.replaced));
      }
    }
    _leaving = false;

    final room = lk.Room(
      roomOptions: lk.RoomOptions(
        // Видео получает только тот, кто его смотрит, и в размер его плитки;
        // невостребованные слои отправитель не кодирует вовсе.
        adaptiveStream: true,
        dynacast: true,
        defaultCameraCaptureOptions: lk.CameraCaptureOptions(
          params: CallVideoQuality.camera,
          cameraPosition: frontCamera ? lk.CameraPosition.front : lk.CameraPosition.back,
        ),
        defaultScreenShareCaptureOptions: lk.ScreenShareCaptureOptions(
          params: CallVideoQuality.screen(phone: isAndroidPlatform),
        ),
        defaultAudioPublishOptions: const lk.AudioPublishOptions(encoding: CallAudioQuality.voice),
        defaultVideoPublishOptions: lk.VideoPublishOptions(
          screenShareEncoding: CallVideoQuality.screenEncoding(phone: isAndroidPlatform),
          degradationPreference: CallVideoQuality.degradation,
        ),
      ),
    );
    _room = room;
    roomName = pass.room;
    _identity = pass.identity;
    state = VoiceLinkState.connecting;
    bindPageHide(() => unawaited(disconnect()));
    prepareVoicePlayback();
    room.addListener(_onRoomChanged);
    _events = room.createListener()
      ..on<lk.ActiveSpeakersChangedEvent>((e) => _onSpeakers(room, e.speakers))
      ..on<lk.ParticipantAttributesChanged>((_) => _readTalking(room))
      ..on<lk.RoomReconnectingEvent>((_) {
        reconnects++;
        _setState(VoiceLinkState.reconnecting);
      })
      ..on<lk.RoomReconnectedEvent>((_) => _setState(VoiceLinkState.connected))
      ..on<lk.TrackSubscribedEvent>((e) => _onTrackSubscribed(e))
      ..on<lk.TrackUnsubscribedEvent>((e) {
        if (e.publication.kind == lk.TrackType.AUDIO) stopRemoteAudio(e.publication.sid);
      })
      ..on<lk.LocalTrackPublishedEvent>((e) {
        if (e.publication.source == lk.TrackSource.microphone) unawaited(_syncMic(room));
      })
      ..on<lk.LocalTrackUnpublishedEvent>((e) {
        if (!identical(_room, room)) return;
        if (e.publication.source == lk.TrackSource.screenShareVideo && !_screenStopping) {
          unawaited(releaseScreenCapture());
        }
        notifyListeners();
      })
      ..on<lk.ParticipantPermissionsUpdatedEvent>((e) => _onPermissions(room, e))
      ..on<lk.ParticipantMetadataUpdatedEvent>((_) => notifyListeners())
      ..on<lk.ParticipantNameUpdatedEvent>((_) => notifyListeners())
      ..on<lk.ParticipantConnectedEvent>((_) {
        _peerCue(room, VoiceCue.connected);
        _readTalking(room);
      })
      ..on<lk.ParticipantDisconnectedEvent>((_) {
        _peerCue(room, VoiceCue.disconnected);
        _readTalking(room);
      })
      ..on<lk.RoomDisconnectedEvent>((e) => _onDisconnected(room, e.reason));
    notifyListeners();

    try {
      await room.connect(pass.url, pass.token);
    } catch (e, s) {
      if (!identical(_room, room)) return; // пока подключались, ушли
      errorReporter.report(e, stack: s, screen: 'voice:connect');
      await _teardown(room);
      rethrow;
    }
    if (!identical(_room, room)) return;
    _readPermissions(room);
    _readTalking(room);
    connectedAt = DateTime.now();
    reconnects = 0;
    _setState(VoiceLinkState.connected);
    ping.start(room);
    if (_moving) {
      _movedAt = null;
      _cue(VoiceCue.moved);
    } else if (!pass.room.startsWith(_callRoomPrefix) || room.remoteParticipants.isNotEmpty) {
      _cue(VoiceCue.connected);
    }
    // Браузер не даёт играть звук без жеста человека. Вход в звонок и есть
    // жест (нажатие «Принять» / «Позвонить»), поэтому разрешаем здесь.
    unawaited(room.startAudio().catchError((Object _) {}));

    await _applyAudioChoice(room);
    if (!identical(_room, room)) return;

    if (micEnabled && micAllowed) {
      try {
        await _enableMic(room);
      } catch (e, s) {
        errorReporter.report(e, stack: s, screen: 'voice:microphone');
        micEnabled = false;
        notifyListeners();
        _reportFlags();
        throw VoiceMicUnavailable(e);
      }
    }
  }

  /// Выйти из комнаты и отпустить всё захваченное. Идемпотентно.
  Future<void> disconnect() async {
    final room = _room;
    if (room == null) return;
    _leaving = true;
    await _teardown(room);
  }

  Future<void> _teardown(lk.Room room) async {
    // Свой выход — звуком, если мы правда были в комнате: неудавшийся вход
    // и повторный вызов (teardown идемпотентен) молчат.
    if (identical(_room, room) && isConnected && !_moving) _cue(VoiceCue.disconnected);
    if (identical(_room, room)) {
      unbindPageHide();
      _room = null;
      screenCaptureDebug.sync(null, null);
      roomName = null;
      _identity = null;
      state = VoiceLinkState.idle;
      unawaited(releaseScreenCapture());
      unawaited(releaseMicChain().catchError((Object e, StackTrace s) {
        errorReporter.report(e, stack: s, screen: 'voice:micChainRelease');
      }));
      unawaited(stopMicTest());
      stopAllRemoteAudio();
      _pttReset();
      micAllowed = true;
      hearAllowed = true;
      streamAllowed = true;
      _clearSpeakers();
      _cards.clear();
      ping.stop();
      voiceDebugExchange.reset();
      connectedAt = null;
      reconnects = 0;
    }
    room.removeListener(_onRoomChanged);
    final events = _events;
    _events = null;
    try {
      await room.disconnect();
    } catch (e, s) {
      errorReporter.report(e, stack: s, screen: 'voice:disconnect');
    }
    try {
      await events?.dispose();
      await room.dispose();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> reset() async {
    _pendingDrop?.timer.cancel();
    _pendingDrop = null;
    await disconnect();
    micEnabled = true;
    deafened = false;
    frontCamera = true;
    await stopCameraTest();
    await callAudioPrefs.clearPeople();
    personAudio.value++;
  }

  void _setState(VoiceLinkState next) {
    if (state == next) return;
    state = next;
    _pttChanged();
    unawaited(_syncInputMonitor());
    notifyListeners();
  }

  void _onDisconnected(lk.Room room, lk.DisconnectReason? reason) {
    if (!identical(_room, room)) return;
    final name = roomName ?? '';
    final byUs = _leaving || reason == lk.DisconnectReason.clientInitiated;
    unawaited(_teardown(room));
    if (byUs) return;
    final kind = switch (reason) {
      lk.DisconnectReason.participantRemoved ||
      lk.DisconnectReason.duplicateIdentity => VoiceDropReason.removed,
      lk.DisconnectReason.roomDeleted => VoiceDropReason.roomClosed,
      _ => VoiceDropReason.lost,
    };
    if (kind == VoiceDropReason.lost) {
      _drops.add(VoiceDrop(name, kind));
      return;
    }
    _pendingDrop?.timer.cancel();
    _pendingDrop = _PendingDrop(name, kind, Timer(_causeWait, () {
      final pending = _pendingDrop;
      if (pending == null || pending.room != name) return;
      _pendingDrop = null;
      _drops.add(VoiceDrop(name, kind));
    }));
  }

  void _onWsEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'voice.disconnected':
        _onServerDisconnect(event);
      case 'voice.state':
        _onOwnState(event);
      case 'voice.debug.request' || 'voice.debug.report':
        voiceDebugExchange.onWsEvent(event);
    }
  }

  void _onWsReconnected() {
    if (!isConnected) return;
    _sendFlags();
    _sendTalking();
  }

  void _onOwnState(Map<String, dynamic> event) {
    if (_room == null || event['chat_id'] == null) return; // не в голосе / «вышел»
    final me = VoiceMember._parseIdentity(_identity ?? '');
    if (me == null || event['user_id'] != me.$1 || event['session_id'] != me.$2) return;
    if (_pttOpen) _sendTalking();
    if (event['self_mute'] == !micEnabled && event['self_deaf'] == deafened) return;
    _sendFlags();
  }

  void _onServerDisconnect(Map<String, dynamic> event) {
    final room = event['room'];
    if (room is! String) return;
    final cause = event['reason'] as String?;
    final toChat = event['to_chat_id'];
    final toName = (event['to_name'] as String?) ?? '';
    VoiceDrop drop(VoiceDropReason kind) => VoiceDrop(room, kind,
        cause: cause, moveToChatId: toChat is int ? toChat : null, moveToName: toName);
    final lostRoom = cause == 'room_lost';
    if (cause == 'moved') _movedAt = DateTime.now();

    final pending = _pendingDrop;
    if (pending != null && pending.room == room) {
      pending.timer.cancel();
      _pendingDrop = null;
      _drops.add(drop(lostRoom ? VoiceDropReason.roomLost : pending.reason));
      return;
    }
    if (roomName != room) return; // уже не там — старое известие
    unawaited(disconnect());
    _drops.add(drop(lostRoom ? VoiceDropReason.roomLost : VoiceDropReason.removed));
  }

  Future<void> disconnectFrom(String room, {Future<void>? after}) async {
    if (roomName != room) return;
    if (after != null) {
      _leaving = true;
      await after.timeout(_leaveAckWait, onTimeout: () {});
      if (roomName != room) return;
    }
    await disconnect();
  }

  static const _leaveAckWait = Duration(seconds: 2);

  void _onPermissions(lk.Room room, lk.ParticipantPermissionsUpdatedEvent e) {
    if (!identical(_room, room) || e.participant is! lk.LocalParticipant) return;
    final couldSpeak = micAllowed;
    _readPermissions(room);
    _pttChanged();
    notifyListeners();
    if (!couldSpeak && micAllowed && micEnabled && state == VoiceLinkState.connected) {
      unawaited(_publishMicrophone(room));
    }
  }

  Future<void> _publishMicrophone(lk.Room room) async {
    try {
      await _enableMic(room);
    } catch (e, s) {
      errorReporter.report(e, stack: s, screen: 'voice:micAfterPermission');
    }
    notifyListeners();
  }

  void _readPermissions(lk.Room room) {
    final p = room.localParticipant?.permissions;
    if (p == null) return;
    bool may(lk_pb.TrackSource source) =>
        p.canPublish && (p.canPublishSources.isEmpty || p.canPublishSources.contains(source));
    micAllowed = may(lk_pb.TrackSource.MICROPHONE);
    streamAllowed = may(lk_pb.TrackSource.CAMERA) && may(lk_pb.TrackSource.SCREEN_SHARE);
    hearAllowed = p.canSubscribe;
  }

  void _onTrackSubscribed(lk.TrackSubscribedEvent e) {
    if (e.publication.kind != lk.TrackType.AUDIO) return;
    final userId = _userOf(e.participant);
    playRemoteAudio(e.publication.sid, e.track, _levelOf(userId, e.publication.source));
    if (!_shouldHear(e.participant, e.publication.source)) unawaited(e.publication.disable());
  }


  Future<void> setMicEnabled(bool enabled) async {
    await stopMicTest();
    await _setFlags(mic: enabled, deaf: deafened);
  }

  Future<void> toggleMute() async {
    if (micTesting) return stopMicTest();
    if (deafened) return toggleDeafen();
    _cueFlags(to: (mic: !micEnabled, deaf: false));
    await _setFlags(mic: !micEnabled, deaf: false);
  }

  Future<void> toggleDeafen() async {
    if (micTesting) return stopMicTest();
    _cueFlags(to: (mic: deafened, deaf: !deafened));
    await _setFlags(mic: deafened, deaf: !deafened);
  }

  void _cueFlags({required ({bool mic, bool deaf}) to}) {
    if (to.deaf != deafened) {
      _cue(to.deaf ? VoiceCue.deafen : VoiceCue.undeafen, dedupe: false);
    } else if (to.mic != micEnabled) {
      _cue(to.mic ? VoiceCue.micOn : VoiceCue.micOff, dedupe: false);
    }
  }

  Future<void> clearDeafen() async {
    await stopMicTest();
    await _setFlags(mic: micEnabled, deaf: false);
  }

  Future<void> restoreFlags({required bool mic, required bool deaf}) async {
    await stopMicTest();
    await _setFlags(mic: mic, deaf: deaf);
  }

  bool get chosenMic => _flagsBeforeTest?.mic ?? micEnabled;
  bool get chosenDeaf => _flagsBeforeTest?.deaf ?? deafened;

  Future<void> _setFlags({required bool mic, required bool deaf}) async {
    final micChanged = mic != micEnabled;
    final deafChanged = deaf != deafened;
    if (!micChanged && !deafChanged) return;
    micEnabled = mic;
    deafened = deaf;
    _pttChanged();
    notifyListeners();
    _reportFlags();
    final room = _room;
    if (room == null || !isConnected) return;
    if (deafChanged) await _applyHearing(room);
    if (micChanged && micAllowed) await _applyMic(room);
  }

  Future<void> _applyMic(lk.Room room) async {
    final local = room.localParticipant;
    if (local == null) return;
    try {
      if (micEnabled) {
        await _enableMic(room);
      } else {
        await local.setMicrophoneEnabled(false);
      }
    } catch (e, s) {
      errorReporter.report(e, stack: s, screen: 'voice:setMicrophoneEnabled');
      if (!identical(_room, room)) return;
      micEnabled = local.isMicrophoneEnabled();
      notifyListeners();
      _reportFlags();
    }
  }

  Future<void> _applyHearing(lk.Room room, {int? onlyUser, String? onlyIdentity}) async {
    for (final p in room.remoteParticipants.values) {
      final userId = _userOf(p);
      if (onlyUser != null && userId != onlyUser) continue;
      if (onlyIdentity != null && p.identity != onlyIdentity) continue;
      for (final pub in p.audioTrackPublications) {
        try {
          await (_shouldHear(p, pub.source) ? pub.enable() : pub.disable());
        } catch (e, s) {
          errorReporter.report(e, stack: s, screen: 'voice:hearing');
        }
      }
    }
  }

  void _reportFlags() {
    if (isConnected) _sendFlags();
  }

  void _sendFlags() {
    try {
      wsService.send({'type': 'voice.update', ...selfFlags});
    } catch (e, s) {
      errorReporter.report(e, stack: s, screen: 'voice:update');
    }
  }

  Future<bool> setCameraEnabled(bool enabled) async {
    final local = _room?.localParticipant;
    if (local == null) return false;
    try {
      if (enabled) {
        await local.setCameraEnabled(
          true,
          cameraCaptureOptions: lk.CameraCaptureOptions(
            params: CallVideoQuality.camera,
            cameraPosition: frontCamera ? lk.CameraPosition.front : lk.CameraPosition.back,
            deviceId: await _cameraToUse(),
          ),
        );
      } else {
        final camera = local.getTrackPublicationBySource(lk.TrackSource.camera);
        if (camera != null) await local.removePublishedTrack(camera.sid);
      }
      notifyListeners();
      return true;
    } catch (e, s) {
      errorReporter.report(e, stack: s, screen: 'voice:setCameraEnabled');
      notifyListeners();
      return false;
    }
  }

  Future<void> flipCamera() async {
    frontCamera = !frontCamera;
    notifyListeners();
    final track = _room?.localParticipant
        ?.getTrackPublicationBySource(lk.TrackSource.camera)
        ?.track;
    if (track is lk.LocalVideoTrack) {
      try {
        await track.setCameraPosition(frontCamera ? lk.CameraPosition.front : lk.CameraPosition.back);
      } catch (e, s) {
        errorReporter.report(e, stack: s, screen: 'voice:flipCamera');
      }
    }
  }


  bool get canStream => state == VoiceLinkState.connected && streamAllowed;

  Future<void> toggleCamera() async {
    if (cameraOn) {
      await setCameraEnabled(false);
      return;
    }
    if (!canStream) return;
    final room = _room;
    if (!await ensureCameraPermission()) return;
    if (!identical(_room, room) || !canStream) return;
    await setCameraEnabled(true);
  }

  /// Включить или выключить показ экрана. true — показ включился, но звук
  /// всего экрана снят: браузер не умеет убрать из него голоса собеседников, и
  /// они вернулись бы в канал эхом (call_screen_capture_web.startScreenShare).
  /// Сказать об этом человеку — дело кнопки.
  Future<bool> toggleScreenShare() async {
    if (screenOn) {
      await _stopScreenShare();
      await releaseScreenCapture();
      return false;
    }
    if (!canStream || !screenCaptureSupported) return false;
    final room = _room;
    if (!await prepareScreenCapture()) return false;
    if (!identical(_room, room) || !canStream) {
      await releaseScreenCapture();
      return false;
    }
    final soundDropped = await _startScreenShare();
    if (soundDropped == null) await releaseScreenCapture();
    return soundDropped ?? false;
  }

  bool _wakelockOn = false;

  void _syncWakelock() {
    final want = isConnected && members.any((m) => m.camera != null || m.screen != null);
    if (want == _wakelockOn) return;
    _wakelockOn = want;
    unawaited(WakelockPlus.toggle(enable: want).catchError((_) {}));
  }

  @override
  void notifyListeners() {
    final before = _members;
    _members = _membersOf(_room);
    _streamCues(before, _members);
    _pruneWatching();
    _audioBlockedSeen = audioBlocked;
    _syncWakelock();
    final screen = _room?.localParticipant?.getTrackPublicationBySource(lk.TrackSource.screenShareVideo);
    screenCaptureDebug.sync(_screenStopping || screen?.muted == true ? null : screen?.track, screen?.sid);
    super.notifyListeners();
  }

  void _onRoomChanged() {
    final next = _membersOf(_room);
    if (audioBlocked == _audioBlockedSeen && VoiceMember.sameList(_members, next)) return;
    notifyListeners();
  }

  Future<bool?> _startScreenShare() async {
    final local = _room?.localParticipant;
    if (local == null) return null;
    try {
      final soundDropped = await startScreenShare(local);
      notifyListeners();
      return screenOn ? soundDropped : null;
    } catch (e, s) {
      _reportCaptureError(e, s, 'voice:startScreenShare');
      notifyListeners();
      return null;
    }
  }

  void _reportCaptureError(Object e, StackTrace s, String screen) {
    final text = e.toString();
    if (text.contains('NotAllowed') || text.contains('Permission') || text.contains('permission')) return;
    errorReporter.report(e, stack: s, screen: screen);
  }

  bool get canChangeScreenSource => screenSourceChangeable && screenOn;

  Future<bool?> changeScreenSource() async {
    final local = _room?.localParticipant;
    if (local == null || !canChangeScreenSource) return null;
    final previous = local.getTrackPublicationBySource(lk.TrackSource.screenShareVideo)?.sid;
    final ScreenCapture capture;
    try {
      capture = await captureScreen(local);
    } catch (e, s) {
      _reportCaptureError(e, s, 'voice:changeScreenSource');
      return null;
    }
    if (!identical(_room?.localParticipant, local) || !canStream || !screenOn ||
        local.getTrackPublicationBySource(lk.TrackSource.screenShareVideo)?.sid != previous) {
      await discardScreen(capture);
      return null;
    }
    await _stopScreenShare();
    if (!identical(_room?.localParticipant, local) || !canStream || screenOn) {
      await discardScreen(capture);
      return null;
    }
    try {
      final soundDropped = await publishScreen(local, capture);
      notifyListeners();
      return screenOn ? soundDropped : null;
    } catch (e, s) {
      _reportCaptureError(e, s, 'voice:changeScreenSource');
      notifyListeners();
      return null;
    }
  }

  bool _screenStopping = false;

  Future<void> _stopScreenShare() async {
    final local = _room?.localParticipant;
    if (local == null) return;
    _screenStopping = true;
    notifyListeners();
    try {
      await local.setScreenShareEnabled(false);
    } catch (e, s) {
      errorReporter.report(e, stack: s, screen: 'voice:stopScreenShare');
    } finally {
      _screenStopping = false;
    }
    notifyListeners();
  }


  Future<void> setSpeakerPreferred(bool on) async {
    final audio = lk.AudioManager.instance;
    if (!audio.canSwitchSpeakerphone) return;
    try {
      await audio.setSpeakerOutputPreferred(on);
    } catch (e, s) {
      errorReporter.report(e, stack: s, screen: 'voice:setSpeakerOutputPreferred');
    }
  }

  Future<bool> requestScreenCapturePermission() =>
      lk.Hardware.instance.requestCapturePermission();


  bool get canSelectInput => callSupportsAudioInputSelection;
  bool get canSelectOutput => outputDeviceSelectionSupported;
  bool get canSetOutputVolume => outputVolumeSupported;

  List<VoiceAudioDevice> inputDevices = const [];
  List<VoiceAudioDevice> outputDevices = const [];

  String? get inputDeviceId => _shownDevice(inputDevices, callAudioPrefs.inputId);
  String? get outputDeviceId => _shownDevice(outputDevices, callAudioPrefs.outputId);

  static String? _shownDevice(List<VoiceAudioDevice> devices, String? saved) {
    if (devices.isEmpty) return null;
    if (saved != null && devices.any((d) => d.id == saved)) return saved;
    return devices.any((d) => d.id == 'default') ? 'default' : devices.first.id;
  }

  Future<void> refreshAudioDevices() async {
    await callAudioPrefs.load();
    outputVolume = callAudioPrefs.volume;
    if (!canSelectInput && !canSelectOutput) {
      notifyListeners();
      return;
    }
    try {
      if (canSelectInput) {
        inputDevices = [for (final d in await lk.Hardware.instance.audioInputs()) (id: d.deviceId, label: d.label)];
      }
      if (canSelectOutput) {
        outputDevices = [for (final d in await lk.Hardware.instance.audioOutputs()) (id: d.deviceId, label: d.label)];
      }
    } catch (e, s) {
      errorReporter.report(e, stack: s, screen: 'voice:enumerateDevices');
    }
    notifyListeners();
  }

  Future<void> chooseInput(String deviceId) async {
    if (!canSelectInput) return;
    await callAudioPrefs.saveInput(deviceId);
    notifyListeners();
    await _selectInput(deviceId);
    await _captureChanged();
  }

  Future<void> chooseOutput(String deviceId) async {
    if (!canSelectOutput) return;
    await callAudioPrefs.saveOutput(deviceId);
    notifyListeners();
    await _selectOutput(deviceId);
    try {
      await _micTest?.setOutput(deviceId);
    } catch (e, s) {
      errorReporter.report(e, stack: s, screen: 'voice:micTestOutput');
    }
  }

  double outputVolume = 1.0;

  void setOutputVolume(double volume, {bool persist = false}) {
    if (!canSetOutputVolume) return;
    callAudioPrefs.setVolume(volume);
    outputVolume = callAudioPrefs.volume;
    applyOutputVolume(outputVolume);
    _micTest?.setVolume(outputVolume);
    notifyListeners();
    if (persist) unawaited(callAudioPrefs.saveVolume());
  }

  Future<void> _applyAudioChoice(lk.Room room) async {
    await callAudioPrefs.load();
    final input = callAudioPrefs.inputId;
    if (canSelectInput && input != null) await _selectInput(input);
    final output = callAudioPrefs.outputId;
    if (canSelectOutput && output != null) await _selectOutput(output);
    if (canSetOutputVolume) {
      outputVolume = callAudioPrefs.volume;
      applyOutputVolume(outputVolume);
    }
  }

  Future<void> _selectInput(String deviceId) async {
    try {
      final device = (await lk.Hardware.instance.audioInputs()).where((d) => d.deviceId == deviceId).firstOrNull;
      if (device != null) lk.Hardware.instance.selectedAudioInput = device;
    } catch (e, s) {
      errorReporter.report(e, stack: s, screen: 'voice:selectAudioInput');
    }
  }

  Future<void> _selectOutput(String deviceId) async {
    try {
      final device = (await lk.Hardware.instance.audioOutputs()).where((d) => d.deviceId == deviceId).firstOrNull;
      if (device == null) return;
      final room = _room;
      if (room == null) {
        lk.Hardware.instance.selectedAudioOutput = device;
      } else {
        await room.setAudioOutputDevice(device);
      }
      await setVoiceOutputDevice(deviceId);
    } catch (e, s) {
      errorReporter.report(e, stack: s, screen: 'voice:selectAudioOutput');
    }
  }


  bool get canSelectCamera => callSupportsCameraSelection;

  List<VoiceAudioDevice> cameraDevices = const [];

  String? get cameraDeviceId => _shownDevice(cameraDevices, callAudioPrefs.cameraId);

  Future<void> refreshCameras() async {
    if (!canSelectCamera) return;
    await callAudioPrefs.load();
    try {
      cameraDevices = [
        for (final d in await lk.Hardware.instance.videoInputs())
          if (d.deviceId.isNotEmpty) (id: d.deviceId, label: d.label),
      ];
    } catch (e, s) {
      errorReporter.report(e, stack: s, screen: 'voice:enumerateCameras');
    }
    notifyListeners();
  }

  Future<void> chooseCamera(String deviceId) async {
    if (!canSelectCamera) return;
    await callAudioPrefs.saveCamera(deviceId);
    notifyListeners();
    final live = _room?.localParticipant?.getTrackPublicationBySource(lk.TrackSource.camera)?.track;
    final test = cameraTest;
    for (final track in [if (live is lk.LocalVideoTrack) live, if (test != null) test]) {
      try {
        await track.switchCamera(deviceId);
      } catch (e, s) {
        errorReporter.report(e, stack: s, screen: 'voice:switchCamera');
      }
    }
    notifyListeners();
  }

  Future<String?> _cameraToUse() async {
    if (!canSelectCamera) return null;
    await callAudioPrefs.load();
    try {
      final ids = [
        for (final d in await lk.Hardware.instance.videoInputs())
          if (d.deviceId.isNotEmpty) d.deviceId,
      ];
      final saved = callAudioPrefs.cameraId;
      if (saved != null && ids.contains(saved)) return saved;
      return ids.firstOrNull;
    } catch (e, s) {
      errorReporter.report(e, stack: s, screen: 'voice:enumerateCameras');
      return null;
    }
  }

  lk.LocalVideoTrack? cameraTest;

  int _cameraTestSeq = 0;

  Future<bool> startCameraTest() async {
    if (cameraTest != null) return true;
    final seq = ++_cameraTestSeq;
    try {
      if (!await ensureCameraPermission()) return false;
      final track = await lk.LocalVideoTrack.createCameraTrack(lk.CameraCaptureOptions(
        params: CallVideoQuality.camera,
        deviceId: await _cameraToUse(),
      ));
      if (seq != _cameraTestSeq) {
        await track.stop();
        return false;
      }
      cameraTest = track;
      notifyListeners();
      unawaited(refreshCameras());
      return true;
    } catch (e, s) {
      errorReporter.report(e, stack: s, screen: 'voice:cameraTest');
      return false;
    }
  }

  Future<void> stopCameraTest() async {
    _cameraTestSeq++;
    final track = cameraTest;
    if (track == null) return;
    cameraTest = null;
    notifyListeners();
    try {
      await track.stop();
    } catch (e, s) {
      errorReporter.report(e, stack: s, screen: 'voice:cameraTestStop');
    }
  }

  final VoicePing ping = VoicePing();

  DateTime? connectedAt;
  int reconnects = 0;

  lk.Room? get statsRoom => _room;


  final ValueNotifier<Set<int>> speakers = ValueNotifier(const {});

  static const Duration _speakingHold = Duration(milliseconds: 250);

  Set<int> _heard = const {};

  final Map<int, Timer> _speakingOff = {};

  Set<int> _talking = const {};

  /// Перечитать «передаёт» у остальных — на смену атрибутов и состава
  /// комнаты. Целиком из комнаты: пропущенное событие не оставит обводку.
  void _readTalking(lk.Room room) {
    if (!identical(_room, room)) return;
    _talking = {
      for (final p in room.remoteParticipants.values)
        if (p.attributes['ptt'] == '1')
          if (VoiceMember._parseIdentity(p.identity)?.$1 case final id?) id,
    };
    _publishSpeakers();
  }

  void _onSpeakers(lk.Room room, List<lk.Participant> list) {
    if (!identical(_room, room)) return;
    final heard = <int>{};
    for (final p in list) {
      final id = VoiceMember._parseIdentity(p.identity)?.$1;
      if (id != null) heard.add(id);
    }
    _heard = heard;
    for (final id in heard) {
      _speakingOff.remove(id)?.cancel();
    }
    for (final id in speakers.value) {
      if (heard.contains(id) || _speakingOff.containsKey(id)) continue;
      _speakingOff[id] = Timer(_speakingHold, () {
        _speakingOff.remove(id);
        _publishSpeakers();
      });
    }
    _publishSpeakers();
  }

  void _publishSpeakers() {
    final me = _pttOpen ? VoiceMember._parseIdentity(_identity ?? '')?.$1 : null;
    final shown = {..._heard, ..._speakingOff.keys, ..._talking, if (me != null) me};
    if (!setEquals(shown, speakers.value)) speakers.value = Set.unmodifiable(shown);
  }

  void _clearSpeakers() {
    for (final t in _speakingOff.values) {
      t.cancel();
    }
    _speakingOff.clear();
    _heard = const {};
    _talking = const {};
    _publishSpeakers();
  }


  final ValueNotifier<int> personAudio = ValueNotifier(0);

  double personVolume(int userId) => callAudioPrefs.voice.volumeOf(userId);
  bool isPersonMuted(int userId) => callAudioPrefs.voice.isMuted(userId);

  void setPersonVolume(int userId, double volume, {bool persist = false}) =>
      _setPeopleVolume(callAudioPrefs.voice, userId, volume, persist: persist);

  Future<void> togglePersonMuted(int userId) => _togglePeopleMuted(callAudioPrefs.voice, userId);


  double streamVolume(int userId) => callAudioPrefs.stream.volumeOf(userId);
  bool isStreamMuted(int userId) => callAudioPrefs.stream.isMuted(userId);

  void setStreamVolume(int userId, double volume, {bool persist = false}) =>
      _setPeopleVolume(callAudioPrefs.stream, userId, volume, persist: persist);

  Future<void> toggleStreamMuted(int userId) => _togglePeopleMuted(callAudioPrefs.stream, userId);

  void _setPeopleVolume(PeopleAudio prefs, int userId, double volume, {required bool persist}) {
    prefs.setVolume(userId, volume);
    _applyPerson(userId);
    personAudio.value++;
    if (persist) unawaited(prefs.saveVolumes());
  }

  Future<void> _togglePeopleMuted(PeopleAudio prefs, int userId) async {
    await callAudioPrefs.load();
    final saving = prefs.saveMuted(userId, !prefs.isMuted(userId));
    _applyPerson(userId);
    personAudio.value++;
    await saving;
  }

  static int? _userOf(lk.Participant p) => VoiceMember._parseIdentity(p.identity)?.$1;

  static bool _isVoice(lk.TrackSource source) => source == lk.TrackSource.microphone;

  double _levelOf(int? userId, lk.TrackSource source) {
    final prefs = _peopleAudioOf(source);
    if (userId == null || prefs == null) return 1;
    return prefs.isMuted(userId) ? 0 : prefs.volumeOf(userId);
  }

  static PeopleAudio? _peopleAudioOf(lk.TrackSource source) => _isVoice(source)
      ? callAudioPrefs.voice
      : source == lk.TrackSource.screenShareAudio
          ? callAudioPrefs.stream
          : null;

  bool _shouldHear(lk.Participant p, lk.TrackSource source) {
    if (deafened) return false;
    if (source == lk.TrackSource.screenShareAudio && !isWatching(p.identity)) return false;
    final userId = _userOf(p);
    final prefs = _peopleAudioOf(source);
    return !(userId != null && prefs != null && prefs.isMuted(userId));
  }


  final List<String> _watching = [];

  bool isWatching(String identity) => _watching.contains(identity);

  String? get lastWatched => _watching.isEmpty ? null : _watching.last;

  void watch(String identity) {
    if (lastWatched == identity) return;
    _watching
      ..remove(identity)
      ..add(identity);
    final room = _room;
    if (room != null) unawaited(_applyHearing(room, onlyIdentity: identity));
    notifyListeners();
  }

  void stopWatching(String identity) {
    if (!_watching.remove(identity)) return;
    final room = _room;
    if (room != null) unawaited(_applyHearing(room, onlyIdentity: identity));
    notifyListeners();
  }

  void stopWatchingAll() {
    if (_watching.isEmpty) return;
    _watching.clear();
    final room = _room;
    if (room != null) unawaited(_applyHearing(room));
    notifyListeners();
  }

  void _pruneWatching() {
    _watching.removeWhere((id) => !_members.any((m) => m.identity == id && m.screen != null));
  }

  void _applyPerson(int userId) {
    final room = _room;
    if (room == null) return;
    for (final p in room.remoteParticipants.values) {
      if (_userOf(p) != userId) continue;
      for (final pub in p.audioTrackPublications) {
        setRemoteAudioLevel(pub.sid, _levelOf(userId, pub.source));
      }
    }
    unawaited(_applyHearing(room, onlyUser: userId));
  }


  bool get echoCancellation => callAudioPrefs.echoCancellation;
  bool get autoGainControl => callAudioPrefs.autoGainControl;

  Future<void> setEchoCancellation(bool on) async {
    await callAudioPrefs.load();
    final saving = callAudioPrefs.saveEchoCancellation(on);
    notifyListeners();
    await saving;
    await _captureChanged();
  }

  Future<void> setAutoGainControl(bool on) async {
    await callAudioPrefs.load();
    final saving = callAudioPrefs.saveAutoGainControl(on);
    notifyListeners();
    await saving;
    await _captureChanged();
  }

  Future<lk.AudioCaptureOptions> _micCapture() async {
    await callAudioPrefs.load();
    return micCaptureOptions(
      deviceId: await _connectedInput(),
      echoCancellation: callAudioPrefs.echoCancellation,
      autoGainControl: callAudioPrefs.autoGainControl,
    );
  }

  Future<String?> _connectedInput() async {
    final saved = callAudioPrefs.inputId;
    if (!canSelectInput || saved == null) return null;
    try {
      final inputs = await lk.Hardware.instance.audioInputs();
      return inputs.any((d) => d.deviceId == saved) ? saved : null;
    } catch (e, s) {
      errorReporter.report(e, stack: s, screen: 'voice:enumerateInputs');
      return null;
    }
  }

  lk.LocalAudioTrack? _micTrack(lk.Room room) =>
      room.localParticipant?.getTrackPublicationBySource(lk.TrackSource.microphone)?.track as lk.LocalAudioTrack?;

  Future<void> _enableMic(lk.Room room) async {
    final options = await _micCapture();
    final local = room.localParticipant;
    if (local == null || !identical(_room, room)) return;
    _micTrack(room)?.currentOptions = options;
    await local.setMicrophoneEnabled(true, audioCaptureOptions: options);
    unawaited(_syncMic(room));
  }

  /// Перезахваты — строго по очереди: два переключателя подряд не должны
  /// перезапускать одну дорожку одновременно.
  Future<void> _recaptureQueue = Future.value();

  Future<void> _captureChanged() async {
    final next = _recaptureQueue.then((_) => _recaptureMic());
    _recaptureQueue = next.catchError((Object _) {});
    await next;
    if (micTesting) await _reopenMicTest();
    await _reopenInputMonitor();
  }

  Future<void> _recaptureMic() async {
    final room = _room;
    if (room == null) return;
    final options = await _micCapture();
    final track = _micTrack(room);
    if (track == null || !identical(_room, room)) return;
    track.currentOptions = options;
    if (track.muted) return;
    try {
      await track.restartTrack();
    } catch (e, s) {
      errorReporter.report(e, stack: s, screen: 'voice:recaptureMic');
      return;
    }
    unawaited(_syncMic(room));
  }


  static const double _noiseAttenuationDb = 80;

  bool get noiseSuppression => callAudioPrefs.noiseSuppression;

  bool _noiseFailed = false;

  bool get noiseAvailable => noiseFilterSupported && !_noiseFailed;

  bool get noiseActive => noiseSuppression && noiseAvailable;

  Future<bool> toggleNoiseSuppression() async {
    if (!noiseAvailable) return false;
    await callAudioPrefs.load();
    final saving = callAudioPrefs.saveNoiseSuppression(!noiseSuppression);
    notifyListeners();
    await saving;
    await _processingChanged();
    return noiseAvailable;
  }


  bool get canSetMicVolume => micVolumeSupported;

  double get micVolume => callAudioPrefs.micVolume;

  void setMicVolume(double volume, {bool persist = false}) {
    if (!canSetMicVolume) return;
    callAudioPrefs.setMicVolume(volume);
    notifyListeners();
    unawaited(_processingChanged());
    if (persist) unawaited(callAudioPrefs.saveMicVolume());
  }


  bool get canSetSensitivity => micGateSupported;

  bool get autoSensitivity => callAudioPrefs.autoSensitivity;

  double get sensitivityDb => callAudioPrefs.sensitivityDb.toDouble();

  Future<void> setAutoSensitivity(bool on) async {
    if (!canSetSensitivity) return;
    await callAudioPrefs.load();
    final saving = callAudioPrefs.saveAutoSensitivity(on);
    notifyListeners();
    await saving;
    await _processingChanged();
  }

  void setSensitivity(double db, {bool persist = false}) {
    if (!canSetSensitivity) return;
    final rounded = db.round();
    if (rounded != callAudioPrefs.sensitivityDb) {
      callAudioPrefs.setSensitivity(rounded);
      notifyListeners();
      unawaited(_processingChanged());
    }
    if (persist) unawaited(callAudioPrefs.saveSensitivity());
  }

  MicGate? get _micGate =>
      canSetSensitivity && !pushToTalk ? (auto: autoSensitivity, thresholdDb: sensitivityDb) : null;


  final ValueNotifier<double> inputLevelDb = ValueNotifier(kMicSilenceDb);

  int _inputMeterUsers = 0;
  Timer? _inputMeterTimer;
  bool _inputMeterReading = false;

  MicTest? _inputMonitor;
  bool _inputMonitorOpening = false;

  int _inputMonitorAttempt = 0;

  bool _inputMonitorFailed = false;

  void watchInputLevel() {
    if (_inputMeterUsers++ > 0) return;
    _inputMonitorFailed = false;
    _inputMeterTimer = Timer.periodic(_micTestMeterTick, (_) => unawaited(_readInputLevel()));
    unawaited(_syncInputMonitor());
  }

  void unwatchInputLevel() {
    if (_inputMeterUsers == 0 || --_inputMeterUsers > 0) return;
    _inputMeterTimer?.cancel();
    _inputMeterTimer = null;
    inputLevelDb.value = kMicSilenceDb;
    unawaited(_syncInputMonitor());
  }

  Future<void> _readInputLevel() async {
    if (_inputMeterReading) return;
    _inputMeterReading = true;
    double? db;
    try {
      final test = _micTest ?? _inputMonitor;
      if (test != null) {
        db = test.inputLevelDb;
      } else if (isConnected && micEnabled && micAllowed && !deafened) {
        db = await micChainLevel();
      }
    } catch (_) {
    } finally {
      _inputMeterReading = false;
    }
    if (_inputMeterUsers > 0) inputLevelDb.value = db ?? kMicSilenceDb;
  }

  bool get _inputMonitorWanted =>
      _inputMeterUsers > 0 &&
      canTestMic &&
      !_inputMonitorFailed &&
      !micTesting &&
      state == VoiceLinkState.idle;

  Future<void> _syncInputMonitor() async {
    if (!_inputMonitorWanted) {
      _inputMonitorAttempt++;
      final monitor = _inputMonitor;
      _inputMonitor = null;
      await _stopInputMonitor(monitor);
      return;
    }
    if (_inputMonitor != null || _inputMonitorOpening) return;
    final attempt = ++_inputMonitorAttempt;
    _inputMonitorOpening = true;
    MicTest? opened;
    try {
      opened = await _openMicTest(_micProcessing, hear: false);
    } catch (e, s) {
      if (attempt == _inputMonitorAttempt) {
        _inputMonitorFailed = true;
        errorReporter.report(e, stack: s, screen: 'voice:inputMonitor');
      }
    } finally {
      _inputMonitorOpening = false;
    }
    if (opened == null) return;
    if (attempt != _inputMonitorAttempt) {
      await _stopInputMonitor(opened);
      await _syncInputMonitor();
      return;
    }
    _inputMonitor = opened;
    await _setTestProcessing(opened);
  }

  Future<void> _reopenInputMonitor() async {
    final monitor = _inputMonitor;
    if (monitor == null) return;
    _inputMonitorAttempt++;
    _inputMonitor = null;
    await _stopInputMonitor(monitor);
    await _syncInputMonitor();
  }

  Future<void> _stopInputMonitor(MicTest? monitor) async {
    try {
      await monitor?.stop();
    } catch (e, s) {
      errorReporter.report(e, stack: s, screen: 'voice:inputMonitorStop');
    }
  }


  MicProcessing get _micProcessing => (
        noise: noiseActive,
        volume: canSetMicVolume ? callAudioPrefs.micVolume : 1.0,
        gate: _micGate,
      );

  Future<void> _processingChanged() async {
    final test = _micTest;
    if (test != null) await _setTestProcessing(test);
    final monitor = _inputMonitor;
    if (monitor != null) await _setTestProcessing(monitor);
    final room = _room;
    if (room != null) await _syncMic(room);
  }

  Future<void> _setTestProcessing(MicTest test) async {
    try {
      await test.setProcessing(_micProcessing);
    } catch (e, s) {
      errorReporter.report(e, stack: s, screen: 'voice:micTestProcessing');
    }
  }

  Future<void> _syncMic(lk.Room room) async {
    if (!identical(_room, room) || !isConnected) return;
    _applyGate(room);
    final processing = _micProcessing;
    try {
      await syncMicChain(room, processing, attenuationDb: _noiseAttenuationDb);
    } catch (e, s) {
      errorReporter.report(e, stack: s, screen: 'voice:micChain');
      if (!processing.noise) return;
      _noiseFailed = true;
      notifyListeners();
      try {
        await syncMicChain(room, _micProcessing, attenuationDb: _noiseAttenuationDb);
      } catch (e, s) {
        errorReporter.report(e, stack: s, screen: 'voice:micChainNoNoise');
      }
    }
  }


  bool get pushToTalk => callAudioPrefs.pushToTalk;

  Duration get pushToTalkDelay => Duration(milliseconds: callAudioPrefs.pushToTalkDelayMs);

  bool get pushToTalkOpen => _pttOpen;

  bool _pttKeyHeld = false;
  bool _pttTouchHeld = false;
  bool _pttOpen = false;
  Timer? _pttRelease;

  Future<void> setPushToTalk(bool on) async {
    await callAudioPrefs.load();
    final saving = callAudioPrefs.savePushToTalk(on);
    _pttChanged();
    _applyGateNow();
    notifyListeners();
    final processing = _processingChanged();
    await saving;
    await processing;
  }

  void setPushToTalkDelay(Duration delay, {bool persist = false}) {
    callAudioPrefs.setPushToTalkDelay(delay.inMilliseconds);
    notifyListeners();
    if (persist) unawaited(callAudioPrefs.savePushToTalkDelay());
  }

  void pushToTalkPress() {
    _pttTouchHeld = true;
    _pttChanged();
  }

  void pushToTalkRelease() {
    _pttTouchHeld = false;
    _pttChanged();
  }

  bool get _pttCanTalk => isConnected && micEnabled && micAllowed && !deafened && !micTesting;

  void _pttChanged() {
    keybinds.setArmed(KeybindAction.pushToTalk, pushToTalk && isConnected);
    final can = pushToTalk && _pttCanTalk;
    if (can && (_pttKeyHeld || _pttTouchHeld)) {
      _pttRelease?.cancel();
      _pttRelease = null;
      if (_pttOpen) return;
      _pttOpen = true;
      _cue(VoiceCue.pttOn, dedupe: false);
      _applyGateNow();
      _talkingChanged();
      notifyListeners();
      return;
    }
    if (!_pttOpen) return;
    if (!can) {
      _pttClose(cue: false);
      return;
    }
    _pttRelease ??= Timer(pushToTalkDelay, () {
      _pttRelease = null;
      _pttClose(cue: true);
    });
  }

  void _pttClose({required bool cue}) {
    _pttRelease?.cancel();
    _pttRelease = null;
    if (!_pttOpen) return;
    _pttOpen = false;
    if (cue) _cue(VoiceCue.pttOff, dedupe: false);
    _applyGateNow();
    _talkingChanged();
    notifyListeners();
  }

  void _talkingChanged() {
    _publishSpeakers();
    _sendTalking();
  }

  void _sendTalking() {
    if (!isConnected) return;
    try {
      wsService.send({'type': 'voice.talking', 'talking': _pttOpen});
    } catch (e, s) {
      errorReporter.report(e, stack: s, screen: 'voice:talking');
    }
  }

  void _pttReset() {
    _pttRelease?.cancel();
    _pttRelease = null;
    _pttOpen = false;
    _pttTouchHeld = false;
    _publishSpeakers();
  }

  void _applyGateNow() {
    final room = _room;
    if (room != null) _applyGate(room);
  }

  void _applyGate(lk.Room room) {
    final track = _micTrack(room);
    if (track == null || track.muted) return;
    final open = !pushToTalk || _pttOpen;
    try {
      if (track.mediaStreamTrack.enabled != open) track.mediaStreamTrack.enabled = open;
    } catch (e, s) {
      errorReporter.report(e, stack: s, screen: 'voice:pttGate');
    }
  }


  bool get canTestMic => micTestSupported;

  bool micTesting = false;

  MicTest? _micTest;

  int _micTestAttempt = 0;

  ({bool mic, bool deaf})? _flagsBeforeTest;

  final ValueNotifier<double> micTestLevel = ValueNotifier(0);
  Timer? _micTestMeter;
  static const _micTestMeterTick = Duration(milliseconds: 50);

  Future<bool> startMicTest() async {
    if (!canTestMic || micTesting) return true;
    final attempt = ++_micTestAttempt;
    micTesting = true;
    unawaited(_syncInputMonitor());
    if (isConnected) {
      _flagsBeforeTest = (mic: micEnabled, deaf: deafened);
      _cueFlags(to: (mic: false, deaf: true));
      await _setFlags(mic: false, deaf: true);
    }
    notifyListeners();
    final processing = _micProcessing;
    final MicTest test;
    try {
      test = await _openMicTest(processing);
    } catch (e, s) {
      errorReporter.report(e, stack: s, screen: 'voice:micTest');
      if (attempt == _micTestAttempt) await stopMicTest();
      return false;
    }
    if (attempt != _micTestAttempt) {
      await test.stop();
      return true;
    }
    _adoptMicTest(test, processing);
    return true;
  }

  Future<MicTest> _openMicTest(MicProcessing processing, {bool hear = true}) async {
    final capture = await _micCapture();
    return openMicTest(
      capture: capture,
      processing: processing,
      attenuationDb: _noiseAttenuationDb,
      outputDeviceId: canSelectOutput ? callAudioPrefs.outputId : null,
      volume: canSetOutputVolume ? outputVolume : 1.0,
      hear: hear,
    );
  }

  /// Закончить проверку. Флаги возвращаются СРАЗУ (до того, как отпущен
  /// микрофон проверки): следующий шаг — вход в другое место, ответ на
  /// звонок — должен видеть уже их. Повторный вызов ничего не делает.
  Future<void> stopMicTest() async {
    if (!micTesting) return;
    _micTestAttempt++;
    micTesting = false;
    _micTestMeter?.cancel();
    _micTestMeter = null;
    micTestLevel.value = 0;
    final test = _micTest;
    _micTest = null;
    final before = _flagsBeforeTest;
    _flagsBeforeTest = null;
    if (before != null && isConnected) _cueFlags(to: before);
    final restoring = before == null ? null : _setFlags(mic: before.mic, deaf: before.deaf);
    notifyListeners();
    try {
      await test?.stop();
    } catch (e, s) {
      errorReporter.report(e, stack: s, screen: 'voice:micTestStop');
    }
    await restoring;
    await _syncInputMonitor();
  }

  void _adoptMicTest(MicTest test, MicProcessing opened) {
    _micTest = test;
    _micTestMeter = Timer.periodic(_micTestMeterTick, (_) => micTestLevel.value = test.level);
    final now = _micProcessing;
    if (opened != now) {
      unawaited(test.setProcessing(now).catchError((Object e, StackTrace s) {
        errorReporter.report(e, stack: s, screen: 'voice:micTestProcessing');
      }));
    }
  }

  Future<void> _reopenMicTest() async {
    final old = _micTest;
    if (old == null) return;
    final attempt = ++_micTestAttempt;
    _micTest = null;
    _micTestMeter?.cancel();
    _micTestMeter = null;
    try {
      await old.stop();
      final processing = _micProcessing;
      final test = await _openMicTest(processing);
      if (attempt != _micTestAttempt || !micTesting) {
        await test.stop();
        return;
      }
      _adoptMicTest(test, processing);
    } catch (e, s) {
      errorReporter.report(e, stack: s, screen: 'voice:micTestReopen');
      if (attempt == _micTestAttempt) await stopMicTest();
    }
  }


  /// Мы в голосе, а браузер не даёт странице играть звук: на ней ещё не было
  /// ни одного действия человека. Так бывает после перезагрузки вкладки —
  /// в разговор мы вернулись сами (voice_resume), без нажатия. Собеседников
  /// при этом не слышно, пока человек не кликнет по странице.
  bool get audioBlocked => isConnected && !voicePlaybackAllowed();

  VoiceConnection() {
    voicePlaybackChanges.addListener(_onPlaybackChanged);
    final pttKey = keybinds.heldOf(KeybindAction.pushToTalk);
    pttKey.addListener(() {
      _pttKeyHeld = pttKey.value;
      _pttChanged();
    });
  }

  /// Ответ «можно ли играть звук» мог измениться (ответ пробы, запуск
  /// цепочки голосов — voice_audio_web, [voicePlaybackChanges]). От него
  /// зависят подсказка «звук на паузе» и шумоподавление — пересчитать оба,
  /// как после клика в [unlockAudio]. Сверка фильтра идемпотентна и идёт
  /// очередью, лишний вызов ничего не ломает.
  void _onPlaybackChanged() {
    final room = _room;
    if (room == null || !isConnected) return;
    if (audioBlocked != _audioBlockedSeen) notifyListeners();
    unawaited(_syncMic(room));
  }

  Future<void> unlockAudio() async {
    final room = _room;
    if (room == null) return;
    await resumeVoicePlayback();
    unawaited(room.startAudio().catchError((Object _) {}));
    notifyListeners();
    unawaited(_syncMic(room));
  }


  static const _callRoomPrefix = 'c';

  static const _cueRepeatGap = Duration(milliseconds: 1500);

  VoiceCue? _lastCue;
  DateTime _lastCueAt = DateTime.fromMillisecondsSinceEpoch(0);

  DateTime? _movedAt;
  static const _moveWindow = Duration(seconds: 15);

  bool get _moving {
    final at = _movedAt;
    return at != null && DateTime.now().difference(at) < _moveWindow;
  }

  void playCue(VoiceCue cue) => _cue(cue, dedupe: cue == VoiceCue.message);

  /// [dedupe] — не повторять тот же звук раньше [_cueRepeatGap]: защита от
  /// двойного «вышел» в конце звонка. Микрофону и звуку не нужна — их
  /// переключают быстро, и каждое нажатие обязано прозвучать.
  void _cue(VoiceCue cue, {bool dedupe = true}) {
    if (!appSounds.isOn(cue)) return;
    final now = DateTime.now();
    if (dedupe && _lastCue == cue && now.difference(_lastCueAt) < _cueRepeatGap) return;
    _lastCue = cue;
    _lastCueAt = now;
    unawaited(playVoiceCue(
      cue,
      volume: outputVolume,
      outputDeviceId: lk.Hardware.instance.selectedAudioOutput?.deviceId,
    ));
  }

  void previewCue(VoiceCue cue) => unawaited(playVoiceCue(
        cue,
        volume: outputVolume,
        outputDeviceId: lk.Hardware.instance.selectedAudioOutput?.deviceId,
      ));

  void _streamCues(List<VoiceMember> before, List<VoiceMember> after) {
    if (!isConnected) return;
    var on = false;
    var off = false;
    for (final now in after) {
      final was = before.where((m) => m.identity == now.identity).firstOrNull;
      if (was == null || (!now.isLocal && deafened)) continue;
      for (final (a, b) in [(was.camera != null, now.camera != null), (was.screen != null, now.screen != null)]) {
        if (!a && b) on = true;
        if (a && !b) off = true;
      }
    }
    if (on) _cue(VoiceCue.streamOn);
    if (off) _cue(VoiceCue.streamOff);
  }

  void _peerCue(lk.Room room, VoiceCue cue) {
    if (!identical(_room, room) || deafened) return;
    _cue(cue);
  }


  List<VoiceMember> get members => _members;
  List<VoiceMember> _members = const [];

  bool _audioBlockedSeen = false;

  final Map<String, Map<String, dynamic>> _cards = {};

  List<VoiceMember> _membersOf(lk.Room? room) {
    if (room == null) return const [];
    final local = room.localParticipant;
    return [
      if (local != null)
        VoiceMember._from(local, _cardOf(local), isLocal: true, mirror: frontCamera, hideScreen: _screenStopping),
      for (final p in room.remoteParticipants.values) VoiceMember._from(p, _cardOf(p), isLocal: false),
    ];
  }

  Map<String, dynamic> _cardOf(lk.Participant p) {
    final raw = p.metadata;
    if (raw == null || raw.isEmpty) return const {};
    return _cards.putIfAbsent(raw, () {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {
      }
      return const {};
    });
  }

  int get othersCount {
    final room = _room;
    if (room == null) return 0;
    final me = VoiceMember._parseIdentity(room.localParticipant?.identity ?? '')?.$1;
    return {
      for (final p in room.remoteParticipants.values)
        VoiceMember._parseIdentity(p.identity)?.$1,
    }.where((id) => id != null && id != me).length;
  }
}

enum VoiceLinkState { idle, connecting, connected, reconnecting }

enum VoiceDropReason {
  replaced,

  removed,

  roomClosed,

  lost,

  roomLost,
}

class VoiceDrop {
  final String room;
  final VoiceDropReason reason;

  final String? cause;

  final int? moveToChatId;
  final String moveToName;

  const VoiceDrop(this.room, this.reason, {this.cause, this.moveToChatId, this.moveToName = ''});
}

class _PendingDrop {
  final String room;
  final VoiceDropReason reason;
  final Timer timer;
  const _PendingDrop(this.room, this.reason, this.timer);
}

class VoiceMicUnavailable implements Exception {
  final Object cause;
  const VoiceMicUnavailable(this.cause);
  @override
  String toString() => 'VoiceMicUnavailable: $cause';
}

class VoiceMember {
  final String identity;
  final int userId;
  final int sessionId;
  final bool isLocal;
  final String name;
  final String? nickname;
  final String? avatar;
  final Color? avatarColor;
  final bool micOn;
  final lk.VideoTrack? camera;
  final lk.VideoTrack? screen;

  final bool screenSound;

  final bool mirror;

  const VoiceMember({
    required this.identity,
    required this.userId,
    required this.sessionId,
    required this.isLocal,
    required this.name,
    this.nickname,
    this.avatar,
    this.avatarColor,
    this.micOn = false,
    this.camera,
    this.screen,
    this.screenSound = false,
    this.mirror = false,
  });

  static (int, int)? _parseIdentity(String identity) {
    final m = RegExp(r'^u(\d+)\.s(\d+)$').firstMatch(identity);
    if (m == null) return null;
    return (int.parse(m.group(1)!), int.parse(m.group(2)!));
  }

  factory VoiceMember._from(
    lk.Participant p,
    Map<String, dynamic> card, {
    required bool isLocal,
    bool mirror = false,
    bool hideScreen = false,
  }) {
    final ids = _parseIdentity(p.identity);
    lk.VideoTrack? video(lk.TrackSource source) {
      final pub = p.getTrackPublicationBySource(source);
      final track = pub?.track;
      if (pub == null || pub.muted || track is! lk.VideoTrack) return null;
      return track;
    }

    return VoiceMember(
      identity: p.identity,
      userId: ids?.$1 ?? 0,
      sessionId: ids?.$2 ?? 0,
      isLocal: isLocal,
      name: (card['display_name'] as String?) ?? p.name,
      nickname: card['nickname'] as String?,
      avatar: card['avatar'] as String?,
      avatarColor: parseAvatarColor(card['avatar_color']),
      micOn: p.isMicrophoneEnabled(),
      camera: video(lk.TrackSource.camera),
      screen: hideScreen ? null : video(lk.TrackSource.screenShareVideo),
      screenSound: p.getTrackPublicationBySource(lk.TrackSource.screenShareAudio) != null,
      mirror: isLocal && mirror,
    );
  }

  bool sameAs(VoiceMember o) =>
      identity == o.identity &&
      isLocal == o.isLocal &&
      name == o.name &&
      nickname == o.nickname &&
      avatar == o.avatar &&
      avatarColor == o.avatarColor &&
      micOn == o.micOn &&
      identical(camera, o.camera) &&
      identical(screen, o.screen) &&
      screenSound == o.screenSound &&
      mirror == o.mirror;

  static bool sameList(List<VoiceMember> a, List<VoiceMember> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!a[i].sameAs(b[i])) return false;
    }
    return true;
  }
}

final voiceConnection = VoiceConnection();

typedef VoiceAudioDevice = ({String id, String label});
