import '../core/text_match.dart' as text_match;
import '../core/time_json.dart';
import 'activity.dart';
import 'presence.dart';
import 'server.dart';

enum RelationshipKind { friend, incoming, outgoing }

RelationshipKind? _kindFrom(dynamic raw) => switch (raw) {
      'friend' => RelationshipKind.friend,
      'incoming' => RelationshipKind.incoming,
      'outgoing' => RelationshipKind.outgoing,
      _ => null,
    };

class Relationship {
  final ServerUser user;
  final RelationshipKind kind;

  final DateTime since;
  final bool isOnline;
  final PresenceStatus presenceStatus;

  final List<UserActivity> activities;

  const Relationship({
    required this.user,
    required this.kind,
    required this.since,
    this.isOnline = false,
    this.presenceStatus = PresenceStatus.offline,
    this.activities = const [],
  });

  static Relationship? fromJson(Map<String, dynamic> j) {
    final kind = _kindFrom(j['kind']);
    final user = j['user'];
    if (kind == null || user is! Map<String, dynamic> || user['id'] is! int) return null;
    return Relationship(
      user: ServerUser.fromJson(user),
      kind: kind,
      since: parseUtcLocal(j['since']),
      isOnline: j['is_online'] as bool? ?? false,
      presenceStatus: presenceStatusFrom(j['status'], online: j['is_online'] == true),
      activities: UserActivity.listFromJson(j['activities']),
    );
  }

  bool matchesQuery(String query) =>
      text_match.matchesQuery(query, [user.displayName, user.nickname]);

  Relationship copyWith({ServerUser? user, bool? isOnline, PresenceStatus? presenceStatus}) => Relationship(
        user: user ?? this.user,
        kind: kind,
        since: since,
        isOnline: isOnline ?? this.isOnline,
        presenceStatus: presenceStatus ?? this.presenceStatus,
        activities: activities,
      );
}
