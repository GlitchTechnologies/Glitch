import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../core/adaptive_open.dart';
import '../core/group_exit.dart';
import '../core/shell_controller.dart';
import '../core/shell_metrics.dart';
import '../core/l10n.dart';
import '../core/own_account_open.dart';
import '../core/search_open.dart';
import '../theme/app_theme.dart';
import '../widgets/theme_workspace.dart';
import '../theme/glitch_icons.dart';
import '../main.dart' show routeObserver;
import '../services/api_service.dart';
import '../services/current_screen.dart';
import '../models/chat.dart';
import '../models/folder.dart';
import '../providers/chats_provider.dart';
import '../providers/folders_provider.dart';
import '../providers/server_provider.dart' show serverRail;
import '../widgets/glitch_action_button.dart';
import '../widgets/glitch_avatar.dart';
import '../widgets/home_section_rows.dart';
import '../widgets/glitch_pressable.dart';
import '../core/collectibles.dart';
import '../widgets/glitch_toast.dart';
import '../widgets/list_selection.dart';
import '../widgets/message_interactions.dart' show confirmDeleteWithOption;
import 'chat_screen.dart';
import 'create_group_screen.dart';
import '../providers/theme_provider.dart';
import '../widgets/chat_preview_line.dart';
import '../widgets/glitch_tooltip.dart';
import '../widgets/glitch_icon_button.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});
  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> with WidgetsBindingObserver, RouteAware, ThemeAwareState<ChatsScreen> {
  late final ChatsProvider _provider;
  final Set<String> _cachedAvatarUrls = {};

  static const double _chatRowAvatarSize = 54;

  final _selection = SelectionController();

  final _folders = FoldersProvider();
  int _tabIndex = 0;
  final _pageCtrl = PageController();

  final _tabsStackKey = GlobalKey();
  final Map<int, GlobalKey> _tabKeys = {};
  List<({double left, double width})> _tabMetrics = [];

  GlobalKey _tabKey(int i) => _tabKeys.putIfAbsent(i, () => GlobalKey());

  void _measureTabs() {
    if (!mounted) return;
    final stackBox = _tabsStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null) return;
    final metrics = <({double left, double width})>[];
    for (var i = 0; i <= _folders.folders.length; i++) {
      final box = _tabKeys[i]?.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) {
        if (_folders.folders.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _measureTabs());
        }
        return;
      }
      metrics.add((left: box.localToGlobal(Offset.zero, ancestor: stackBox).dx, width: box.size.width));
    }
    var changed = metrics.length != _tabMetrics.length;
    if (!changed) {
      for (var i = 0; i < metrics.length; i++) {
        if (metrics[i] != _tabMetrics[i]) { changed = true; break; }
      }
    }
    if (changed) setState(() => _tabMetrics = metrics);
  }

  ChatFolder? get _currentFolder {
    final list = _folders.folders;
    if (_tabIndex <= 0 || _tabIndex > list.length) return null;
    return list[_tabIndex - 1];
  }

  bool _ensureScheduled = false;

  @override
  void initState() {
    super.initState();
    CurrentScreen.name = 'ChatsScreen';
    WidgetsBinding.instance.addObserver(this);
    _provider = ChatsProvider()..init();
    _provider.addListener(_onProviderChange);
    _selection.addListener(_onSelectionChanged);
    _folders.addListener(_onFoldersChanged);
    _folders.load();
    _scheduleEnsureChatOpen();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      routeObserver.subscribe(this, ModalRoute.of(context)!);
    });
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _provider.removeListener(_onProviderChange);
    _provider.dispose();
    _selection.removeListener(_onSelectionChanged);
    _selection.dispose();
    _folders.removeListener(_onFoldersChanged);
    _folders.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    _provider.load();
    _folders.load();
  }

  void _onProviderChange() {
    if (!mounted) return;
    if (_selection.selecting) {
      _selection.prune(_provider.chats.map((c) => c.id).toSet());
    }
    setState(() {});
    _precacheAvatars(_provider.chats);
    _scheduleEnsureChatOpen();
  }


  void _scheduleEnsureChatOpen() {
    if (_ensureScheduled) return;
    _ensureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureScheduled = false;
      _ensureChatOpen();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _ensureChatOpen() {
    if (!mounted) return;
    if (ShellPlace.slotOf(context) != ShellSlot.list) return;
    if (serverRail.space != null) return;
    if (spaceOfScope(shellController.mainScope) == null) return;
    if (_provider.loading || _folders.loading) return;
    final first = _folders.apply(_provider.chats, _currentFolder).firstOrNull;
    if (first != null) {
      _openChatFromList(first);
    } else {
      shellController.closeAll(ShellSlot.main);
    }
  }

  void _onSelectionChanged() {
    if (mounted) setState(() {});
  }

  void _onFoldersChanged() {
    if (!mounted) return;
    if (_tabIndex > _folders.folders.length) {
      _tabIndex = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageCtrl.hasClients) _pageCtrl.jumpToPage(0);
      });
    }
    setState(() {});
    _scheduleEnsureChatOpen();
  }

  void _goToTab(int i) {
    if (_tabIndex == i) return;
    if (_pageCtrl.hasClients) {
      _pageCtrl.animateToPage(i,
          duration: const Duration(milliseconds: 260), curve: Curves.easeInOut);
    } else {
      _selection.clear();
      setState(() => _tabIndex = i);
    }
  }

  int get _pinFolderId => _currentFolder?.id ?? FoldersProvider.allFolderId;

  List<SelectionAction> _selectionActions() {
    final sel = _selectedChats;
    final allPinned = sel.isNotEmpty && sel.every((c) => _folders.isPinned(_pinFolderId, c.id));
    return [
      SelectionAction(
        icon: allPinned ? Icons.push_pin : Icons.push_pin_outlined,
        onTap: _togglePinSelected,
      ),
      SelectionAction(
        icon: Icons.delete_outline_rounded,
        color: GlitchColors.error,
        onTap: _deleteSelected,
      ),
      SelectionAction(icon: Icons.more_vert_rounded, onTap: () => _stub(context.s.more)),
    ];
  }

  Future<void> _togglePinSelected() async {
    final sel = _selectedChats;
    if (sel.isEmpty) return;
    final pin = !sel.every((c) => _folders.isPinned(_pinFolderId, c.id));
    _selection.clear();
    try {
      await _folders.setPins(_pinFolderId, sel.map((c) => c.id).toList(), pin);
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    }
  }

  void _stub(String label) =>
      GlitchToast.show(context, context.s.comingSoon(label), type: ToastType.info);

  List<ChatListItem> get _selectedChats =>
      _provider.chats.where((c) => _selection.isSelected(c.id)).toList();

  Widget _dialogAvatar(ChatListItem chat) {
    final name = ChatsProvider.chatName(chat);
    return GlitchAvatar(
      initials: GlitchAvatar.initialsFromName(name),
      size: 40,
      colorIndex: GlitchAvatar.colorFromNickname(name),
      imageUrl: chat.avatar != null ? api.mediaUrl(chat.avatar!) : null,
      avatarSizes: chat.avatarSizes,
    );
  }

  Future<void> _deleteSelected() async {
    final sel = _selectedChats;
    if (sel.isEmpty) return;

    final personal = sel.where((c) => c.type == 'personal').toList();
    final owned    = sel.where((c) => c.type != 'personal' && c.isOwner);
    final groups   = sel.where((c) => c.type == 'group' && !c.isOwner);

    final lines = [
      if (personal.isNotEmpty) context.s.chatsDeleteHideLine,
      if (groups.isNotEmpty) context.s.chatsDeleteLeaveLine,
      if (owned.isNotEmpty) context.s.chatsDeleteOwnedLine,
    ];

    final single = sel.length == 1 && personal.length == 1 ? personal.first : null;

    final (confirmed, alsoForOther) = await confirmDeleteWithOption(
      context,
      title: context.s.chatsDeleteTitle(sel.length),
      body: lines.join('\n'),
      optionLabel: single == null
          ? null
          : context.s.chatsDeleteAlsoFor(ChatsProvider.chatName(single)),
      leading: single == null ? null : _dialogAvatar(single),
    );
    if (!confirmed || !mounted) return;
    _selection.clear();

    for (final c in sel) {
      try {
        if (c.type == 'personal') {
          await api.hideChat(c.id, forEveryone: alsoForOther);
        } else if (c.isOwner) {
          await api.deleteChat(c.id);
        } else {
          await leaveGroup(c.id);
        }
      } catch (e) {
        if (!mounted) return;
        GlitchToast.show(context, errorMessage(e));
      }
    }
    if (mounted) _provider.load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _provider.load();
    }
  }

  void _precacheAvatars(List<ChatListItem> chats) {
    final decodeSize = avatarDecodeSize(context, _chatRowAvatarSize);
    for (final chat in chats) {
      if (chat.avatar == null) continue;
      final url = api.mediaUrl(chat.avatar!);
      if (_cachedAvatarUrls.contains(url)) continue;
      _cachedAvatarUrls.add(url);
      precacheImage(
        ResizeImage(
          CachedNetworkImageProvider(url, cacheManager: mediaCacheManager),
          width: decodeSize,
          height: decodeSize,
        ),
        context,
      );
    }
  }

  Future<void> _openChatFromList(ChatListItem chat) async {
    await openAdaptive(
      context,
      builder: (_) => ChatScreen.fromListItem(chat),
      slotKey: chatSlotKey(chat.id),
    );
    if (!mounted) return;
    _provider.load();
  }

  Future<void> _createGroup() => openAdaptive(
        context,
        slot: ShellSlot.list,
        slotKey: 'create-group',
        builder: (_) => const CreateGroupScreen(),
      );

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return DateFormat('HH:mm').format(dt);
    }
    return DateFormat('dd.MM').format(dt);
  }

  Widget _buildNormalHeader() {
    return Row(
      children: [
        Expanded(
          child: GlitchActionButton(
            label: context.s.chatsFindOrStart,
            soft: true,
            onTap: () => openSearchWindow(context),
          ),
        ),
        const SizedBox(width: 4),
        GlitchTooltip(
          message: context.s.tipCreateGroup,
          side: GlitchTooltipSide.bottom,
          child: GlitchIconButton(
            icon: Icon(Icons.add_rounded, color: GlitchColors.textPrimary, size: 24),
            onTap: _createGroup,
          ),
        ),
        if (!isWideLayout(context))
          GlitchIconButton(
            icon: Icon(GlitchIcons.settings, color: GlitchColors.textPrimary, size: 22),
            onTap: () async {
              await openMySettings(context);
              if (mounted) _provider.load();
            },
          ),
      ],
    );
  }


  Widget _buildChatList(ChatFolder? folder) {
    final filtered = _folders.apply(_provider.chats, folder);
    final pinFolderId = folder?.id ?? FoldersProvider.allFolderId;
    return _provider.loading
        ? Center(child: CircularProgressIndicator(color: GlitchColors.accentBlue))
        : filtered.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(
                  folder != null ? Icons.folder_open_rounded : Icons.chat_bubble_outline_rounded,
                  color: GlitchColors.textHint, size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  folder != null ? context.s.folderEmpty : context.s.chatsEmpty,
                  style: TextStyle(color: GlitchColors.textSecond, fontSize: 17),
                ),
                if (folder == null) ...[
                  const SizedBox(height: 8),
                  Text(context.s.chatsEmptyHint, style: TextStyle(color: GlitchColors.textHint, fontSize: 14)),
                ],
              ]))
            : RefreshIndicator(
                onRefresh: _provider.load,
                color: GlitchColors.accentBlue,
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) {
                    final chat = filtered[i];
                    final name = ChatsProvider.chatName(chat);
                    final initials = GlitchAvatar.initialsFromName(name);
                    final colorIdx = GlitchAvatar.colorFromNickname(name);
                    final lastMsg = chat.lastMessage;

                    return SelectableRow(
                      controller: _selection,
                      id: chat.id,
                      // Наведение запускает анимацию украшения аватарки.
                      child: GlitchHoverArea(
                        onTap: null,
                        hoverWhenDisabled: true,
                        builder: (context, hovered) => InkWell(
                          onTap: () async {
                            await _openChatFromList(chat);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            child: Row(
                              children: [
                                GlitchAvatar(initials: initials, size: _chatRowAvatarSize, colorIndex: colorIdx,
                                    imageUrl: chat.avatar != null ? api.mediaUrl(chat.avatar!) : null,
                                    avatarSizes: chat.avatarSizes,
                                    showOnline: chat.isOnline,
                                    presenceUserId: chat.otherUserId,
                                    presenceBlocked: chat.presenceBlocked,
                                    personalPresence: true,
                                    presenceStatus: chat.type == 'personal' ? chat.presenceStatus : null,
                                    decoration: chat.avatarDecoration,
                                    animateDecoration: animateInList(hovered)),
                                const SizedBox(width: 13),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Row(
                                              children: [
                                                Flexible(child: Text(name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary), overflow: TextOverflow.ellipsis)),
                                              ],
                                            ),
                                          ),
                                          if (lastMsg != null) Text(_formatTime(lastMsg.createdAt), style: TextStyle(fontSize: 12.5, color: GlitchColors.textHint)),
                                          if (_folders.isPinned(pinFolderId, chat.id)) ...[
                                            const SizedBox(width: 5),
                                            Icon(Icons.push_pin_rounded, size: 14, color: GlitchColors.textHint),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: ChatPreviewLine(
                                              preview: lastMsg,
                                              style: TextStyle(fontSize: 14, color: GlitchColors.textSecond),
                                            ),
                                          ),
                                          if (chat.unreadCount > 0)
                                            Container(
                                              constraints: const BoxConstraints(minWidth: 20),
                                              height: 20,
                                              padding: const EdgeInsets.symmetric(horizontal: 6),
                                              decoration: BoxDecoration(color: GlitchColors.accentDark, borderRadius: BorderRadius.circular(10)),
                                              child: Center(child: Text('${chat.unreadCount}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
  }

  Widget _buildFolderTabs() {
    final folders = _folders.folders;
    if (folders.isEmpty) return const SizedBox.shrink();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureTabs());
    final measured = _tabIndex < _tabMetrics.length;
    return SizedBox(
      height: 49,
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        child: Stack(
          key: _tabsStackKey,
          children: [
            Row(
              children: [
                for (var i = 0; i <= folders.length; i++) // 0 — «Все»
                  _folderTab(
                    contentKey: _tabKey(i),
                    label: i == 0 ? context.s.foldersAll : folders[i - 1].name,
                    count: _folders.unreadCount(_provider.chats, i == 0 ? null : folders[i - 1]),
                    selected: _tabIndex == i,
                    onTap: () => _goToTab(i),
                  ),
              ],
            ),
            if (measured)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeInOut,
                left: _tabMetrics[_tabIndex].left,
                width: _tabMetrics[_tabIndex].width,
                bottom: 6.5,
                height: 2.7,
                child: Container(
                  decoration: BoxDecoration(
                    color: GlitchColors.accentBlue,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _folderTab({
    required GlobalKey contentKey,
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final color = selected ? GlitchColors.accentBlue : GlitchColors.textSecond;
    return ClickableCursor(child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          children: [
            Expanded(
              child: Center(
                widthFactor: 1, // ширина по содержимому: строка не ограничена по ширине
                child: Row(
                  key: contentKey, // по нему замеряется, куда ехать полоске
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeInOut,
                      style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: color),
                      child: Text(label),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 6.5),
                      Container(
                        constraints: const BoxConstraints(minWidth: 20),
                        height: 20,
                        padding: const EdgeInsets.symmetric(horizontal: 5.5),
                        decoration: BoxDecoration(
                          color: GlitchColors.bgInput,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Center(
                          child: Text('$count',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: GlitchColors.textSecond,
                              )),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 9.2),
          ],
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final sectionDivider = ThemeWorkspace.dividerColor(context);
    // Системная «назад» в режиме выделения снимает выделение, а не сворачивает
    // приложение (как в чате и в Telegram). WillPopScope, а не PopScope —
    // по той же причине, что в chat_screen (на части версий PopScope ещё нет).
    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: () async {
        if (_selection.selecting) {
          _selection.clear();
          return false;
        }
        return true;
      },
      child: Scaffold(
      backgroundColor: ThemeWorkspace.surface(context, GlitchColors.bg, tint: 0.22),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: kShellBarHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: sectionDivider)),
              ),
              padding: EdgeInsets.fromLTRB(_selection.selecting ? 4 : 10, 0, 4, 0),
              child: _selection.selecting
                  ? SelectionTopBar(controller: _selection, actions: _selectionActions())
                  : _buildNormalHeader(),
            ),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: HomeSectionRows(),
            ),
            Divider(height: 1, color: sectionDivider),

            _buildFolderTabs(),

            Expanded(
              child: _folders.folders.isEmpty
                  ? _buildChatList(_currentFolder)
                  : PageView.builder(
                      controller: _pageCtrl,
                      itemCount: _folders.folders.length + 1, // +1 — «Все»
                      onPageChanged: (i) {
                        _selection.clear();
                        setState(() => _tabIndex = i);
                      },
                      itemBuilder: (_, i) =>
                          _buildChatList(i == 0 ? null : _folders.folders[i - 1]),
                    ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
