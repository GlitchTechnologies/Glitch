import 'user_profile_screen.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:cross_file/cross_file.dart';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/current_screen.dart';
import '../services/keyboard_height.dart';
import '../models/gif.dart';
import '../models/presence.dart';
import '../services/user_presences.dart';
import '../models/sticker.dart';
import '../services/media_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show KeyDownEvent, KeyEvent, KeyEventResult, LogicalKeyboardKey;
import '../widgets/local_image_web.dart' if (dart.library.io) '../widgets/local_image_native.dart';
import 'package:intl/intl.dart';
import '../core/shell_metrics.dart';
import '../core/copy_actions.dart';
import '../core/permissions.dart';
import '../core/adaptive_open.dart';
import '../core/platform_info.dart' show hasPointerInput;
import '../core/glitch_link.dart' show messageLink;
import '../widgets/adaptive_shell.dart' show AdaptiveShell;
import '../core/shell_controller.dart' show ShellPlace, ShellSlot, shellController;
import '../models/server.dart';
import '../core/l10n.dart';
import '../core/file_size.dart';
import '../theme/app_theme.dart';
import '../widgets/theme_workspace.dart';
import '../theme/glitch_palette.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/auth_service.dart';
import '../services/keybinds.dart';
import '../services/websocket_service.dart';
import '../services/chat_viewing.dart';
import '../services/recent_places.dart';
import '../models/search.dart' show PlaceRef;
import '../providers/composer_drafts.dart';
import '../providers/message_composer.dart';
import '../providers/chat_provider.dart';
import '../providers/server_provider.dart' show serverRail;
import '../models/message.dart';
import '../models/bubble_data.dart';
import '../models/chat_arrival.dart';
import '../models/mention.dart';
import '../models/shared_content.dart';
import '../widgets/glitch_avatar.dart';
import '../widgets/presence_indicator.dart' show presenceColor;
import '../widgets/marquee_text.dart';
import '../widgets/glitch_menu.dart';
import '../widgets/dm_profile_panel.dart';
import '../widgets/member_card.dart';
import '../widgets/webhook_card.dart';
import '../widgets/server_roster_panel.dart';
import '../widgets/glitch_dialog.dart';
import '../widgets/poll_card.dart' show showPollVoters;
import '../widgets/glitch_pressable.dart';
import '../widgets/glitch_toast.dart';
import '../widgets/room_welcome_header.dart';
import 'room_settings_screen.dart' show openRoomSettings, roomSettingsAllowed;
import '../models/attach_result.dart' show PendingFile;
import '../widgets/message_bubble.dart';
import '../widgets/message_action_menu.dart';
import '../widgets/message_interactions.dart';
import '../widgets/pinned_banner.dart';
import '../widgets/call_stage.dart' show callInk, kCallBackground;
import '../widgets/chat_call_area.dart';
import '../widgets/record_handlers.dart';
import '../widgets/linked_text.dart';
import '../widgets/selectable_content.dart';
import '../widgets/mention_input.dart';
import '../widgets/video_thumb_preview.dart';
import 'forward_target_screen.dart';
import '../models/chat.dart' show ChatListItem;
import '../providers/chats_provider.dart' show ChatsProvider;
import '../providers/call_provider.dart';
import '../widgets/chat_background.dart';
import '../widgets/horizontal_drag.dart';
import '../widgets/anchored_feed.dart';
import '../widgets/viewport_gate.dart';
import '../widgets/chat_metrics.dart';
import '../widgets/message_row.dart';
import '../widgets/content_picker.dart';
import '../widgets/content_picker_dock.dart';
import '../widgets/gif_picker_sheet.dart' show sendGifFile;
import '../widgets/file_badge.dart';
import '../widgets/composer_input_bar.dart';
import '../widgets/composer_notice_bar.dart';
import 'group_screen.dart';
import 'media_viewer_screen.dart';
import '../providers/theme_provider.dart';
import '../widgets/glitch_tooltip.dart';
import '../widgets/glitch_icon_button.dart';

Future<void> forwardBubblesTo(BuildContext context, List<BubbleData> bubbles) async {
  if (bubbles.isEmpty) return;
  bubbles = bubbles.where((b) => b.isForwardable).toList();
  if (bubbles.isEmpty) return;
  await openForwardWindow(context, bubbles);
}

class ChatScreen extends StatefulWidget {
  final int? chatId;
  final String chatName;
  final int colorIndex;
  final bool isGroup;
  final String? otherNickname;
  final String? targetNickname;
  final String? avatarUrl;
  final Map<String, String>? avatarSizes;
  final bool? initialIsOnline;
  final PresenceStatus? initialPresenceStatus;
  final DateTime? initialLastSeen;
  /// С чем открыли: «Поделиться», текст из карточки участника
  /// (models/chat_arrival.dart). Обычно null. Принимается и при открытии, и
  /// когда переписку, уже открытую в центре, открыли снова с новым
  /// (`didUpdateWidget`) — см. [_ChatScreenState._receive].
  final ChatArrival? arrival;

  final bool isRoom;

  final Perms? roomPermissions;

  final int? roomServerId;

  final String? roomDescription;

  final int? initialMessageId;

  const ChatScreen({super.key, this.chatId, required this.chatName, required this.colorIndex, this.isGroup = false, this.isRoom = false, this.roomPermissions, this.roomServerId, this.roomDescription, this.initialMessageId, this.otherNickname, this.targetNickname, this.avatarUrl, this.avatarSizes, this.initialIsOnline, this.initialPresenceStatus, this.initialLastSeen, this.arrival});

  factory ChatScreen.fromRoom(Room room, {int? initialMessageId, ChatArrival? arrival}) {
    return ChatScreen(
      chatId: room.id,
      initialMessageId: initialMessageId,
      arrival: arrival,
      chatName: room.name,
      colorIndex: GlitchAvatar.colorFromNickname(room.name),
      isGroup: true,
      isRoom: true,
      roomPermissions: room.permissions,
      roomServerId: room.serverId,
      roomDescription: room.description,
    );
  }

  factory ChatScreen.fromListItem(ChatListItem item) {
    final name = ChatsProvider.chatName(item);
    return ChatScreen(
      chatId: item.id,
      chatName: name,
      colorIndex: GlitchAvatar.colorFromNickname(name),
      isGroup: item.type == 'group',
      otherNickname: item.otherNickname,
      avatarUrl: item.avatar != null ? api.mediaUrl(item.avatar!) : null,
      avatarSizes: item.avatarSizes,
      initialIsOnline: item.isOnline,
      initialPresenceStatus: item.otherUserId == null ? item.presenceStatus
          : userPresences.personalStatusOf(item.otherUserId!, item.presenceStatus,
              serverLastSeen: item.lastSeen, blocked: item.presenceBlocked),
      initialLastSeen: item.otherUserId == null ? item.lastSeen
          : userPresences.personalLastSeenOf(item.otherUserId!, item.lastSeen, blocked: item.presenceBlocked),
    );
  }

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

typedef _MessageActions = ({
  VoidCallback? onReply,
  VoidCallback? onForward,
  VoidCallback? onEdit,
  // Удаление целиком, без подтверждения — `deleteMessageByUser`.
  VoidCallback? onDelete,
  Future<void> Function(String emoji)? onReact,
  VoidCallback? onEndPoll,
});

class _ChatScreenState extends State<ChatScreen> with ThemeAwareState<ChatScreen>, MessageEditing<BubbleData, ChatScreen>, MessageJump<ChatScreen>, MessageReply<ChatScreen>, RecordHandlers<ChatScreen> {
  final _inputCtrl = MentionTextController();

  late final MentionAutocomplete _mentions =
      MentionAutocomplete(controller: _inputCtrl, chatId: () => _provider.chatId, focusNode: _inputFocus);
  final _inputFocus = FocusNode();
  bool _findingLastEdit = false;
  final _scrollCtrl = ScrollController();
  Timer? _draftTimer;
  Timer? _typingTimer;


  late final MessageComposer _composer;
  late final ChatProvider _provider;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<void>? _ownAddedSub;
  bool _autoPopped = false; // чтобы не вызвать pop дважды, если событие придёт ещё раз
  StreamSubscription<ServerGone>? _serverGoneSub;

  StreamSubscription<ServerRoomEvent>? _roomEventSub;

  StreamSubscription<int>? _roleChangeSub;

  /// Номер перепроверки — защита от устаревшего ответа: две перепроверки
  /// подряд (событие о ролях и тут же переподключение) могут ответить в
  /// обратном порядке, и старый ответ не должен затереть новый.
  int _recheckSeq = 0;

  bool _openingRoomSettings = false;

  String? _roomName;
  String? _roomTopic;
  bool _roomProfileSet = false;

  bool _callShown = false;

  bool get _callOnHeader => _callShown && !_searching;


  bool _dockOpen = false;
  bool _dockInstant = false;
  final _dockKey = GlobalKey<ContentPickerDockState>();
  final _dockSpace = ValueNotifier<double>(0);

  double _keyboardHold = 0;
  Timer? _holdTimer;

  bool get _ownsBottom => _dockShown || _keyboardHold > 0;

  bool get _dockShown => _dockOpen && _provider.canWrite;

  bool _searching = false;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  List<Message> _searchResults = [];
  bool _searchLoading = false;
  Timer? _searchDebounce;

  final Map<int, GlobalKey> _msgKeys = {};

  Map<int, ({Object inputs, Widget cell})> _feedCells = {};

  final ValueNotifier<int> _feedLaidOut = ValueNotifier<int>(0);
  void _onFeedLaidOut() {
    _feedLaidOut.value++;
    _scheduleShownReport();
  }

  bool _shownReportScheduled = false;

  void _scheduleShownReport() {
    if (_shownReportScheduled) return;
    _shownReportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _shownReportScheduled = false;
      if (mounted) _reportShown();
    });
  }

  void _reportShown() {
    final myId = authService.currentUser?.id;
    final messages = _provider.messages;
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      final id = m.id;
      if (id <= 0 || m.senderId == myId) continue; // своё или ещё отправляется
      final key = _msgKeys[id];
      if (key == null) continue;
      if (feedRowPlace(key) == FeedRowPlace.shown) {
        _provider.messagesShown(id);
        return;
      }
    }
  }
  @override
  Map<int, GlobalKey> get messageKeys => _msgKeys;

  String get _draftKey => '${ComposerDrafts.chatPrefix}${_provider.chatId ?? 'new_${widget.targetNickname}'}';

  @override
  void initState() {
    super.initState();
    CurrentScreen.name = 'ChatScreen';
    _composer = MessageComposer();
    _provider = ChatProvider(
      initialChatId: widget.chatId,
      isGroup: widget.isGroup,
      isRoom: widget.isRoom,
      roomServerId: widget.roomServerId,
      roomPermissions: widget.roomPermissions,
      targetNickname: widget.targetNickname,
      otherNickname: widget.otherNickname,
      composer: _composer,
      initialIsOnline: widget.initialIsOnline,
      initialPresenceStatus: widget.initialPresenceStatus,
      initialLastSeen: widget.initialLastSeen,
    );
    _provider.addListener(_onProviderChange);
    _recordRecent();
    _composer.addListener(_onComposerChange);
    bindVideoNoteLimit();
    _errorSub = _provider.errors.listen(_showError);
    _inputFocus.addListener(_onInputFocus);
    keyboardHeight.load();
    _ownAddedSub = _provider.ownMessageAdded.listen((_) => _scrollToBottom());
    if (_sidePanel != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoOpenSidePanel());
    }
    final roomServerId = widget.roomServerId;
    if (roomServerId != null) {
      _serverGoneSub = serverRail.serverGone.listen((gone) {
        if (gone.id == roomServerId) _closeBecauseGone();
      });
      _roomEventSub = serverRail.roomEvents.listen((e) {
        if (e.chatId != widget.chatId || !mounted) return;
        if (e.deleted) {
          _closeBecauseGone(toast: context.s.roomDeleted);
          return;
        }
        setState(() {
          _roomName = e.name;
          _roomTopic = e.description;
          _roomProfileSet = true;
        });
      });
      _roleChangeSub = serverRail.roleChanges.listen((id) {
        if (id == roomServerId) _recheckRoom();
      });
      // После переподключения перечитываем права, чтобы учесть пропущенные события.
      wsService.addReconnectListener(_recheckRoom);
    }
    _provider.init(aroundMessageId: widget.initialMessageId);
    _provider.openedAround?.then(_revealInitialMessage);
    _loadDraft();
    _composer.restoreAttachments(_draftKey);
    _inputCtrl.addListener(_scheduleDraftSave);
    _scrollCtrl.addListener(_onScroll);
    _receive(widget.arrival);
  }

  @override
  void didUpdateWidget(ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.arrival, oldWidget.arrival)) _receive(widget.arrival);
  }

  void _receive(ChatArrival? arrival) {
    if (arrival == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final shared = arrival.shared;
      if (shared != null && !shared.isEmpty) _applySharedContent(shared);
      final text = arrival.text?.trim() ?? '';
      if (text.isNotEmpty) _provider.sendText(text);
    });
  }

  void _applySharedContent(SharedContent s) {
    if (s.media.isNotEmpty) {
      _composer.stageSharedPhotos(context, s.media);
    } else if (s.file != null) {
      _composer.stageFile(context, PendingFile(
        file: s.file!,
        name: s.fileName ?? s.file!.path.split('/').last,
        size: s.fileSize ?? 0,
        mimeType: s.fileMime ?? 'application/octet-stream',
      ));
    }
    if (s.text.isNotEmpty) {
      _inputCtrl.text = s.text;
      _inputCtrl.selection = TextSelection.collapsed(offset: s.text.length);
    }
  }

  // Список reverse:true — "старое" физически на конце скролл-экстента,
  // "новое" у нулевой позиции. Тот же приём, что и в attach_sheet.dart
  // (подгрузка галереи): триггерим за 400px до края, не впритык. Повторные
  // вызовы во время загрузки провайдер отсекает сам (loadingOlder/Newer).
  // Ленту догрузка не двигает: вниз её везёт только своё новое сообщение
  // (ChatProvider.ownMessageAdded), а не рост списка.
  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    _scheduleShownReport();
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 400) _provider.loadMoreOlder();
    if (pos.pixels <= 400) _provider.loadMoreNewer();
  }

  int? _recordedRecent;

  void _recordRecent() {
    final id = _provider.chatId;
    if (id == null || id == _recordedRecent) return;
    _recordedRecent = id;
    recentPlaces.record(widget.isRoom ? PlaceRef.room(id) : PlaceRef.chat(id));
  }

  void _onProviderChange() {
    _recordRecent();
    if (_provider.chatDeleted) {
      _closeBecauseGone(toast: context.s.chatDeletedToast);
      return;
    }
    final left = _provider.leftReason;
    if (left != null) {
      _closeBecauseGone(toast: switch (left) {
        'removed' => context.s.groupRemovedToast,
        'deleted' => context.s.groupDeletedToast,
        _ => null,
      });
      return;
    }
    if (editing != null && !_provider.bubbles.any((b) => b.id == editing!.id)) {
      cancelEditing();
    }
    pruneReplyIfGone(_provider.bubbles.map((b) => b.id));
    if (!_provider.canWrite) {
      if (editing != null) cancelEditing();
      replyingTo = null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _recheckRoom() async {
    final serverId = widget.roomServerId;
    final chatId = widget.chatId;
    if (serverId == null || chatId == null) return;
    final seq = ++_recheckSeq;
    try {
      final room = await api.getRoom(serverId, chatId);
      if (!mounted || seq != _recheckSeq) return;
      _provider.applyRoomPermissions(room.permissions);
      setState(() {
        _roomName = room.name;
        _roomTopic = room.description;
        _roomProfileSet = true;
      });
    } on ApiException catch (e) {
      if (!mounted || seq != _recheckSeq) return;
      if (e.statusCode == 403) {
        _closeBecauseGone(toast: context.s.roomUnavailable);
      }
    }
  }

  void _showRoomTopic(String topic) {
    glitchInfo(
      context,
      title: _chatName,
      leading: Icon(Icons.tag_rounded, size: 22, color: GlitchColors.textSecond),
      content: SingleChildScrollView(
        child: SelectableContent(
          fillWidth: true,
          child: LinkedText(
            text: topic,
            baseStyle: GlitchDialog.bodyStyle,
            onLaunch: launchSmartUrl,
          ),
        ),
      ),
    );
  }

  String get _chatName => _roomName ?? widget.chatName;

  String? get _chatTopic => _roomProfileSet ? _roomTopic : widget.roomDescription;

  void _closeBecauseGone({String? toast}) {
    if (_autoPopped) return;
    _autoPopped = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (toast != null) GlitchToast.show(context, toast, type: ToastType.info);
      final route = ModalRoute.of(context);
      if (ShellPlace.slotOf(context) == null && route != null && route.isActive) {
        final nav = Navigator.of(context);
        nav.popUntil((r) => r == route);
        nav.pop();
      } else {
        closeAdaptive(context);
      }
    });
  }

  void _onComposerChange() {
    if (mounted) setState(() {});
  }

  void _showError(String msg) {
    if (mounted) GlitchToast.show(context, msg);
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _saveDraft();
    // Ключ черновика читает провайдер — до его dispose ниже.
    _composer.stashAttachments(_draftKey);
    _errorSub?.cancel();
    _ownAddedSub?.cancel();
    _feedLaidOut.dispose();
    _serverGoneSub?.cancel();
    _roomEventSub?.cancel();
    _roleChangeSub?.cancel();
    if (widget.roomServerId != null) wsService.removeReconnectListener(_recheckRoom);
    _provider.removeListener(_onProviderChange);
    _provider.dispose();
    _composer.removeListener(_onComposerChange);
    _composer.dispose();
    _typingTimer?.cancel();
    _inputCtrl.removeListener(_scheduleDraftSave);
    _mentions.dispose();
    _inputCtrl.dispose();
    _inputFocus.removeListener(_onInputFocus);
    _inputFocus.dispose();
    _dockSpace.dispose();
    _holdTimer?.cancel();
    _scrollCtrl.dispose();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    disposeMessageJump();
    super.dispose();
  }

  void _startSearch() => setState(() => _searching = true);

  void _stopSearch() {
    _searchDebounce?.cancel();
    _searchCtrl.clear();
    setState(() {
      _searching = false;
      _searchQuery = '';
      _searchResults = [];
      _searchLoading = false;
    });
  }

  void _onSearchChanged(String v) {
    _searchQuery = v.trim();
    _searchDebounce?.cancel();
    if (_searchQuery.isEmpty) {
      setState(() { _searchResults = []; _searchLoading = false; });
      return;
    }
    setState(() => _searchLoading = true);
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      final chatId = _provider.chatId;
      if (chatId == null) {
        if (mounted) setState(() { _searchResults = []; _searchLoading = false; });
        return;
      }
      try {
        final results = await api.searchChatMessages(chatId, _searchQuery);
        if (!mounted || _searchQuery.isEmpty) return;
        setState(() { _searchResults = results; _searchLoading = false; });
      } catch (e) {
        if (!mounted) return;
        setState(() => _searchLoading = false);
        GlitchToast.show(context, errorMessage(e));
      }
    });
  }

  @override
  ScrollController get jumpScrollController => _scrollCtrl;

  @override
  int jumpIndexFromBottom(int id) {
    final bubbles = _provider.bubbles;
    final i = bubbles.indexWhere((b) => b.id == id);
    return i < 0 ? -1 : bubbles.length - 1 - i;
  }

  @override
  Future<void> scrollOffscreenIntoView(int id) async {
    final ok = await _provider.jumpToMessage(id);
    if (!mounted) return;
    if (!ok) { GlitchToast.show(context, context.s.errorLoad); return; }
    await _revealInLoadedWindow(id);
  }

  Future<void> _revealInLoadedWindow(int id) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
    if (!await revealMessage(id) && mounted) {
      GlitchToast.show(context, context.s.errorLoad);
    }
  }

  Future<void> _revealInitialMessage(bool found) async {
    final id = widget.initialMessageId;
    if (!mounted || id == null) return;
    if (!found) {
      GlitchToast.show(context, context.s.messageNotFound);
      return;
    }
    highlightMessage(id);
    await _revealInLoadedWindow(id);
  }

  Future<void> _jumpToResult(Message msg) async {
    _stopSearch();
    await jumpToMessageId(msg.id);
  }

  bool _isMine(BubbleData bubble, int? myId) => bubble.senderId == myId;

  _MessageActions _actionsFor(BubbleData bubble, {required bool isMine}) {
    final canEdit = isMine && bubble.isEditable && _provider.canWrite;
    final canDelete = _provider.canDeleteMessage(bubble, isMine: isMine);
    return (
      onReply: _provider.canWrite && bubble.isReplyable ? () => _replyTo(bubble) : null,
      onForward: bubble.isForwardable ? () => forwardBubblesTo(context, [bubble]) : null,
      onEdit: canEdit ? () => startEditing(bubble) : null,
      onDelete: canDelete
          ? () => deleteMessageByUser(context, () => _provider.deleteMessage(bubble.id))
          : null,
      onReact: _provider.canReact ? (String emoji) => _react(bubble.id, emoji) : null,
      onEndPoll: isMine && bubble.type == 'poll' && !(bubble.poll?.isClosed(DateTime.now()) ?? true)
          ? () => _confirmEndPoll(bubble.id)
          : null,
    );
  }

  KeyEventResult _composerKey(KeyEvent event) {
    if (_mentions.handleKey(event) == KeyEventResult.handled) return KeyEventResult.handled;
    if (editing != null && event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      cancelEditing();
      return KeyEventResult.handled;
    }
    if (!keybinds.matchesPress(KeybindAction.editLastMessage, event)) return KeyEventResult.ignored;
    if (_findingLastEdit || !_canEditFromComposer) return KeyEventResult.ignored;
    unawaited(_editLastMessage());
    return KeyEventResult.handled;
  }

  bool get _canEditFromComposer => editing == null && _provider.canWrite &&
      _inputCtrl.text.trim().isEmpty && !_inputCtrl.value.composing.isValid &&
      replyingTo == null && _composer.selectedPhotos.isEmpty &&
      _composer.pendingFile == null && _composer.pendingGeo == null &&
      !_composer.isRecording;

  Future<void> _editLastMessage() async {
    final chatId = _provider.chatId;
    if (chatId == null) return;
    _findingLastEdit = true;
    try {
      final id = await api.getLastEditableMessageId(chatId);
      if (!mounted || _provider.chatId != chatId || !_inputFocus.hasFocus ||
          !_canEditFromComposer || id == null) return;
      if (!_provider.bubbles.any((b) => b.id == id)) {
        if (!await _provider.jumpToMessage(id)) return;
      }
      if (!mounted || _provider.chatId != chatId || !_inputFocus.hasFocus ||
          !_canEditFromComposer) return;
      for (final bubble in _provider.bubbles) {
        if (bubble.id == id && _actionsFor(bubble, isMine: _isMine(bubble, authService.currentUser?.id)).onEdit != null) {
          startEditing(bubble);
          return;
        }
      }
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    } finally {
      _findingLastEdit = false;
    }
  }

  Future<void> _confirmEndPoll(int messageId) async {
    final s = context.s;
    final ok = await glitchConfirm(context, title: s.pollEnd, body: s.pollEndConfirmBody, confirmLabel: s.pollEnd);
    if (!ok || !mounted) return;
    await _provider.endPoll(messageId);
  }

  Widget _buildMessageRow(BubbleData bubble, BubbleData? above, {required bool dividerAbove, required int? myId}) {
    final isMine = _isMine(bubble, myId);
    final confirmed = bubble.id > 0;
    final actions = confirmed ? _actionsFor(bubble, isMine: isMine) : null;
    return MessageRow(
      data: bubble,
      startsGroup: startsMessageGroup(bubble, above, dividerAbove: dividerAbove),
      highlighted: highlightedId == bubble.id,
      onMenu: actions == null ? null : (pos) => _showMessageMenu(pos, bubble, actions),
      onQuickReact: actions?.onReact,
      onReply: actions?.onReply,
      onForward: actions?.onForward,
      onEdit: actions?.onEdit,
      onSwipeReply: actions?.onReply,
      onAuthorTap: (anchor) {
        if (bubble.fromWebhook) {
          showWebhookCard(anchor, name: bubble.senderDisplayName, avatar: bubble.senderAvatar);
        } else {
          _openAuthor(bubble, anchor);
        }
      },
      onReplyTap: jumpToMessageId,
      onReactTap: confirmed ? (emoji) => _react(bubble.id, emoji) : null,
      child: bubble.type == 'system'
          ? SystemMessageText(
              data: bubble,
              onPersonTap: (anchor, person) => _openPerson(
                anchor,
                ServerUser(id: person.id, nickname: person.nickname, displayName: person.displayName),
              ),
            )
          : MessageBubble(
              data: bubble,
              isMine: isMine,
              uploadProgress: _composer.uploadProgress[bubble.id],
              uploadBytes: _composer.uploadBytes[bubble.id],
              onTranscribe: _provider.chatId != null ? () => api.transcribeMessage(_provider.chatId!, bubble.id) : null,
              onPollVote: (ids) => _provider.votePoll(bubble.id, ids),
              onPollVoters: _provider.chatId == null
                  ? null
                  : (answer) => showPollVoters(context, chatId: _provider.chatId!, messageId: bubble.id, answer: answer),
              onOpenPoll: jumpToMessageId,
              onMentionTap: (anchor, mention, rect) => _openPerson(
                anchor,
                ServerUser(id: mention.id!, nickname: mention.nickname!, displayName: mention.name),
                anchorRect: rect,
              ),
            ),
    );
  }

  Future<void> _showMessageMenu(Offset position, BubbleData bubble, _MessageActions actions) {
    final chatId = _provider.chatId;
    final copyText = bubble.type == 'text' ? (bubble.content ?? '') : (bubble.caption ?? '');
    return showMessageActionMenu(
      context: context,
      position: position,
      copyText: copyText,
      messageId: bubble.id,
      messageLink: chatId == null
          ? null
          : messageLink(serverId: widget.roomServerId, chatId: chatId, messageId: bubble.id),
      onDelete: actions.onDelete,
      onEdit: actions.onEdit,
      onReply: actions.onReply,
      onForward: actions.onForward,
      onPin: _isPinnable(bubble) ? () => _togglePin(bubble) : null,
      onEndPoll: actions.onEndPoll,
      isPinned: _provider.pin.isPinned(bubble.id),
      currentUserReaction: bubble.reactions.mine,
      onReact: actions.onReact ?? (emoji) => _react(bubble.id, emoji),
      allowReactions: actions.onReact != null,
    );
  }

  Future<void> _react(int messageId, String emoji) async {
    if (!_provider.canReact) {
      final idx = _provider.messages.indexWhere((m) => m.id == messageId);
      final mine = idx == -1 ? null : _provider.messages[idx].reactions.mine;
      if (mine != emoji) {
        GlitchToast.show(context, context.s.roomNoReactions);
        return;
      }
    }
    try {
      await _provider.toggleReaction(messageId, emoji);
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    }
  }


  void _openAuthor(BubbleData bubble, BuildContext avatarContext) => _openPerson(
        avatarContext,
        ServerUser(
          id: bubble.senderId,
          nickname: bubble.senderNickname,
          displayName: bubble.senderDisplayName,
          avatar: bubble.senderAvatar,
          avatarSizes: bubble.senderAvatarSizes,
          avatarDecoration: bubble.senderAvatarDecoration,
        ),
      );

  void _openPerson(BuildContext anchor, ServerUser user, {Rect? anchorRect}) {
    final serverId = widget.roomServerId;
    if (widget.isRoom && serverId != null) {
      showMemberCard(
        anchor,
        serverId: serverId,
        user: user,
        name: user.displayName,
        side: GlitchPopupSide.right,
        anchorRect: anchorRect,
      );
      return;
    }
    showUserProfile(context, nickname: user.nickname);
  }

  void _replyTo(BubbleData bubble) {
    cancelEditing(); // ответ и редактирование взаимоисключаемы
    startReply(bubble);
  }


  bool get _canPin => _provider.chatId != null && _provider.canPin;

  bool _isPinnable(BubbleData b) => _canPin && b.id > 0 && b.type != 'system';

  Future<void> _setPinned(BubbleData? bubble) async {
    try {
      await _provider.pin.set(bubble == null ? null : MessagePreview.fromBubble(bubble));
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    }
  }

  void _togglePin(BubbleData bubble) =>
      _setPinned(_provider.pin.isPinned(bubble.id) ? null : bubble);

  void _jumpToPinned() {
    final id = _provider.pin.pinned?.id;
    if (id != null) jumpToMessageId(id);
  }

  @override
  MentionTextController get editTextController => _inputCtrl;
  @override
  FocusNode get composerFocus => _inputFocus;
  @override
  String? editableContentOf(BubbleData b) => b.type == 'text' ? b.content : b.caption;
  @override
  List<Mention> editableMentionsOf(BubbleData b) => b.mentions;
  @override
  Future<bool> submitEdit(BubbleData b, String text) => _provider.editMessage(b.id, text);
  @override
  Future<void> onEditEmptied(BubbleData b) async {
    if (b.type == 'text') {
      final confirmed = await confirmDeleteMessage(context,
          title: context.s.messageDeleteTitle, body: context.s.messageDeleteBody);
      if (!mounted || !confirmed) return; // отменил — остаёмся в правке
      cancelEditing();
      await _provider.deleteMessage(b.id);
    } else {
      final ok = await _provider.editMessage(b.id, '');
      if (!mounted) return;
      if (ok) cancelEditing(); else GlitchToast.show(context, context.s.errorLoad);
    }
  }

  void _scheduleDraftSave() {
    if (editing != null) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 600), _saveDraft);
  }

  Future<void> _loadDraft() async {
    if (widget.arrival?.shared?.text.isNotEmpty ?? false) return;
    final draft = await composerDrafts.load(_draftKey);
    if (draft.isNotEmpty && mounted) {
      _inputCtrl.text = draft;
      _inputCtrl.selection = TextSelection.collapsed(offset: draft.length);
    }
  }

  Future<void> _saveDraft() async {
    if (editing != null) return; // не перетираем черновик текстом редактируемого
    await composerDrafts.save(_draftKey, _inputCtrl.wireText);
  }

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  Future<void> _openProfile() async {
    if (widget.isGroup && _provider.chatId != null) {
      await openAdaptive(
        context,
        slot: ShellSlot.details,
        slotKey: 'group:${_provider.chatId}',
        builder: (_) => GroupScreen(chatId: _provider.chatId!),
      );
    } else if (widget.otherNickname != null) {
      await showUserProfile(context, nickname: widget.otherNickname!);
      if (!mounted) return;
      _provider.checkChatBlocked();
    }
  }

  Future<void> _openRoster({bool ambient = false}) async {
    final serverId = widget.roomServerId;
    if (serverId == null) return;
    await openAdaptive(
      context,
      slot: ShellSlot.details,
      slotKey: _rosterSlotKey(serverId),
      detailsWidth: kRosterPanelWidth,
      ambient: ambient,
      scope: ServerScope(serverId),
      builder: (_) => ServerRosterPanel(serverId: serverId, roomId: widget.chatId),
    );
  }

  static String _rosterSlotKey(int serverId) => 'roster:$serverId';

  Future<void> _openDmProfile({bool ambient = false}) async {
    final nickname = widget.otherNickname;
    if (nickname == null) return;
    await openAdaptive(
      context,
      slot: ShellSlot.details,
      slotKey: _dmProfileSlotKey(nickname),
      detailsWidth: kDmProfilePanelWidth,
      ambient: ambient,
      builder: (_) => DmProfilePanel(
        nickname: nickname,
        onFullProfileClosed: () {
          if (mounted) _provider.checkChatBlocked();
        },
      ),
    );
  }

  static String _dmProfileSlotKey(String nickname) => 'dm_profile:$nickname';

  ({
    String key,
    bool Function() hidden,
    Future<void> Function(bool) remember,
    Future<void> Function({bool ambient}) open,
  })?
      get _sidePanel {
    final serverId = widget.roomServerId;
    if (widget.isRoom && serverId != null) {
      return (
        key: _rosterSlotKey(serverId),
        hidden: cache.loadRosterHidden,
        remember: cache.saveRosterHidden,
        open: _openRoster,
      );
    }
    final nickname = widget.otherNickname;
    if (!widget.isGroup && nickname != null) {
      return (
        key: _dmProfileSlotKey(nickname),
        hidden: cache.loadDmProfileHidden,
        remember: cache.saveDmProfileHidden,
        open: _openDmProfile,
      );
    }
    return null;
  }

  void _autoOpenSidePanel() {
    final panel = _sidePanel;
    if (!mounted || panel == null || _callShown) return;
    if (ShellPlace.slotOf(context) != ShellSlot.main) return;
    if (shellController.hasDetails) return;
    if (panel.hidden()) return;
    panel.open(ambient: true);
  }

  void _toggleSidePanel() {
    final panel = _sidePanel;
    if (panel == null || _callShown) return;
    if (shellController.detailsKey == panel.key &&
        AdaptiveShell.detailsFit(context, shellController.detailsWidth)) {
      panel.remember(true).catchError((_) {});
      shellController.close(ShellSlot.details);
      return;
    }
    panel.remember(false).catchError((_) {});
    panel.open();
  }

  void _onCallShown(bool shown) {
    if (!mounted) return;
    setState(() => _callShown = shown);
    final panel = _sidePanel;
    if (panel == null) return;
    if (shown) {
      if (shellController.detailsKey == panel.key) shellController.close(ShellSlot.details);
    } else {
      _autoOpenSidePanel();
    }
  }

  bool get _attachAvailable =>
      editing == null && (_provider.canAttach || _provider.canSendPolls);

  Future<void> _openAttach() async {
    if (!_attachAvailable) return;
    final poll = await _composer.openAttach(
      context,
      allowFiles: _provider.canAttach,
      allowPoll: _provider.canSendPolls,
    );
    if (poll == null || !mounted) return;
    final (rid, rp) = consumeReply();
    await _provider.sendPoll(poll, replyToId: rid, replyPreview: rp);
  }

  Future<void> _openContentPicker(BuildContext button) async {
    if (!isWideLayout(context)) {
      _toggleDock();
      return;
    }
    await openContentPicker(button, onEmoji: _insertEmoji, onGif: _sendGif, onSticker: _sendSticker);
    if (mounted) _inputFocus.requestFocus();
  }

  void _insertEmoji(String emoji) {
    final text = _inputCtrl.text;
    final sel = _inputCtrl.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    _inputCtrl.value = TextEditingValue(
      text: text.replaceRange(start, end, emoji),
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  void _sendGif(GifItem gif) => sendGifFile(context, gif, (file) => _provider.sendWithPhotos([file], null));

  void _sendSticker(Sticker sticker) {
    final (rid, rp) = consumeReply();
    _provider.sendSticker(sticker, replyToId: rid, replyPreview: rp);
  }

  void _toggleDock() {
    if (_dockOpen) {
      _inputFocus.requestFocus();
      return;
    }
    _holdTimer?.cancel();
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0 || _keyboardHold > 0;
    _dockSpace.value = keyboardUp ? math.max(_keyboardHold, _visibleKeyboard()) : 0;
    setState(() {
      _dockInstant = keyboardUp;
      _keyboardHold = 0;
      _dockOpen = true;
    });
    _inputFocus.unfocus();
  }

  void _onInputFocus() {
    if (!_inputFocus.hasFocus || !_dockOpen) return;
    setState(() {
      _keyboardHold = _dockSpace.value;
      _dockOpen = false;
    });
    _holdTimer?.cancel();
    _holdTimer = Timer(const Duration(milliseconds: 600), _releaseKeyboardHold);
  }

  void _releaseKeyboardHold() {
    _holdTimer?.cancel();
    if (mounted && _keyboardHold > 0) setState(() => _keyboardHold = 0);
  }

  void _closeDock() => _dockKey.currentState?.close();

  double _visibleKeyboard() => math.max(
      0.0, MediaQuery.viewInsetsOf(context).bottom - MediaQuery.viewPaddingOf(context).bottom);

  Future<void> _onSend() async {
    if (editing != null) { await applyEdit(); return; } // режим редактирования
    if (_composer.selectedPhotos.isNotEmpty) await _sendWithPhotos();
    else if (_composer.pendingFile != null) await _sendWithFile();
    else if (_composer.pendingGeo != null) await _sendGeo();
    else await _sendText();
  }


  Future<void> _sendText() async {
    final text = _inputCtrl.wireText.trim();
    if (text.isEmpty || _provider.sending) return;
    final (rid, rp) = consumeReply();
    _inputCtrl.clear();
    _saveDraft();
    await _provider.sendText(text, replyToId: rid, replyPreview: rp);
  }

  Future<void> _sendWithPhotos() async {
    final photos = List<XFile>.from(_composer.selectedPhotos);
    final caption = _inputCtrl.wireText.trim();
    final (rid, rp) = consumeReply();
    _inputCtrl.clear();
    _saveDraft();
    _composer.clearAttachments();
    await _provider.sendWithPhotos(photos, caption.isNotEmpty ? caption : null, replyToId: rid, replyPreview: rp);
  }

  Future<void> _sendGeo() async {
    final geo = _composer.pendingGeo;
    if (geo == null) return;
    final caption = _inputCtrl.wireText.trim();
    final (rid, rp) = consumeReply();
    _inputCtrl.clear();
    _saveDraft();
    _composer.clearAttachments();
    await _provider.sendGeo(geo, caption.isNotEmpty ? caption : null, replyToId: rid, replyPreview: rp);
  }

  Future<void> _sendWithFile() async {
    final pf = _composer.pendingFile;
    if (pf == null) return;
    final text = _inputCtrl.wireText.trim();
    final (rid, rp) = consumeReply();
    _inputCtrl.clear();
    _saveDraft();
    _composer.clearAttachments();
    await _provider.sendWithFile(pf, null, replyToId: rid, replyPreview: rp);
    if (text.isNotEmpty) await _provider.sendText(text);
  }

  void _onTyping(String text) {
    final chatId = _provider.chatId;
    if (chatId == null) return;
    if (editing != null) return; // редактирование — не «печатает…» для собеседника
    if (text.isNotEmpty) {
      wsService.sendTypingStart(chatId);
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 2), () => wsService.sendTypingStop(chatId));
    } else {
      _typingTimer?.cancel();
      _typingTimer = null;
      wsService.sendTypingStop(chatId);
    }
  }

  List<Widget> _feedChildren(int? myId) {
    final bubbles = _provider.bubbles;
    final cells = <int, ({Object inputs, Widget cell})>{};
    final rows = <Widget>[];
    for (var i = 0; i < bubbles.length; i++) {
      final bubble = bubbles[i];
      final cell = _feedRow(bubble, i > 0 ? bubbles[i - 1] : null, divider: _showDateSeparator(i), myId: myId);
      cells[bubble.id] = cell;
      rows.add(cell.cell);
    }
    _feedCells = cells;
    _msgKeys.removeWhere((id, _) => !cells.containsKey(id));
    return [
      if (_provider.loadingOlder) KeyedSubtree(key: const ValueKey('feed-older'), child: _buildEdgeSpinner()),
      if (widget.isRoom && !_provider.hasMoreOlder && !_provider.loadingOlder)
        KeyedSubtree(key: const ValueKey('feed-room-welcome'), child: _buildRoomWelcome()),
      ...rows,
      if (_provider.typingVisible) KeyedSubtree(key: const ValueKey('feed-typing'), child: _buildTyping()),
      if (_provider.loadingNewer) KeyedSubtree(key: const ValueKey('feed-newer'), child: _buildEdgeSpinner()),
    ];
  }

  Widget _buildRoomWelcome() {
    final perms = _provider.roomPermissions;
    return RoomWelcomeHeader(
      roomName: _chatName,
      onSetup: perms != null && roomSettingsAllowed(perms) ? _openRoomSettingsFromFeed : null,
      setupLoading: _openingRoomSettings,
    );
  }

  Future<void> _openRoomSettingsFromFeed() async {
    final serverId = widget.roomServerId;
    final chatId = widget.chatId;
    if (serverId == null || chatId == null || _openingRoomSettings) return;
    setState(() => _openingRoomSettings = true);
    try {
      final room = await api.getRoom(serverId, chatId);
      if (!mounted) return;
      openRoomSettings(context, room);
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _openingRoomSettings = false);
    }
  }

  ({Object inputs, Widget cell}) _feedRow(BubbleData bubble, BubbleData? above,
      {required bool divider, required int? myId}) {
    final isMine = _isMine(bubble, myId);
    final Object inputs = (
      bubble,
      above,
      divider,
      isMine,
      highlightedId == bubble.id,
      _provider.canWrite,
      _provider.canReact,
      _provider.canDeleteMessage(bubble, isMine: isMine),
      _provider.chatId,
      _composer.uploadProgress[bubble.id],
      _composer.uploadBytes[bubble.id],
      themeProvider.palette,
      Localizations.localeOf(context),
    );
    final cached = _feedCells[bubble.id];
    if (cached != null && cached.inputs == inputs) return cached;
    final cell = Column(
      key: _msgKeys.putIfAbsent(bubble.id, () => GlobalKey()),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (divider) DateDivider(bubble.createdAt, key: const ValueKey('divider')),
        KeyedSubtree(
          key: const ValueKey('row'),
          child: _buildMessageRow(bubble, above, dividerAbove: divider, myId: myId),
        ),
      ],
    );
    return (inputs: inputs, cell: cell);
  }

  bool _showDateSeparator(int index) {
    final bubbles = _provider.bubbles;
    return needsDateSeparator(
      bubbles[index].createdAt,
      index > 0 ? bubbles[index - 1].createdAt : null,
    );
  }

  bool get _hasBackStep => ShellPlace.slotForBuild(context) != ShellSlot.main;

  @override
  Widget build(BuildContext context) {
    final myId = authService.currentUser?.id;
    final initials = GlitchAvatar.initialsFromName(_chatName);

    return ChatOnScreen(
      chatId: _provider.chatId,
      // ignore: deprecated_member_use
      child: WillPopScope(
      onWillPop: () async {
        if (_dockOpen) {
          _closeDock();
          return false;
        }
        if (editing != null) {
          cancelEditing(); // «назад» при редактировании — отмена, не выход с экрана
          return false;
        }
        if (replyingTo != null) {
          setState(() => replyingTo = null);
          return false;
        }
        return true;
      },
      child: SwipeBackScope(
        enabled: _hasBackStep && !hasPointerInput,
        onBack: () => closeAdaptive(context),
        child: _KeyboardProbe(
          hold: _keyboardHold,
          onKeyboardUp: _releaseKeyboardHold,
          child: Scaffold(
      backgroundColor: ThemeWorkspace.surface(context, GlitchColors.bg),
      resizeToAvoidBottomInset: !_ownsBottom,
      body: SafeArea(
        bottom: !_ownsBottom,
        child: LayoutBuilder(
          builder: (context, box) => Stack(
          children: [
        Column(
          key: const ValueKey('chat-column'),
          children: [
            Container(
              key: const ValueKey('chat-header'),
              height: kShellBarHeight,
              alignment: Alignment.center,
              padding: const EdgeInsets.fromLTRB(4, 0, 14, 0),
              decoration: BoxDecoration(
                color: _callOnHeader
                    ? kCallBackground
                    : ThemeWorkspace.surface(context, GlitchColors.bg, tint: ThemeWorkspace.barTint),
                border: Border(
                  bottom: BorderSide(
                    color: _callOnHeader
                        ? kCallBackground
                        : ThemeWorkspace.surface(context, GlitchColors.border),
                  ),
                ),
              ),
              child: _searching ? _buildSearchBar() : _buildChatHeader(initials),
            ),

            if (!widget.isRoom && widget.chatId != null)
              ChatCallArea(
                key: ValueKey('call-area-${widget.chatId}'),
                chatId: widget.chatId!,
                chatName: _chatName,
                onShownChanged: _onCallShown,
              ),

            if (!_searching && _provider.pin.pinned != null)
              PinnedBanner(
                key: const ValueKey('chat-pinned'),
                title: context.s.pinnedMessage,
                preview: _provider.pin.pinned!,
                onTap: _jumpToPinned,
                onUnpin: _canPin ? () => _setPinned(null) : null,
              ),

            Expanded(
              key: const ValueKey('chat-list'),
              child: SwipeBackArea(
                child: ChatBackground(
              child: _searching
                  ? _buildSearchResults()
                  : _provider.loading
                  ? Center(child: CircularProgressIndicator(color: GlitchColors.accentBlue))
                  : SelectableContent(
                      child: ChatContentWidth.scrollable(
                        builder: (_, sideInset) => SingleChildScrollView(
                          controller: _scrollCtrl,
                          reverse: true,
                          child: ViewportGateScope(
                            relayout: _feedLaidOut,
                            child: AnchoredFeed(
                              controller: _scrollCtrl,
                              anchors: _msgKeys.values,
                              onLaidOut: _onFeedLaidOut,
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                    sideInset + kFeedSidePadding, 8, sideInset + kFeedSidePadding, 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: _feedChildren(myId),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ),
              ),
            ),

            if (!_provider.canWrite)
              _provider.chatBlocked
                  ? ComposerNoticeBar(
                      icon: Icons.block_rounded,
                      text: context.s.chatBlockedBanner,
                      color: GlitchColors.error,
                    )
                  : ComposerNoticeBar(
                      icon: Icons.lock_outline_rounded,
                      text: context.s.roomNoSendBanner,
                      color: GlitchColors.textPrimary,
                    )
            else
            Container(
              decoration: BoxDecoration(
                color: ThemeWorkspace.surface(context, GlitchColors.bg, tint: ThemeWorkspace.barTint),
                border: Border(
                  top: BorderSide(color: ThemeWorkspace.surface(context, GlitchColors.borderSoft)),
                ),
              ),
              child: ChatContentWidth(
              child: TextFieldTapRegion(
              child: MentionSuggestions(
              autocomplete: _mentions,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (editing != null) buildEditBanner(),
                  if (replyingTo != null) replyComposerBanner(context),
                  if (!_composer.isRecording) ...[
                    if (_composer.selectedPhotos.isNotEmpty) _buildPhotoPicker(),
                    if (_composer.pendingFile != null) _buildFilePicker(),
                    if (_composer.pendingGeo != null) _buildGeoPicker(),
                  ],
                  ComposerInputBar(
                    controller: _inputCtrl,
                    focusNode: _inputFocus,
                    composer: _composer,
                    hintText: _composer.selectedPhotos.isNotEmpty ? context.s.inputHintCaptionPhoto : _composer.pendingFile != null ? context.s.inputHintCaptionFile : _composer.pendingGeo != null ? context.s.inputHintCaptionGeo : context.s.inputHintMessage,
                    onChanged: _onTyping,
                    onAttach: _attachAvailable ? _openAttach : null,
                    onContentPicker: _openContentPicker,
                    contentPickerOpen: _dockOpen,
                    disableAttachments: editing != null || !_provider.canAttach,
                    forceSendButton: editing != null,
                    onSend: _onSend,
                    onKey: _composerKey,
                    onRecordStart: handleRecordStart,
                    onRecordEnd: handleRecordEnd,
                    onRecordCancel: handleRecordCancel,
                    allowVideoNote: true, // кружки пока только в чатах
                  ),
                ],
              ),
              ),
              ),
              ),
            ),
            if (_ownsBottom)
              _ComposerBottomSpace(key: const ValueKey('composer-bottom-space'), dock: _dockSpace, hold: _keyboardHold),
          ],
        ),
            if (_dockShown)
              Positioned.fill(
                key: const ValueKey('content-picker-dock'),
                child: ContentPickerDock(
                  key: _dockKey,
                  height: _dockHeight(box.maxHeight),
                  maxHeight: box.maxHeight - kShellBarHeight - MediaQuery.viewPaddingOf(context).bottom,
                  instant: _dockInstant,
                  space: _dockSpace,
                  onClosed: () {
                    if (mounted) setState(() => _dockOpen = false);
                  },
                  child: ContentPicker(
                    onEmoji: _insertEmoji,
                    onGif: (gif) {
                      _closeDock();
                      _sendGif(gif);
                    },
                    onSticker: (sticker) {
                      _closeDock();
                      _sendSticker(sticker);
                    },
                  ),
                ),
              ),
          ],
          ),
        ),
      ),
      ),
      ),
      ),
      ),
    );
  }

  double _dockHeight(double available) =>
      math.min(keyboardHeight.value ?? available * 0.42, available * 0.6);

  Future<void> _startCall() async {
    var id = widget.chatId;
    if (id == null) {
      if (!await _provider.ensureChatCreated()) return;
      id = _provider.chatId;
      if (id == null) return;
    }
    callProvider.startCall(
      chat: id,
      name: _chatName,
      avatar: widget.avatarUrl,
      group: widget.isGroup && !widget.isRoom,
    );
  }

  Widget _buildChatHeader(String initials) {
    // Стрелка ОСТАЁТСЯ там, где переписка — отдельный экран поверх другого:
    // на телефоне (в браузере на телефоне системного «назад» нет, стрелка —
    // единственный путь к списку) и в широком окне, когда переписку открыли
    // маршрутом поверх всего каркаса (ссылка из экрана поверх, «Поделиться»
    // из другого приложения). Отличаем по месту в каркасе, а не по ширине:
    // экраны ширину не спрашивают, они спрашивают каркас о себе. Во время
    // звонка шапка лежит на чёрном (см. build) — текст и значки из палитры
    // звонка, иначе в светлой теме тёмное пропало бы на чёрном.
    final GlitchPalette ink = _callOnHeader ? callInk : themeProvider.palette;
    final noBack = !_hasBackStep;
    return Row(
      children: [
        if (noBack)
          const SizedBox(width: 12)
        else
          GlitchIconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: GlitchColors.accentBlue, size: 22),
            onTap: () => closeAdaptive(context),
          ),
        if (widget.isRoom)
          Builder(builder: (context) {
            final topic = _chatTopic;
            final hasTopic = topic != null && topic.isNotEmpty;
            return Expanded(
              child: Row(
                children: [
                  Icon(Icons.tag_rounded, size: 22, color: ink.textSecond),
                  const SizedBox(width: 8),
                  if (hasTopic)
                    Text(
                      _chatName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: ink.textPrimary),
                    )
                  else
                    Expanded(
                      child: MarqueeText(
                        _chatName,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: ink.textPrimary),
                      ),
                    ),
                  if (hasTopic) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text('·', style: TextStyle(fontSize: 16, color: ink.textSecond)),
                    ),
                    Expanded(
                      child: ClickableCursor(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _showRoomTopic(topic),
                          child: Text(
                            topic,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13.5, color: ink.textSecond),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          })
        else
        Expanded(
          child: ClickableCursor(child: GestureDetector(
            onTap: _openProfile,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                GlitchAvatar(initials: initials, size: 42, colorIndex: widget.colorIndex,
                    imageUrl: widget.avatarUrl, avatarSizes: widget.avatarSizes),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MarqueeText(_chatName, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: ink.textPrimary)),
                      if (widget.isGroup)
                        Text(context.s.group, style: TextStyle(fontSize: 12.5, color: ink.textSecond))
                      else if (_provider.presenceText(context).isNotEmpty)
                        Text(
                          _provider.presenceText(context),
                          style: TextStyle(fontSize: 12.5, color: presenceColor(context, _provider.presenceStatus)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        )),
        if (!widget.isRoom &&
            (widget.chatId != null || widget.targetNickname != null) &&
            !_provider.chatBlocked)
          GlitchTooltip(
            message: context.s.tipStartCall,
            side: GlitchTooltipSide.bottom,
            child: GlitchIconButton(
              icon: Icon(Icons.call_rounded, color: GlitchColors.accentBlue, size: 23),
              onTap: _startCall,
            ),
          ),
        if (widget.isRoom && widget.roomServerId != null)
          ListenableBuilder(
            listenable: shellController,
            builder: (context, _) => GlitchTooltip(
              message: _sidePanel != null && shellController.detailsKey == _sidePanel?.key
                  ? context.s.tipCloseMemberList
                  : context.s.tipOpenMemberList,
              side: GlitchTooltipSide.bottom,
              child: GlitchIconButton(
                icon: Icon(Icons.people_alt_outlined, color: ink.textPrimary, size: 23),
                onTap: _toggleSidePanel,
              ),
            ),
          ),
        if (!widget.isRoom && _sidePanel != null && ShellPlace.slotForBuild(context) == ShellSlot.main)
          ListenableBuilder(
            listenable: shellController,
            builder: (context, _) => GlitchTooltip(
              message: shellController.detailsKey == _sidePanel?.key
                  ? context.s.tipCloseProfilePanel
                  : context.s.tipOpenProfilePanel,
              side: GlitchTooltipSide.bottom,
              child: GlitchIconButton(
                icon: Icon(Icons.account_circle_outlined, color: ink.textPrimary, size: 23),
                onTap: _callShown ? null : _toggleSidePanel,
              ),
            ),
          ),
        GlitchTooltip(
          message: context.s.tipMore,
          side: GlitchTooltipSide.bottom,
          child: GlitchMenuButton<String>(
            icon: Icon(Icons.more_horiz_rounded, color: ink.textPrimary, size: 26),
            onSelected: (v) {
              if (v == 'search') _startSearch();
            },
            itemBuilder: (_) => [
              GlitchMenuItem(
                value: 'search',
                child: Row(children: [
                  Icon(Icons.search_rounded, color: ink.textPrimary, size: 18),
                  const SizedBox(width: 10),
                  Text(context.s.search, style: TextStyle(color: ink.textPrimary, fontSize: 15)),
                ]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Row(
      children: [
        GlitchIconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: GlitchColors.accentBlue),
          onTap: _stopSearch,
        ),
        Expanded(
          child: TextField(
            controller: _searchCtrl,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            style: TextStyle(color: GlitchColors.textPrimary, fontSize: 16),
            decoration: InputDecoration(
              hintText: context.s.chatSearchHint,
              hintStyle: TextStyle(color: GlitchColors.textHint, fontSize: 16),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: true,
              fillColor: Colors.transparent,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: _onSearchChanged,
          ),
        ),
        if (_searchQuery.isNotEmpty)
          GlitchIconButton(
            icon: Icon(Icons.close_rounded, size: 20),
            onTap: () {
              _searchCtrl.clear();
              _onSearchChanged('');
            },
          ),
      ],
    );
  }

  Widget _buildSearchResults() {
    if (_searchQuery.isEmpty) return const SizedBox.shrink();
    if (_searchLoading) {
      return Center(child: CircularProgressIndicator(color: GlitchColors.accentBlue));
    }
    if (_searchResults.isEmpty) {
      return Center(
        child: Text(context.s.chatsNothingFound, style: TextStyle(color: GlitchColors.textSecond, fontSize: 14)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _searchResults.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: GlitchColors.borderSoft, indent: 16, endIndent: 16),
      itemBuilder: (_, i) {
        final msg = _searchResults[i];
        // Текст строки — общим правилом превью (как список чатов и цитата):
        // у текста — он сам, у медиа — подпись, иначе название вида.
        final snippet = bubblePreviewText(context, msg.type, msg.toBubble().previewText);
        final isMine = msg.senderId == authService.currentUser?.id;
        return GlitchPressable(
          onTap: () => _jumpToResult(msg),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isMine ? context.s.you : _chatName,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: GlitchColors.accentBlue),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        snippet,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14.5, color: GlitchColors.textPrimary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(DateFormat('dd.MM HH:mm').format(msg.createdAt), style: TextStyle(fontSize: 12, color: GlitchColors.textHint)),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  MessageComposer get recordComposer => _composer;

  @override
  bool get canRecord => editing == null; // в режиме правки кнопка и так «отправить»

  @override
  Future<void> onVoiceRecorded(PendingVoice pv) async {
    final (rid, rp) = consumeReply();
    await _provider.sendVoice(pv, replyToId: rid, replyPreview: rp);
  }

  @override
  Future<void> onVideoNoteRecorded(PendingVideoNote note) async {
    final (rid, rp) = consumeReply();
    await _provider.sendVideoNote(note, replyToId: rid, replyPreview: rp);
  }

  String _attachLabel() {
    final photos = _composer.selectedPhotos;
    final n = photos.length;
    final videos = photos.where(_composer.isVideo).length;
    final stills = n - videos;
    if (videos == 0) return '$n фото';
    if (stills == 0) return '$n видео';
    return '$stills фото, $videos видео';
  }

  Widget _buildPhotoPicker() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Container(
        decoration: BoxDecoration(
          color: GlitchColors.bgCard,
          border: Border.all(color: GlitchColors.borderCard),
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 62,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _composer.selectedPhotos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (ctx, i) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      GestureDetector(
                        onTap: () => openLocalMediaGallery(
                          context,
                          _composer.selectedPhotos,
                          initialIndex: i,
                          isVideo: _composer.isVideo,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: _composer.isVideo(_composer.selectedPhotos[i])
                              ? _VideoThumbPreview(
                                  file: _composer.selectedPhotos[i],
                                  size: 62,
                                  duration: _composer.videoDurations[_composer.selectedPhotos[i].path],
                                )
                              : localImage(_composer.selectedPhotos[i].path, width: 62, height: 62, fit: BoxFit.cover),
                        ),
                      ),
                      Positioned(
                        top: -4, right: -4,
                        child: GestureDetector(
                          onTap: () => _composer.removePhoto(i),
                          child: Container(
                            width: 18, height: 18,
                            decoration: BoxDecoration(
                              color: GlitchColors.error,
                              shape: BoxShape.circle,
                              border: Border.all(color: GlitchColors.bgCard, width: 1.5),
                            ),
                            child: const Icon(Icons.close, color: Colors.white, size: 11),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _attachLabel(),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary),
                ),
                ClickableCursor(
                  child: GestureDetector(
                    onTap: _composer.clearAttachments,
                    child: Text(context.s.cancel, style: TextStyle(fontSize: 12.5, color: GlitchColors.textSecond)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilePicker() {
    final pf = _composer.pendingFile!;
    final sizeStr = formatBytes(context.s, pf.size);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Container(
        decoration: BoxDecoration(
          color: GlitchColors.bgCard,
          border: Border.all(color: GlitchColors.borderCard),
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            FileBadge(pf.name),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pf.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(sizeStr, style: TextStyle(fontSize: 12, color: GlitchColors.textSecond)),
                ],
              ),
            ),
            ClickableCursor(
              child: GestureDetector(
                onTap: _composer.clearAttachments,
                child: Container(
                  width: 28, height: 28,
                  decoration: const BoxDecoration(color: GlitchColors.error, shape: BoxShape.circle),
                  child: const Icon(Icons.close, color: Colors.white, size: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeoPicker() {
    final geo = _composer.pendingGeo!;
    final mapUrl = 'https://static-maps.yandex.ru/1.x/'
        '?ll=${geo.lon.toStringAsFixed(6)},${geo.lat.toStringAsFixed(6)}'
        '&z=14&size=400,120&l=map'
        '&pt=${geo.lon.toStringAsFixed(6)},${geo.lat.toStringAsFixed(6)},pm2rdl'
        '&lang=ru_RU';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Container(
        decoration: BoxDecoration(color: GlitchColors.bgCard, border: Border.all(color: GlitchColors.borderCard), borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            SizedBox(
              height: 80,
              width: double.infinity,
              child: CachedNetworkImage(
                imageUrl: mapUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: const Color(0xFF1a2218),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: GlitchColors.accentBlue))),
                errorWidget: (_, __, ___) => Container(color: const Color(0xFF1a2218),
                  child: const Center(child: Icon(Icons.location_on_rounded, color: Color(0xFF4caf50), size: 32))),
              ),
            ),
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                color: GlitchColors.bgCard,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.location_on_rounded, color: Color(0xFF4caf50), size: 18),
                    const SizedBox(width: 6),
                    Expanded(child: Text(
                      context.s.geoLabel('${geo.lat.toStringAsFixed(4)}, ${geo.lon.toStringAsFixed(4)}'),
                      style: TextStyle(fontSize: 13, color: GlitchColors.textPrimary, fontWeight: FontWeight.w500),
                    )),
                    ClickableCursor(
                      child: GestureDetector(
                        onTap: _composer.clearAttachments,
                        child: Container(width: 24, height: 24, decoration: const BoxDecoration(color: GlitchColors.error, shape: BoxShape.circle),
                          child: const Icon(Icons.close, color: Colors.white, size: 14)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEdgeSpinner() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: SizedBox(width: 20, height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: GlitchColors.accentBlue)),
      ),
    );
  }

  Widget _buildTyping() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const SizedBox(width: kMessageRowPadLeft + kMessageGutter),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(color: GlitchColors.bgMessage, borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20), bottomRight: Radius.circular(20), bottomLeft: Radius.circular(5))),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) => _dot(i * 0.2)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(double delay) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.35, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOut,
      builder: (_, val, __) => Container(
        width: 7, height: 7,
        margin: const EdgeInsets.symmetric(horizontal: 2.5),
        decoration: BoxDecoration(shape: BoxShape.circle, color: GlitchColors.textSecond.withOpacity(val)),
      ),
    );
  }
}

typedef _VideoThumbPreview = VideoThumbPreview;


class _KeyboardProbe extends StatelessWidget {
  final double hold;
  final VoidCallback onKeyboardUp;
  final Widget child;

  const _KeyboardProbe({required this.hold, required this.onKeyboardUp, required this.child});

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom - MediaQuery.viewPaddingOf(context).bottom;
    keyboardHeight.note(keyboard);
    if (hold > 0 && keyboard >= hold - 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onKeyboardUp());
    }
    return child;
  }
}

class _ComposerBottomSpace extends StatelessWidget {
  final ValueNotifier<double> dock;
  final double hold;

  const _ComposerBottomSpace({super.key, required this.dock, required this.hold});

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final safe = MediaQuery.viewPaddingOf(context).bottom;
    return ValueListenableBuilder<double>(
      valueListenable: dock,
      builder: (_, panel, __) {
        final fromBottom = hold > 0 ? math.max(keyboard, safe + hold) : safe + panel;
        return SizedBox(height: fromBottom);
      },
    );
  }
}
