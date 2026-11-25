import 'dart:ui' show Color;

import '../core/time_json.dart';
import '../core/avatar_color.dart';
import '../core/avatar_sizes.dart';
import 'activity.dart';
import 'presence.dart';
import 'collectible.dart';

class User {
  final int id;
  final String nickname;
  final String displayName;
  final String? email;
  final String? avatar;
  final Map<String, String>? avatarSizes;
  final Color? avatarColor;
  final String? bio;
  final String? banner;
  final Map<String, String>? bannerSizes;
  final DateTime createdAt;
  final DateTime lastSeen;
  final bool isOnline;
  final PresenceStatus presenceStatus;

  final List<UserActivity> activities;

  final List<RecentActivity> recentActivities;
  final bool isBlocked;
  final bool isBlockedBy; // заблокировал ли этот пользователь МЕНЯ (обратное направление)
  final bool isMutedInAdvance; // заглушено заранее, реального чата ещё нет
  final bool isGlitchPlus;
  final CollectibleLook? avatarDecoration;
  final CollectibleLook? nameplate;
  final CollectibleLook? profileEffect;

  const User({
    required this.id,
    required this.nickname,
    required this.displayName,
    this.email,
    this.avatar,
    this.avatarSizes,
    this.avatarColor,
    this.bio,
    this.banner,
    this.bannerSizes,
    required this.createdAt,
    required this.lastSeen,
    this.isOnline = false,
    this.presenceStatus = PresenceStatus.offline,
    this.activities = const [],
    this.recentActivities = const [],
    this.isBlocked = false,
    this.isBlockedBy = false,
    this.isMutedInAdvance = false,
    this.isGlitchPlus = false,
    this.avatarDecoration,
    this.nameplate,
    this.profileEffect,
  });

  factory User.fromJson(Map<String, dynamic> j) => User(
    id: j['id'],
    nickname: j['nickname'],
    displayName: j['display_name'],
    email: j['email'] as String?,
    avatar: j['avatar'],
    avatarSizes: parseAvatarSizes(j['avatar_sizes']),
    avatarColor: parseAvatarColor(j['avatar_color']),
    bio: j['bio'],
    banner: j['banner'] as String?,
    bannerSizes: parseAvatarSizes(j['banner_sizes']),
    createdAt: parseUtcLocal(j['created_at']),
    lastSeen: parseUtcLocal(j['last_seen']),
    isOnline: j['is_online'] == true || j['is_online'] == 1,
    presenceStatus: presenceStatusFrom(j['status'], online: j['is_online'] == true || j['is_online'] == 1),
    activities: UserActivity.listFromJson(j['activities']),
    recentActivities: RecentActivity.listFromJson(j['recent_activities']),
    isBlocked: j['is_blocked'] == true || j['is_blocked'] == 1,
    isBlockedBy: j['is_blocked_by'] == true || j['is_blocked_by'] == 1,
    isMutedInAdvance: j['is_muted_in_advance'] == true || j['is_muted_in_advance'] == 1,
    isGlitchPlus: j['is_glitch_plus'] == true || j['is_glitch_plus'] == 1,
    avatarDecoration: CollectibleLook.fromJson(j['avatar_decoration']),
    nameplate: CollectibleLook.fromJson(j['nameplate']),
    profileEffect: CollectibleLook.fromJson(j['profile_effect']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'nickname': nickname,
    'display_name': displayName,
    'email': email,
    'avatar': avatar,
    'avatar_sizes': avatarSizes,
    'avatar_color': avatarColorToJson(avatarColor),
    'bio': bio,
    'banner': banner,
    'banner_sizes': bannerSizes,
    'created_at': utcIso(createdAt),
    'last_seen': utcIso(lastSeen),
    'is_online': isOnline,
    'status': presenceStatus.name,
    'activities': [for (final a in activities) a.toJson()],
    'recent_activities': [for (final a in recentActivities) a.toJson()],
    'is_blocked': isBlocked,
    'is_blocked_by': isBlockedBy,
    'is_muted_in_advance': isMutedInAdvance,
    'is_glitch_plus': isGlitchPlus,
    'avatar_decoration': avatarDecoration?.toJson(),
    'nameplate': nameplate?.toJson(),
    'profile_effect': profileEffect?.toJson(),
  };
}

class UserSession {
  final int id;
  final String deviceName;
  final DateTime createdAt;
  final DateTime lastActiveAt;
  final bool isCurrent;

  const UserSession({
    required this.id,
    required this.deviceName,
    required this.createdAt,
    required this.lastActiveAt,
    this.isCurrent = false,
  });

  factory UserSession.fromJson(Map<String, dynamic> j) => UserSession(
    id: j['id'],
    deviceName: j['device_name'],
    createdAt: parseUtcLocal(j['created_at']),
    lastActiveAt: parseUtcLocal(j['last_active_at']),
    isCurrent: j['is_current'] == true || j['is_current'] == 1,
  );
}

class BlockedUser {
  final int id;
  final String nickname;
  final String displayName;
  final String? avatar;
  final Map<String, String>? avatarSizes;

  const BlockedUser({
    required this.id,
    required this.nickname,
    required this.displayName,
    this.avatar,
    this.avatarSizes,
  });

  factory BlockedUser.fromJson(Map<String, dynamic> j) => BlockedUser(
    id: j['id'],
    nickname: j['nickname'],
    displayName: j['display_name'],
    avatar: j['avatar'],
    avatarSizes: parseAvatarSizes(j['avatar_sizes']),
  );
}
