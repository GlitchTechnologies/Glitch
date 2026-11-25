import 'dart:async';

import 'package:flutter/material.dart';
import '../core/adaptive_open.dart' show ServerScope, catalogScope, chatSlotKey, openAdaptive;
import '../core/l10n.dart';
import '../core/shell_controller.dart' show shellController, ShellSlot;
import '../models/chat.dart' show ChatListItem;
import '../models/chat_arrival.dart';
import '../models/server.dart' show ServerGone, ServerGoneReason;
import '../models/voice_pass.dart' show VoiceStateInfo;
import '../providers/chats_provider.dart' show ChatsProvider;
import '../providers/room_unread.dart';
import '../providers/server_notifications.dart';
import '../providers/server_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/voice_channels.dart';
import '../screens/chat_screen.dart' show ChatScreen;
import '../services/api_service.dart';
import '../services/unread_summary.dart';
import '../theme/app_theme.dart';
import 'theme_workspace.dart';
import 'count_badge.dart';
import 'create_server_sheets.dart';
import 'edge_pill.dart';
import 'glitch_avatar.dart';
import 'glitch_glyph.dart';
import 'glitch_pressable.dart';
import 'glitch_toast.dart';
import 'glitch_tooltip.dart';

class ServerRail extends StatefulWidget {
  const ServerRail({super.key});

  static const double width = 64;

  @override
  State<ServerRail> createState() => _ServerRailState();
}

class _ServerRailState extends State<ServerRail> with ThemeAwareState<ServerRail> {
  StreamSubscription<ServerGone>? _goneSub;

  @override
  void initState() {
    super.initState();
    serverRail.addListener(_onChange);
    roomUnread.addListener(_onChange);
    serverNotifications.addListener(_onChange);
    unreadSummary.addListener(_onChange);
    _goneSub = serverRail.serverGone.listen(_onGone);
    serverRail.load();
  }

  @override
  void dispose() {
    serverRail.removeListener(_onChange);
    roomUnread.removeListener(_onChange);
    serverNotifications.removeListener(_onChange);
    unreadSummary.removeListener(_onChange);
    _goneSub?.cancel();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _onGone(ServerGone gone) {
    if (!mounted || gone.name.isEmpty) return;
    final text = switch (gone.reason) {
      ServerGoneReason.removed => context.s.serverRemovedToast(gone.name),
      ServerGoneReason.left => null,
      ServerGoneReason.deleted => context.s.serverDeletedToast(gone.name),
    };
    if (text != null) GlitchToast.show(context, text, type: ToastType.info);
  }

  void _pick(Object? space) {
    if (shellController.hasListOverride) shellController.close(ShellSlot.list);
    serverRail.selectSpace(space);
  }

  @override
  Widget build(BuildContext context) {
    final items = serverRail.servers;
    final onChats = serverRail.space == null;
    return Material(
      color: ThemeWorkspace.frameSurface(context, GlitchColors.bgCard),
      child: SizedBox(
        width: ServerRail.width,
        child: SafeArea(
          right: false,
          child: Column(
            children: [
              const SizedBox(height: 8),
              _RailButton(
                selected: onChats,
                tooltip: context.s.tipDirectMessages,
                onTap: () => _pick(null),
                child: _withBadge(
                  _RailTile(
                    child: GlitchGlyph(size: 24, color: GlitchColors.textPrimary),
                  ),
                  unreadSummary.count,
                ),
              ),
              if (unreadSummary.latest case final ChatListItem chat)
                _RailButton(
                  key: ValueKey('rail-chat-${chat.id}'),
                  selected: false,
                  onTap: () => _openChat(chat),
                  child: _withBadge(
                    GlitchAvatar(
                      initials: GlitchAvatar.initialsFromName(ChatsProvider.chatName(chat)),
                      size: 44,
                      colorIndex: GlitchAvatar.colorFromNickname(ChatsProvider.chatName(chat)),
                      imageUrl: chat.avatar != null ? api.mediaUrl(chat.avatar!) : null,
                      avatarSizes: chat.avatarSizes,
                    ),
                    chat.unreadCount,
                  ),
                ),
              _separator(context),
              Expanded(
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final s = items[i];
                      return _RailButton(
                        selected: serverRail.selectedId == s.id,
                        unread: roomUnread.serverUnreadShown(s.id),
                        tooltip: s.name,
                        tooltipExtra: _ServerVoicePeek(serverId: s.id),
                        onTap: () => _pick(ServerScope(s.id)),
                        child: _withVoiceMark(s.id, _withBadge(
                          GlitchAvatar(
                            initials: GlitchAvatar.initialsFromName(s.name),
                            size: 44,
                            colorIndex: GlitchAvatar.colorFromNickname(s.name),
                            imageUrl: s.avatar != null ? api.mediaUrl(s.avatar!) : null,
                            avatarSizes: s.avatarSizes,
                            shape: AvatarShape.community,
                          ),
                          roomUnread.mentionsInServer(s.id),
                        )),
                      );
                    },
                  ),
                ),
              ),
              _separator(context),
              _RailButton(
                selected: null,
                tooltip: context.s.tipCreateServer,
                onTap: () => showCreateServerSheet(context),
                child: _RailTile(
                  child: Icon(Icons.add_rounded, size: 26, color: GlitchColors.textPrimary),
                ),
              ),
              _RailButton(
                selected: serverRail.onCatalog,
                tooltip: context.s.tipCatalog,
                onTap: () => _pick(catalogScope),
                child: _RailTile(
                  child: Icon(Icons.explore_rounded, size: 24, color: GlitchColors.textPrimary),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _withBadge(Widget icon, int count) => Stack(
        clipBehavior: Clip.none,
        children: [
          icon,
          Positioned(
            right: -2,
            bottom: -2,
            child: CountBadge(count: count, outline: GlitchColors.bgCard),
          ),
        ],
      );

  Widget _withVoiceMark(int serverId, Widget icon) => Stack(
        clipBehavior: Clip.none,
        children: [
          icon,
          Positioned(right: -3, top: -3, child: _VoiceMark(serverId: serverId)),
        ],
      );

  void _openChat(ChatListItem chat) {
    _pick(null);
    unawaited(openAdaptive(
      context,
      builder: (_) => ChatScreen.fromListItem(chat),
      slotKey: chatSlotKey(chat.id),
    ));
  }

  Widget _separator(BuildContext context) => Container(
    width: 24,
    height: 1,
    margin: const EdgeInsets.symmetric(vertical: 6),
    color: ThemeWorkspace.dividerColor(context),
  );
}

class _RailTile extends StatelessWidget {
  final Widget child;

  const _RailTile({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ThemeWorkspace.surface(context, GlitchColors.bgChip, tint: 0.30),
          borderRadius: AvatarShape.community.borderRadius(44),
        ),
        child: child,
      );
}

class _RailButton extends StatefulWidget {
  final bool? selected;

  final bool unread;
  final VoidCallback? onTap;
  final Widget child;

  final String? tooltip;

  final Widget? tooltipExtra;

  const _RailButton({
    super.key,
    required this.selected,
    this.unread = false,
    required this.onTap,
    required this.child,
    this.tooltip,
    this.tooltipExtra,
  });

  @override
  State<_RailButton> createState() => _RailButtonState();
}

class _RailButtonState extends State<_RailButton> {
  bool _hovered = false;

  EdgePillState get _pill {
    final selected = widget.selected;
    if (selected == null) return EdgePillState.none;
    if (selected) return EdgePillState.selected;
    if (_hovered) return EdgePillState.hover;
    return widget.unread ? EdgePillState.unread : EdgePillState.none;
  }

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            EdgePill(state: _pill),
            Expanded(
              child: Center(
                child: GlitchTooltip(
                  message: widget.tooltip,
                  extra: widget.tooltipExtra,
                  side: GlitchTooltipSide.right,
                  child: GlitchPressable(
                    onTap: onTap,
                    child: SizedBox(width: 46, height: 46, child: Center(child: widget.child)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceMark extends StatelessWidget {
  final int serverId;

  const _VoiceMark({required this.serverId});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: voiceChannels,
        builder: (context, _) => voiceChannels.inServer(serverId).isEmpty
            ? const SizedBox.shrink()
            : Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: GlitchColors.bgCard),
                child: const Icon(Icons.volume_up_rounded, size: 14, color: Colors.white),
              ),
      );
}

class _ServerVoicePeek extends StatelessWidget {
  final int serverId;

  const _ServerVoicePeek({required this.serverId});

  static const int _shown = 5;
  static const double _avatar = 22 * kTooltipScale;
  static const double _ring = 2 * kTooltipScale;
  static const double _overlap = 6 * kTooltipScale;
  static const double _gap = 6 * kTooltipScale;
  static const double _full = _avatar + _ring * 2;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: voiceChannels,
        builder: (context, _) {
          final people = voiceChannels.inServer(serverId);
          if (people.isEmpty) return const SizedBox.shrink();
          final shown = people.take(_shown).toList();
          final more = people.length - shown.length;
          return Padding(
            padding: const EdgeInsets.only(top: _gap),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.volume_up_rounded, size: 18.4 * kTooltipScale, color: GlitchColors.textNavIdle),
                const SizedBox(width: _gap),
                for (var i = 0; i < shown.length; i++)
                  Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: i == shown.length - 1 && more == 0 ? 1 : (_full - _overlap) / _full,
                    child: _ringed(_avatarOf(shown[i])),
                  ),
                if (more > 0)
                  Container(
                    height: _full,
                    constraints: const BoxConstraints(minWidth: _full),
                    padding: const EdgeInsets.symmetric(horizontal: _gap),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: GlitchColors.bgChip,
                      borderRadius: BorderRadius.circular(_full / 2),
                      border: Border.all(color: GlitchColors.bgMenu, width: _ring),
                    ),
                    child: Text(
                      '+$more',
                      style: TextStyle(fontSize: 11.5 * kTooltipScale, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary),
                    ),
                  ),
              ],
            ),
          );
        },
      );

  static Widget _ringed(Widget avatar) => Container(
        width: _full,
        height: _full,
        padding: const EdgeInsets.all(_ring),
        decoration: BoxDecoration(shape: BoxShape.circle, color: GlitchColors.bgMenu),
        child: avatar,
      );

  static Widget _avatarOf(VoiceStateInfo v) {
    final name = v.displayName ?? v.nickname ?? '';
    return GlitchAvatar(
      initials: GlitchAvatar.initialsFromName(name),
      size: _avatar,
      colorIndex: GlitchAvatar.colorFromNickname(v.nickname ?? name),
      imageUrl: v.avatar,
    );
  }
}

/// К выбору в полосе добавляется одно: снять всё, что лежит маршрутами поверх
/// главного экрана ([rootNavigator] — корневая навигация), иначе выбор
/// случился бы под ними и выглядел бы мёртвым. Дальше всё как при нажатии в
/// полосе: на широком окне колонка каналов сама откроет канал, на телефоне
/// человек увидит список каналов сообщества.
void revealServerInRail(NavigatorState rootNavigator, int id, {int? roomId, ChatArrival? arrival}) {
  rootNavigator.popUntil((route) => route.isFirst);
  if (shellController.hasListOverride) shellController.close(ShellSlot.list);
  if (roomId != null) {
    serverRail.openRoom(id, roomId, chosen: true, arrival: arrival);
  } else {
    serverRail.select(id);
  }
}
