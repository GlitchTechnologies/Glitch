import 'dart:async';

import 'package:flutter/material.dart';
import 'profile_achievements.dart';
import 'achievement_viewer.dart';

import '../core/date_text.dart';
import '../core/l10n.dart';
import '../core/own_account_open.dart';
import '../core/shell_controller.dart' show shellController, ShellSlot;
import '../models/profile.dart';
import '../providers/contact_provider.dart';
import '../providers/theme_provider.dart';
import '../screens/user_profile_screen.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'theme_workspace.dart';
import 'banner_header_art.dart';
import 'friend_button.dart';
import 'glitch_action_button.dart';
import 'glitch_avatar.dart';
import 'glitch_plus_badge.dart';
import 'glitch_pressable.dart' show ClickableCursor;
import 'profile_parts.dart';
import 'selectable_content.dart';
import 'profile_effect_overlay.dart';
import 'user_banner.dart';

const double kDmProfilePanelWidth = 340;
const double _kAvatarSize = 80;

class DmProfilePanel extends StatefulWidget {
  final String nickname;

  final VoidCallback? onFullProfileClosed;

  const DmProfilePanel({super.key, required this.nickname, this.onFullProfileClosed});

  @override
  State<DmProfilePanel> createState() => _DmProfilePanelState();
}

class _DmProfilePanelState extends State<DmProfilePanel> with ThemeAwareState<DmProfilePanel> {
  late final ContactProvider _provider;
  Mutual? _mutual;
  bool _mutualStarted = false;

  @override
  void initState() {
    super.initState();
    _provider = ContactProvider(nickname: widget.nickname)..init();
    _provider.addListener(_onProvider);
  }

  @override
  void dispose() {
    _provider.removeListener(_onProvider);
    _provider.dispose();
    super.dispose();
  }

  void _onProvider() {
    final user = _provider.user;
    if (user != null && !_mutualStarted) {
      _mutualStarted = true;
      _loadMutual(user.id);
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadMutual(int userId) async {
    try {
      final mutual = await api.getMutual(userId);
      if (mounted) setState(() => _mutual = mutual);
    } catch (_) {
    }
  }

  Future<void> _openFull() async {
    await showUserProfile(context, nickname: widget.nickname);
    widget.onFullProfileClosed?.call();
    if (!mounted) return;
    unawaited(_provider.reload());
  }

  @override
  Widget build(BuildContext context) {
    final user = _provider.user;
    Widget body;
    if (_provider.loading) {
      body = Center(child: CircularProgressIndicator(color: GlitchColors.accentBlue));
    } else if (user == null) {
      body = Center(
        child: Text(context.s.errorLoad, style: TextStyle(color: GlitchColors.textPrimary)),
      );
    } else {
      body = _content();
    }
    return Scaffold(backgroundColor: ThemeWorkspace.surface(context, GlitchColors.bg, tint: 0.22), body: SafeArea(child: body));
  }

  Widget _content() {
    final s = context.s;
    final user = _provider.user!;
    final blocked = _provider.isBlocked;
    final mutualLine = _mutualLine();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ProfileEffectOverlay(
            effect: user.profileEffect,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BannerHeaderArt(
                    besideAvatar: ProfileAchievements(userId: user.id, onShowAll: () {
                      final nav = Navigator.of(context, rootNavigator: true);
                      shellController.close(ShellSlot.details);
                      editMyProfile(nav.context, achievements: true);
                    }, onOpenAchievement: (item) {
                      final nav = Navigator.of(context, rootNavigator: true);
                      shellController.close(ShellSlot.details);
                      openAchievement(nav.context, item);
                    }),
                    bannerAspect: kUserBannerAspect,
                    banner: UserBanner(
                      url: user.banner,
                      sizes: user.bannerSizes,
                      color: user.avatarColor,
                      nickname: user.nickname,
                    ),
                    avatar: GlitchAvatar(
                      initials: GlitchAvatar.initialsFromName(user.displayName),
                      size: _kAvatarSize,
                      colorIndex: GlitchAvatar.colorFromNickname(user.nickname),
                      imageUrl: user.avatar != null ? api.mediaUrl(user.avatar!) : null,
                      avatarSizes: user.avatarSizes,
                      showOnline: !blocked && user.isOnline,
                      presenceUserId: user.id,
                      presenceStatus: user.presenceStatus,
                      presenceBlocked: blocked,
                      personalPresence: true,
                      // В открытом профиле украшение играет всегда.
                      decoration: user.avatarDecoration,
                      animateDecoration: true,
                    ),
                    avatarSize: _kAvatarSize,
                    avatarShape: AvatarShape.person,
                    ringColor: GlitchColors.bg,
                    onAvatarTap: _openFull,
                    bannerOverlay: (_) => FriendBannerButton(userId: user.id, hidden: blocked),
                  ),
                  SelectableContent(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          UserDisplayName(
                            displayName: user.displayName,
                            isGlitchPlus: user.isGlitchPlus,
                            ellipsis: true,
                            badgeSize: 18,
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary),
                          ),
                          const SizedBox(height: 2),
                          ProfileNickname(user.nickname),
                          if (mutualLine != null) ...[
                            const SizedBox(height: 10),
                            SelectionContainer.disabled(
                              child: ClickableCursor(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _openFull,
                                  child: Row(
                                    children: [
                                      Icon(Icons.groups_rounded, size: 16, color: GlitchColors.textSecond),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          mutualLine,
                                          style: TextStyle(fontSize: 12.5, color: GlitchColors.textSecond),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (blocked) ...[
                            const SizedBox(height: 14),
                            const ProfileBlockedNotice(),
                          ],
                          if ((user.bio ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 16),
                            ProfileBio(bio: user.bio),
                          ],
                          const SizedBox(height: 16),
                          ProfileFact(label: s.serverMembersColAccount, value: formatDay(user.createdAt)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: GlitchActionButton(label: s.userProfileOpenFull, soft: true, onTap: _openFull),
        ),
      ],
    );
  }

  String? _mutualLine() {
    final m = _mutual;
    if (m == null) return null;
    final s = context.s;
    final parts = [
      if (m.friends.isNotEmpty) s.mutualFriendsCount(m.friends.length),
      if (m.servers.isNotEmpty) s.memberCardMutualServers(m.servers.length),
    ];
    return parts.isEmpty ? null : parts.join(' • ');
  }
}
