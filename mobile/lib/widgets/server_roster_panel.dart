import 'dart:async';

import 'package:flutter/material.dart';

import '../core/adaptive_open.dart';
import '../core/collectibles.dart';
import '../core/name_color.dart';
import '../core/l10n.dart';
import '../core/shell_controller.dart';
import '../models/collectible.dart';
import '../models/server.dart';
import '../providers/server_provider.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/user_activities.dart';
import '../services/user_presences.dart';
import '../theme/app_theme.dart';
import 'theme_workspace.dart';
import 'activity_parts.dart';
import 'glitch_hover_row.dart';
import 'glitch_menu.dart' show GlitchPopupSide;
import 'glitch_pressable.dart';
import 'member_card.dart';
import 'nameplate_background.dart';
import 'server_user_avatar.dart';
import 'glitch_icon_button.dart';

const double kRosterPanelWidth = 256;

class ServerRosterPanel extends StatefulWidget {
  final int serverId;

  final int? roomId;

  const ServerRosterPanel({super.key, required this.serverId, this.roomId});

  @override
  State<ServerRosterPanel> createState() => _ServerRosterPanelState();
}

class _ServerRosterPanelState extends State<ServerRosterPanel> {
  ServerRoster? _roster;
  bool _loading = true;
  String? _error;

  StreamSubscription<MemberDisplayChange>? _displaySub;
  StreamSubscription<int>? _rolesSub;
  StreamSubscription<int>? _presenceSub;
  Timer? _presenceReload;

  late int? _roomId = widget.roomId;

  @override
  void initState() {
    super.initState();
    _presenceSub = userPresences.changes.listen((id) {
      if (!_shows(id)) return;
      _presenceReload?.cancel();
      _presenceReload = Timer(const Duration(milliseconds: 100), () {
        if (mounted) _load();
      });
    });
    _rolesSub = serverRail.roleChanges.listen((id) {
      if (mounted && id == widget.serverId) _load();
    });
    shellController.addListener(_onCenter);
    _displaySub = serverRail.memberDisplay.listen((c) {
      if (!mounted || !c.affects(widget.serverId)) return;
      final userId = c.userId;
      if (userId == null || _shows(userId) || c.serverId == widget.serverId) _load();
    });
    _load();
  }

  @override
  void dispose() {
    _displaySub?.cancel();
    _rolesSub?.cancel();
    _presenceSub?.cancel();
    _presenceReload?.cancel();
    shellController.removeListener(_onCenter);
    super.dispose();
  }

  void _onCenter() {
    if (serverIdOfScope(shellController.mainScope) != widget.serverId) return;
    final id = placeIdOfSlotKey(shellController.mainKey);
    if (id == null || id == _roomId) return;
    _roomId = id;
    _load();
  }

  bool _shows(int userId) =>
      _roster?.groups.any((g) => g.members.any((m) => m.user.id == userId)) ?? false;

  int _seq = 0;

  Future<void> _load() async {
    if (!mounted) return;
    final seq = ++_seq;
    final snapshot = userActivities.beginSnapshot();
    final presenceSnapshot = userPresences.beginSnapshot();
    setState(() {
      _loading = _roster == null; // спиннер только когда показывать нечего
      _error = null;
    });
    try {
      final data = await api.getServerRoster(widget.serverId, roomId: _roomId);
      if (!mounted || seq != _seq) return;
      userPresences.seedAll([
        for (final g in data.groups)
          for (final m in g.members) (m.user.id, m.presenceStatus),
      ], snapshot: presenceSnapshot);
      userActivities.seedAll([
        for (final g in data.groups)
          for (final m in g.members) (m.user.id, m.activities),
      ], snapshot: snapshot);
      setState(() {
        _roster = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _error = errorMessage(e);
        _loading = false;
      });
    }
  }

  void _openMember(RosterMember m, BuildContext rowContext) {
    showMemberCard(
      rowContext,
      serverId: widget.serverId,
      user: m.user,
      name: m.shownName,
      isOnline: m.isOnline,
      presenceStatus: m.presenceStatus,
      side: GlitchPopupSide.left,
    );
  }

  String _groupTitle(RosterGroup g) {
    final s = context.s;
    return switch (g.kind) {
      'role' => g.name ?? '',
      'offline' => s.rosterOffline,
      _ => s.rosterOnline,
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final roster = _roster;

    return Scaffold(
      backgroundColor: ThemeWorkspace.surface(context, GlitchColors.bg, tint: 0.22),
      body: SafeArea(
        child: Column(
          children: [
            _PanelHeader(
              title: s.rosterTitle,
              subtitle: roster == null ? null : s.rosterTotal(roster.total),
            ),
            Divider(height: 1, color: ThemeWorkspace.surface(context, GlitchColors.borderSoft)),
            Expanded(
              child: Builder(builder: (context) {
                if (_loading && roster == null) {
                  return Center(
                    child: CircularProgressIndicator(color: GlitchColors.accentBlue),
                  );
                }
                if (_error != null && roster == null) {
                  return _Retry(text: _error!, onRetry: _load);
                }
                if (roster == null || roster.groups.isEmpty) {
                  return Center(
                    child: Text(
                      s.rosterEmpty,
                      style: TextStyle(fontSize: 14, color: GlitchColors.textPrimary),
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(RosterRowFrame.listInset, 10, RosterRowFrame.listInset, 24),
                  children: [
                    for (final g in roster.groups) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                        child: Text(
                          '${_groupTitle(g).toUpperCase()} — ${g.members.length}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                            color: GlitchColors.textHint,
                          ),
                        ),
                      ),
                      for (final m in g.members)
                        _RosterRow(member: m, onTap: (rowContext) => _openMember(m, rowContext)),
                    ],
                    if (roster.shown < roster.total)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 14, 10, 0),
                        child: Text(
                          s.rosterMore(roster.total - roster.shown),
                          style: TextStyle(fontSize: 12.5, color: GlitchColors.textHint),
                        ),
                      ),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _PanelHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: GlitchColors.textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(fontSize: 12.5, color: GlitchColors.textHint),
                  ),
                ],
              ],
            ),
          ),
          GlitchIconButton(
            onTap: () {
              cache.saveRosterHidden(true).catchError((_) {});
              closeAdaptive(context, slot: ShellSlot.details);
            },
            size: 36,
            extent: 36,
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

class _RosterRow extends StatelessWidget {
  final RosterMember member;

  final void Function(BuildContext rowContext) onTap;

  const _RosterRow({required this.member, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = member.shownName;
    final color = nameColor(member.color);
    // Наведение — только ради оформления: украшение и плашка оживают
    // (core/collectibles.dart). Подсветки у строки нет, как и раньше.
    return GlitchHoverArea(
      onTap: () => onTap(context),
      builder: (context, hovered) => RosterRowFrame(
        nameplate: member.user.nameplate,
        animate: animateInList(hovered),
        avatar: Opacity(
          opacity: member.isOnline ? 1 : 0.45,
          child: ServerUserAvatar(
            user: member.user,
            name: name,
            size: RosterRowFrame.avatarSize,
            showOnline: member.isOnline,
            presenceStatus: member.presenceStatus,
            decorated: true,
            animateDecoration: animateInList(hovered),
          ),
        ),
        name: Opacity(
          opacity: member.isOnline ? 1 : 0.6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: RosterRowFrame.nameStyle(color),
              ),
              UserActivityBuilder(
                userId: member.user.id,
                builder: (context, activities) => ActivityLine(activities: activities),
              ),
            ],
          ),
        ),
        trailing: member.isOwner
            ? Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(Icons.workspace_premium_rounded, size: 15, color: GlitchColors.accentBlue),
              )
            : null,
      ),
    );
  }
}

class RosterRowFrame extends StatelessWidget {
  final CollectibleLook? nameplate;
  final bool animate;
  final Widget avatar;
  final Widget name;
  final Widget? trailing;

  const RosterRowFrame({
    super.key,
    required this.nameplate,
    required this.animate,
    required this.avatar,
    required this.name,
    this.trailing,
  });

  static const double avatarSize = 32;
  static const EdgeInsets padding = EdgeInsets.symmetric(horizontal: 10, vertical: 6);

  static const double listInset = 8;

  static double get defaultWidth => kRosterPanelWidth - 2 * listInset;
  static double get height => avatarSize + padding.vertical;

  static TextStyle nameStyle(Color color) => TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: color);

  @override
  Widget build(BuildContext context) {
    final end = trailing;
    return NameplateBackground(
      nameplate: nameplate,
      animate: animate,
      borderRadius: BorderRadius.circular(GlitchHoverRow.radius),
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            avatar,
            const SizedBox(width: 10),
            Expanded(child: name),
            if (end != null) end,
          ],
        ),
      ),
    );
  }
}

class _Retry extends StatelessWidget {
  final String text;
  final VoidCallback onRetry;

  const _Retry({required this.text, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: GlitchColors.textPrimary),
              ),
              const SizedBox(height: 12),
              GlitchPressable(
                onTap: onRetry,
                child: Text(
                  context.s.retry,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: GlitchColors.accentBlue,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
