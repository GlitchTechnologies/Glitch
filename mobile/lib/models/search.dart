import '../core/avatar_sizes.dart';
import 'server.dart';


enum SearchKind { person, group, room, server }

SearchKind? _kindFrom(Object? raw) => switch (raw) {
      'person' => SearchKind.person,
      'group' => SearchKind.group,
      'room' => SearchKind.room,
      'server' => SearchKind.server,
      _ => null,
    };

class SearchGroup {
  final int id;
  final String name;
  final String? avatar;
  final Map<String, String>? avatarSizes;

  const SearchGroup({required this.id, required this.name, this.avatar, this.avatarSizes});

  factory SearchGroup.fromJson(Map<String, dynamic> j) => SearchGroup(
        id: j['id'] as int,
        name: j['name'] as String? ?? '',
        avatar: j['avatar'] as String?,
        avatarSizes: parseAvatarSizes(j['avatar_sizes']),
      );
}

class SearchRoom {
  final int id;
  final int serverId;
  final String name;
  final bool isVoice;

  final String? category;

  final ServerListItem server;

  final bool canSend;

  const SearchRoom({
    required this.id,
    required this.serverId,
    required this.name,
    required this.isVoice,
    required this.server,
    this.category,
    this.canSend = false,
  });

  factory SearchRoom.fromJson(Map<String, dynamic> j) => SearchRoom(
        id: j['id'] as int,
        serverId: j['server_id'] as int,
        name: j['name'] as String? ?? '',
        isVoice: j['kind'] == 'voice',
        category: j['category'] as String?,
        server: ServerListItem.fromJson(j['server'] as Map<String, dynamic>),
        canSend: j['can_send'] as bool? ?? false,
      );
}

class SearchHit {
  final SearchKind kind;
  final ServerUser? person;
  final SearchGroup? group;
  final SearchRoom? room;
  final ServerListItem? server;

  final int? chatId;

  const SearchHit._({
    required this.kind,
    this.person,
    this.group,
    this.room,
    this.server,
    this.chatId,
  });

  static SearchHit? fromJson(Map<String, dynamic> j) {
    final kind = _kindFrom(j['kind']);
    Map<String, dynamic>? body(String key) => j[key] as Map<String, dynamic>?;
    switch (kind) {
      case SearchKind.person:
        final p = body('person');
        return p == null
            ? null
            : SearchHit._(kind: kind!, person: ServerUser.fromJson(p), chatId: j['chat_id'] as int?);
      case SearchKind.group:
        final g = body('group');
        return g == null ? null : SearchHit._(kind: kind!, group: SearchGroup.fromJson(g));
      case SearchKind.room:
        final r = body('room');
        return r == null ? null : SearchHit._(kind: kind!, room: SearchRoom.fromJson(r));
      case SearchKind.server:
        final s = body('server');
        return s == null ? null : SearchHit._(kind: kind!, server: ServerListItem.fromJson(s));
      case null:
        return null;
    }
  }

  static List<SearchHit> listFrom(Map<String, dynamic> data) => [
        for (final raw in (data['items'] as List? ?? const []))
          if (SearchHit.fromJson(raw as Map<String, dynamic>) case final hit?) hit,
      ];

  PlaceRef? get place => switch (kind) {
        SearchKind.person => chatId == null ? null : PlaceRef.chat(chatId!),
        SearchKind.group => PlaceRef.chat(group!.id),
        SearchKind.room => room!.isVoice ? null : PlaceRef.room(room!.id),
        SearchKind.server => null,
      };
}

class PlaceRef {
  final String kind;
  final int id;

  const PlaceRef._(this.kind, this.id);
  const PlaceRef.chat(int id) : this._('chat', id);
  const PlaceRef.room(int id) : this._('room', id);

  String get wire => '$kind:$id';

  static PlaceRef? parse(String raw) {
    final i = raw.indexOf(':');
    if (i < 0) return null;
    final id = int.tryParse(raw.substring(i + 1));
    if (id == null) return null;
    return switch (raw.substring(0, i)) {
      'chat' => PlaceRef.chat(id),
      'room' => PlaceRef.room(id),
      _ => null,
    };
  }

  @override
  bool operator ==(Object other) => other is PlaceRef && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}
