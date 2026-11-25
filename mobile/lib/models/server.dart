import 'dart:ui' show Color;

import '../core/avatar_color.dart';
import '../core/time_json.dart';
import '../core/avatar_sizes.dart';
import '../core/permissions.dart';
import 'notification_settings.dart';
import 'activity.dart';
import 'presence.dart';
import 'collectible.dart';
import 'voice_pass.dart';


enum RoomKind {
  text,
  voice;

  static RoomKind parse(dynamic raw) =>
      raw == 'voice' ? RoomKind.voice : RoomKind.text;
}

const int kMaxRoomName = 64;

class Room {
  final int id;
  final int serverId;
  final String name;
  final String? description;
  final RoomKind kind;

  final int? categoryId;

  final int position;

  final Perms permissions;

  final int? userLimit;

  const Room({
    required this.id,
    required this.serverId,
    required this.name,
    this.description,
    required this.kind,
    this.categoryId,
    this.position = 0,
    required this.permissions,
    this.userLimit,
  });

  Room withProfile({String? name, String? description, int? userLimit}) => Room(
    id: id,
    serverId: serverId,
    name: name ?? this.name,
    description: description,
    kind: kind,
    categoryId: categoryId,
    position: position,
    permissions: permissions,
    userLimit: userLimit,
  );

  Room inCategory(int? categoryId) => Room(
    id: id,
    serverId: serverId,
    name: name,
    description: description,
    kind: kind,
    categoryId: categoryId,
    position: position,
    permissions: permissions,
    userLimit: userLimit,
  );

  factory Room.fromJson(Map<String, dynamic> j) => Room(
    id: j['id'],
    serverId: j['server_id'],
    name: j['name'] ?? '',
    description: j['description'],
    kind: RoomKind.parse(j['kind']),
    categoryId: j['category_id'],
    position: j['position'] ?? 0,
    // Маска приходит СТРОКОЙ — почему именно так, см. core/permissions.dart.
    // Отсутствие поля (старый ответ сервера) — это «ничего нельзя», а не сбой
    // разбора: Perms.fromJson сам возвращает пустой набор на null.
    permissions: Perms.fromJson(j['permissions']),
    userLimit: (j['user_limit'] as num?)?.toInt(),
  );
}

class RoomCategory {
  final int id;
  final int serverId;
  final String name;
  final int position;
  final List<Room> rooms;

  final Perms permissions;

  const RoomCategory({
    required this.id,
    required this.serverId,
    required this.name,
    this.position = 0,
    this.rooms = const [],
    required this.permissions,
  });

  RoomCategory withName(String name) => RoomCategory(
    id: id,
    serverId: serverId,
    name: name,
    position: position,
    rooms: rooms,
    permissions: permissions,
  );

  RoomCategory withRooms(List<Room> rooms) => RoomCategory(
    id: id,
    serverId: serverId,
    name: name,
    position: position,
    rooms: rooms,
    permissions: permissions,
  );

  factory RoomCategory.fromJson(Map<String, dynamic> j) => RoomCategory(
    id: j['id'],
    serverId: j['server_id'],
    name: j['name'] ?? '',
    position: j['position'] ?? 0,
    rooms: ((j['rooms'] as List?) ?? const [])
        .map((e) => Room.fromJson(e))
        .toList(),
    permissions: Perms.fromJson(j['permissions']),
  );
}


class OverwriteRole {
  final int id;
  final String name;
  final String? color;
  final bool isDefault;

  final bool canEdit;

  const OverwriteRole({
    required this.id,
    required this.name,
    this.color,
    required this.isDefault,
    required this.canEdit,
  });

  factory OverwriteRole.fromJson(Map<String, dynamic> j) => OverwriteRole(
    id: j['id'],
    name: j['name'] ?? '',
    color: j['color'] as String?,
    isDefault: j['is_default'] == true,
    canEdit: j['can_edit'] == true,
  );
}

class RoleOverwrite {
  final Perms allow;
  final Perms deny;

  const RoleOverwrite(this.allow, this.deny);

  static final RoleOverwrite empty = RoleOverwrite(Perms.none, Perms.none);

  bool get isEmpty => allow.value == BigInt.zero && deny.value == BigInt.zero;

  @override
  bool operator ==(Object other) =>
      other is RoleOverwrite && other.allow == allow && other.deny == deny;

  @override
  int get hashCode => Object.hash(allow, deny);
}

class OverwriteMember {
  final ServerUser user;
  final RoleOverwrite overwrite;

  const OverwriteMember({required this.user, required this.overwrite});

  factory OverwriteMember.fromJson(Map<String, dynamic> j) => OverwriteMember(
    user: ServerUser.fromJson(j['user'] as Map<String, dynamic>),
    overwrite: RoleOverwrite(Perms.fromJson(j['allow']), Perms.fromJson(j['deny'])),
  );
}

class PlaceOverwrites {
  final List<OverwriteRole> roles;

  final Map<int, RoleOverwrite> overwrites;

  final List<OverwriteMember> members;

  final bool canEditMembers;

  final Perms grantable;

  final bool? synced;
  final String? categoryName;

  const PlaceOverwrites({
    required this.roles,
    required this.overwrites,
    this.members = const [],
    this.canEditMembers = false,
    required this.grantable,
    this.synced,
    this.categoryName,
  });

  factory PlaceOverwrites.fromJson(Map<String, dynamic> j) => PlaceOverwrites(
    roles: ((j['roles'] as List?) ?? const [])
        .map((e) => OverwriteRole.fromJson(e as Map<String, dynamic>))
        .toList(),
    overwrites: {
      for (final e in ((j['overwrites'] as List?) ?? const []).cast<Map<String, dynamic>>())
        e['role_id'] as int: RoleOverwrite(Perms.fromJson(e['allow']), Perms.fromJson(e['deny'])),
    },
    members: [
      for (final e in (j['members'] as List? ?? const []))
        if (e is Map<String, dynamic>) OverwriteMember.fromJson(e),
    ],
    canEditMembers: j['can_edit_members'] as bool? ?? false,
    grantable: Perms.fromJson(j['grantable']),
    synced: j['synced'] as bool?,
    categoryName: j['category_name'] as String?,
  );
}

class ServerListItem {
  final int id;
  final String name;
  final String? avatar;
  final Map<String, String>? avatarSizes;

  final String? avatarColor;
  final bool isOwner;

  final int mentionCount;

  final bool hasUnread;

  final ServerNotifSettings? notifications;

  final List<VoiceStateInfo>? voiceStates;

  const ServerListItem({
    required this.id,
    required this.name,
    this.avatar,
    this.avatarSizes,
    this.avatarColor,
    this.isOwner = false,
    this.mentionCount = 0,
    this.hasUnread = false,
    this.notifications,
    this.voiceStates,
  });

  factory ServerListItem.fromJson(Map<String, dynamic> j) => ServerListItem(
    id: j['id'],
    name: j['name'] ?? '',
    avatar: j['avatar'],
    avatarSizes: parseAvatarSizes(j['avatar_sizes']),
    avatarColor: j['avatar_color'],
    isOwner: j['is_owner'] ?? false,
    mentionCount: j['mention_count'] as int? ?? 0,
    hasUnread: j['has_unread'] == true,
    notifications: j['notifications'] is Map<String, dynamic>
        ? ServerNotifSettings.fromJson(j['notifications'] as Map<String, dynamic>)
        : null,
    voiceStates: j['voice_states'] is List
        ? [
            for (final v in j['voice_states'] as List)
              if (v is Map<String, dynamic>) VoiceStateInfo.fromJson(v),
          ]
        : null,
  );

  ServerListItem withProfile(ServerProfile p) => ServerListItem(
    id: id,
    name: p.name,
    avatar: p.avatar,
    avatarSizes: p.avatarSizes,
    avatarColor: p.avatarColor,
    isOwner: isOwner,
    mentionCount: mentionCount,
    hasUnread: hasUnread,
    notifications: notifications,
    voiceStates: voiceStates,
  );
}

const int kMaxServerGames = 5;

class Game {
  final int id;
  final String name;

  const Game({required this.id, required this.name});

  factory Game.fromJson(Map<String, dynamic> j) => Game(
    id: j['id'] as int,
    name: j['name'] as String? ?? '',
  );
}

/// Разбор списка игр из ответа — одна точка на профиль, полный ответ и
/// карточку приглашения. Нет поля (старый ответ) — пустой список.
List<Game> _parseGames(dynamic raw) => ((raw as List?) ?? const [])
    .whereType<Map<String, dynamic>>()
    .map(Game.fromJson)
    .toList();

class ServerProfile {
  final int id;
  final String name;
  final String? description;
  final String? avatar;
  final Map<String, String>? avatarSizes;
  final String? avatarColor;
  final String? banner;

  final Map<String, String>? bannerSizes;
  final DateTime createdAt;

  final List<Game> games;

  final bool isPublic;

  final NotifLevel defaultNotifications;

  final ServerSystemSettings system;

  const ServerProfile({
    required this.id,
    required this.name,
    this.description,
    this.avatar,
    this.avatarSizes,
    this.avatarColor,
    this.banner,
    this.bannerSizes,
    required this.createdAt,
    this.games = const [],
    this.isPublic = false,
    this.defaultNotifications = NotifLevel.all,
    this.system = ServerSystemSettings.initial,
  });

  factory ServerProfile.fromJson(Map<String, dynamic> j) => ServerProfile(
    id: j['id'],
    name: j['name'] ?? '',
    description: j['description'],
    avatar: j['avatar'],
    avatarSizes: parseAvatarSizes(j['avatar_sizes']),
    avatarColor: j['avatar_color'],
    banner: j['banner'],
    bannerSizes: parseAvatarSizes(j['banner_sizes']),
    createdAt: parseUtcLocal(j['created_at']),
    games: _parseGames(j['games']),
    isPublic: j['is_public'] as bool? ?? false,
    defaultNotifications: NotifLevel.parse(j['default_notifications']),
    system: ServerSystemSettings.fromJson(j),
  );
}

class ServerSystemSettings {
  final int? roomId;

  final bool joinMessages;

  final bool leaveMessages;

  const ServerSystemSettings({this.roomId, required this.joinMessages, required this.leaveMessages});

  static const initial = ServerSystemSettings(joinMessages: true, leaveMessages: false);

  factory ServerSystemSettings.fromJson(Map<String, dynamic> j) => ServerSystemSettings(
    roomId: j['system_room_id'] as int?,
    joinMessages: j['system_join_messages'] as bool? ?? true,
    leaveMessages: j['system_leave_messages'] as bool? ?? false,
  );

  @override
  bool operator ==(Object other) =>
      other is ServerSystemSettings &&
      other.roomId == roomId &&
      other.joinMessages == joinMessages &&
      other.leaveMessages == leaveMessages;

  @override
  int get hashCode => Object.hash(roomId, joinMessages, leaveMessages);
}

class ServerInvitePreview {
  final int serverId;
  final String name;
  final String? description;
  final String? avatar;
  final Map<String, String>? avatarSizes;
  final String? avatarColor;
  final String? banner;
  final Map<String, String>? bannerSizes;

  /// Дата основания для карточки. `null` — старый ответ без поля.
  final DateTime? createdAt;
  final List<Game> games;
  final int memberCount;

  /// Сколько участников в сети (правило приватности — на сервере). В
  /// карточке приглашения с 2026-10-03; у старого ответа поля нет — 0.
  final int onlineCount;

  final bool alreadyMember;

  const ServerInvitePreview({
    required this.serverId,
    required this.name,
    this.description,
    this.avatar,
    this.avatarSizes,
    this.avatarColor,
    this.banner,
    this.bannerSizes,
    this.createdAt,
    this.games = const [],
    this.memberCount = 0,
    this.onlineCount = 0,
    this.alreadyMember = false,
  });

  factory ServerInvitePreview.fromJson(Map<String, dynamic> j) => ServerInvitePreview(
    serverId: j['server_id'],
    name: j['name'] ?? '',
    description: j['description'],
    avatar: j['avatar'],
    avatarSizes: parseAvatarSizes(j['avatar_sizes']),
    avatarColor: j['avatar_color'],
    banner: j['banner'],
    bannerSizes: parseAvatarSizes(j['banner_sizes']),
    createdAt: j['created_at'] != null ? parseUtcLocal(j['created_at']) : null,
    games: _parseGames(j['games']),
    memberCount: j['member_count'] ?? 0,
    onlineCount: j['online_count'] ?? 0,
    alreadyMember: j['already_member'] ?? false,
  );
}

class ServerCatalogItem {
  final ServerInvitePreview server;

  const ServerCatalogItem({required this.server});

  int get onlineCount => server.onlineCount;

  factory ServerCatalogItem.fromJson(Map<String, dynamic> j) =>
      ServerCatalogItem(server: ServerInvitePreview.fromJson(j));
}

class ServerDetail {
  final int id;
  final String name;
  final String? description;
  final String? avatar;
  final Map<String, String>? avatarSizes;
  final String? avatarColor;
  final String? banner;
  final Map<String, String>? bannerSizes;
  final int ownerId;
  final bool isPublic;

  final NotifLevel defaultNotifications;

  final ServerSystemSettings system;
  final DateTime createdAt;
  final bool isOwner;

  final int memberCount;

  final List<Game> games;

  final Perms myPermissions;

  final List<Room> rooms;
  final List<RoomCategory> categories;

  final List<VoiceStateInfo> voiceStates;

  final List<int> unreadRoomIds;

  final Map<int, int> mentionCounts;

  const ServerDetail({
    required this.id,
    required this.name,
    this.description,
    this.avatar,
    this.avatarSizes,
    this.avatarColor,
    this.banner,
    this.bannerSizes,
    required this.ownerId,
    this.isPublic = false,
    this.defaultNotifications = NotifLevel.all,
    this.system = ServerSystemSettings.initial,
    required this.createdAt,
    this.isOwner = false,
    this.memberCount = 0,
    this.games = const [],
    required this.myPermissions,
    this.rooms = const [],
    this.categories = const [],
    this.voiceStates = const [],
    this.unreadRoomIds = const [],
    this.mentionCounts = const {},
  });

  factory ServerDetail.fromJson(Map<String, dynamic> j) => ServerDetail(
    id: j['id'],
    name: j['name'] ?? '',
    description: j['description'],
    avatar: j['avatar'],
    avatarSizes: parseAvatarSizes(j['avatar_sizes']),
    avatarColor: j['avatar_color'],
    banner: j['banner'],
    bannerSizes: parseAvatarSizes(j['banner_sizes']),
    ownerId: j['owner_id'],
    isPublic: j['is_public'] ?? false,
    defaultNotifications: NotifLevel.parse(j['default_notifications']),
    system: ServerSystemSettings.fromJson(j),
    createdAt: parseUtcLocal(j['created_at']),
    isOwner: j['is_owner'] ?? false,
    memberCount: j['member_count'] ?? 0,
    games: _parseGames(j['games']),
    myPermissions: Perms.fromJson(j['my_permissions']),
    rooms: ((j['rooms'] as List?) ?? const [])
        .map((e) => Room.fromJson(e))
        .toList(),
    categories: ((j['categories'] as List?) ?? const [])
        .map((e) => RoomCategory.fromJson(e))
        .toList(),
    voiceStates: [
      for (final v in (j['voice_states'] as List? ?? const []))
        if (v is Map<String, dynamic>) VoiceStateInfo.fromJson(v),
    ],
    unreadRoomIds: [
      for (final id in (j['unread_room_ids'] as List? ?? const []))
        if (id is int) id,
    ],
    mentionCounts: {
      for (final e in ((j['mention_counts'] as Map?) ?? const {}).entries)
        if (int.tryParse('${e.key}') != null && e.value is int) int.parse('${e.key}'): e.value as int,
    },
  );

  ServerProfile get profile => ServerProfile(
    id: id,
    name: name,
    description: description,
    avatar: avatar,
    avatarSizes: avatarSizes,
    avatarColor: avatarColor,
    banner: banner,
    bannerSizes: bannerSizes,
    createdAt: createdAt,
    games: games,
    isPublic: isPublic,
    defaultNotifications: defaultNotifications,
    system: system,
  );

  ServerDetail withProfile(ServerProfile p) => ServerDetail(
    id: id,
    name: p.name,
    description: p.description,
    avatar: p.avatar,
    avatarSizes: p.avatarSizes,
    avatarColor: p.avatarColor,
    banner: p.banner,
    bannerSizes: p.bannerSizes,
    ownerId: ownerId,
    isPublic: p.isPublic,
    defaultNotifications: p.defaultNotifications,
    system: p.system,
    createdAt: p.createdAt,
    isOwner: isOwner,
    memberCount: memberCount,
    games: p.games,
    myPermissions: myPermissions,
    rooms: rooms,
    categories: categories,
    voiceStates: voiceStates,
    unreadRoomIds: unreadRoomIds,
    mentionCounts: mentionCounts,
  );

  ServerDetail _withLayout(List<Room> rooms, List<RoomCategory> categories) => ServerDetail(
    id: id,
    name: name,
    description: description,
    avatar: avatar,
    avatarSizes: avatarSizes,
    avatarColor: avatarColor,
    banner: banner,
    bannerSizes: bannerSizes,
    ownerId: ownerId,
    isPublic: isPublic,
    defaultNotifications: defaultNotifications,
    system: system,
    createdAt: createdAt,
    isOwner: isOwner,
    memberCount: memberCount,
    games: games,
    myPermissions: myPermissions,
    rooms: rooms,
    categories: categories,
    voiceStates: voiceStates,
    unreadRoomIds: unreadRoomIds,
    mentionCounts: mentionCounts,
  );

  ServerDetail withRoomMoved(int roomId, {required int? categoryId, required int? afterId}) {
    Room? moved;
    for (final r in allRooms) {
      if (r.id == roomId) moved = r;
    }
    if (moved == null) return this;
    final room = moved.inCategory(categoryId);

    List<Room> place(List<Room> list, bool isTarget) {
      final rest = [for (final r in list) if (r.id != roomId) r];
      if (!isTarget) return rest;
      return [...rest]..insert(_insertAt(rest.map((r) => r.id).toList(), afterId), room);
    }

    return _withLayout(
      place(rooms, categoryId == null),
      [for (final c in categories) c.withRooms(place(c.rooms, c.id == categoryId))],
    );
  }

  ServerDetail withCategoryMoved(int categoryId, {required int? afterId}) {
    final i = categories.indexWhere((c) => c.id == categoryId);
    if (i < 0) return this;
    final moved = categories[i];
    final rest = [for (final c in categories) if (c.id != categoryId) c];
    return _withLayout(
      rooms,
      [...rest]..insert(_insertAt(rest.map((c) => c.id).toList(), afterId), moved),
    );
  }

  static int _insertAt(List<int> ids, int? afterId) {
    if (afterId == null) return 0;
    final i = ids.indexOf(afterId);
    return i < 0 ? ids.length : i + 1;
  }

  List<Room> get allRooms => [
    ...rooms,
    for (final c in categories) ...c.rooms,
  ];
}


class ServerUser {
  final int id;
  final String nickname;
  final String displayName;
  final String? avatar;
  final Map<String, String>? avatarSizes;

  final Color? avatarColor;

  /// Надетое оформление (2026-10-24, models/collectible.dart): украшение
  /// рисует аватарка, плашка — фон строки человека. `null` — не надето.
  final CollectibleLook? avatarDecoration;
  final CollectibleLook? nameplate;

  const ServerUser({
    required this.id,
    required this.nickname,
    required this.displayName,
    this.avatar,
    this.avatarSizes,
    this.avatarColor,
    this.avatarDecoration,
    this.nameplate,
  });

  factory ServerUser.fromJson(Map<String, dynamic> j) => ServerUser(
    id: j['id'] as int,
    nickname: j['nickname'] as String? ?? '',
    displayName: j['display_name'] as String? ?? '',
    avatar: j['avatar'] as String?,
    avatarSizes: parseAvatarSizes(j['avatar_sizes']),
    avatarColor: parseAvatarColor(j['avatar_color']),
    avatarDecoration: CollectibleLook.fromJson(j['avatar_decoration']),
    nameplate: CollectibleLook.fromJson(j['nameplate']),
  );
}

class MemberRole {
  final int id;
  final String name;
  final String? color;

  const MemberRole({required this.id, required this.name, this.color});

  factory MemberRole.fromJson(Map<String, dynamic> j) => MemberRole(
    id: j['id'] as int,
    name: j['name'] as String? ?? '',
    color: j['color'] as String?,
  );
}

class MyServerProfile {
  final int serverId;
  final String? nick;
  final String? bio;
  final String? avatar;
  final Map<String, String>? avatarSizes;
  final String? banner;
  final Map<String, String>? bannerSizes;

  final bool canChangeNick;

  const MyServerProfile({
    required this.serverId,
    this.nick,
    this.bio,
    this.avatar,
    this.avatarSizes,
    this.banner,
    this.bannerSizes,
    this.canChangeNick = false,
  });

  factory MyServerProfile.fromJson(Map<String, dynamic> j) => MyServerProfile(
    serverId: j['server_id'],
    nick: j['nick'],
    bio: j['bio'],
    avatar: j['avatar'],
    avatarSizes: parseAvatarSizes(j['avatar_sizes']),
    banner: j['banner'],
    bannerSizes: parseAvatarSizes(j['banner_sizes']),
    canChangeNick: j['can_change_nick'] ?? false,
  );
}

class MemberCard {
  final ServerUser user;

  final String? nick;
  final String? bio;
  final String? banner;
  final Map<String, String>? bannerSizes;
  final CollectibleLook? profileEffect;
  final bool isGlitchPlus;
  final DateTime joinedAt;
  final DateTime accountCreatedAt;

  final List<MemberRole> roles;
  final bool isOwner;

  final bool isOnline;
  final PresenceStatus presenceStatus;

  final List<UserActivity> activities;

  final int? mutualServers;

  final int? mutualFriends;

  final bool canManageRoles;

  const MemberCard({
    required this.user,
    this.nick,
    this.bio,
    this.banner,
    this.bannerSizes,
    this.profileEffect,
    this.isGlitchPlus = false,
    required this.joinedAt,
    required this.accountCreatedAt,
    this.roles = const [],
    this.isOwner = false,
    this.isOnline = false,
    this.presenceStatus = PresenceStatus.offline,
    this.activities = const [],
    this.mutualServers,
    this.mutualFriends,
    this.canManageRoles = false,
  });

  String get shownName => user.displayName;

  factory MemberCard.fromJson(Map<String, dynamic> j) => MemberCard(
    user: ServerUser.fromJson(j['user'] as Map<String, dynamic>),
    nick: j['nick'] as String?,
    bio: j['bio'] as String?,
    banner: j['banner'] as String?,
    profileEffect: CollectibleLook.fromJson(j['profile_effect']),
    bannerSizes: parseAvatarSizes(j['banner_sizes']),
    isGlitchPlus: j['is_glitch_plus'] as bool? ?? false,
    joinedAt: parseUtcLocal(j['joined_at']),
    accountCreatedAt: parseUtcLocal(j['account_created_at']),
    roles: ((j['roles'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(MemberRole.fromJson)
        .toList(),
    isOwner: j['is_owner'] as bool? ?? false,
    isOnline: j['is_online'] as bool? ?? false,
    presenceStatus: presenceStatusFrom(j['status'], online: j['is_online'] == true),
    activities: UserActivity.listFromJson(j['activities']),
    mutualServers: j['mutual_servers'] as int?,
    mutualFriends: j['mutual_friends'] as int?,
    canManageRoles: j['can_manage_roles'] as bool? ?? false,
  );
}

class ServerMember {
  final ServerUser user;

  final String? nick;
  final DateTime joinedAt;
  final DateTime accountCreatedAt;

  final String? inviteCode;

  final List<MemberRole> roles;
  final bool isOwner;

  final bool canKick;
  final bool canBan;

  final bool canEditNick;

  const ServerMember({
    required this.user,
    this.nick,
    required this.joinedAt,
    required this.accountCreatedAt,
    this.inviteCode,
    this.roles = const [],
    this.isOwner = false,
    this.canKick = false,
    this.canBan = false,
    this.canEditNick = false,
  });

  String get shownName => user.displayName;

  factory ServerMember.fromJson(Map<String, dynamic> j) => ServerMember(
    user: ServerUser.fromJson(j['user'] as Map<String, dynamic>),
    nick: j['nick'] as String?,
    joinedAt: parseUtcLocal(j['joined_at']),
    accountCreatedAt: parseUtcLocal(j['account_created_at']),
    inviteCode: j['invite_code'] as String?,
    roles: ((j['roles'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(MemberRole.fromJson)
        .toList(),
    isOwner: j['is_owner'] as bool? ?? false,
    canKick: j['can_kick'] as bool? ?? false,
    canBan: j['can_ban'] as bool? ?? false,
    canEditNick: j['can_edit_nick'] as bool? ?? false,
  );
}

class ServerBan {
  final ServerUser user;
  final String? reason;

  final ServerUser? bannedBy;
  final DateTime createdAt;

  const ServerBan({required this.user, this.reason, this.bannedBy, required this.createdAt});

  factory ServerBan.fromJson(Map<String, dynamic> j) => ServerBan(
    user: ServerUser.fromJson(j['user'] as Map<String, dynamic>),
    reason: j['reason'] as String?,
    bannedBy: j['banned_by'] is Map<String, dynamic>
        ? ServerUser.fromJson(j['banned_by'] as Map<String, dynamic>)
        : null,
    createdAt: parseUtcLocal(j['created_at']),
  );
}

class MemberDisplayChange {
  final int? serverId;

  final int? userId;

  const MemberDisplayChange({this.serverId, this.userId});

  bool affects(int serverId, {int? userId}) =>
      (this.serverId == null || this.serverId == serverId) &&
      (this.userId == null || userId == null || this.userId == userId);
}

class ServerRoomEvent {
  final int serverId;
  final int chatId;
  final bool deleted;

  final String? name;
  final String? description;

  final int? userLimit;

  const ServerRoomEvent({
    required this.serverId,
    required this.chatId,
    required this.deleted,
    this.name,
    this.description,
    this.userLimit,
  });
}

enum ServerGoneReason {
  removed,

  left,

  deleted;

  static ServerGoneReason fromWire(Object? reason) =>
      reason == 'left' ? ServerGoneReason.left : ServerGoneReason.removed;
}

class ServerGone {
  final int id;
  final String name;
  final ServerGoneReason reason;

  const ServerGone({required this.id, required this.name, required this.reason});
}

class ServerRole {
  final int id;
  final String name;

  final String? color;
  final int position;

  /// Права роли. СТРОКОЙ с сервера, здесь — [Perms] поверх BigInt: в вебе
  /// обычный int точен лишь до 2^53 (см. core/permissions.dart).
  final Perms permissions;

  /// @everyone: её нельзя удалить, выдать, снять и переставить, а из формы у
  /// неё читаются только права. Сервер это проверяет сам — клиент лишь рисует
  /// урезанный редактор.
  final bool isDefault;

  final bool hoist;

  final bool mentionable;

  final int memberCount;

  final bool canEdit;

  const ServerRole({
    required this.id,
    required this.name,
    this.color,
    required this.position,
    required this.permissions,
    this.isDefault = false,
    this.hoist = false,
    this.mentionable = false,
    this.memberCount = 0,
    this.canEdit = false,
  });

  factory ServerRole.fromJson(Map<String, dynamic> j) => ServerRole(
    id: j['id'] as int,
    name: j['name'] as String? ?? '',
    color: j['color'] as String?,
    position: j['position'] as int? ?? 0,
    permissions: Perms.fromJson(j['permissions']),
    isDefault: j['is_default'] as bool? ?? false,
    hoist: j['hoist'] as bool? ?? false,
    mentionable: j['mentionable'] as bool? ?? false,
    memberCount: j['member_count'] as int? ?? 0,
    canEdit: j['can_edit'] as bool? ?? false,
  );
}

/// ⚠️ Права уходят СТРОКОЙ (`Perms.toJson`), а не числом: в вебе int точен
/// лишь до 2^53.
class ServerRoleForm {
  final String name;
  final String? color;
  final Perms permissions;
  final bool hoist;
  final bool mentionable;

  const ServerRoleForm({
    required this.name,
    this.color,
    required this.permissions,
    this.hoist = false,
    this.mentionable = false,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'color': color,
    'permissions': permissions.toJson(),
    'hoist': hoist,
    'mentionable': mentionable,
  };
}

class ServerRolesPage {
  final List<ServerRole> roles;
  final bool canCreate;

  const ServerRolesPage({required this.roles, this.canCreate = false});

  factory ServerRolesPage.fromJson(Map<String, dynamic> j) => ServerRolesPage(
    roles: ((j['roles'] as List?) ?? const [])
        .map((e) => ServerRole.fromJson(e as Map<String, dynamic>))
        .toList(),
    canCreate: j['can_create'] as bool? ?? false,
  );
}

class RosterMember {
  final ServerUser user;

  final String? nick;

  final String? color;
  final bool isOwner;

  final bool isOnline;
  final PresenceStatus presenceStatus;

  final List<UserActivity> activities;

  const RosterMember({
    required this.user,
    this.nick,
    this.color,
    this.isOwner = false,
    this.isOnline = false,
    this.presenceStatus = PresenceStatus.offline,
    this.activities = const [],
  });

  String get shownName => user.displayName;

  factory RosterMember.fromJson(Map<String, dynamic> j) => RosterMember(
    user: ServerUser.fromJson(j['user'] as Map<String, dynamic>),
    nick: j['nick'] as String?,
    color: j['color'] as String?,
    isOwner: j['is_owner'] as bool? ?? false,
    isOnline: j['is_online'] as bool? ?? false,
    presenceStatus: presenceStatusFrom(j['status'], online: j['is_online'] == true),
    activities: UserActivity.listFromJson(j['activities']),
  );
}

class RosterGroup {
  final String kind;
  final int? roleId;

  final String? name;
  final String? color;
  final List<RosterMember> members;

  const RosterGroup({
    required this.kind,
    this.roleId,
    this.name,
    this.color,
    this.members = const [],
  });

  factory RosterGroup.fromJson(Map<String, dynamic> j) => RosterGroup(
    kind: j['kind'] as String? ?? 'online',
    roleId: j['role_id'] as int?,
    name: j['name'] as String?,
    color: j['color'] as String?,
    members: ((j['members'] as List?) ?? const [])
        .map((e) => RosterMember.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class ServerRoster {
  final List<RosterGroup> groups;

  final int total;
  final int shown;

  const ServerRoster({this.groups = const [], this.total = 0, this.shown = 0});

  factory ServerRoster.fromJson(Map<String, dynamic> j) => ServerRoster(
    groups: ((j['groups'] as List?) ?? const [])
        .map((e) => RosterGroup.fromJson(e as Map<String, dynamic>))
        .toList(),
    total: j['total'] as int? ?? 0,
    shown: j['shown'] as int? ?? 0,
  );
}
