import 'package:flutter/material.dart';
import '../widgets/presence_indicator.dart';

import '../core/l10n.dart';
import '../core/personal_chat_open.dart';
import '../models/relationship.dart';
import '../providers/friends.dart';
import '../providers/theme_provider.dart' show ThemeAwareState;
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/activity_parts.dart';
import '../widgets/friend_button.dart';
import '../widgets/glitch_action_button.dart';
import '../widgets/glitch_form_field.dart';
import '../widgets/glitch_hover_row.dart';
import '../widgets/glitch_menu.dart';
import '../widgets/glitch_search_field.dart';
import '../widgets/home_section_header.dart';
import '../widgets/server_user_avatar.dart';
import '../core/collectibles.dart';
import 'home_section_screen.dart';
import 'user_profile_screen.dart';
import '../widgets/glitch_icon_button.dart';

enum FriendsTab { online, all, pending, add }

class FriendsTabRequest {
  final FriendsTab tab;
  FriendsTabRequest(this.tab);
}

class FriendsScreen extends StatefulWidget {
  final FriendsTabRequest? request;

  const FriendsScreen({super.key, this.request});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> with ThemeAwareState<FriendsScreen> {
  late FriendsTab _tab = widget.request?.tab ?? FriendsTab.online;
  final _query = TextEditingController();
  final _add = TextEditingController();
  bool _adding = false;

  ({bool ok, String text})? _addResult;

  @override
  void didUpdateWidget(FriendsScreen old) {
    super.didUpdateWidget(old);
    final request = widget.request;
    // Без setState: после didUpdateWidget страница строится и так.
    if (request != null && !identical(request, old.request)) _show(request.tab);
  }

  @override
  void dispose() {
    _query.dispose();
    _add.dispose();
    super.dispose();
  }

  void _select(FriendsTab tab) {
    if (_tab != tab) setState(() => _show(tab));
  }

  void _show(FriendsTab tab) {
    _tab = tab;
    _query.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GlitchColors.bg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: friends,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              Expanded(child: _tab == FriendsTab.add ? _addPage() : _listPage()),
            ],
          ),
        ),
      ),
    );
  }


  Widget _header() {
    final s = context.s;
    return HomeSectionHeader(
      section: HomeSection.friends,
      tabs: [
        for (final (tab, label) in [
          (FriendsTab.online, s.friendsTabOnline),
          (FriendsTab.all, s.friendsTabAll),
          (FriendsTab.pending, s.friendsTabPending),
        ])
          HomeSectionTab(
            label: label,
            selected: _tab == tab,
            badge: tab == FriendsTab.pending ? friends.incomingCount : 0,
            onTap: () => _select(tab),
          ),
        HomeSectionTab(
          label: s.friendsAdd,
          selected: _tab == FriendsTab.add,
          primary: true,
          onTap: () => _select(FriendsTab.add),
        ),
      ],
    );
  }


  Widget _listPage() {
    final s = context.s;
    final error = friends.error;
    if (!friends.loaded) {
      return Center(
        child: error == null
            ? SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: GlitchColors.accentBlue),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error, style: TextStyle(fontSize: 14, color: GlitchColors.textPrimary)),
                  const SizedBox(height: 8),
                  GlitchActionButton(label: s.retry, soft: true, compact: true, onTap: friends.load),
                ],
              ),
      );
    }

    final all = switch (_tab) {
      FriendsTab.online => friends.friends.where((r) => r.isOnline).toList(),
      FriendsTab.pending => friends.pending,
      _ => friends.friends,
    };
    if (all.isEmpty) return _empty();

    final query = _query.text;
    final shown = query.trim().isEmpty ? all : all.where((r) => r.matchesQuery(query)).toList();
    final title = switch (_tab) {
      FriendsTab.online => s.friendsOnlineCount(shown.length),
      FriendsTab.pending => s.friendsPendingCount(shown.length),
      _ => s.friendsAllCount(shown.length),
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        GlitchSearchField(controller: _query, hint: s.search, onChanged: (_) => setState(() {})),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.only(left: 10, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary),
          ),
        ),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Center(
              child: Text(s.searchNothingFound, style: TextStyle(fontSize: 14, color: GlitchColors.textPrimary)),
            ),
          ),
        for (final rel in shown) _FriendRow(key: ValueKey(rel.user.id), rel: rel),
      ],
    );
  }

  Widget _empty() {
    final s = context.s;
    final text = switch (_tab) {
      FriendsTab.online => s.friendsEmptyOnline,
      FriendsTab.pending => s.friendsEmptyPending,
      _ => s.friendsEmptyAll,
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(homeSectionIcon(HomeSection.friends), size: 56, color: GlitchColors.textHint),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: GlitchColors.textPrimary)),
            if (_tab == FriendsTab.all) ...[
              const SizedBox(height: 16),
              GlitchActionButton(label: s.friendsAdd, compact: true, onTap: () => _select(FriendsTab.add)),
            ],
          ],
        ),
      ),
    );
  }


  Widget _addPage() {
    final s = context.s;
    final result = _addResult;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        Text(s.friendsAdd, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary)),
        const SizedBox(height: 6),
        Text(s.friendsAddDesc, style: TextStyle(fontSize: 14, color: GlitchColors.textPrimary)),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, c) {
            final field = GlitchFormField(
              controller: _add,
              placeholder: s.friendsAddHint,
              maxLength: 64,
              enabled: !_adding,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              onChanged: (_) => setState(() => _addResult = null),
            );
            final button = GlitchActionButton(
              label: s.friendsAddSend,
              compact: true,
              loading: _adding,
              onTap: _add.text.trim().isEmpty ? null : _send,
            );
            if (c.maxWidth < 520) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [field, const SizedBox(height: 10), button],
              );
            }
            return Row(children: [Expanded(child: field), const SizedBox(width: 10), button]);
          },
        ),
        if (result != null) ...[
          const SizedBox(height: 10),
          Text(
            result.text,
            style: TextStyle(fontSize: 13.5, color: result.ok ? GlitchColors.online : GlitchColors.error),
          ),
        ],
      ],
    );
  }

  Future<void> _send() async {
    final nickname = _add.text.trim();
    if (nickname.isEmpty || _adding) return;
    final s = context.s;
    setState(() {
      _adding = true;
      _addResult = null;
    });
    try {
      final rel = await friends.addByNickname(nickname);
      if (!mounted) return;
      final shown = rel?.user.nickname ?? nickname.replaceFirst('@', '');
      _addResult = (
        ok: true,
        text: rel?.kind == RelationshipKind.friend ? s.friendsAddBecame(shown) : s.friendsAddSent(shown),
      );
      _add.clear();
    } catch (e) {
      if (!mounted) return;
      _addResult = (ok: false, text: errorMessage(e));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }
}

class _FriendRow extends StatelessWidget {
  final Relationship rel;

  const _FriendRow({super.key, required this.rel});

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final user = rel.user;
    final isFriend = rel.kind == RelationshipKind.friend;
    final subtitle = switch (rel.kind) {
      RelationshipKind.friend => presenceLabel(context, rel.presenceStatus),
      RelationshipKind.incoming => s.friendsIncoming,
      RelationshipKind.outgoing => s.friendsOutgoing,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 10), color: GlitchColors.border),
        GlitchHoverRow(
          onTap: () {
            if (isFriend) {
              _write(context);
            } else {
              showUserProfile(context, nickname: user.nickname);
            }
          },
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          builder: (active) => Row(
            children: [
              ServerUserAvatar(
                user: user,
                name: user.displayName,
                size: 40,
                showOnline: isFriend && rel.isOnline,
                presenceStatus: isFriend ? rel.presenceStatus : null,
                decorated: true,
                animateDecoration: animateInList(active),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: user.displayName,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary),
                        ),
                        if (active)
                          TextSpan(
                            text: '  @${user.nickname}',
                            style: TextStyle(fontSize: 13.5, color: GlitchColors.textSecond),
                          ),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    UserActivityBuilder(
                      userId: user.id,
                      builder: (context, activities) => isFriend && activities.isNotEmpty
                          ? ActivityLine(activities: activities)
                          : Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, color: GlitchColors.textSecond),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ..._actions(context),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _actions(BuildContext context) {
    final s = context.s;
    final id = rel.user.id;
    if (friends.isBusy(id)) {
      return [
        SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: GlitchColors.accentBlue),
        ),
        const SizedBox(width: 8),
      ];
    }
    return switch (rel.kind) {
      RelationshipKind.friend => [
          _RoundAction(icon: Icons.chat_bubble_rounded, onTap: () => _write(context)),
          const SizedBox(width: 8),
          _RoundMenu(
            itemBuilder: (_) => [
              GlitchMenuItem(value: 'profile', child: _menuRow(Icons.person_outline_rounded, s.userProfileOpenFull)),
              GlitchMenuItem(
                value: 'remove',
                child: _menuRow(Icons.person_remove_alt_1_rounded, s.friendsRemove, destructive: true),
              ),
            ],
            onSelected: (v) {
              if (v == 'profile') showUserProfile(context, nickname: rel.user.nickname);
              if (v == 'remove') {
                confirmRemoveFriend(context, userId: id, displayName: rel.user.displayName);
              }
            },
          ),
        ],
      RelationshipKind.incoming => [
          _RoundAction(
            icon: Icons.check_rounded,
            onTap: () => runFriendAction(context, () => friends.request(id)),
          ),
          const SizedBox(width: 8),
          _RoundAction(
            icon: Icons.close_rounded,
            onTap: () => runFriendAction(context, () => friends.remove(id)),
          ),
        ],
      RelationshipKind.outgoing => [
          _RoundAction(
            icon: Icons.close_rounded,
            onTap: () => runFriendAction(context, () => friends.remove(id)),
          ),
        ],
    };
  }

  Widget _menuRow(IconData icon, String label, {bool destructive = false}) {
    final color = destructive ? GlitchColors.error : GlitchColors.textPrimary;
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontSize: 15, color: color)),
      ],
    );
  }

  void _write(BuildContext context) => openPersonalChat(
        context,
        nickname: rel.user.nickname,
        displayName: rel.user.displayName,
        avatar: rel.user.avatar,
        avatarSizes: rel.user.avatarSizes,
      );
}

class _RoundAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GlitchIconButton(
        size: 36,
        extent: 36,
        onTap: onTap,
        icon: Icon(icon, size: 19),
      );
}

class _RoundMenu extends StatelessWidget {
  final List<GlitchMenuItem<String>> Function(BuildContext) itemBuilder;
  final ValueChanged<String> onSelected;

  const _RoundMenu({required this.itemBuilder, required this.onSelected});

  @override
  Widget build(BuildContext context) => GlitchMenuButton<String>(
        icon: const Icon(Icons.more_vert_rounded, size: 19),
        size: 36,
        extent: 36,
        itemBuilder: itemBuilder,
        onSelected: onSelected,
      );
}
