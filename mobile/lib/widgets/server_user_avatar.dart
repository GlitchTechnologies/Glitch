import 'package:flutter/material.dart';
import '../models/presence.dart';

import '../models/server.dart';
import '../services/api_service.dart';
import 'glitch_avatar.dart';

class ServerUserAvatar extends StatelessWidget {
  final ServerUser user;

  final String name;
  final double size;
  final bool showOnline;
  final PresenceStatus? presenceStatus;

  /// Показать украшение аватарки (оформление профиля, 2026-10-24). Только
  /// там, где его показывает Discord: строки участников и друзей, карточка;
  /// в мелких значках подсказок и выбора людей — нет. Анимация —
  /// [animateDecoration] (правила — core/collectibles.dart).
  final bool decorated;
  final bool animateDecoration;

  const ServerUserAvatar({
    super.key,
    required this.user,
    required this.name,
    required this.size,
    this.showOnline = false,
    this.presenceStatus,
    this.decorated = false,
    this.animateDecoration = false,
  });

  @override
  Widget build(BuildContext context) => GlitchAvatar(
        initials: GlitchAvatar.initialsFromName(name),
        size: size,
        colorIndex: GlitchAvatar.colorFromNickname(user.nickname),
        imageUrl: user.avatar != null ? api.mediaUrl(user.avatar!) : null,
        avatarSizes: user.avatarSizes,
        showOnline: showOnline,
        presenceUserId: showOnline || presenceStatus != null ? user.id : null,
        presenceStatus: presenceStatus,
        decoration: decorated ? user.avatarDecoration : null,
        animateDecoration: animateDecoration,
      );
}
