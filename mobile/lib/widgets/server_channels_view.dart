import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../core/shell_metrics.dart';
import '../core/adaptive_open.dart';
import '../core/l10n.dart';
import '../core/server_leave.dart';
import '../core/avatar_color.dart';
import '../core/copy_actions.dart';
import '../core/own_account_open.dart' show editMyProfile;
import '../core/permissions.dart';
import '../core/platform_info.dart';
import '../core/shell_controller.dart' show ShellPlace, ShellSlot, shellController;
import '../models/chat_arrival.dart';
import '../models/invite.dart';
import '../models/server.dart';
import '../providers/room_unread.dart';
import '../providers/server_notifications.dart';
import '../providers/server_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/voice_channels.dart';
import '../models/voice_pass.dart';
import '../screens/category_settings_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/room_settings_screen.dart';
import '../screens/server_settings_screen.dart';
import '../services/api_service.dart' show api, errorMessage;
import '../services/auth_service.dart' show authService;
import '../services/voice_connection.dart' show voiceConnection;
import '../theme/app_theme.dart';
import 'theme_workspace.dart';
import '../theme/glitch_icons.dart';
import 'create_server_sheets.dart';
import 'count_badge.dart';
import 'elapsed_time.dart';
import 'glitch_hover_row.dart';
import 'live_badge.dart';
import 'stream_preview_card.dart';
import 'glitch_toast.dart';
import 'glitch_tooltip.dart';
import 'room_layout_drag.dart';
import 'edge_pill.dart';
import 'glitch_menu.dart';
import 'glitch_divider.dart';
import 'member_card.dart';
import 'invite_sheet.dart';
import 'server_notifications_window.dart';
import 'glitch_pressable.dart';
import 'glitch_avatar.dart';
import 'voice_member_menu.dart';
import 'voice_room_view.dart';
import 'voice_panel.dart';
import 'server_profile_card.dart';
import 'speaking_builder.dart';
import 'glitch_icon_button.dart';

enum _ServerMenuAction { invite, settings, room, category, notifications, editProfile, leave, copyId }

enum _CategoryMenuAction { settings, collapse, collapseAll, delete, copyId }
enum _RoomMenuAction { settings, copyId }

class ServerChannelsView extends StatefulWidget {
  final int serverId;

  final String? initialName;

  const ServerChannelsView({super.key, required this.serverId, this.initialName});

  @override
  State<ServerChannelsView> createState() => _ServerChannelsViewState();
}

class _ServerChannelsViewState extends State<ServerChannelsView>
    with ThemeAwareState<ServerChannelsView> {
  static const double _columnTint = 0.22;

  late ServerProvider _provider;

  final _bannerOffset = ValueNotifier<double>(0);

  bool _openedOnSelect = false;

  bool _ensureScheduled = false;

  int? _cardUserId;

  bool _draggingCategory = false;

  @override
  void initState() {
    super.initState();
    _provider = ServerProvider(widget.serverId)..addListener(_onChange);
    _provider.load();
    shellController.addListener(_onShellChange);
    serverRail.addListener(_onRailChange);
    voiceChannels.addListener(_onVoice);
    voiceConnection.personAudio.addListener(_onVoice);
    roomUnread.addListener(_onUnread);
    serverNotifications.addListener(_onUnread);
  }

  void _onUnread() {
    if (mounted) setState(() {});
  }

  void _onVoice() {
    if (mounted) setState(() {});
  }

  /// Рейл переключили на ДРУГОЙ сервер, а виджет тот же — Flutter
  /// переиспользует состояние при совпадении типа. Без этого обработчика
  /// колонка осталась бы показывать каналы прошлого сервера.
  @override
  void didUpdateWidget(covariant ServerChannelsView old) {
    super.didUpdateWidget(old);
    if (old.serverId == widget.serverId) return;
    _provider.removeListener(_onChange);
    _provider.dispose();
    _provider = ServerProvider(widget.serverId)..addListener(_onChange);
    _provider.load();
    _openedOnSelect = false;
    // Другое сообщество — прокрутка с начала: список получает новый ключ
    // (ValueKey по serverId) и создаётся заново, а значение для строки
    // сбрасываем после кадра — didUpdateWidget идёт посреди построения, и
    // уведомить слушателя прямо здесь нельзя.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bannerOffset.value = 0;
    });
  }

  @override
  void dispose() {
    voiceChannels.removeListener(_onVoice);
    voiceConnection.personAudio.removeListener(_onVoice);
    roomUnread.removeListener(_onUnread);
    serverNotifications.removeListener(_onUnread);
    shellController.removeListener(_onShellChange);
    serverRail.removeListener(_onRailChange);
    _provider.removeListener(_onChange);
    _provider.dispose();
    _bannerOffset.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    _scheduleEnsureRoomOpen();
  }

  void _onShellChange() {
    if (!mounted) return;
    setState(() {});
    _scheduleEnsureRoomOpen();
  }

  void _onRailChange() {
    if (mounted) _scheduleEnsureRoomOpen();
  }


  void _scheduleEnsureRoomOpen() {
    if (_ensureScheduled) return;
    _ensureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureScheduled = false;
      _ensureRoomOpen();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _ensureRoomOpen() {
    if (!mounted) return;
    final server = _provider.server;
    if (server == null || _provider.loading) return;

    final request = serverRail.takeRoomRequest(server.id);
    if (request != null) {
      final room = server.allRooms
          .where((r) => r.id == request.roomId && (r.kind == RoomKind.text || request.chosen))
          .firstOrNull;
      if (room != null) {
        _openedOnSelect = true;
        _openRoom(room, messageId: request.messageId, arrival: request.arrival);
        return;
      }
    }

    if (ShellPlace.slotOf(context) != ShellSlot.list) return;

    final ours = shellController.mainScope == ServerScope(server.id);
    if (!_openedOnSelect) {
      _openedOnSelect = true;
      if (ours) return;
    } else if (shellController.hasMain) {
      return;
    }
    final room = _roomToOpen(server);
    if (room != null) {
      _openRoom(room);
    } else if (shellController.hasMain && !ours) {
      shellController.closeAll(ShellSlot.main);
    }
  }

  Room? _roomToOpen(ServerDetail server) {
    final remembered = serverRail.lastRoomOf(server.id);
    if (remembered != null) {
      for (final r in server.allRooms) {
        if (r.id == remembered && r.kind == RoomKind.text) return r;
      }
    }
    return _provider.firstTextRoom;
  }

  Future<void> _openRoom(Room room, {int? messageId, ChatArrival? arrival}) async {
    if (room.kind == RoomKind.voice) {
      if (voiceChannels.serverId == room.serverId && voiceChannels.roomId == room.id) {
        await openVoiceRoom(context, room);
      } else {
        await voiceChannels.join(room);
      }
      return;
    }
    serverRail.rememberRoom(room.serverId, room.id);
    await openAdaptive(
      context,
      builder: (_) => ChatScreen.fromRoom(room, initialMessageId: messageId, arrival: arrival),
      slotKey: chatSlotKey(room.id),
      scope: ServerScope(room.serverId),
    );
  }

  void _addRoom({int? categoryId}) {
    final server = _provider.server;
    if (server == null) return;
    final where = categoryId == null
        ? server.myPermissions
        : server.categories.where((c) => c.id == categoryId).firstOrNull?.permissions;
    showCreateRoomSheet(
      context,
      serverId: server.id,
      categoryId: categoryId,
      canMakePrivate: where?.can(Perm.manageRoles) ?? false,
      onCreated: (room) {
        _provider.load();
        if (mounted && room.kind == RoomKind.text) _openRoom(room);
      },
    );
  }

  void _addCategory() {
    final server = _provider.server;
    if (server == null) return;
    showCreateCategorySheet(
      context,
      serverId: server.id,
      canMakePrivate: server.myPermissions.can(Perm.manageRoles),
      onCreated: _provider.load,
    );
  }

  void _invite() {
    final server = _provider.server;
    if (server == null) return;
    showInviteSheet(context, InviteTarget.server(server.id, server.name));
  }

  List<GlitchMenuItem<_ServerMenuAction>> _roomCreateItems() => [
    GlitchMenuItem(
      value: _ServerMenuAction.room,
      child: glitchMenuRow(Icons.tag_rounded, context.s.roomCreateTitle),
    ),
    GlitchMenuItem(
      value: _ServerMenuAction.category,
      child: glitchMenuRow(Icons.folder_outlined, context.s.categoryCreateTitle),
    ),
  ];

  void _onMenuAction(_ServerMenuAction action, {required int serverId}) {
    switch (action) {
      case _ServerMenuAction.invite:
        _invite();
      case _ServerMenuAction.settings:
        _openSettings();
      case _ServerMenuAction.room:
        _addRoom();
      case _ServerMenuAction.category:
        _addCategory();
      case _ServerMenuAction.notifications:
        final server = _provider.server;
        if (server != null) openServerNotifications(context, serverId: serverId, serverName: server.name);
      case _ServerMenuAction.editProfile:
        editMyProfile(context, serverId: serverId);
      case _ServerMenuAction.leave:
        final server = _provider.server;
        if (server != null) confirmLeaveServer(context, server);
      case _ServerMenuAction.copyId:
        copyId(context, serverId);
    }
  }

  void _openEmptyAreaMenu(Offset position) {
    final server = _provider.server;
    if (server == null) return;
    showGlitchContextMenuAt<_ServerMenuAction>(
      context,
      position,
      _roomCreateItems(),
      (action) => _onMenuAction(action, serverId: server.id),
    );
  }

  void _openCategoryMenu(RoomCategory category, Offset position) {
    final s = context.s;
    final collapsed = _provider.isCollapsed(category.id);
    showGlitchContextMenuAt<_CategoryMenuAction>(
      context,
      position,
      [
        if (categorySettingsAvailable(category))
          GlitchMenuItem(
            value: _CategoryMenuAction.settings,
            child: glitchMenuRow(GlitchIcons.settings, s.categorySettings),
          ),
        GlitchMenuItem(
          value: _CategoryMenuAction.collapse,
          child: glitchMenuRow(
            collapsed ? Icons.unfold_more_rounded : Icons.unfold_less_rounded,
            collapsed ? s.categoryExpand : s.categoryCollapse,
          ),
        ),
        if (!_provider.allCollapsed)
          GlitchMenuItem(
            value: _CategoryMenuAction.collapseAll,
            child: glitchMenuRow(Icons.vertical_align_center_rounded, s.categoryCollapseAll),
          ),
        if (categoryDeleteAvailable(category))
          GlitchMenuItem(
            value: _CategoryMenuAction.delete,
            child: glitchMenuRow(Icons.delete_outline_rounded, s.categorySettingsDelete, danger: true),
          ),
        GlitchMenuItem(
          value: _CategoryMenuAction.copyId,
          child: copyIdMenuRow(context, IdKind.category),
        ),
      ],
      (action) {
        switch (action) {
          case _CategoryMenuAction.settings:
            _openCategorySettings(category);
          case _CategoryMenuAction.collapse:
            _provider.toggleCategory(category.id);
          case _CategoryMenuAction.collapseAll:
            _provider.collapseAll();
          case _CategoryMenuAction.delete:
            confirmDeleteCategory(context, category);
          case _CategoryMenuAction.copyId:
            copyId(context, category.id);
        }
      },
    );
  }

  void _openRoomMenu(Room room, Offset position) {
    showGlitchContextMenuAt<_RoomMenuAction>(
      context,
      position,
      [
        if (roomSettingsAvailable(room))
          GlitchMenuItem(
            value: _RoomMenuAction.settings,
            child: glitchMenuRow(GlitchIcons.settings, context.s.roomSettings),
          ),
        GlitchMenuItem(
          value: _RoomMenuAction.copyId,
          child: copyIdMenuRow(context, IdKind.channel),
        ),
      ],
      (action) {
        switch (action) {
          case _RoomMenuAction.settings:
            _openRoomSettings(room);
          case _RoomMenuAction.copyId:
            copyId(context, room.id);
        }
      },
    );
  }

  void _openCategorySettings(RoomCategory category) {
    openAdaptiveFullscreen(
      context,
      narrowBuilder: (_) => CategorySettingsScreen(category: category),
      wideBuilder: (_) => CategorySettingsWideScreen(category: category),
    );
  }

  void _openRoomSettings(Room room) => openRoomSettings(context, room);

  void _openSettings() {
    final server = _provider.server;
    if (server == null) return;
    openServerSettings(context, server);
  }

  @override
  Widget build(BuildContext context) {
    final server = _provider.server;
    final title = server?.name ?? widget.initialName ?? '';
    final canManageRooms = server?.myPermissions.can(Perm.manageRooms) ?? false;
    final canInvite = server?.myPermissions.can(Perm.createInvite) ?? false;
    final canSettings = server != null && ServerSettingsScreen.isAvailable(context, server);
    final canLeave = server != null && !server.isOwner;

    return Material(
      color: ThemeWorkspace.surface(context, GlitchColors.bg, tint: _columnTint),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (server?.banner == null) ...[
              Container(
                decoration: BoxDecoration(
                  border: _headerBorder(context),
                ),
                height: _headerHeight,
                alignment: Alignment.center,
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                child: _headerRow(
                  title: title,
                  serverId: server?.id,
                  canInvite: canInvite,
                  canSettings: canSettings,
                  canManageRooms: canManageRooms,
                  canLeave: canLeave,
                  fg: GlitchColors.textPrimary,
                  dim: GlitchColors.textHint,
                  inviteColor: GlitchColors.textSecond,
                ),
              ),
              Expanded(child: _body(server, canManageRooms)),
            ] else
              Expanded(
                child: _withBanner(
                  server!,
                  title: title,
                  canInvite: canInvite,
                  canSettings: canSettings,
                  canManageRooms: canManageRooms,
                  canLeave: canLeave,
                ),
              ),
            const VoicePanel(),
          ],
        ),
      ),
    );
  }

  static const double _headerHeight = kShellBarHeight;

  Border _headerBorder(BuildContext context) =>
      Border(bottom: BorderSide(color: ThemeWorkspace.dividerColor(context)));

  Widget _headerRow({
    required String title,
    required int? serverId,
    required bool canInvite,
    required bool canSettings,
    required bool canManageRooms,
    required bool canLeave,
    required Color fg,
    required Color dim,
    required Color inviteColor,
    List<Shadow>? shadows,
  }) {
    return Row(
      children: [
        Expanded(
          child: serverId != null
              ? Builder(
                  builder: (btnCtx) => GlitchPressable(
                    onTap: () => openGlitchMenu<_ServerMenuAction>(
                      btnCtx,
                      items: [
                        if (canInvite)
                          GlitchMenuItem(
                            value: _ServerMenuAction.invite,
                            child: glitchMenuRow(
                                Icons.person_add_alt_1_rounded, context.s.inviteMenu),
                          ),
                        if (canSettings)
                          GlitchMenuItem(
                            value: _ServerMenuAction.settings,
                            child: glitchMenuRow(GlitchIcons.settings, context.s.serverSettings),
                          ),
                        if (canManageRooms) ..._roomCreateItems(),
                        GlitchMenuItem(
                          value: _ServerMenuAction.notifications,
                          child: glitchMenuRow(Icons.notifications_none_rounded, context.s.notifServerTitle),
                        ),
                        GlitchMenuItem(
                          value: _ServerMenuAction.editProfile,
                          child: glitchMenuRow(Icons.edit_outlined, context.s.serverEditMyProfile),
                        ),
                        if (canLeave)
                          GlitchMenuItem(
                            value: _ServerMenuAction.leave,
                            child: glitchMenuRow(Icons.logout_rounded, context.s.serverLeave, danger: true),
                          ),
                        GlitchMenuItem(
                          value: _ServerMenuAction.copyId,
                          child: copyIdMenuRow(context, IdKind.server),
                        ),
                      ],
                      onSelected: (action) => _onMenuAction(action, serverId: serverId),
                      centerInContext: context,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: fg,
                              shadows: shadows,
                            ),
                          ),
                        ),
                        Icon(Icons.expand_more_rounded, size: 20, color: dim, shadows: shadows),
                      ],
                    ),
                  ),
                )
              : Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: fg,
                    shadows: shadows,
                  ),
                ),
        ),
        if (canInvite)
          GlitchTooltip(
            message: context.s.tipInviteToServer,
            side: GlitchTooltipSide.bottom,
            child: GlitchIconButton(
              onTap: _invite,
              size: 36,
              extent: 36,
              icon: Icon(Icons.person_add_alt_1_rounded, size: 19, color: inviteColor, shadows: shadows),
            ),
          ),
      ],
    );
  }

  void _setBannerOffset(double value) {
    final phase = SchedulerBinding.instance.schedulerPhase;
    final midFrame =
        phase == SchedulerPhase.persistentCallbacks || phase == SchedulerPhase.midFrameMicrotasks;
    if (midFrame) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _bannerOffset.value = value;
      });
    } else {
      _bannerOffset.value = value;
    }
  }

  Widget _withBanner(
    ServerDetail server, {
    required String title,
    required bool canInvite,
    required bool canSettings,
    required bool canManageRooms,
    required bool canLeave,
  }) {
    return LayoutBuilder(builder: (context, constraints) {
      final bannerHeight = constraints.maxWidth / kServerBannerStripAspect;
      final banner = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTap: () {},
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: bannerHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ServerBanner(
                    url: server.banner,
                    sizes: server.bannerSizes,
                    fallbackColor: parseAvatarColor(server.avatarColor),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.center,
                        colors: [Color(0x99000000), Color(0x00000000)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const GlitchDivider(),
          ],
        ),
      );
      return Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.depth == 0) _setBannerOffset(n.metrics.pixels);
              return false;
            },
            child: _body(server, canManageRooms, leading: banner),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<double>(
              valueListenable: _bannerOffset,
              builder: (context, offset, _) {
                final room = (bannerHeight - _headerHeight).clamp(1.0, double.infinity);
                final t = (offset / room).clamp(0.0, 1.0);
                return SizedBox(
                  height: _headerHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      IgnorePointer(
                        child: ThemeWorkspace.backdrop(context, GlitchColors.bg, opacity: t, tint: _columnTint),
                      ),
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                        decoration: BoxDecoration(border: t >= 1 ? _headerBorder(context) : null),
                        child: _headerRow(
                          title: title,
                          serverId: server.id,
                          canInvite: canInvite,
                          canSettings: canSettings,
                          canManageRooms: canManageRooms,
                          canLeave: canLeave,
                          fg: Color.lerp(Colors.white, GlitchColors.textPrimary, t)!,
                          dim: Color.lerp(Colors.white, GlitchColors.textHint, t)!,
                          inviteColor: Color.lerp(Colors.white, GlitchColors.textSecond, t)!,
                          shadows: t < 0.5 ? const [Shadow(color: Color(0x8A000000), blurRadius: 6)] : null,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      );
    });
  }

  static const double _roomsTopGap = 8;

  Widget _body(ServerDetail? server, bool canManageRooms, {Widget? leading}) {
    if (_provider.loading && server == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_provider.error != null && server == null) {
      return _errorState(_provider.error!);
    }
    if (server == null) return const SizedBox.shrink();

    final hasAnything = server.rooms.isNotEmpty || server.categories.isNotEmpty;
    if (!hasAnything) {
      if (leading == null) {
        return _emptyAreaTap(
          canManageRooms,
          child: _emptyState(context.s.serverNoRooms),
        );
      }
      return _emptyAreaTap(
        canManageRooms,
        child: ListView(
          key: ValueKey('rooms-${widget.serverId}'),
          children: [leading, const SizedBox(height: 40), _emptyState(context.s.serverNoRooms)],
        ),
      );
    }

    return _emptyAreaTap(
      canManageRooms,
      child: ListView(
        // Ключ по сообществу — при смене сообщества список создаётся заново и
        // начинает с верха (см. didUpdateWidget).
        key: ValueKey('rooms-${widget.serverId}'),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (leading != null) KeyedSubtree(key: const ValueKey('banner'), child: leading),
          // Каналы вне категорий идут первыми — так же у Discord. Над ними
          // небольшой отступ, как у Discord: иначе верхний канал прилипает к
          // баннеру или к шапке. Категории он не нужен — у её заголовка свой
          // отступ сверху.
          if (server.rooms.isNotEmpty) const SizedBox(key: ValueKey('rooms-top-gap'), height: _roomsTopGap),
          for (final room in server.rooms) _roomTile(room),
          for (final category in server.categories) ..._category(category, canManageRooms),
        ],
      ),
    );
  }

  Widget _emptyAreaTap(bool canManageRooms, {required Widget child}) {
    if (!canManageRooms) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapUp: (d) => _openEmptyAreaMenu(d.globalPosition),
      child: child,
    );
  }

  Widget _roomMenuArea(Room room, Widget child) => GestureDetector(
    behavior: HitTestBehavior.deferToChild,
    onSecondaryTapUp: (d) => _openRoomMenu(room, d.globalPosition),
    onLongPressStart: (d) => _openRoomMenu(room, d.globalPosition),
    child: child,
  );

  List<Widget> _category(RoomCategory category, bool canManageRooms) {
    final collapsed = _provider.isCollapsed(category.id) || _draggingCategory;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onSecondaryTapUp: (d) => _openCategoryMenu(category, d.globalPosition),
                onLongPressStart: (d) => _openCategoryMenu(category, d.globalPosition),
                child: GlitchHoverArea(
                  onTap: () => _provider.toggleCategory(category.id),
                  builder: (context, active) {
                    final ink = active ? GlitchColors.textPrimary : GlitchColors.textHint;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            category.name.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          collapsed ? Icons.chevron_right_rounded : Icons.expand_more_rounded,
                          size: 18,
                          color: ink,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          if (canManageRooms)
            GlitchTooltip(
              message: context.s.tipCreateRoom,
              child: GlitchIconButton(
                icon: Icon(Icons.add_rounded, size: 18),
                onTap: () => _addRoom(categoryId: category.id),
                size: 28,
                extent: 28,
              ),
            ),
        ],
      ),
    );
    return [
      LayoutDropZone(
        key: ValueKey('category-${category.id}'),
        indent: 16,
        accepts: (drag, before) => _acceptsOnHeader(category, drag, before),
        onDrop: (drag, before) => _dropOnHeader(category, drag, before),
        child: LayoutDraggable(
          data: LayoutDrag.category(category),
          enabled: _mayMoveCategory(category),
          onStarted: () => setState(() => _draggingCategory = true),
          onEnded: () {
            if (mounted) setState(() => _draggingCategory = false);
          },
          child: header,
        ),
      ),
      if (!collapsed)
        for (final room in category.rooms) _roomTile(room),
    ];
  }


  bool _mayMoveRoom(Room room) => hasPointerInput && room.permissions.can(Perm.manageRooms);
  bool _mayMoveCategory(RoomCategory c) => hasPointerInput && c.permissions.can(Perm.manageRooms);

  RoomCategory? _categoryById(int id) {
    for (final c in _provider.server?.categories ?? const <RoomCategory>[]) {
      if (c.id == id) return c;
    }
    return null;
  }

  List<Room> _roomsOf(int? categoryId) {
    if (categoryId == null) return _provider.server?.rooms ?? const <Room>[];
    return _categoryById(categoryId)?.rooms ?? const <Room>[];
  }

  bool _mayDropInto(int? categoryId) {
    if (categoryId == null) return true;
    return _categoryById(categoryId)?.permissions.can(Perm.manageRooms) ?? false;
  }

  int? _boxAbove(RoomCategory header) {
    final cats = _provider.server?.categories ?? const <RoomCategory>[];
    final i = cats.indexWhere((c) => c.id == header.id);
    return i > 0 ? cats[i - 1].id : null;
  }

  static int? _previous(List<int> ids, int movedId, int beforeId) {
    final rest = [for (final id in ids) if (id != movedId) id];
    final i = rest.indexOf(beforeId);
    return i > 0 ? rest[i - 1] : null;
  }

  bool _acceptsOnRoom(Room target, LayoutDrag drag) {
    final room = drag.room;
    return room != null && room.id != target.id && _mayDropInto(target.categoryId);
  }

  void _dropOnRoom(Room target, LayoutDrag drag, bool before) {
    final room = drag.room;
    if (room == null) return;
    final ids = [for (final r in _roomsOf(target.categoryId)) r.id];
    _moveRoom(room, target.categoryId, before ? _previous(ids, room.id, target.id) : target.id);
  }

  bool _acceptsOnHeader(RoomCategory header, LayoutDrag drag, bool before) {
    if (drag.room != null) return _mayDropInto(before ? _boxAbove(header) : header.id);
    final category = drag.category;
    return category != null && category.id != header.id;
  }

  void _dropOnHeader(RoomCategory header, LayoutDrag drag, bool before) {
    final room = drag.room;
    if (room != null) {
      if (before) {
        final box = _boxAbove(header);
        final rest = [for (final r in _roomsOf(box)) if (r.id != room.id) r];
        _moveRoom(room, box, rest.isEmpty ? null : rest.last.id);
      } else {
        _moveRoom(room, header.id, null);
      }
      return;
    }
    final category = drag.category;
    if (category == null) return;
    final ids = [for (final c in _provider.server?.categories ?? const <RoomCategory>[]) c.id];
    _moveCategory(category, before ? _previous(ids, category.id, header.id) : header.id);
  }

  void _moveRoom(Room room, int? categoryId, int? afterId) {
    if (room.categoryId == categoryId) {
      final ids = [for (final r in _roomsOf(categoryId)) r.id];
      final i = ids.indexOf(room.id);
      if (i >= 0 && (i > 0 ? ids[i - 1] : null) == afterId) return;
    }
    _report(_provider.moveRoom(room.id, categoryId: categoryId, afterId: afterId));
  }

  void _moveCategory(RoomCategory category, int? afterId) {
    final ids = [for (final c in _provider.server?.categories ?? const <RoomCategory>[]) c.id];
    final i = ids.indexOf(category.id);
    if (i >= 0 && (i > 0 ? ids[i - 1] : null) == afterId) return;
    _report(_provider.moveCategory(category.id, afterId: afterId));
  }

  Future<void> _report(Future<String?> move) async {
    final error = await move;
    if (error != null && mounted) GlitchToast.show(context, error);
  }

  Widget _roomTile(Room room) {
    final isVoice = room.kind == RoomKind.voice;
    final row = LayoutDraggable(
      data: LayoutDrag.room(room),
      enabled: _mayMoveRoom(room),
      child: _roomRow(room),
    );
    return LayoutDropZone(
      key: ValueKey('room-${room.id}'),
      indent: 16,
      accepts: (drag, _) => _acceptsOnRoom(room, drag),
      onDrop: (drag, before) => _dropOnRoom(room, drag, before),
      child: isVoice
          ? VoiceMemberDropZone(
              accepts: (drag) => _mayMoveMemberTo(room, drag),
              onDrop: (drag) => _moveMemberTo(room, drag),
              child: _voiceRoomContent(room, row),
            )
          : row,
    );
  }

  Widget _voiceRoomContent(Room room, Widget row) {
    final inside = voiceChannels.inRoom(room.serverId, room.id);
    if (inside.isEmpty) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        row,
        for (final v in inside) _voiceMember(room, v),
      ],
    );
  }

  bool _mayDragMember(Room room, VoiceStateInfo v) {
    if (!hasPointerInput) return false;
    if (_isMe(v)) return voiceChannels.serverId == room.serverId && voiceChannels.roomId == room.id;
    return room.permissions.can(Perm.moveMembers);
  }

  bool _isMe(VoiceStateInfo v) => v.userId == authService.currentUser?.id;

  bool _mayMoveMemberTo(Room target, VoiceMemberDrag drag) {
    if (target.id == drag.fromRoomId) return true;
    if (_isMe(drag.member)) return target.permissions.can(Perm.connect);
    return target.permissions.can(Perm.moveMembers);
  }

  Future<void> _moveMemberTo(Room target, VoiceMemberDrag drag) async {
    if (target.id == drag.fromRoomId) return;
    if (_isMe(drag.member)) {
      await voiceChannels.join(target);
      return;
    }
    try {
      await api.moveMemberVoice(target.serverId, drag.member.userId, target.id);
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    }
  }

  Widget _voiceMember(Room room, VoiceStateInfo v) {
    final name = v.displayName ?? v.nickname ?? '';
    final muted = v.selfMute || v.serverMute;
    final deaf = v.selfDeaf || v.serverDeaf;
    final personMuted = voiceConnection.isPersonMuted(v.userId);
    const indent = 42.0;
    final row = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapUp: (d) => _openVoiceMemberMenu(room, v, d.globalPosition),
      onLongPressStart: (d) => _openVoiceMemberMenu(room, v, d.globalPosition),
      child: Builder(
        builder: (rowContext) => GlitchHoverRow(
          onTap: () => _openVoiceMemberCard(room, v, name, rowContext),
          selected: _cardUserId == v.userId,
          highlightInset: EdgeInsets.fromLTRB(indent - 8, 1, 8, 1),
          padding: EdgeInsets.fromLTRB(indent, 4, 16, 4),
          builder: (active) => Row(
            children: [
              SpeakingBuilder(
                userId: v.userId,
                builder: (context, speaking) => Container(
                  padding: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: speaking ? GlitchColors.online : Colors.transparent, width: 2),
                  ),
                  child: GlitchAvatar(
                    initials: GlitchAvatar.initialsFromName(name),
                    size: 22,
                    colorIndex: GlitchAvatar.colorFromNickname(v.nickname ?? name),
                    imageUrl: v.avatar,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: active ? GlitchColors.textPrimary : GlitchColors.textSecond,
                  ),
                ),
              ),
              if (muted) ...[
                const SizedBox(width: 4),
                Icon(Icons.mic_off_rounded, size: 15,
                    color: v.serverMute ? GlitchColors.error : GlitchColors.textHint),
              ],
              if (deaf) ...[
                const SizedBox(width: 4),
                Icon(Icons.headset_off_rounded, size: 15,
                    color: v.serverDeaf ? GlitchColors.error : GlitchColors.textHint),
              ],
              if (personMuted) ...[
                const SizedBox(width: 4),
                Icon(Icons.volume_off_rounded, size: 15, color: GlitchColors.textHint),
              ],
              if (v.streaming) ...[
                const SizedBox(width: 6),
                LiveBadge(context.s.voiceBadgeScreen),
              ],
              if (v.video) ...[
                const SizedBox(width: 6),
                LiveBadge(context.s.voiceBadgeCamera),
              ],
            ],
          ),
        ),
      ),
    );
    return VoiceMemberDraggable(
      data: VoiceMemberDrag(v, room.id),
      enabled: _mayDragMember(room, v),
      feedback: row,
      child: StreamPreviewHover(room: room, state: v, child: row),
    );
  }

  Future<void> _openVoiceMemberCard(Room room, VoiceStateInfo v, String name, BuildContext rowContext) async {
    setState(() => _cardUserId = v.userId);
    await showMemberCard(
      rowContext,
      serverId: room.serverId,
      user: ServerUser(
        id: v.userId,
        nickname: v.nickname ?? '',
        displayName: name,
        avatar: v.avatar,
        avatarColor: parseAvatarColor(v.avatarColor),
      ),
      name: name,
      side: GlitchPopupSide.right,
    );
    if (mounted && _cardUserId == v.userId) setState(() => _cardUserId = null);
  }

  void _openVoiceMemberMenu(Room room, VoiceStateInfo v, Offset position) => openVoiceMemberMenu(
        context,
        room: room,
        member: v,
        position: position,
      );

  Widget _roomRow(Room room) {
    final isVoice = room.kind == RoomKind.voice;
    final selected = shellController.mainKey == (isVoice ? voiceRoomSlotKey(room.id) : chatSlotKey(room.id));
    final unread = roomUnread.isUnread(room.id) && !selected && !serverNotifications.isMuted(room.serverId);
    final mentions = selected ? 0 : roomUnread.mentionsIn(room.id);
    final occupied = isVoice && voiceChannels.inRoom(room.serverId, room.id).isNotEmpty;
    final timer = occupied ? voiceChannels.channelTimer(room.id) : null;
    final row = _roomMenuArea(room, GlitchHoverRow(
      onTap: () => _openRoom(room),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      trailing: roomSettingsAvailable(room)
          ? GlitchTooltip(
              message: context.s.tipRoomSettings,
              child: GlitchHoverArea(
                onTap: () => _openRoomSettings(room),
                builder: (_, active) => Center(
                  child: Icon(
                    GlitchIcons.settings,
                    size: 17,
                    color: active ? GlitchColors.textPrimary : GlitchColors.textSecond,
                  ),
                ),
              ),
            )
          : null,
      selected: selected,
      builder: (active) {
        final bright = active || unread || occupied;
        final color = bright ? GlitchColors.textPrimary : GlitchColors.textNavIdle;
        return Row(
          children: [
            Icon(
              isVoice ? Icons.volume_up_rounded : Icons.tag_rounded,
              size: 20,
              color: occupied ? GlitchColors.online : color,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                room.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                  color: color,
                ),
              ),
            ),
            if (timer != null) ...[
              const SizedBox(width: 8),
              ElapsedTime.counting(
                key: ValueKey(room.id),
                readElapsed: () => timer.elapsed,
              ),
            ],
            if (mentions > 0) ...[
              const SizedBox(width: 6),
              CountBadge(count: mentions),
            ],
          ],
        );
      },
    ));
    if (!unread) return row;
    return Stack(
      children: [
        row,
        const Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: Center(child: EdgePill(state: EdgePillState.unread)),
        ),
      ],
    );
  }

  Widget _emptyState(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 15, color: GlitchColors.textHint),
      ),
    ),
  );

  Widget _errorState(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: GlitchColors.textSecond),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _provider.load,
            child: Text(context.s.retry, style: TextStyle(color: GlitchColors.accentBlue)),
          ),
        ],
      ),
    ),
  );
}
