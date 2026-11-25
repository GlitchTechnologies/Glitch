import 'dart:async';

import 'package:flutter/material.dart';
import '../core/adaptive_open.dart' show openAdaptiveFullscreen;
import '../core/l10n.dart';
import '../core/permissions.dart';
import '../models/invite.dart';
import '../models/server.dart';
import '../providers/server_provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glitch_avatar.dart';
import '../widgets/glitch_dialog.dart';
import '../widgets/glitch_toast.dart';
import '../widgets/settings_window.dart';
import 'server_members_section.dart';
import 'server_profile_section.dart';
import 'server_system_section.dart';
import 'server_roles_section.dart';
import 'server_stickers_section.dart';


enum ServerSettingsSection { profile, system, stickers, members, roles, invites, bans }

typedef _Group = (String? title, List<ServerSettingsSection> sections);

List<_Group> _sectionGroups(BuildContext context, ServerDetail server) {
  final s = context.s;
  final p = server.myPermissions;
  final groups = <_Group>[
    (null, [
      if (p.can(Perm.manageServer)) ServerSettingsSection.profile,
      if (p.can(Perm.manageServer)) ServerSettingsSection.system,
      if (p.can(Perm.manageStickers)) ServerSettingsSection.stickers,
    ]),
    (s.serverSettingsGroupPeople, [
      if (p.can(Perm.kickMembers) || p.can(Perm.banMembers) || p.can(Perm.manageRoles))
        ServerSettingsSection.members,
      if (p.can(Perm.manageRoles)) ServerSettingsSection.roles,
      if (p.can(Perm.manageServer)) ServerSettingsSection.invites,
    ]),
    (s.serverSettingsGroupModeration, [
      if (p.can(Perm.banMembers)) ServerSettingsSection.bans,
    ]),
  ];
  return [for (final g in groups) if (g.$2.isNotEmpty) g];
}

String _label(BuildContext context, ServerSettingsSection section) {
  final s = context.s;
  return switch (section) {
    ServerSettingsSection.profile => s.serverSettingsProfile,
    ServerSettingsSection.system => s.serverSettingsSystem,
    ServerSettingsSection.stickers => s.serverSettingsStickers,
    ServerSettingsSection.members => s.serverSettingsMembers,
    ServerSettingsSection.roles => s.serverSettingsRoles,
    ServerSettingsSection.invites => s.invitesTitle,
    ServerSettingsSection.bans => s.serverSettingsBans,
  };
}

IconData _icon(ServerSettingsSection section) => switch (section) {
      ServerSettingsSection.profile => Icons.edit_outlined,
      ServerSettingsSection.system => Icons.tune_rounded,
      ServerSettingsSection.stickers => Icons.sticky_note_2_outlined,
      ServerSettingsSection.members => Icons.people_outline_rounded,
      ServerSettingsSection.roles => Icons.shield_outlined,
      ServerSettingsSection.invites => Icons.link_rounded,
      ServerSettingsSection.bans => Icons.block_rounded,
    };

Future<void> confirmDeleteServer(BuildContext context, ServerDetail server) async {
  final s = context.s;
  final agreed = await glitchConfirmByTyping(
    context,
    title: s.serverDeleteTitle(server.name),
    body: s.serverDeleteBody,
    fieldLabel: s.serverDeleteNameLabel,
    expected: server.name,
    mismatch: s.serverDeleteMismatch,
    confirmLabel: s.serverSettingsDelete,
  );
  if (!agreed) return;
  try {
    await api.deleteServer(server.id);
    serverRail.forget(server.id, ServerGoneReason.deleted);
  } catch (e) {
    if (context.mounted) GlitchToast.show(context, errorMessage(e));
  }
}

Widget _sectionContent(
  BuildContext context,
  ServerSettingsSection section,
  ServerDetail server, {
  Widget? header,
  GlobalKey<State>? sectionKey,
  bool wide = false,
}) {
  return switch (section) {
    ServerSettingsSection.profile =>
      ServerProfileSection(key: sectionKey, server: server, header: header),
    ServerSettingsSection.system =>
      ServerSystemSection(key: sectionKey, server: server, header: header),
    ServerSettingsSection.stickers => ServerStickersSection(server: server, header: header),
    ServerSettingsSection.members => ServerMembersSection(server: server, header: header),
    ServerSettingsSection.bans => ServerBansSection(server: server, header: header),
    ServerSettingsSection.invites => InvitesSection(
        target: InviteTarget.server(server.id, server.name),
        header: header,
        showVanity: server.myPermissions.can(Perm.manageServer)),
    ServerSettingsSection.roles =>
      ServerRolesSection(
        key: sectionKey,
        server: server,
        header: header,
        wide: wide,
      ),
  };
}

mixin _FreshServer<T extends StatefulWidget> on State<T> {
  late ServerDetail server;
  StreamSubscription<ServerProfile>? _profileSub;
  StreamSubscription<ServerGone>? _goneSub;

  ServerDetail get initialServer;

  @override
  void initState() {
    super.initState();
    server = initialServer;
    _profileSub = serverRail.profileChanges.listen((p) {
      if (p.id != server.id || !mounted) return;
      setState(() => server = server.withProfile(p));
    });
    _goneSub = serverRail.serverGone.listen((g) {
      if (g.id == server.id && mounted) _closeWindow();
    });
    serverRail.addListener(_onViewAs);
  }

  void _onViewAs() {
    if (mounted && serverRail.viewAs?.serverId == server.id) _closeWindow();
  }

  void _closeWindow() {
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    final nav = Navigator.of(context);
    nav.popUntil((r) => r == route);
    nav.pop();
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    _goneSub?.cancel();
    serverRail.removeListener(_onViewAs);
    super.dispose();
  }
}


SettingsWindowSpec<ServerSettingsSection> _spec(
  BuildContext context,
  ServerDetail server, {
  ServerSettingsSection? initialSection,
}) {
  final s = context.s;
  return SettingsWindowSpec<ServerSettingsSection>(
    title: s.serverSettings,
    initialSection: initialSection,
    objectName: server.name,
    narrowHeader: Row(
      children: [
        GlitchAvatar(
          initials: GlitchAvatar.initialsFromName(server.name),
          size: 48,
          colorIndex: GlitchAvatar.colorFromNickname(server.name),
          imageUrl: server.avatar != null ? api.mediaUrl(server.avatar!) : null,
          avatarSizes: server.avatarSizes,
          shape: AvatarShape.community,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            server.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary),
          ),
        ),
      ],
    ),
    groups: _sectionGroups(context, server),
    label: (section) => _label(context, section),
    icon: _icon,
    subtitle: (section) => switch (section) {
          ServerSettingsSection.profile => s.serverProfileSubtitle,
          ServerSettingsSection.system => s.serverSystemSubtitle,
          ServerSettingsSection.roles => s.serverRolesSubtitle,
          _ => null,
        },
    content: (section, {header, sectionKey, wide = false}) => _sectionContent(
      context, section, server,
      header: header, sectionKey: sectionKey, wide: wide,
    ),
    danger: server.isOwner
        ? SettingsDangerAction(
            label: s.serverSettingsDelete,
            onTap: () => confirmDeleteServer(context, server),
          )
        : null,
  );
}

Future<void> openServerSettings(
  BuildContext context,
  ServerDetail server, {
  ServerSettingsSection? section,
}) =>
    openAdaptiveFullscreen(
      context,
      narrowBuilder: (_) => ServerSettingsScreen(server: server, initialSection: section),
      wideBuilder: (_) => ServerSettingsWideScreen(server: server, initialSection: section),
    );

class ServerSettingsScreen extends StatefulWidget {
  final ServerDetail server;

  final ServerSettingsSection? initialSection;

  const ServerSettingsScreen({super.key, required this.server, this.initialSection});

  static bool isAvailable(BuildContext context, ServerDetail server) =>
      server.isOwner || _sectionGroups(context, server).isNotEmpty;

  @override
  State<ServerSettingsScreen> createState() => _ServerSettingsScreenState();
}

class _ServerSettingsScreenState extends State<ServerSettingsScreen>
    with ThemeAwareState<ServerSettingsScreen>, _FreshServer<ServerSettingsScreen> {
  @override
  ServerDetail get initialServer => widget.server;

  @override
  Widget build(BuildContext context) =>
      SettingsWindowNarrow<ServerSettingsSection>(
          spec: _spec(context, server, initialSection: widget.initialSection));
}

class ServerSettingsWideScreen extends StatefulWidget {
  final ServerDetail server;
  final ServerSettingsSection? initialSection;

  const ServerSettingsWideScreen({super.key, required this.server, this.initialSection});

  @override
  State<ServerSettingsWideScreen> createState() => _ServerSettingsWideScreenState();
}

class _ServerSettingsWideScreenState extends State<ServerSettingsWideScreen>
    with ThemeAwareState<ServerSettingsWideScreen>, _FreshServer<ServerSettingsWideScreen> {
  @override
  ServerDetail get initialServer => widget.server;

  @override
  Widget build(BuildContext context) =>
      SettingsWindowWide<ServerSettingsSection>(
          spec: _spec(context, server, initialSection: widget.initialSection));
}
