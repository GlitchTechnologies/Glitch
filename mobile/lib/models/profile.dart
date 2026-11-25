import '../core/avatar_sizes.dart';
import 'server.dart';

const int kMaxNoteLength = 256;

class MutualServer {
  final int id;
  final String name;
  final String? avatar;
  final Map<String, String>? avatarSizes;

  final String? nick;

  const MutualServer({required this.id, required this.name, this.avatar, this.avatarSizes, this.nick});

  factory MutualServer.fromJson(Map<String, dynamic> j) => MutualServer(
    id: j['id'] as int,
    name: j['name'] as String? ?? '',
    avatar: j['avatar'] as String?,
    avatarSizes: parseAvatarSizes(j['avatar_sizes']),
    nick: j['nick'] as String?,
  );
}

class Mutual {
  final List<MutualServer> servers;
  final List<ServerUser> friends;

  const Mutual({this.servers = const [], this.friends = const []});

  factory Mutual.fromJson(Map<String, dynamic> j) => Mutual(
    friends: ((j['friends'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ServerUser.fromJson)
        .toList(),
    servers: ((j['servers'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(MutualServer.fromJson)
        .toList(),
  );
}
