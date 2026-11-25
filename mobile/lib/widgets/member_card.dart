import 'dart:async';

import 'package:flutter/material.dart';
import '../models/presence.dart';
import '../models/achievement.dart';
import 'achievement_viewer.dart';

import '../core/date_text.dart';
import '../core/l10n.dart';
import '../core/own_account_open.dart';
import '../core/personal_chat_open.dart';
import '../models/chat_arrival.dart';
import '../models/collectible.dart';
import '../models/server.dart';
import '../providers/server_provider.dart' show serverRail;
import '../screens/user_profile_screen.dart';
import '../services/api_service.dart';
import '../services/user_presences.dart';
import '../services/auth_service.dart';
import '../services/user_activities.dart';
import '../theme/app_theme.dart';
import 'activity_parts.dart';
import 'adaptive_sheet.dart';
import 'banner_header_art.dart';
import 'friend_button.dart';
import 'glitch_action_button.dart';
import 'glitch_form_field.dart';
import 'glitch_menu.dart' show GlitchPopupSide;
import 'glitch_plus_badge.dart';
import 'profile_parts.dart';
import 'selectable_content.dart';
import 'selection_contrast_text.dart';
import 'profile_effect_overlay.dart';
import 'profile_achievements.dart';
import 'server_user_avatar.dart';
import 'user_banner.dart';

const double kMemberCardWidth = 300;
const double kMemberCardAvatar = 80;
const EdgeInsets kMemberCardPadding = EdgeInsets.fromLTRB(16, 10, 16, 16);
const double kMemberCardNameSize = 20;

Future<void> showMemberCard(
  BuildContext anchorContext, {
  required int serverId,
  required ServerUser user,
  required String name,
  bool isOnline = false,
  PresenceStatus? presenceStatus,
  required GlitchPopupSide side,
  Rect? anchorRect,
}) =>
    openAdaptivePopup(
      anchorContext,
      width: kMemberCardWidth,
      side: side,
      anchorRect: anchorRect,
      builder: (close, _) => _MemberCardView(
        anchorContext: anchorContext,
        serverId: serverId,
        user: user,
        name: name,
        isOnline: isOnline,
        presenceStatus: presenceStatus,
        close: close,
      ),
    );

class _MemberCardView extends StatefulWidget {
  final BuildContext anchorContext;
  final int serverId;
  final ServerUser user;
  final String name;
  final bool isOnline;
  final PresenceStatus? presenceStatus;
  final Future<void> Function() close;

  const _MemberCardView({
    required this.anchorContext,
    required this.serverId,
    required this.user,
    required this.name,
    required this.isOnline,
    this.presenceStatus,
    required this.close,
  });

  @override
  State<_MemberCardView> createState() => _MemberCardViewState();
}

class _MemberCardViewState extends State<_MemberCardView> {
  MemberCard? _card;
  String? _error;
  final _message = TextEditingController();
  bool _sent = false;

  StreamSubscription<MemberDisplayChange>? _displaySub;

  @override
  void initState() {
    super.initState();
    _displaySub = serverRail.memberDisplay.listen((c) {
      if (mounted && c.affects(widget.serverId, userId: widget.user.id)) _load();
    });
    _load();
  }

  @override
  void dispose() {
    _displaySub?.cancel();
    _message.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final snapshot = userActivities.beginSnapshot();
    final presenceSnapshot = userPresences.beginSnapshot();
    if (_error != null) setState(() => _error = null);
    try {
      final card = await api.getMemberCard(widget.serverId, widget.user.id);
      if (!mounted) return;
      userPresences.seed(card.user.id, card.presenceStatus, snapshot: presenceSnapshot);
      userActivities.seed(card.user.id, card.activities, snapshot: snapshot);
      setState(() => _card = card);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = errorMessage(e));
    }
  }

  bool get _isMe => widget.user.id == authService.currentUser?.id;

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty || _sent) return;
    _sent = true;
    final user = _card?.user ?? widget.user;
    final anchor = widget.anchorContext;
    await widget.close();
    if (!anchor.mounted) return;
    await openPersonalChat(
      anchor,
      nickname: user.nickname,
      displayName: user.displayName,
      avatar: user.avatar,
      avatarSizes: user.avatarSizes,
      arrival: ChatArrival(text: text),
    );
  }

  Future<void> _openFullProfile() async {
    final anchor = widget.anchorContext;
    await widget.close();
    if (!anchor.mounted) return;
    await showUserProfile(anchor, nickname: widget.user.nickname, serverId: widget.serverId);
  }

  bool _openingEditor = false;
  Future<void> _viewAchievement(Achievement item) async {
    if (_openingEditor) return;
    _openingEditor = true;
    final anchor = widget.anchorContext;
    await widget.close();
    if (anchor.mounted) await openAchievement(anchor, item);
  }
  Future<void> _editMyProfile({bool achievements = false}) async {
    if (_openingEditor) return;
    _openingEditor = true;
    final anchor = widget.anchorContext;
    await widget.close();
    if (!anchor.mounted) return;
    await editMyProfile(anchor, serverId: achievements ? null : widget.serverId, achievements: achievements);
  }

  @override
  Widget build(BuildContext context) {
    final card = _card;
    final user = card?.user ?? widget.user;
    final name = card?.shownName ?? widget.name;
    final online = card?.isOnline ?? widget.isOnline;

    // Фон карточка рисует САМА, а не берёт у оболочки: у попапа и шторки
    // оболочки разного цвета, а кольцо вокруг аватарки обязано совпадать с
    // фоном под ним — иначе вокруг аватарки была бы видна рамка.
    return MemberCardLayout(
      achievementUserId: user.id,
      onShowAchievements: () => _editMyProfile(achievements: true),
      onOpenAchievement: _viewAchievement,
      effect: card?.profileEffect,
      scrollable: true,
      selectable: true,
      banner: card == null && user.avatarColor == null
          ? ColoredBox(color: GlitchColors.bgInput)
          : UserBanner(
              url: card?.banner,
              sizes: card?.bannerSizes,
              color: user.avatarColor,
              nickname: user.nickname,
            ),
      avatar: ServerUserAvatar(
        user: user,
        name: name,
        size: kMemberCardAvatar,
        showOnline: online,
        presenceStatus: card?.presenceStatus ?? widget.presenceStatus ?? PresenceStatus.offline,
        // В открытом профиле украшение играет всегда.
        decorated: true,
        animateDecoration: true,
      ),
      onAvatarTap: _isMe ? _editMyProfile : _openFullProfile,
      bannerOverlay: (_) => FriendBannerButton(userId: user.id),
      name: UserDisplayName(
        displayName: name,
        isGlitchPlus: card?.isGlitchPlus ?? false,
        ellipsis: true,
        badgeSize: 18,
        style: MemberCardLayout.nameStyle(),
      ),
      nickname: ProfileNickname(user.nickname),
      body: _body(context, card),
      bottom: _isMe
          ? GlitchActionButton(label: context.s.profileEdit, soft: true, onTap: _editMyProfile)
          : GlitchFormField(
              controller: _message,
              placeholder: context.s.memberCardMessageHint(user.nickname),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
            ),
    );
  }

  List<Widget> _body(BuildContext context, MemberCard? card) {
    final s = context.s;
    if (_error != null) {
      return [
        const SizedBox(height: 16),
        Text(_error!, style: TextStyle(fontSize: 13.5, color: GlitchColors.textPrimary)),
        const SizedBox(height: 8),
        SelectionContainer.disabled(
          child: GlitchActionButton(label: s.retry, soft: true, onTap: _load),
        ),
      ];
    }
    if (card == null) {
      return [
        const SizedBox(height: 24),
        Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: GlitchColors.accentBlue),
          ),
        ),
        const SizedBox(height: 12),
      ];
    }

    final bio = card.bio?.trim() ?? '';
    final mutual = card.mutualServers ?? 0;
    final mutualFriends = card.mutualFriends ?? 0;
    final mutualLine = [
      if (mutualFriends > 0) s.mutualFriendsCount(mutualFriends),
      if (mutual > 0) s.memberCardMutualServers(mutual),
    ].join(' • ');
    return [
      if (mutualLine.isNotEmpty) ...[
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.groups_rounded, size: 16, color: GlitchColors.textSecond),
            const SizedBox(width: 6),
            Flexible(
              child: SelectionContrastText(
                Text(
                  mutualLine,
                  style: TextStyle(fontSize: 12.5, color: GlitchColors.textSecond),
                ),
              ),
            ),
          ],
        ),
      ],
      if (bio.isNotEmpty) ...[
        const SizedBox(height: 16),
        ProfileBio(bio: bio),
      ],
      UserActivityBuilder(
        key: const ValueKey('activity'),
        userId: card.user.id,
        builder: (context, activities) => activities.isEmpty
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(top: 16),
                child: ActivityCard(activity: activities.last, compact: true),
              ),
      ),
      const SizedBox(height: 16),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: ProfileFact(label: s.serverMembersColJoined, value: formatDay(card.joinedAt))),
          const SizedBox(width: 12),
          Expanded(child: ProfileFact(label: s.serverMembersColAccount, value: formatDay(card.accountCreatedAt))),
        ],
      ),
      if (EditableProfileRoles.shown(roles: card.roles, canManage: card.canManageRoles)) ...[
        const SizedBox(height: 16),
        EditableProfileRoles(
          serverId: widget.serverId,
          userId: card.user.id,
          roles: card.roles,
          canManage: card.canManageRoles,
        ),
      ],
    ];
  }
}

class MemberCardLayout extends StatelessWidget {
  final int? achievementUserId;
  final VoidCallback? onShowAchievements;
  final ValueChanged<Achievement>? onOpenAchievement;
  final CollectibleLook? effect;
  final bool animateEffect;
  final Widget banner;
  final Widget avatar;
  final VoidCallback? onAvatarTap;
  final Widget Function(bool active)? bannerOverlay;
  final Widget name;
  final Widget nickname;
  final List<Widget> body;
  final Widget bottom;

  final bool scrollable;

  final bool selectable;

  const MemberCardLayout({
    super.key,
    this.achievementUserId,
    this.onShowAchievements,
    this.onOpenAchievement,
    required this.effect,
    this.animateEffect = true,
    required this.banner,
    required this.avatar,
    this.onAvatarTap,
    this.bannerOverlay,
    required this.name,
    required this.nickname,
    this.body = const [],
    required this.bottom,
    this.scrollable = false,
    this.selectable = false,
  }) : assert(achievementUserId == null || (onShowAchievements != null && onOpenAchievement != null));

  static TextStyle nameStyle() =>
      TextStyle(fontSize: kMemberCardNameSize, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary);

  static Widget nicknameText(String nickname) => Text(
        '@$nickname',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13.5, color: GlitchColors.textSecond),
      );

  @override
  Widget build(BuildContext context) {
    final details = Padding(
      padding: kMemberCardPadding.copyWith(bottom: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          name,
          const SizedBox(height: 2),
          nickname,
          ...body,
        ],
      ),
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        BannerHeaderArt(
          besideAvatar: achievementUserId == null ? null : ProfileAchievements(userId: achievementUserId!, onShowAll: onShowAchievements!, onOpenAchievement: onOpenAchievement!),
          bannerAspect: kUserBannerAspect,
          banner: banner,
          avatar: avatar,
          avatarSize: kMemberCardAvatar,
          avatarShape: AvatarShape.person,
          ringColor: GlitchColors.bgCard,
          onAvatarTap: onAvatarTap,
          bannerOverlay: bannerOverlay,
        ),
        selectable ? SelectableContent(child: details) : details,
        const SizedBox(height: 18),
        Padding(
          padding: kMemberCardPadding.copyWith(top: 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [bottom],
          ),
        ),
      ],
    );
    // Фон карточка рисует САМА, а не берёт у оболочки: у попапа и шторки
    // оболочки разного цвета, а кольцо вокруг аватарки обязано совпадать с
    // фоном под ним — иначе вокруг аватарки была бы видна рамка.
    return ColoredBox(
      color: GlitchColors.bgCard,
      child: ProfileEffectOverlay(
        effect: effect,
        playing: animateEffect,
        child: scrollable ? SingleChildScrollView(child: content) : content,
      ),
    );
  }
}
