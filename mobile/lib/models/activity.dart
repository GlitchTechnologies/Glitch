import '../core/time_json.dart';

class ActivityGame {
  final int id;
  final String name;

  final String? cover;
  final int? coverWidth;
  final int? coverHeight;

  const ActivityGame({required this.id, required this.name, this.cover, this.coverWidth, this.coverHeight});

  static ActivityGame? fromJson(dynamic raw) {
    if (raw is! Map<String, dynamic>) return null;
    final id = raw['id'];
    final name = raw['name'];
    if (id is! int || name is! String) return null;
    return ActivityGame(
      id: id,
      name: name,
      cover: raw['cover'] as String?,
      coverWidth: raw['cover_width'] as int?,
      coverHeight: raw['cover_height'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'cover': cover,
    'cover_width': coverWidth,
    'cover_height': coverHeight,
  };
}

class UserActivity {
  final String kind;
  final ActivityGame game;

  final DateTime startedAt;

  static const playing = 'playing';

  const UserActivity({required this.kind, required this.game, required this.startedAt});

  /// Поле `activities` ответа или события. Сломанное и незнакомое — мимо.
  static List<UserActivity> listFromJson(dynamic raw) {
    if (raw is! List) return const [];
    return [
      for (final a in raw.whereType<Map<String, dynamic>>())
        if (a['kind'] == playing)
          if (ActivityGame.fromJson(a['game']) case final game?)
            UserActivity(kind: playing, game: game, startedAt: parseUtcLocal(a['started_at'])),
    ];
  }

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'game': game.toJson(),
    'started_at': utcIso(startedAt),
  };

  bool sameAs(UserActivity other) =>
      kind == other.kind && game.id == other.game.id && startedAt == other.startedAt &&
      game.cover == other.game.cover && game.name == other.game.name;
}

class RecentActivity {
  final String kind;
  final ActivityGame game;

  final DateTime lastPlayedAt;

  const RecentActivity({required this.kind, required this.game, required this.lastPlayedAt});

  /// Поле `recent_activities` ответа. Сломанное и незнакомое — мимо.
  static List<RecentActivity> listFromJson(dynamic raw) {
    if (raw is! List) return const [];
    return [
      for (final a in raw.whereType<Map<String, dynamic>>())
        if (a['kind'] == UserActivity.playing)
          if (ActivityGame.fromJson(a['game']) case final game?)
            RecentActivity(kind: UserActivity.playing, game: game, lastPlayedAt: parseUtcLocal(a['last_played_at'])),
    ];
  }

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'game': game.toJson(),
    'last_played_at': utcIso(lastPlayedAt),
  };
}
