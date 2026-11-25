import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/l10n.dart';
import '../core/platform_info.dart';
import '../main.dart' show navigatorKey;
import '../providers/call_provider.dart';
import '../models/server.dart' show Room;
import '../providers/voice_channels.dart';
import '../services/call_screen_capture_web.dart'
    if (dart.library.io) '../services/call_screen_capture_native.dart' show screenCaptureSupported;
import '../services/voice_connection.dart';
import 'chat_call_area.dart' show openCallChat;
import 'glitch_toast.dart';
import 'screen_source_picker.dart';
import 'server_rail.dart' show revealServerInRail;


enum VoiceWhere { none, call, channel }

class VoiceControls {
  VoiceControls._();

  late final Listenable changes = Listenable.merge(
      [callProvider, voiceChannels, voiceConnection, voiceConnection.personAudio, _focusRequest]);

  VoiceWhere get where {
    final p = callProvider;
    if (p.isBusy && p.state != CallState.incoming) return VoiceWhere.call;
    if (voiceChannels.link != VoiceChannelLink.idle) return VoiceWhere.channel;
    return VoiceWhere.none;
  }


  bool get micOff => voiceChannels.muted || voiceChannels.speakBlocked;

  bool get deafOff => voiceChannels.deafened || voiceChannels.hearBlocked;

  void tapMic(BuildContext context) {
    if (!toggleMic()) GlitchToast.show(context, context.s.voiceSpeakBlocked, type: ToastType.info);
  }

  void tapDeafen(BuildContext context) {
    if (!toggleDeafen()) GlitchToast.show(context, context.s.voiceHearBlocked, type: ToastType.info);
  }


  bool get showsPushToTalk => !hasPointerInput && voiceConnection.pushToTalk && where != VoiceWhere.none;

  bool get pushToTalkOpen => voiceConnection.pushToTalkOpen;

  void pressPushToTalk() => voiceConnection.pushToTalkPress();
  void releasePushToTalk() => voiceConnection.pushToTalkRelease();

  bool toggleMic() {
    if (voiceChannels.speakBlocked) return false;
    unawaited(voiceConnection.toggleMute());
    return true;
  }

  bool toggleDeafen() {
    if (voiceChannels.hearBlocked) return false;
    unawaited(voiceConnection.toggleDeafen());
    return true;
  }


  bool get noiseOn => voiceConnection.noiseActive;


  bool get cameraOn => voiceConnection.cameraOn;
  bool get sharingScreen => voiceConnection.screenOn;

  bool get watchingStreams => voiceConnection.lastWatched != null;

  void stopWatchingAll() => voiceConnection.stopWatchingAll();

  bool get showsScreenShare => screenCaptureSupported;

  bool get canUseCamera => switch (where) {
        VoiceWhere.call => callProvider.canUseCamera,
        VoiceWhere.channel => voiceChannels.link == VoiceChannelLink.connected && voiceConnection.canStream,
        VoiceWhere.none => false,
      };

  bool get canShareScreen => showsScreenShare && canUseCamera;

  void toggleCamera() {
    if (cameraOn || canUseCamera) unawaited(voiceConnection.toggleCamera());
  }

  /// Нажатие на показ экрана. Показ включился без звука (браузер не умеет
  /// убрать из звука всего экрана голоса собеседников — иначе у всех эхо) —
  /// сказать, как показать со звуком.
  void tapScreenShare(BuildContext context) {
    if (!sharingScreen && !canShareScreen) return;
    unawaited(() async {
      if (!sharingScreen && isDesktopApp && !await pickScreenSource(context)) return;
      final soundDropped = await voiceConnection.toggleScreenShare();
      if (soundDropped && context.mounted) _soundDroppedNotice(context);
    }());
  }

  bool get canChangeScreenSource => voiceConnection.canChangeScreenSource;

  void changeScreenSource(BuildContext context) {
    if (!canChangeScreenSource) return;
    unawaited(() async {
      if (isDesktopApp && !await pickScreenSource(context)) return;
      final soundDropped = await voiceConnection.changeScreenSource();
      if (soundDropped == true && context.mounted) _soundDroppedNotice(context);
    }());
  }

  void _soundDroppedNotice(BuildContext context) => GlitchToast.show(
        context,
        isDesktopApp ? context.s.voiceScreenSoundDroppedApp : context.s.voiceScreenSoundDropped,
        type: ToastType.info,
        duration: const Duration(seconds: 6),
      );


  void leave() {
    switch (where) {
      case VoiceWhere.call:
        callProvider.hangup();
      case VoiceWhere.channel:
        unawaited(voiceChannels.leave());
      case VoiceWhere.none:
        break;
    }
  }


  String get placeName => switch (where) {
        VoiceWhere.call => callProvider.peerName,
        VoiceWhere.channel => voiceChannels.roomName,
        VoiceWhere.none => '',
      };

  Future<void> watchStream(Room room, int userId, {required bool screen}) async {
    _focusRequest.value = (key: screen ? 'u$userId:screen' : 'u$userId:person', at: DateTime.now());
    final here = voiceChannels.serverId == room.serverId && voiceChannels.roomId == room.id;
    if (!here) await voiceChannels.join(room);
    if (voiceChannels.serverId != room.serverId || voiceChannels.roomId != room.id) {
      _focusRequest.value = null; // не пустили — экран открывать некуда
      return;
    }
    openStage();
  }

  static const _kFocusTtl = Duration(seconds: 20);
  final _focusRequest = ValueNotifier<({String key, DateTime at})?>(null);

  String? takePendingFocus(Iterable<String> available) {
    final p = _focusRequest.value;
    if (p == null) return null;
    if (DateTime.now().difference(p.at) > _kFocusTtl) {
      _focusRequest.value = null;
      return null;
    }
    if (!available.contains(p.key)) return null;
    _focusRequest.value = null;
    return p.key;
  }

  bool get hasPendingFocus => _focusRequest.value != null;

  void openStage() {
    switch (where) {
      case VoiceWhere.call:
        final chatId = callProvider.chatId;
        if (chatId != null) unawaited(openCallChat(chatId));
      case VoiceWhere.channel:
        final nav = navigatorKey.currentState;
        final serverId = voiceChannels.serverId;
        final roomId = voiceChannels.roomId;
        if (nav != null && serverId != null && roomId != null) revealServerInRail(nav, serverId, roomId: roomId);
      case VoiceWhere.none:
        break;
    }
  }
}

final voiceControls = VoiceControls._();
