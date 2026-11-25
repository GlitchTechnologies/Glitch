import 'dart:async';
import 'dart:convert';

import '../providers/call_provider.dart';
import '../providers/voice_channels.dart';
import 'error_reporter.dart';
import 'voice_connection.dart';
import 'websocket_service.dart';
import 'voice_resume_store_web.dart' if (dart.library.io) 'voice_resume_store_native.dart';

/// ДУБЛИКАТ ВКЛАДКИ не возвращается: копия получает ту же память вкладки, но
/// оригинал держит отметку «голос занят» (см. voice_resume_store_web.dart).
class VoiceResume {
  static const _beat = Duration(seconds: 5);

  static const _fresh = Duration(seconds: 30);

  static const _otherTabWithin = Duration(minutes: 3);

  _VoicePlace? _place;
  Timer? _timer;
  bool _resumeTried = false;

  void rememberCall({
    required String room,
    required int chatId,
    required int callId,
    required String title,
    required bool isGroup,
  }) =>
      _remember(_VoicePlace.call(room: room, chatId: chatId, callId: callId, title: title, isGroup: isGroup));

  void rememberChannel({
    required String room,
    required int serverId,
    required int roomId,
    required String name,
  }) =>
      _remember(_VoicePlace.channel(room: room, serverId: serverId, roomId: roomId, title: name));

  void forget(String? room) {
    if (room == null || _place?.room != room) return;
    _place = null;
    _timer?.cancel();
    _timer = null;
    voiceConnection.removeListener(_onVoiceChanged);
    unawaited(clearVoicePlace());
    clearVoiceAlive();
  }

  void _remember(_VoicePlace place) {
    _place = place;
    _timer?.cancel();
    _timer = Timer.periodic(_beat, (_) => _write());
    voiceConnection.removeListener(_onVoiceChanged);
    voiceConnection.addListener(_onVoiceChanged);
    _write();
  }

  (bool, bool)? _written;

  void _onVoiceChanged() {
    final flags = (voiceConnection.chosenMic, voiceConnection.chosenDeaf);
    if (flags != _written) _write();
  }

  void _write() {
    final place = _place;
    if (place == null) return;
    final mic = voiceConnection.chosenMic;
    final deaf = voiceConnection.chosenDeaf;
    _written = (mic, deaf);
    markVoiceAlive();
    unawaited(writeVoicePlace(jsonEncode({...place.toJson(), 'mic': mic, 'deaf': deaf})));
  }

  Future<void> resumeOnStart() async {
    if (_resumeTried) return;
    _resumeTried = true;
    final Map<String, dynamic> j;
    try {
      final saved = await readVoicePlace();
      if (saved == null) return;
      await clearVoicePlace();
      final age = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(saved.at));
      if (age > _fresh) return;
      final decoded = jsonDecode(saved.value);
      if (decoded is! Map<String, dynamic>) return;
      j = decoded;
    } catch (e, s) {
      errorReporter.report(e, stack: s, screen: 'voice:resumeRead');
      return;
    }
    // Голос держит другая живая вкладка (это дубликат, а не перезагрузка) —
    // её разговор не трогаем.
    if (otherTabHoldsVoice(_otherTabWithin)) return;
    await wsService.waitUntilConnected();
    if (callProvider.isBusy || voiceChannels.link != VoiceChannelLink.idle) return;

    await voiceConnection.restoreFlags(mic: j['mic'] != false, deaf: j['deaf'] == true);
    final chatId = j['chat_id'];
    final callId = j['call_id'];
    final serverId = j['server_id'];
    final roomId = j['room_id'];
    final title = (j['title'] as String?) ?? '';
    switch (j['kind']) {
      case 'call':
        if (chatId is int && callId is int) {
          await callProvider.joinOngoing(
              chat: chatId, call: callId, name: title, group: j['is_group'] == true);
        }
      case 'channel':
        if (serverId is int && roomId is int) {
          await voiceChannels.joinRoom(serverId, roomId, title);
        }
    }
  }
}

class _VoicePlace {
  final String kind;
  final String room;
  final String title;
  final int? chatId;
  final int? callId;
  final bool isGroup;
  final int? serverId;
  final int? roomId;

  const _VoicePlace.call({
    required this.room,
    required int this.chatId,
    required int this.callId,
    required this.title,
    required this.isGroup,
  })  : kind = 'call',
        serverId = null,
        roomId = null;

  const _VoicePlace.channel({
    required this.room,
    required int this.serverId,
    required int this.roomId,
    required this.title,
  })  : kind = 'channel',
        chatId = null,
        callId = null,
        isGroup = false;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'room': room,
        'title': title,
        if (chatId != null) 'chat_id': chatId,
        if (callId != null) 'call_id': callId,
        'is_group': isGroup,
        if (serverId != null) 'server_id': serverId,
        if (roomId != null) 'room_id': roomId,
      };
}

final voiceResume = VoiceResume();
