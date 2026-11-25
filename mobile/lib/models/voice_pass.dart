import '../core/time_json.dart';

/// Формы зеркалят app/schemas/voice.py. Разбор — без единого `!`: сервер может
/// дополнить формат новыми полями, а старый ответ — прийти без части из них.

class VoicePass {
  final String url;
  final String token;

  final String room;

  final String identity;

  const VoicePass({
    required this.url,
    required this.token,
    required this.room,
    required this.identity,
  });

  factory VoicePass.fromJson(Map<String, dynamic> j) => VoicePass(
        url: j['url'] as String? ?? '',
        token: j['token'] as String? ?? '',
        room: j['room'] as String? ?? '',
        identity: j['identity'] as String? ?? '',
      );
}

/// Пропуск в звонок — ответ и на «позвонить», и на «принять / войти». Номер
/// звонка приходит сразу: гонки «нажал отбой раньше, чем узнал номер» нет.
class CallPass {
  final VoicePass pass;
  final int callId;
  final int chatId;
  final bool isVideo;
  final bool isGroup;

  final bool created;

  final CurrentCall? call;

  const CallPass({
    required this.pass,
    required this.callId,
    required this.chatId,
    this.isVideo = false,
    this.isGroup = false,
    this.created = false,
    this.call,
  });

  factory CallPass.fromJson(Map<String, dynamic> j) => CallPass(
        pass: VoicePass.fromJson(j),
        callId: (j['call_id'] as num?)?.toInt() ?? 0,
        chatId: (j['chat_id'] as num?)?.toInt() ?? 0,
        isVideo: j['is_video'] == true,
        isGroup: j['is_group'] == true,
        created: j['created'] == true,
        call: j['call'] is Map<String, dynamic>
            ? CurrentCall.fromJson(j['call'] as Map<String, dynamic>)
            : null,
      );
}

class VoiceChannelElapsed {
  final DateTime startedAt;
  final bool fromServer;
  final Duration _atReceipt;
  final Stopwatch _sinceReceipt = Stopwatch()..start();

  VoiceChannelElapsed(this.startedAt, int? elapsedMs)
      : fromServer = elapsedMs != null,
        _atReceipt = elapsedMs == null
            ? DateTime.now().difference(startedAt)
            : Duration(milliseconds: elapsedMs);

  Duration get elapsed => _atReceipt + _sinceReceipt.elapsed;
}

class VoiceStateInfo {
  final int userId;
  final int sessionId;
  final int? serverId;
  final int? chatId;
  final int? callId;
  final bool selfMute;
  final bool selfDeaf;
  final bool serverMute;
  final bool serverDeaf;
  final bool streaming;
  final bool video;
  final VoiceChannelElapsed? channelElapsed;
  final String? displayName;
  final String? nickname;
  final String? avatar;
  final String? avatarColor;

  const VoiceStateInfo({
    required this.userId,
    required this.sessionId,
    this.serverId,
    this.chatId,
    this.callId,
    this.selfMute = false,
    this.selfDeaf = false,
    this.serverMute = false,
    this.serverDeaf = false,
    this.streaming = false,
    this.video = false,
    this.channelElapsed,
    this.displayName,
    this.nickname,
    this.avatar,
    this.avatarColor,
  });

  bool get left => chatId == null;

  factory VoiceStateInfo.fromJson(Map<String, dynamic> j) {
    final user = j['user'];
    final card = user is Map ? user : const {};
    final startedAt = j['channel_started_at'];
    return VoiceStateInfo(
      userId: (j['user_id'] as num?)?.toInt() ?? 0,
      sessionId: (j['session_id'] as num?)?.toInt() ?? 0,
      serverId: (j['server_id'] as num?)?.toInt(),
      chatId: (j['chat_id'] as num?)?.toInt(),
      callId: (j['call_id'] as num?)?.toInt(),
      selfMute: j['self_mute'] == true,
      selfDeaf: j['self_deaf'] == true,
      serverMute: j['server_mute'] == true,
      serverDeaf: j['server_deaf'] == true,
      streaming: j['streaming'] == true,
      video: j['video'] == true,
      channelElapsed: startedAt == null
          ? null
          : VoiceChannelElapsed(parseUtcLocal(startedAt), (j['channel_elapsed_ms'] as num?)?.toInt()),
      displayName: card['display_name'] as String?,
      nickname: card['nickname'] as String?,
      avatar: card['avatar'] as String?,
      avatarColor: card['avatar_color'] as String?,
    );
  }
}

enum CallMemberState {
  ringing,

  joining,

  connected,

  reconnecting,

  left,

  declined,

  missed;

  static CallMemberState? parse(Object? raw) {
    for (final v in values) {
      if (v.name == raw) return v;
    }
    return null;
  }

  bool get inCall => this == joining || this == connected || this == reconnecting;
}

class CallMember {
  final int userId;
  final CallMemberState state;
  final String? displayName;
  final String? nickname;
  final String? avatar;
  final String? avatarColor;

  const CallMember({
    required this.userId,
    required this.state,
    this.displayName,
    this.nickname,
    this.avatar,
    this.avatarColor,
  });

  static CallMember? fromJson(Map<String, dynamic> j) {
    final state = CallMemberState.parse(j['state']);
    if (state == null) return null;
    final user = j['user'];
    final card = user is Map ? user : const {};
    return CallMember(
      userId: (j['user_id'] as num?)?.toInt() ?? 0,
      state: state,
      displayName: card['display_name'] as String?,
      nickname: card['nickname'] as String?,
      avatar: card['avatar'] as String?,
      avatarColor: card['avatar_color'] as String?,
    );
  }
}

class CurrentCall {
  final int callId;
  final int chatId;
  final bool isVideo;
  final bool isGroup;
  final String status;
  final int initiatorId;
  final List<VoiceStateInfo> participants;

  final List<CallMember> members;

  final int version;

  const CurrentCall({
    required this.callId,
    required this.chatId,
    required this.isVideo,
    required this.isGroup,
    required this.status,
    required this.initiatorId,
    required this.participants,
    this.members = const [],
    this.version = 0,
  });

  factory CurrentCall.fromJson(Map<String, dynamic> j) => CurrentCall(
        callId: (j['call_id'] as num?)?.toInt() ?? 0,
        chatId: (j['chat_id'] as num?)?.toInt() ?? 0,
        isVideo: j['is_video'] == true,
        isGroup: j['is_group'] == true,
        status: j['status'] as String? ?? 'ringing',
        initiatorId: (j['initiator_id'] as num?)?.toInt() ?? 0,
        participants: [
          for (final p in (j['participants'] as List? ?? const []))
            if (p is Map<String, dynamic>) VoiceStateInfo.fromJson(p),
        ],
        members: [
          for (final m in (j['members'] as List? ?? const []))
            if (m is Map<String, dynamic>) CallMember.fromJson(m),
        ].whereType<CallMember>().toList(),
        version: (j['version'] as num?)?.toInt() ?? 0,
      );
}
