import '../core/time_json.dart';
import 'collectible.dart';
import 'presence.dart';
import 'message.dart';
import '../core/avatar_sizes.dart';
import '../core/text_match.dart' as text_match;

class ChatListItem {
  bool matchesQuery(String query) => text_match.matchesQuery(query, [name, otherNickname]);

  final int id;
  final String type;
  final String? name;
  final String? avatar;
  final Map<String, String>? avatarSizes;
  final String? otherNickname; // только для personal
  final CollectibleLook? avatarDecoration;
  final MessagePreview? lastMessage;
  final int unreadCount;
  final bool isOwner;
  final bool isOnline;
  final PresenceStatus presenceStatus;
  final int? otherUserId;
  final bool presenceBlocked;
  final DateTime? lastSeen;

  const ChatListItem({
    required this.id,
    required this.type,
    this.name,
    this.avatar,
    this.avatarSizes,
    this.otherNickname,
    this.avatarDecoration,
    this.lastMessage,
    required this.unreadCount,
    this.isOwner = false,
    this.isOnline = false,
    this.presenceStatus = PresenceStatus.offline,
    this.otherUserId,
    this.presenceBlocked = false,
    this.lastSeen,
  });

  factory ChatListItem.fromJson(Map<String, dynamic> j) => ChatListItem(
    id: j['id'],
    type: j['type'],
    name: j['name'],
    avatar: j['avatar'],
    avatarSizes: parseAvatarSizes(j['avatar_sizes']),
    otherNickname: j['other_nickname'],
    avatarDecoration: CollectibleLook.fromJson(j['avatar_decoration']),
    lastMessage: j['last_message'] != null ? MessagePreview.fromJson(j['last_message']) : null,
    unreadCount: j['unread_count'] ?? 0,
    isOwner: j['is_owner'] ?? false,
    isOnline: j['is_online'] == true || j['is_online'] == 1,
    presenceStatus: presenceStatusFrom(j['status'], online: j['is_online'] == true || j['is_online'] == 1),
    otherUserId: j['other_user_id'] as int?,
    presenceBlocked: j['presence_blocked'] == true,
    lastSeen: j['last_seen'] != null ? parseUtcLocal(j['last_seen']) : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'name': name,
    'avatar': avatar,
    'avatar_sizes': avatarSizes,
    'other_nickname': otherNickname,
    'avatar_decoration': avatarDecoration?.toJson(),
    'last_message': lastMessage?.toJson(),
    'unread_count': unreadCount,
    'is_owner': isOwner,
    'is_online': isOnline,
    'status': presenceStatus.name,
    'other_user_id': otherUserId,
    'presence_blocked': presenceBlocked,
    'last_seen': lastSeen == null ? null : utcIso(lastSeen!),
  };

  ChatListItem copyWith({int? unreadCount}) => ChatListItem(
    id: id,
    type: type,
    name: name,
    avatar: avatar,
    avatarSizes: avatarSizes,
    otherNickname: otherNickname,
    avatarDecoration: avatarDecoration,
    lastMessage: lastMessage,
    unreadCount: unreadCount ?? this.unreadCount,
    isOwner: isOwner,
    isOnline: isOnline,
    presenceStatus: presenceStatus,
    otherUserId: otherUserId,
    presenceBlocked: presenceBlocked,
    lastSeen: lastSeen,
  );
}

class ChatMember {
  bool matchesQuery(String query) => text_match.matchesQuery(query, [displayName, nickname]);

  final int id;
  final String nickname;
  final String displayName;
  final String? avatar;
  final Map<String, String>? avatarSizes;
  final String role;
  final bool isOnline;
  final PresenceStatus presenceStatus;
  final DateTime lastSeen;

  const ChatMember({
    required this.id,
    required this.nickname,
    required this.displayName,
    this.avatar,
    this.avatarSizes,
    required this.role,
    this.isOnline = false,
    this.presenceStatus = PresenceStatus.offline,
    required this.lastSeen,
  });

  factory ChatMember.fromJson(Map<String, dynamic> j) {
    final user = j['user'] as Map<String, dynamic>;
    return ChatMember(
      id: user['id'],
      nickname: user['nickname'],
      displayName: user['display_name'],
      avatar: user['avatar'],
      avatarSizes: parseAvatarSizes(user['avatar_sizes']),
      role: j['role'],
      isOnline: user['is_online'] == true || user['is_online'] == 1,
      presenceStatus: presenceStatusFrom(user['status'], online: user['is_online'] == true || user['is_online'] == 1),
      lastSeen: parseUtcLocal(user['last_seen']),
    );
  }
}

class Chat {
  final int id;
  final String type;
  final String? name;
  final String? description;
  final String? avatar;
  final Map<String, String>? avatarSizes;
  final List<ChatMember> members;
  final bool isMuted;

  const Chat({
    required this.id,
    required this.type,
    this.name,
    this.description,
    this.avatar,
    this.avatarSizes,
    required this.members,
    this.isMuted = false,
  });

  factory Chat.fromJson(Map<String, dynamic> j) => Chat(
    id: j['id'],
    type: j['type'],
    name: j['name'],
    description: j['description'],
    avatar: j['avatar'],
    avatarSizes: parseAvatarSizes(j['avatar_sizes']),
    members: (j['members'] as List).map((m) => ChatMember.fromJson(m)).toList(),
    isMuted: j['is_muted'] ?? false,
  );

  String displayName(int currentUserId) {
    if (type == 'group') return name ?? 'Группа';
    final other = members.where((m) => m.id != currentUserId).firstOrNull;
    return other?.displayName ?? 'Чат';
  }
}

class GroupInvitePreview {
  final int id;
  final String? name;
  final String? avatar;
  final Map<String, String>? avatarSizes;
  final int memberCount;
  final bool alreadyMember;

  const GroupInvitePreview({
    required this.id,
    this.name,
    this.avatar,
    this.avatarSizes,
    required this.memberCount,
    required this.alreadyMember,
  });

  factory GroupInvitePreview.fromJson(Map<String, dynamic> j) => GroupInvitePreview(
    id: j['id'],
    name: j['name'],
    avatar: j['avatar'],
    avatarSizes: parseAvatarSizes(j['avatar_sizes']),
    memberCount: j['member_count'] ?? 0,
    alreadyMember: j['already_member'] ?? false,
  );
}
