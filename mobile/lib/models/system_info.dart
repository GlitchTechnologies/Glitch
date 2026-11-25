class SystemInfo {
  final String event;

  final SystemPerson? target;

  const SystemInfo({required this.event, this.target});

  static SystemInfo? fromJson(Object? j) {
    if (j is! Map<String, dynamic>) return null;
    final event = j['event'];
    if (event is! String) return null;
    return SystemInfo(event: event, target: SystemPerson.fromJson(j['target']));
  }

  Map<String, dynamic> toJson() => {
    'event': event,
    'target': target?.toJson(),
  };

  SystemInfo withPersonName(int userId, String displayName) {
    final t = target;
    if (t == null || t.id != userId || t.displayName == displayName) return this;
    return SystemInfo(
      event: event,
      target: SystemPerson(id: t.id, nickname: t.nickname, displayName: displayName),
    );
  }
}

class SystemPerson {
  final int id;
  final String nickname;
  final String displayName;

  const SystemPerson({required this.id, required this.nickname, required this.displayName});

  static SystemPerson? fromJson(Object? j) {
    if (j is! Map<String, dynamic>) return null;
    final id = j['id'];
    if (id is! int) return null;
    return SystemPerson(
      id: id,
      nickname: j['nickname'] as String? ?? '',
      displayName: j['display_name'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'nickname': nickname, 'display_name': displayName};
}
