import 'dart:async';

import 'package:flutter/material.dart';
import '../widgets/profile_achievements.dart';
import '../widgets/achievement_viewer.dart';

import '../core/adaptive_open.dart';
import '../core/own_account_open.dart';
import '../core/copy_actions.dart';
import '../core/date_text.dart';
import '../core/l10n.dart';
import '../core/personal_chat_open.dart';
import '../models/profile.dart';
import '../models/server.dart';
import '../providers/contact_provider.dart';
import '../providers/server_provider.dart' show serverRail;
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/user_presences.dart';
import '../theme/app_theme.dart';
import '../widgets/activity_parts.dart';
import '../widgets/adaptive_sheet.dart';
import '../widgets/banner_header_art.dart';
import '../widgets/friend_button.dart';
import '../widgets/glitch_action_button.dart';
import '../widgets/glitch_avatar.dart';
import '../widgets/glitch_form_field.dart';
import '../widgets/glitch_menu.dart';
import '../widgets/glitch_plus_badge.dart';
import '../widgets/glitch_pressable.dart' show ClickableCursor;
import '../widgets/glitch_segmented_control.dart';
import '../widgets/glitch_toast.dart';
import '../widgets/profile_media_tabs.dart';
import '../widgets/profile_parts.dart';
import '../widgets/selectable_content.dart';
import '../widgets/server_rail.dart' show revealServerInRail;
import '../widgets/user_banner.dart';
import '../widgets/profile_effect_overlay.dart';
import '../widgets/glitch_icon_button.dart';

Future<void> showUserProfile(
  BuildContext context, {
  required String nickname,
  int? serverId,
}) async {
  final me = authService.currentUser;
  if (me != null && me.nickname == nickname) {
    await editMyProfile(context);
    return;
  }
  await openAdaptiveWindow<void>(
    context,
    narrowBuilder: (_) => UserProfileView(nickname: nickname, serverId: serverId, wide: false),
    wideBuilder: (_) => UserProfileView(nickname: nickname, serverId: serverId, wide: true),
  );
}

const double _kWideSideWidth = 380;
const double _kWideAvatar = 112;
const double _kNarrowAvatar = 96;

class UserProfileView extends StatefulWidget {
  final String nickname;
  final int? serverId;

  final bool wide;

  const UserProfileView({super.key, required this.nickname, this.serverId, required this.wide});

  @override
  State<UserProfileView> createState() => _UserProfileViewState();
}

class _UserProfileViewState extends State<UserProfileView> with ThemeAwareState<UserProfileView> {
  late final ContactProvider _provider;
  StreamSubscription<String>? _errorsSub;

  StreamSubscription<MemberDisplayChange>? _displaySub;

  Mutual? _mutual;
  bool _mutualFailed = false;

  MemberCard? _card;

  bool _extrasStarted = false;

  int _tab = _tabActivity;

  static const _tabActivity = 0;
  static const _tabFriends = 1;
  static const _tabMedia = 3;

  @override
  void initState() {
    super.initState();
    _provider = ContactProvider(nickname: widget.nickname, findChat: true)..init();
    _provider.addListener(_onProvider);
    _errorsSub = _provider.errors.listen((m) {
      if (mounted) GlitchToast.show(context, m);
    });
  }

  @override
  void dispose() {
    _errorsSub?.cancel();
    _displaySub?.cancel();
    _provider.removeListener(_onProvider);
    _provider.dispose();
    super.dispose();
  }

  void _onProvider() {
    final user = _provider.user;
    if (user != null && !_extrasStarted) {
      _extrasStarted = true;
      _loadMutual(user.id);
      final serverId = widget.serverId;
      if (serverId != null) {
        _loadCard(serverId, user.id);
        _displaySub = serverRail.memberDisplay.listen((c) {
          if (mounted && c.affects(serverId, userId: user.id)) _loadCard(serverId, user.id);
        });
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadMutual(int userId) async {
    if (_mutualFailed) setState(() => _mutualFailed = false);
    try {
      final mutual = await api.getMutual(userId);
      if (mounted) setState(() => _mutual = mutual);
    } catch (_) {
      if (mounted) setState(() => _mutualFailed = true);
    }
  }

  Future<void> _loadCard(int serverId, int userId) async {
    try {
      final card = await api.getMemberCard(serverId, userId);
      if (mounted) setState(() => _card = card);
    } catch (_) {
    }
  }


  Future<void> _write() async {
    final user = _provider.user;
    if (user == null) return;
    final nav = Navigator.of(context, rootNavigator: true);
    nav.pop();
    await openPersonalChat(
      nav.context,
      nickname: user.nickname,
      displayName: user.displayName,
      avatar: user.avatar,
      avatarSizes: user.avatarSizes,
    );
  }

  Future<void> _openMyAchievements() async {
    final nav = Navigator.of(context, rootNavigator: true);
    nav.pop();
    await editMyProfile(nav.context, achievements: true);
  }

  void _openServer(MutualServer server) {
    revealServerInRail(Navigator.of(context, rootNavigator: true), server.id);
  }

  Future<void> _toggleBlock() async {
    final was = _provider.isBlocked;
    await _provider.toggleBlock();
    if (!mounted || _provider.isBlocked == was) return;
    GlitchToast.show(
      context,
      _provider.isBlocked ? context.s.contactBlockedTitle : context.s.contactUnblockedTitle,
      type: ToastType.success,
    );
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
      body = widget.wide ? _wideLayout() : _narrowLayout();
    }

    if (widget.wide) {
      return Material(
        color: GlitchColors.bg,
        child: Stack(
          children: [
            Positioned.fill(child: body),
            AdaptiveWindowCloseButton(onPressed: () => Navigator.pop(context)),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: GlitchColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 6, 0),
              child: Row(
                children: [
                  GlitchIconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded, color: GlitchColors.accentBlue),
                    onTap: () => Navigator.pop(context),
                  ),
                  Text(
                    context.s.profileTitle,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary),
                  ),
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _wideLayout() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _kWideSideWidth,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: GlitchColors.bgCard,
                borderRadius: BorderRadius.circular(16),
              ),
              child: SingleChildScrollView(child: _identity(_kWideAvatar)),
            ),
          ),
          const SizedBox(width: 28),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _tabBar(),
                  const SizedBox(height: 16),
                  Expanded(child: _tabContent(fill: true)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _narrowLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: GlitchColors.bgCard,
              borderRadius: BorderRadius.circular(16),
            ),
            child: _identity(_kNarrowAvatar),
          ),
          const SizedBox(height: 18),
          _tabBar(),
          const SizedBox(height: 12),
          _tabContent(fill: false),
        ],
      ),
    );
  }

  Widget _identity(double avatarSize) {
    final s = context.s;
    final user = _provider.user!;
    final card = _card;
    final name = card?.shownName ?? user.displayName;
    final blocked = _provider.isBlocked;

    return ProfileEffectOverlay(
      effect: user.profileEffect,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          BannerHeaderArt(
            besideAvatar: ProfileAchievements(userId: user.id, onShowAll: _openMyAchievements, onOpenAchievement: (item) {
              final nav = Navigator.of(context, rootNavigator: true);
              nav.pop();
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
              size: avatarSize,
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
            avatarSize: avatarSize,
            avatarShape: AvatarShape.person,
            ringColor: GlitchColors.bgCard,
            bannerOverlay: (_) => FriendBannerButton(userId: user.id, hidden: blocked),
          ),
          SelectableContent(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  UserDisplayName(
                    displayName: name,
                    isGlitchPlus: user.isGlitchPlus,
                    ellipsis: true,
                    badgeSize: 20,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  ProfileNickname(user.nickname, fontSize: 14),
                  if (blocked) ...[
                    const SizedBox(height: 14),
                    const ProfileBlockedNotice(),
                  ],
                  const SizedBox(height: 18),
                  SelectionContainer.disabled(child: _actions()),
                  if ((user.bio ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 20),
                    ProfileBio(bio: user.bio),
                  ],
                  const SizedBox(height: 20),
                  if (card != null)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: ProfileFact(label: s.serverMembersColJoined, value: formatDay(card.joinedAt))),
                        const SizedBox(width: 12),
                        Expanded(child: ProfileFact(label: s.serverMembersColAccount, value: formatDay(user.createdAt))),
                      ],
                    )
                  else
                    ProfileFact(label: s.serverMembersColAccount, value: formatDay(user.createdAt)),
                  if (card != null &&
                      widget.serverId != null &&
                      EditableProfileRoles.shown(roles: card.roles, canManage: card.canManageRoles)) ...[
                    const SizedBox(height: 20),
                    EditableProfileRoles(
                      serverId: widget.serverId!,
                      userId: card.user.id,
                      roles: card.roles,
                      canManage: card.canManageRoles,
                    ),
                  ],
                  const SizedBox(height: 20),
                  SelectionContainer.disabled(child: _ProfileNote(userId: user.id)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions() {
    final s = context.s;
    return Row(
      children: [
        Expanded(child: GlitchActionButton(label: s.contactWrite, onTap: _write)),
        const SizedBox(width: 10),
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: GlitchColors.bgInput,
            borderRadius: BorderRadius.circular(15),
          ),
          alignment: Alignment.center,
          child: GlitchMenuButton<String>(
            icon: Icon(Icons.more_horiz_rounded, color: GlitchColors.textPrimary),
            onSelected: (v) {
              switch (v) {
                case 'notifications':
                  _provider.toggleNotifications();
                case 'copy':
                  copyNickname(context, _provider.user?.nickname ?? '');
                case 'block':
                  _toggleBlock();
                case 'copyId':
                  final id = _provider.user?.id;
                  if (id != null) copyId(context, id);
                case 'friend':
                  final user = _provider.user;
                  final action = user != null ? friendMenuActionFor(user.id) : null;
                  if (user != null && action != null) {
                    runFriendMenuAction(context, action, userId: user.id, displayName: user.displayName);
                  }
              }
            },
            itemBuilder: (ctx) {
              final userId = _provider.user?.id;
              final friendAction = userId != null ? friendMenuActionFor(userId) : null;
              return [
              _menuItem(
                'notifications',
                _provider.notificationsOn ? Icons.notifications_off_outlined : Icons.notifications_outlined,
                _provider.notificationsOn ? s.userProfileMute : s.userProfileUnmute,
              ),
              _menuItem('copy', Icons.alternate_email_rounded, s.userProfileCopyNickname),
              if (friendAction != null)
                _menuItem(
                  'friend',
                  friendAction == FriendMenuAction.remove
                      ? Icons.person_remove_alt_1_rounded
                      : Icons.close_rounded,
                  friendMenuLabel(context, friendAction),
                  destructive: friendAction == FriendMenuAction.remove,
                ),
              _menuItem(
                'block',
                Icons.block_rounded,
                _provider.isBlocked ? s.contactUnblock : s.contactBlock,
                destructive: !_provider.isBlocked,
              ),
              if (_provider.user != null)
                GlitchMenuItem(value: 'copyId', child: copyIdMenuRow(context, IdKind.user)),
            ];
            },
          ),
        ),
      ],
    );
  }

  GlitchMenuItem<String> _menuItem(String value, IconData icon, String label, {bool destructive = false}) {
    final color = destructive ? GlitchColors.error : GlitchColors.textPrimary;
    return GlitchMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 15, color: color)),
        ],
      ),
    );
  }


  Widget _tabBar() {
    final s = context.s;
    return GlitchSegmentedControl(
      labels: widget.wide
          ? [s.activityTab, s.userProfileMutualFriendsTab, s.userProfileMutualServersTab, s.userProfileMediaTab]
          : [s.activityTab, s.userProfileTabFriends, s.userProfileTabServers, s.userProfileTabMedia],
      selected: _tab,
      onChanged: (i) => setState(() => _tab = i),
    );
  }

  Widget _tabContent({required bool fill}) {
    if (_tab == _tabActivity) return _activityTab(fill);
    if (_tab == _tabMedia) {
      return ProfileMediaTabs(provider: _provider, height: fill ? null : 320);
    }
    final m = _mutual;
    Widget list;
    if (_mutualFailed) {
      list = _centered(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.s.errorLoad, style: TextStyle(fontSize: 14, color: GlitchColors.textPrimary)),
            TextButton(
              onPressed: () {
                final id = _provider.user?.id;
                if (id != null) _loadMutual(id);
              },
              child: Text(context.s.retry),
            ),
          ],
        ),
        fill,
      );
    } else if (m == null) {
      list = _centered(
        SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: GlitchColors.accentBlue),
        ),
        fill,
      );
    } else {
      final rows = switch (_tab) {
        _tabFriends => [
            for (final u in m.friends)
              _MutualRow.person(u, onTap: () => showUserProfile(context, nickname: u.nickname)),
          ],
        _ => [for (final srv in m.servers) _MutualRow.server(srv, onTap: () => _openServer(srv))],
      };
      if (rows.isEmpty) {
        list = _centered(
          Text(
            _tab == _tabFriends ? context.s.userProfileNoMutualFriends : context.s.userProfileNoMutualServers,
            style: TextStyle(fontSize: 14, color: GlitchColors.textPrimary),
          ),
          fill,
        );
      } else {
        list = fill
            ? ListView(children: rows)
            : Column(mainAxisSize: MainAxisSize.min, children: rows);
      }
    }
    return list;
  }

  Widget _activityTab(bool fill) {
    final user = _provider.user;
    if (user == null) return const SizedBox.shrink();
    return ListenableBuilder(listenable: userPresences, builder: (context, _) {
      if (!userPresences.personalActivityVisible(user.id, user.lastSeen,
          blocked: _provider.isBlocked || user.isBlockedBy)) {
        return _centered(Text(context.s.activityNone,
            style: TextStyle(fontSize: 14, color: GlitchColors.textPrimary)), fill);
      }
      return UserActivityBuilder(
        userId: user.id,
        builder: (context, activities) {
          final playing = {for (final a in activities) a.game.id};
          final recent = [
            for (final r in user.recentActivities)
              if (!playing.contains(r.game.id)) r,
          ];
          if (activities.isEmpty && recent.isEmpty) {
            return _centered(
              Text(context.s.activityNone, style: TextStyle(fontSize: 14, color: GlitchColors.textPrimary)),
              fill,
            );
          }
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (activities.isNotEmpty) ...[
                Padding(
                  key: const ValueKey('activity_current_label'),
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: ProfileSectionLabel(context.s.activityCurrent),
                ),
                for (final a in activities.reversed)
                  Padding(
                    key: ValueKey('activity_${a.game.id}'),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ActivityCard(activity: a),
                  ),
              ],
              if (recent.isNotEmpty) ...[
                Padding(
                  key: const ValueKey('activity_recent_label'),
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: ProfileSectionLabel(context.s.activityRecent),
                ),
                for (final r in recent)
                  Padding(
                    key: ValueKey('recent_${r.game.id}'),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: RecentActivityCard(activity: r),
                  ),
              ],
            ],
          );
          return fill ? SingleChildScrollView(child: content) : content;
        },
      );
    });
  }

  Widget _centered(Widget child, bool fill) =>
      fill ? Center(child: child) : SizedBox(height: 160, child: Center(child: child));
}

class _MutualRow extends StatelessWidget {
  final String name;
  final String? avatar;
  final Map<String, String>? avatarSizes;

  final String? nick;

  final VoidCallback onTap;

  const _MutualRow({
    required this.name,
    this.avatar,
    this.avatarSizes,
    this.nick,
    required this.onTap,
  });

  factory _MutualRow.server(MutualServer server, {required VoidCallback onTap}) => _MutualRow(
        name: server.name,
        avatar: server.avatar,
        avatarSizes: server.avatarSizes,
        nick: server.nick,
        onTap: onTap,
      );

  factory _MutualRow.person(ServerUser u, {required VoidCallback onTap}) => _MutualRow(
        name: u.displayName,
        avatar: u.avatar,
        avatarSizes: u.avatarSizes,
        nick: '@${u.nickname}',
        onTap: onTap,
      );

  @override
  Widget build(BuildContext context) {
    final sub = nick;
    return ClickableCursor(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              GlitchAvatar(
                initials: GlitchAvatar.initialsFromName(name),
                size: 40,
                colorIndex: GlitchAvatar.colorFromNickname(name),
                imageUrl: avatar != null ? api.mediaUrl(avatar!) : null,
                avatarSizes: avatarSizes,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary),
                    ),
                    if (sub != null && sub.isNotEmpty)
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: GlitchColors.textSecond),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileNote extends StatefulWidget {
  final int userId;

  const _ProfileNote({required this.userId});

  @override
  State<_ProfileNote> createState() => _ProfileNoteState();
}

class _ProfileNoteState extends State<_ProfileNote> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  /// Что лежит на сервере. `null` — ещё не загрузили: поле закрыто, иначе
  /// набранное затёрлось бы пришедшим ответом.
  String? _saved;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    _load();
  }

  @override
  void dispose() {
    final saved = _saved;
    final text = _ctrl.text.trim();
    if (saved != null && text != saved) {
      unawaited(api.setNote(widget.userId, text).then((_) {}, onError: (_) {}));
    }
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final text = await api.getNote(widget.userId);
      if (!mounted) return;
      _ctrl.text = text;
      setState(() => _saved = text);
    } catch (_) {
    }
  }

  void _onFocus() {
    if (!_focus.hasFocus) _save();
  }

  Future<void> _save() async {
    final saved = _saved;
    final text = _ctrl.text.trim();
    if (saved == null || text == saved) return;
    try {
      final stored = await api.setNote(widget.userId, text);
      if (!mounted) return;
      _saved = stored;
      if (_ctrl.text.trim() == text) _ctrl.text = stored;
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return GlitchFormField(
      label: s.userProfileNoteLabel,
      placeholder: s.userProfileNotePlaceholder,
      controller: _ctrl,
      focusNode: _focus,
      enabled: _saved != null,
      maxLength: kMaxNoteLength,
      minLines: 1,
      maxLines: 4,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _focus.unfocus(),
    );
  }
}
