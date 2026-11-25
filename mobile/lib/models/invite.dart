import '../core/time_json.dart';
import 'chat.dart';
import 'server.dart';


class InviteTarget {
  final bool isServer;
  final int id;
  final String name;

  const InviteTarget.server(this.id, this.name) : isServer = true;
  const InviteTarget.group(this.id, this.name) : isServer = false;

  String get invitesPath => isServer ? '/servers/$id/invites' : '/chats/$id/invites';
}

class Invite {
  final String code;
  final int uses;

  final int? maxUses;

  final DateTime? expiresAt;
  final DateTime createdAt;

  final ServerUser creator;

  const Invite({
    required this.code,
    this.uses = 0,
    this.maxUses,
    this.expiresAt,
    required this.createdAt,
    required this.creator,
  });

  factory Invite.fromJson(Map<String, dynamic> j) => Invite(
    code: j['code'] as String? ?? '',
    uses: j['uses'] as int? ?? 0,
    maxUses: j['max_uses'] as int?,
    expiresAt: j['expires_at'] == null ? null : parseUtcLocal(j['expires_at']),
    createdAt: parseUtcLocal(j['created_at']),
    creator: ServerUser.fromJson(j['creator'] as Map<String, dynamic>),
  );

  int? get daysLeft {
    final until = expiresAt;
    if (until == null) return null;
    final left = until.difference(DateTime.now()).inMinutes;
    if (left <= 0) return 0;
    return (left / (60 * 24)).ceil();
  }
}

class InvitePreview {
  final String code;
  final ServerInvitePreview? server;
  final GroupInvitePreview? group;

  const InvitePreview({required this.code, this.server, this.group});

  factory InvitePreview.fromJson(Map<String, dynamic> j) => InvitePreview(
    code: j['code'] as String? ?? '',
    server: j['server'] != null ? ServerInvitePreview.fromJson(j['server'] as Map<String, dynamic>) : null,
    group: j['group'] != null ? GroupInvitePreview.fromJson(j['group'] as Map<String, dynamic>) : null,
  );
}

class InviteJoinResult {
  final ServerDetail? server;
  final Chat? chat;

  const InviteJoinResult({this.server, this.chat});

  factory InviteJoinResult.fromJson(Map<String, dynamic> j) => InviteJoinResult(
    server: j['server'] != null ? ServerDetail.fromJson(j['server'] as Map<String, dynamic>) : null,
    chat: j['chat'] != null ? Chat.fromJson(j['chat'] as Map<String, dynamic>) : null,
  );
}

class Vanity {
  final String? code;

  final int uses;

  const Vanity({this.code, this.uses = 0});

  factory Vanity.fromJson(Map<String, dynamic> j) => Vanity(
    code: j['code'] as String?,
    uses: j['uses'] as int? ?? 0,
  );
}
