import 'server.dart' show ServerUser;

/// Смещения заданы в UTF-16. Они относятся к тексту сообщения или подписи вложения.
class Mention {
  /// user | role | everyone | here.
  final String kind;

  final int? id;
  final int start;
  final int end;
  final String name;

  final String? color;

  /// @ник человека (у остальных — null): по нему нажатие на упоминание
  /// открывает профиль, как нажатие на автора сообщения.
  final String? nickname;

  const Mention({
    required this.kind,
    this.id,
    required this.start,
    required this.end,
    required this.name,
    this.color,
    this.nickname,
  });

  factory Mention.fromJson(Map<String, dynamic> j) => Mention(
    kind: j['kind'] as String,
    id: j['id'] as int?,
    start: j['start'] as int,
    end: j['end'] as int,
    name: j['name'] as String,
    color: j['color'] as String?,
    nickname: j['nickname'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'id': id,
    'start': start,
    'end': end,
    'name': name,
    'color': color,
    'nickname': nickname,
  };

  /// Открывает ли нажатие профиль: только у человека, как у Discord (роль и
  /// @everyone/@here — просто подсветка). Ника нет — отметка из кэша прежней
  /// версии, открывать нечем.
  bool get opensProfile => kind == 'user' && id != null && nickname != null;

  String get label => '@$name';

  static List<Mention> listFrom(dynamic raw, String? text) {
    if (raw is! List || text == null) return const [];
    final out = <Mention>[];
    var pos = 0;
    for (final item in raw) {
      if (item is! Map<String, dynamic>) continue;
      final m = Mention.fromJson(item);
      if (m.start < pos || m.end > text.length || m.start >= m.end) continue;
      out.add(m);
      pos = m.end;
    }
    return out;
  }
}

class MentionRoleOption {
  final int id;
  final String name;
  final String? color;

  const MentionRoleOption({required this.id, required this.name, this.color});

  factory MentionRoleOption.fromJson(Map<String, dynamic> j) =>
      MentionRoleOption(id: j['id'] as int, name: j['name'] as String, color: j['color'] as String?);
}

class MentionCandidates {
  final List<ServerUser> users;
  final List<MentionRoleOption> roles;
  final bool everyone;
  final bool here;

  const MentionCandidates({
    this.users = const [],
    this.roles = const [],
    this.everyone = false,
    this.here = false,
  });

  factory MentionCandidates.fromJson(Map<String, dynamic> j) => MentionCandidates(
    users: [
      for (final u in (j['users'] as List? ?? const []))
        if (u is Map<String, dynamic>) ServerUser.fromJson(u),
    ],
    roles: [
      for (final r in (j['roles'] as List? ?? const []))
        if (r is Map<String, dynamic>) MentionRoleOption.fromJson(r),
    ],
    everyone: j['everyone'] == true,
    here: j['here'] == true,
  );
}
