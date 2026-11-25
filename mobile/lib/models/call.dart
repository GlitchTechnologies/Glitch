class CallInfo {
  final int id;

  final String status;

  final int duration;
  final bool isVideo;

  final int participants;

  final bool isGroup;

  const CallInfo({
    required this.id,
    required this.status,
    this.duration = 0,
    this.isVideo = false,
    this.participants = 0,
    this.isGroup = false,
  });

  factory CallInfo.fromJson(Map<String, dynamic> j) => CallInfo(
    id: (j['id'] as num?)?.toInt() ?? 0,
    status: j['status'] as String? ?? 'ended',
    duration: (j['duration'] as num?)?.toInt() ?? 0,
    isVideo: j['is_video'] == true,
    participants: (j['participants'] as num?)?.toInt() ?? 0,
    isGroup: j['is_group'] == true,
  );

  Map<String, dynamic> toJson() =>
      {'id': id, 'status': status, 'duration': duration, 'is_video': isVideo,
       'participants': participants, 'is_group': isGroup};

  bool get isMissed => status == 'missed';

  bool get wasAnswered => status == 'ended' && duration > 0;

  String get formattedDuration {
    final h = duration ~/ 3600;
    final m = (duration % 3600) ~/ 60;
    final s = duration % 60;
    final mm = h > 0 ? m.toString().padLeft(2, '0') : m.toString();
    return h > 0
        ? '$h:$mm:${s.toString().padLeft(2, '0')}'
        : '$mm:${s.toString().padLeft(2, '0')}';
  }
}
