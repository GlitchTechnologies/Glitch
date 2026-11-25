import 'package:flutter/material.dart';

import '../core/copy_actions.dart';
import '../core/l10n.dart';
import '../core/own_account_open.dart';
import '../models/user.dart';
import '../models/presence.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/user_presences.dart';
import '../theme/app_theme.dart';
import '../theme/glitch_ink.dart';
import 'adaptive_sheet.dart';
import 'glitch_avatar.dart';
import 'glitch_menu.dart';
import 'glitch_cascade_menu.dart';
import 'glitch_toast.dart';
import 'presence_indicator.dart';
import 'glitch_plus_badge.dart';
import 'profile_parts.dart';
import 'member_card.dart' show MemberCardLayout, kMemberCardWidth, kMemberCardAvatar;
import '../models/achievement.dart';
import 'achievement_viewer.dart';
import 'user_banner.dart';

Future<void> showOwnAccountCard(
  BuildContext anchorContext, {
  required Rect anchorRect,
  required double horizontalScreenMargin,
}) => openAdaptivePopup(
      anchorContext,
      width: kMemberCardWidth,
      growRight: true,
      anchorRect: anchorRect,
      horizontalScreenMargin: horizontalScreenMargin,
      builder: (close, _) => _OwnAccountCard(anchorContext: anchorContext, close: close),
    );

class _OwnAccountCard extends StatefulWidget {
  final BuildContext anchorContext;
  final Future<void> Function() close;

  const _OwnAccountCard({required this.anchorContext, required this.close});

  @override
  State<_OwnAccountCard> createState() => _OwnAccountCardState();
}

class _OwnAccountCardState extends State<_OwnAccountCard> with ThemeAwareState<_OwnAccountCard> {
  static const _statusWidth = 250.0;
  static const _durationWidth = 190.0;
  bool _openingEditor = false;
  Future<void> _viewAchievement(Achievement item) async {
    if (_openingEditor) return;
    _openingEditor = true;
    final anchor = widget.anchorContext;
    await widget.close();
    if (anchor.mounted) await openAchievement(anchor, item);
  }

  Future<void> _loadStatus() async {
    final anchor = widget.anchorContext;
    final userId = authService.currentUser?.id;
    try {
      await userPresences.load();
    } catch (e) {
      if (anchor.mounted && authService.currentUser?.id == userId) GlitchToast.show(anchor, errorMessage(e));
    }
  }

  Future<void> _selectStatus(PresenceStatus status, int? minutes) async {
    if (userPresences.saving) return;
    final anchor = widget.anchorContext;
    final userId = authService.currentUser?.id;
    try {
      await userPresences.choose(status, minutes);
      if (!mounted) return;
      await widget.close();
    } catch (e) {
      if (anchor.mounted && authService.currentUser?.id == userId) GlitchToast.show(anchor, errorMessage(e));
    }
  }

  String _durationLabel(BuildContext context, int? minutes) => switch (minutes) {
        15 => context.s.notifMuteFor15m,
        60 => context.s.notifMuteFor1h,
        480 => context.s.notifMuteFor8h,
        1440 => context.s.notifMuteFor24h,
        4320 => context.s.presenceFor3d,
        _ => context.s.presenceForever,
      };

  Widget _statusMenu(Future<void> Function() close, double maxHeight) => ListenableBuilder(
        listenable: userPresences,
        builder: (context, _) => !userPresences.ready
            ? GlitchPopupCard(maxHeight: maxHeight, child: GlitchMenuTapRow(
                onTap: userPresences.loading ? null : _loadStatus,
                child: glitchMenuRow(userPresences.loading ? Icons.hourglass_empty : Icons.refresh,
                    userPresences.loading ? context.s.loading : context.s.retry),
              ))
            : GlitchCascadeMenu(
          close: close,
          maxHeight: maxHeight,
          mainWidth: _statusWidth,
          listWidth: _durationWidth,
          entries: [
            for (final status in const [PresenceStatus.online, PresenceStatus.idle, PresenceStatus.dnd, PresenceStatus.invisible])
              GlitchCascadeEntry(
                separatorBefore: status == PresenceStatus.idle,
                title: presenceLabel(context, status),
                value: switch (status) {
                  PresenceStatus.dnd => context.s.presenceDndHint,
                  PresenceStatus.invisible => context.s.presenceInvisibleHint,
                  _ => '',
                },
                leading: PresenceIndicator(status: status, size: 18),
                subtitleMaxLines: 2,
                onSelect: () => _selectStatus(status, null),
                options: [
                  if (status != PresenceStatus.online)
                    for (final minutes in <int?>[...userPresences.durationsMinutes, null])
                      GlitchCascadeOption(label: _durationLabel(context, minutes), onSelect: () => _selectStatus(status, minutes)),
                ],
              ),
          ],
        ),
      );

  Future<void> _editProfile({bool achievements = false}) async {
    if (_openingEditor) return;
    _openingEditor = true;
    final anchor = widget.anchorContext;
    await widget.close();
    if (!anchor.mounted || authService.currentUser == null) return;
    await editMyProfile(anchor, achievements: achievements);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<User?>(
        valueListenable: authService.currentUserListenable,
        builder: (context, me, _) {
          if (me == null) return const SizedBox.shrink();
          return MemberCardLayout(
            achievementUserId: me.id,
            onShowAchievements: () => _editProfile(achievements: true),
            onOpenAchievement: _viewAchievement,
            effect: null,
            scrollable: true,
            selectable: true,
            onAvatarTap: _editProfile,
            banner: UserBanner(
              url: me.banner,
              sizes: me.bannerSizes,
              color: me.avatarColor,
              nickname: me.nickname,
            ),
            avatar: GlitchAvatar(
              initials: GlitchAvatar.initialsFromName(me.displayName),
              size: kMemberCardAvatar,
              colorIndex: GlitchAvatar.colorFromNickname(me.nickname),
              imageUrl: me.avatar != null ? api.mediaUrl(me.avatar!) : null,
              avatarSizes: me.avatarSizes,
              presenceUserId: me.id,
            ),
            name: UserDisplayName(
              displayName: me.displayName,
              isGlitchPlus: me.isGlitchPlus,
              ellipsis: true,
              badgeSize: 18,
              style: MemberCardLayout.nameStyle(),
            ),
            nickname: ProfileNickname(me.nickname),
            bottom: Builder(builder: (surfaceContext) => Material(
              color: GlitchInk.of(context).bgMenu,
              shape: glitchMenuShape(context),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: kGlitchMenuContentPadding,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GlitchMenuTapRow(
                      onTap: _editProfile,
                      child: glitchMenuRow(Icons.edit_outlined, context.s.profileEdit),
                    ),
                    ListenableBuilder(
                      listenable: userPresences,
                      builder: (context, _) => GlitchCascadeAnchor(
                        surfaceContext: surfaceContext,
                        width: GlitchCascadeMenu.popupWidth(mainWidth: _statusWidth, listWidth: _durationWidth),
                        enabled: !userPresences.saving,
                        menuBuilder: _statusMenu,
                        childBuilder: (open) => GlitchMenuTapRow(
                          onTap: userPresences.saving ? null : open,
                          child: Row(children: [
                            PresenceIndicator(status: userPresences.ownKnown ? userPresences.own.status : PresenceStatus.offline, size: 18),
                            const SizedBox(width: 10),
                            Expanded(child: Text(userPresences.ownKnown ? presenceLabel(context, userPresences.own.status) : context.s.loading,
                                style: TextStyle(fontSize: 15, color: GlitchColors.textPrimary))),
                            Icon(Icons.chevron_right_rounded, size: 18, color: GlitchColors.textSecond),
                          ]),
                        ),
                      ),
                    ),
                    glitchMenuSeparator(),
                    GlitchMenuTapRow(
                      onTap: () => copyId(context, me.id),
                      child: copyIdMenuRow(context, IdKind.user),
                    ),
                  ],
                ),
              ),
            )),
          );
        },
      );
}
