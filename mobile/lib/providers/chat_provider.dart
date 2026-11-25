import 'dart:async';
import 'dart:convert';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../core/l10n.dart';
import '../core/permissions.dart';
import '../core/presence.dart' as presence;
import '../models/presence.dart';
import '../services/user_presences.dart';
import '../core/time_json.dart' show parseUtcLocal;
import '../models/chat.dart' show ChatMember;
import '../models/mention.dart';
import '../models/embed.dart';
import '../models/message.dart';
import '../models/poll.dart';
import '../models/sticker.dart';
import '../models/user.dart' show User;
import '../models/bubble_data.dart';
import '../models/attach_result.dart' show GeoResult, PendingFile;
import 'message_composer.dart' show PendingVoice;
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/cache_service.dart';
import '../services/chat_viewing.dart';
import '../services/media_service.dart';
import '../services/send_pipeline.dart';
import '../services/upload_limits.dart' show UploadTooLarge;
import '../services/user_updates.dart';
import '../services/websocket_service.dart';
import '../models/server.dart' show MemberDisplayChange;
import 'server_provider.dart' show serverRail;
import 'message_composer.dart';
import 'pin_state.dart';
import '../core/changes_since_request.dart';

class ChatProvider extends ChangeNotifier {
  final bool isGroup;

  final bool isRoom;

  final int? roomServerId;

  Perms? get roomPermissions => _roomPermissions;
  Perms? _roomPermissions;

  void applyRoomPermissions(Perms perms) {
    if (!isRoom) return;
    _roomPermissions = perms;
    if (!_disposed) notifyListeners();
  }

  final String? targetNickname;
  final String? otherNickname;
  final MessageComposer composer;

  int? chatId;
  List<Message> messages = [];
  bool loading = true;
  bool sending = false;
  bool typingVisible = false;
  bool chatBlocked = false;
  bool chatDeleted = false; // чат удалён (автоматически, после удаления последнего сообщения)

  String? leftReason;
  bool isOnline = false;
  PresenceStatus presenceStatus = PresenceStatus.offline;
  DateTime? lastSeen;

  List<ChatMember> groupMembers = [];

  late final PinState pin = PinState(
    fetch: () => api.getChatPin(chatId!),
    save: (id) => api.setChatPin(chatId!, id),
    onChanged: () { if (!_disposed) notifyListeners(); },
  );

  bool get canPin {
    if (isRoom) return roomPermissions?.can(Perm.manageMessages) ?? false;
    if (!isGroup) return true;
    final myId = authService.currentUser?.id;
    if (myId == null) return false;
    final role = _roleOf(myId);
    return role == 'owner' || role == 'admin';
  }

  bool get canAttach {
    if (isRoom) return roomPermissions?.can(Perm.attachFiles) ?? false;
    return true;
  }

  bool get canReact {
    if (isRoom) return roomPermissions?.can(Perm.addReactions) ?? false;
    return true;
  }

  bool get canSendPolls {
    if (isRoom) return roomPermissions?.can(Perm.sendPolls) ?? false;
    return true;
  }

  bool get canWrite {
    if (chatBlocked) return false;
    if (isRoom) return roomPermissions?.can(Perm.sendMessages) ?? false;
    return true;
  }

  static const int windowSize = 150;
  bool hasMoreOlder = true;
  bool hasMoreNewer = false;
  bool loadingOlder = false;
  bool loadingNewer = false;
  static const _pageSize = 50;
  int _windowSeq = 0;

  /// Что пришло, пока окно грузилось целиком ([loadMessages],
  /// [jumpToMessage]), — проигрывается поверх страницы (общий
  /// core/changes_since_request.dart). Раньше страница стирала только что
  /// отправленное: «Сообщение для @…» из карточки участника уходит сразу
  /// после открытия переписки, событие о нём приходило раньше страницы, и в
  /// ленте его не было до перезахода. Тем же путём пропадало чужое
  /// сообщение, пришедшее во время открытия или досчёта после
  /// переподключения. Номер загрузки — [_windowSeq].
  final _sinceRequest = ChangesSinceRequest();

  static const _feedEvents = {
    'message.new',
    'message.edited',
    'message.deleted',
    'message.reaction',
    'message.poll',
    'mention.new',
    'chat.read',
  };

  void _trimWindow({required bool keepNewest}) {
    final excess = messages.length - windowSize;
    if (excess <= 0) return;
    if (keepNewest) {
      messages = messages.sublist(excess);
      hasMoreOlder = true;
      return;
    }
    if (messages.any((m) => m.id < 0)) return;
    messages = messages.sublist(0, windowSize);
    hasMoreNewer = true;
  }

  int? get _newestConfirmedId {
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].id > 0) return messages[i].id;
    }
    return null;
  }

  Future<void> _saveCache() async {
    final cid = chatId;
    if (cid == null || hasMoreNewer) return;
    await cache.saveMessages(cid, messages);
  }

  int _nextTempId = -1;
  int? _otherUserId;
  Map<String, dynamic>? _pendingBlockEvent;
  Timer? _typingTimer;
  bool _disposed = false;

  final _errorCtrl = StreamController<String>.broadcast();
  Stream<String> get errors => _errorCtrl.stream;

  /// Голый `_errorCtrl.add` звать нельзя. Причина (найдено в журнале
  /// 2026-08-25, «Bad state: Cannot add new events after calling close» у живых
  /// людей): отправка сообщения намеренно доходит до конца, даже если экран уже
  /// закрыли — так решено, чтобы начатое не пропадало. Но к моменту её
  /// завершения `dispose` уже успел закрыть этот поток, и `add` в закрытый
  /// StreamController бросает исключение — прямо из catch-блока, который и сам
  /// разбирался с ошибкой.
  void _emitError(String message) {
    if (_errorCtrl.isClosed) return;
    _errorCtrl.add(message);
  }

  final _ownAddedCtrl = StreamController<void>.broadcast();

  /// Моё новое сообщение встало в конец ленты — экран по нему едет вниз, как
  /// у Discord: своё видно всегда, где бы ни читал. Чужие сообщения, догрузка
  /// истории и сверка после переподключения сюда НЕ попадают.
  ///
  /// До 2026-10-10 экран угадывал это сам — «список вырос, и это не догрузка»
  /// по флагу `_paginating`. Флаг гасил любой повторный вызов догрузки
  /// (мгновенно, пока первая порция ещё в пути), пришедшая порция считалась
  /// «новым сообщением» — и лента при быстрой прокрутке или перетаскивании
  /// ползунка вверх уезжала в самый низ. Теперь о новом своём сообщении
  /// говорит тот, кто его добавил, а не догадка по числу строк.
  Stream<void> get ownMessageAdded => _ownAddedCtrl.stream;

  void _addOwnTemp(Message temp) {
    messages.add(temp);
    if (!_ownAddedCtrl.isClosed) _ownAddedCtrl.add(null);
    if (hasMoreNewer) unawaited(loadMessages(useCache: false));
  }

  final _bubbleOf = Expando<BubbleData>();
  List<BubbleData> get bubbles => [for (final m in messages) _bubbleOf[m] ??= m.toBubble()];

  ChatProvider({
    required int? initialChatId,
    required this.isGroup,
    this.isRoom = false,
    this.roomServerId,
    Perms? roomPermissions,
    required this.targetNickname,
    required this.otherNickname,
    required this.composer,
    bool? initialIsOnline,
    PresenceStatus? initialPresenceStatus,
    DateTime? initialLastSeen,
  }) : _roomPermissions = roomPermissions {
    chatId = initialChatId;
    isOnline = initialIsOnline ?? false;
    presenceStatus = initialPresenceStatus ?? (isOnline ? PresenceStatus.online : PresenceStatus.offline);
    isOnline = presenceStatus.isOnline;
    lastSeen = initialLastSeen != null ? presence.unhideLastSeen(initialLastSeen) : null;
  }

  Future<bool>? openedAround;

  void init({int? aroundMessageId}) {
    wsService.addListener(_onWsEvent);
    wsService.addReconnectListener(_onReconnect);
    chatViewing.addListener(_reportRead);
    _lookSub = userUpdates.looks.listen(_onLook);
    if (isRoom && roomServerId != null) {
      _displaySub = serverRail.memberDisplay.listen(_onMemberDisplay);
    }
    if (chatId != null) {
      if (aroundMessageId != null) {
        openedAround = _openAround(aroundMessageId);
      } else {
        loadMessages();
      }
      if (!isGroup && otherNickname != null) {
        checkChatBlocked();
      }
      if (isGroup && !isRoom) _loadGroupMembers();
      pin.load();
    } else {
      loading = false;
      notifyListeners();
      if (!isGroup && otherNickname != null) {
        _loadUserPresence();
      }
    }
  }

  Future<void> _loadGroupMembers() async {
    final cid = chatId;
    if (cid == null) return;
    try {
      final chat = await api.getChat(cid);
      if (_disposed) return;
      groupMembers = chat.members;
      notifyListeners();
    } catch (_) {
    }
  }

  String? _roleOf(int userId) =>
      groupMembers.where((m) => m.id == userId).firstOrNull?.role;

  /// Может ли ТЕКУЩИЙ пользователь удалить это сообщение — то же правило,
  /// что и на сервере (message_service._require_can_delete_message): своё —
  /// всегда (через [isMine], который экран вычисляет сам — он же учитывает
  /// особый случай агента поддержки, см. ChatScreen._isMine); иначе в группе
  /// владелец может удалить любое, админ — любое, КРОМЕ сообщений владельца.
  /// Только подсказка для UI (показать/спрятать пункт «Удалить») — настоящий
  /// запрет всегда на сервере, см. doc-комментарий у groupMembers.
  bool canDeleteMessage(BubbleData bubble, {required bool isMine}) {
    if (isMine && bubble.type != 'system') return true;
    if (isRoom) return roomPermissions?.can(Perm.manageMessages) ?? false;
    if (!isGroup) return false;
    final myId = authService.currentUser?.id;
    if (myId == null) return false;
    final myRole = _roleOf(myId);
    if (myRole == 'owner') return true;
    if (myRole == 'admin') return _roleOf(bubble.senderId) != 'owner';
    return false;
  }

  void _applyPresence(User user) {
    final blocked = user.isBlocked || user.isBlockedBy;
    presenceStatus = userPresences.personalStatusOf(user.id, user.presenceStatus,
        serverLastSeen: user.lastSeen, blocked: blocked);
    isOnline = presenceStatus.isOnline;
    lastSeen = userPresences.personalLastSeenOf(user.id, user.lastSeen, blocked: blocked);
  }

  Future<void> _loadUserPresence() async {
    if (otherNickname == null) return;
    try {
      final otherUser = await api.getUser(otherNickname!);
      if (_disposed) return;
      _otherUserId = otherUser.id;
      _applyPresence(otherUser);
      chatBlocked  = otherUser.isBlocked || otherUser.isBlockedBy;
      _applyPendingBlockEvent();
      notifyListeners();
    } catch (_) {}
  }

  void _applyPendingBlockEvent() {
    final pending = _pendingBlockEvent;
    _pendingBlockEvent = null;
    if (pending != null && pending['user_id'] == _otherUserId) {
      chatBlocked = pending['blocked'] == true;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _typingTimer?.cancel();
    wsService.removeListener(_onWsEvent);
    wsService.removeReconnectListener(_onReconnect);
    chatViewing.removeListener(_reportRead);
    _lookSub?.cancel();
    _displaySub?.cancel();
    _errorCtrl.close();
    _ownAddedCtrl.close();
    super.dispose();
  }


  int _shownUpTo = 0;

  int _reportedUpTo = 0;
  bool _readInFlight = false;

  void messagesShown(int messageId) {
    if (messageId <= _shownUpTo) return;
    _shownUpTo = messageId;
    _reportRead();
  }

  Future<void> _reportRead() async {
    final cid = chatId;
    if (cid == null || _disposed || _readInFlight) return;
    final upTo = _shownUpTo;
    if (upTo <= _reportedUpTo || !chatViewing.isWatching(cid)) return;
    _readInFlight = true;
    var ok = false;
    try {
      await api.markChatRead(cid, upTo: upTo);
      ok = true;
      if (upTo > _reportedUpTo) _reportedUpTo = upTo;
    } catch (_) {
    } finally {
      _readInFlight = false;
    }
    if (ok) _reportRead();
  }

  StreamSubscription<PersonLook>? _lookSub;

  void _onLook(PersonLook p) {
    final look = p.look;
    if (look == null) return;
    if (isRoom ? p.serverId != roomServerId : p.serverId != null) return;
    var changed = false;
    final next = <Message>[];
    for (final m in messages) {
      final updated = m.withAuthorLook(p.userId, look);
      if (!identical(updated, m)) changed = true;
      next.add(updated);
    }
    if (!changed) return;
    messages = next;
    if (!_disposed) notifyListeners();
  }

  StreamSubscription<MemberDisplayChange>? _displaySub;
  int _colorsSeq = 0;

  void _onMemberDisplay(MemberDisplayChange c) {
    final serverId = roomServerId;
    if (serverId == null || c.serverId == null || !c.affects(serverId)) return;
    final authors = <int>{};
    for (final m in messages) {
      if (m.id <= 0) continue;
      if (m.senderKind != kSenderWebhook) authors.add(m.senderId);
      final quoted = m.replyTo?.senderId;
      if (quoted != null) authors.add(quoted);
    }
    final userId = c.userId;
    if (authors.isEmpty || (userId != null && !authors.contains(userId))) return;
    // Спрашиваем ВСЕХ авторов, а не одного: тогда номер запроса честно
    // отсекает устаревшие ответы — новый запрос покрывает всё, что старый.
    _refreshNameColors(serverId, authors.toList());
  }

  Future<void> _refreshNameColors(int serverId, List<int> userIds) async {
    final seq = ++_colorsSeq;
    final colors = <int, String?>{};
    try {
      for (var i = 0; i < userIds.length; i += ApiService.nameColorsLimit) {
        final end = (i + ApiService.nameColorsLimit).clamp(0, userIds.length);
        colors.addAll(await api.getNameColors(serverId, userIds.sublist(i, end)));
      }
    } catch (_) {
      return;
    }
    if (_disposed || seq != _colorsSeq) return;
    var changed = false;
    final next = <Message>[];
    for (final m in messages) {
      var updated = m;
      if (colors.containsKey(m.senderId)) updated = updated.withNameColor(m.senderId, colors[m.senderId]);
      final quoted = updated.replyTo?.senderId;
      if (quoted != null && quoted != m.senderId && colors.containsKey(quoted)) {
        updated = updated.withNameColor(quoted, colors[quoted]);
      }
      if (!identical(updated, m)) changed = true;
      next.add(updated);
    }
    if (!changed) return;
    messages = next;
    notifyListeners();
  }

  String presenceText(BuildContext context) =>
      presenceStatus == PresenceStatus.idle || presenceStatus == PresenceStatus.dnd
          ? '' : presence.presenceText(context, isOnline: isOnline, lastSeen: lastSeen, status: presenceStatus);

  // ── Загрузка сообщений ─────────────────────────────────────────────────
  // useCache: false — при ресинке после переподключения (см. _onReconnect
  // ниже): дисковый кэш может быть даже устарелее того, что уже нарисовано
  // на экране, подставлять его поверх текущего было бы шагом назад, а не
  // вперёд.
  Future<void> loadMessages({bool useCache = true}) async {
    final cid = chatId;
    if (cid == null) { loading = false; notifyListeners(); return; }

    final seq = ++_windowSeq;
    _sinceRequest.begin(seq);
    if (useCache) {
      final cached = cache.loadMessages(cid);
      if (cached != null && cached.isNotEmpty) {
        messages = cached;
        hasMoreNewer = false;
        loading = false;
        notifyListeners();
      }
    }

    try {
      final msgs = await api.getMessages(cid, limit: _pageSize);
      if (_disposed) return;

      await cache.saveMessages(cid, msgs);
      if (_disposed || seq != _windowSeq) return;

      // Сообщения, которые ещё отправляются локально (id < 0, см.
      // send_pipeline.dart) — сервер о них ещё не знает, свежая страница их
      // не содержит. Без этого ресинк после переподключения стирал бы у
      // человека «зависшую» отправку прямо из-под рук.
      final pending = messages.where((m) => m.id < 0).toList();
      messages = pending.isEmpty ? msgs : [...msgs, ...pending];
      loading  = false;
      hasMoreOlder = msgs.length == _pageSize;
      hasMoreNewer = false;
      _sinceRequest.replay(seq);
      notifyListeners();
    } catch (_) {
      if (_disposed) return;
      _sinceRequest.drop(seq);
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> _openAround(int messageId) async {
    final found = await jumpToMessage(messageId);
    if (_disposed) return false;
    if (!found) {
      await loadMessages(useCache: false);
      return false;
    }
    loading = false;
    notifyListeners();
    return true;
  }

  void _onReconnect() {
    if (!isGroup && otherNickname != null) unawaited(checkChatBlocked());
    if (chatId == null) return;
    loadMessages(useCache: false);
    _reportRead();
    pin.load();
  }

  Future<void> loadMoreOlder() async {
    final cid = chatId;
    if (cid == null || loadingOlder || !hasMoreOlder || messages.isEmpty) return;
    final seq = _windowSeq;
    loadingOlder = true;
    notifyListeners();
    try {
      final older = await api.getMessages(cid, beforeId: messages.first.id, limit: _pageSize);
      if (_disposed || seq != _windowSeq) return;
      hasMoreOlder = older.length == _pageSize;
      messages = [...older, ...messages];
      _trimWindow(keepNewest: false);
    } catch (_) {
    } finally {
      if (!_disposed) {
        loadingOlder = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMoreNewer() async {
    final cid = chatId;
    final afterId = _newestConfirmedId;
    if (cid == null || afterId == null || loadingNewer || !hasMoreNewer) return;
    final seq = _windowSeq;
    loadingNewer = true;
    notifyListeners();
    try {
      final newer = await api.getMessages(cid, afterId: afterId, limit: _pageSize);
      if (_disposed || seq != _windowSeq) return;
      hasMoreNewer = newer.length == _pageSize;
      final pending = messages.where((m) => m.id < 0).toList();
      messages = [...messages.where((m) => m.id > 0), ...newer, ...pending];
      _trimWindow(keepNewest: true);
    } catch (_) {
    } finally {
      if (!_disposed) {
        loadingNewer = false;
        notifyListeners();
      }
    }
  }

  Future<bool> jumpToMessage(int messageId) async {
    final cid = chatId;
    if (cid == null) return false;
    const olderLimit = 30;
    const newerLimit = 8;
    final seq = ++_windowSeq;
    _sinceRequest.begin(seq);
    try {
      final older = await api.getMessages(cid, beforeId: messageId + 1, limit: olderLimit);
      if (_disposed || seq != _windowSeq) return false;
      final hasTarget = older.any((m) => m.id == messageId);
      if (!hasTarget) {
        _sinceRequest.drop(seq);
        return false;
      }
      final newer = await api.getMessages(cid, afterId: messageId, limit: newerLimit);
      if (_disposed || seq != _windowSeq) return false;
      messages = [...older, ...newer];
      hasMoreOlder = older.length == olderLimit;
      hasMoreNewer = newer.length == newerLimit;
      _sinceRequest.replay(seq);
      notifyListeners();
      return true;
    } catch (_) {
      _sinceRequest.drop(seq);
      return false;
    }
  }

  Future<void> checkChatBlocked() async {
    try {
      final otherUser = await api.getUser(otherNickname!);
      if (_disposed) return;
      _otherUserId = otherUser.id;
      chatBlocked  = otherUser.isBlocked || otherUser.isBlockedBy;
      _applyPresence(otherUser);
      _applyPendingBlockEvent();
      notifyListeners();
    } catch (_) {}
  }

  void _onWsEvent(Map<String, dynamic> event) {
    final type = event['type'];
    if (_feedEvents.contains(type)) _sinceRequest.record(() => _onWsEvent(event));

    if (!isGroup && (type == 'presence.online' || type == 'presence.offline')) {
      final eventUserId = event['user_id'] as int?;
      if (eventUserId != null && _otherUserId != null && eventUserId == _otherUserId) {
        if (chatBlocked) return;
        presenceStatus = presenceStatusFrom(event['status'], online: type == 'presence.online');
        if (type == 'presence.online') {
          isOnline = true;
        } else {
          final rawLastSeen = event['last_seen'] as String?;
          isOnline = false;
          if (rawLastSeen != null) lastSeen = presence.unhideLastSeen(parseUtcLocal(rawLastSeen));
        }
        notifyListeners();
      }
      return;
    }

    if (!isGroup && type == 'block.changed') {
      final eventUserId = event['user_id'] as int?;
      if (eventUserId == null) return;
      if (_otherUserId == null) {
        // _otherUserId ещё не загружен (см. комментарий у поля выше) —
        // буферизуем, применится сразу как только он появится, вместо того
        // чтобы молча терять событие без повтора.
        _pendingBlockEvent = event;
        return;
      }
      if (eventUserId == _otherUserId) {
        chatBlocked = event['blocked'] == true;
        if (chatBlocked) {
          isOnline = false;
          presenceStatus = PresenceStatus.offline;
          lastSeen = null;
        } else {
          unawaited(checkChatBlocked());
        }
        notifyListeners();
      }
      return;
    }

    if (type == 'message.new') {
      final msgMap = event['message'] as Map<String, dynamic>;
      if (chatId != null && msgMap['chat_id'] == chatId) {
        final newMsg = Message.fromJson(msgMap);
        if (messages.any((m) => m.id == newMsg.id)) return;
        final myId = authService.currentUser?.id;
        if (newMsg.senderId == myId && kSentByPeopleTypes.contains(newMsg.type)) {
          int tempIdx = -1;
          for (int i = 0; i < messages.length; i++) {
            final m = messages[i];
            if (m.id < 0 && m.type == newMsg.type && m.content == newMsg.content) {
              if (tempIdx == -1 || m.createdAt.isBefore(messages[tempIdx].createdAt)) {
                tempIdx = i;
              }
            }
          }
          // Если точного совпадения нет — берём самый ранний temp того же типа
          if (tempIdx == -1) {
            for (int i = 0; i < messages.length; i++) {
              final m = messages[i];
              if (m.id < 0 && m.type == newMsg.type) {
                if (tempIdx == -1 || m.createdAt.isBefore(messages[tempIdx].createdAt)) {
                  tempIdx = i;
                }
              }
            }
          }
          if (tempIdx == -1) {
            tempIdx = messages.indexWhere((m) => m.id < 0);
          }
          if (tempIdx != -1) {
            messages[tempIdx] = newMsg;
            notifyListeners();
            cache.appendMessage(chatId!, newMsg);
            return;
          }
        }
        cache.appendMessage(chatId!, newMsg);
        if (hasMoreNewer) return;
        messages.add(newMsg);
        _trimWindow(keepNewest: true);
        notifyListeners();
      }
    } else if (type == 'typing') {
      if (chatId != null && event['chat_id'] == chatId) {
        typingVisible = event['is_typing'] == true;
        notifyListeners();
        if (typingVisible) {
          _typingTimer?.cancel();
          _typingTimer = Timer(const Duration(seconds: 3), () {
            typingVisible = false;
            notifyListeners();
          });
        }
      }
    } else if (type == 'chat.read') {
      final eventChatId = event['chat_id'] as int?;
      if (eventChatId != chatId) return;
      final upTo = event['last_read_message_id'] as int?;
      if (upTo == null) return;
      final myId = authService.currentUser?.id;
      bool changed = false;
      for (int i = 0; i < messages.length; i++) {
        final m = messages[i];
        if (m.senderId == myId && m.id > 0 && m.id <= upTo && m.status != 'read' &&
            m.status != 'sending' && m.status != 'failed') {
          messages[i] = m.copyWith(status: 'read');
          changed = true;
        }
      }
      if (changed) notifyListeners();
    } else if (type == 'message.edited') {
      final eventChatId = event['chat_id'] as int?;
      if (eventChatId != chatId) return;
      final msgId = event['message_id'] as int?;
      final newContent = event['content'] as String?;
      if (msgId == null || newContent == null) return;
      final embeds = event.containsKey('embeds') ? Embed.listFrom(event['embeds']) : null;
      pin.onEdited(msgId, newContent.isNotEmpty ? newContent : (Embed.summaryOf(embeds ?? const []) ?? ''));
      final idx = messages.indexWhere((m) => m.id == msgId);
      if (idx != -1) {
        final m = messages[idx];
        final mentions = Mention.listFrom(event['mentions'], newContent);
        messages[idx] = m.type == 'text'
            ? m.copyWith(content: newContent, editedAt: DateTime.now(), mentions: mentions, embeds: embeds)
            : m.copyWith(caption: newContent, editedAt: DateTime.now(), mentions: mentions, embeds: embeds);
        notifyListeners();
        _saveCache();
      }
    } else if (type == 'mention.new') {
      if (event['chat_id'] != chatId) return;
      final msgId = event['message_id'];
      final idx = messages.indexWhere((m) => m.id == msgId);
      if (idx == -1 || messages[idx].mentionsMe) return;
      messages[idx] = messages[idx].copyWith(mentionsMe: true);
      notifyListeners();
      _saveCache();
    } else if (type == 'message.reaction') {
      final eventChatId = event['chat_id'] as int?;
      if (eventChatId != chatId) return;
      final msgId = event['message_id'] as int?;
      final reactionsJson = event['reactions'] as List?;
      if (msgId == null || reactionsJson == null) return;
      final idx = messages.indexWhere((m) => m.id == msgId);
      if (idx != -1) {
        final incoming = reactionsJson.map((r) => Reaction.fromJson(r)).toList();
        final actorIsMe = event['user_id'] == authService.currentUser?.id;
        messages[idx] = messages[idx].copyWith(
          reactions: mergeReactionsFromEvent(incoming, messages[idx].reactions, actorIsMe: actorIsMe),
        );
        notifyListeners();
        _saveCache();
      }
    } else if (type == 'message.poll') {
      if (event['chat_id'] != chatId) return;
      final msgId = event['message_id'] as int?;
      final pollJson = event['poll'];
      if (msgId == null || pollJson is! Map<String, dynamic>) return;
      final incoming = PollInfo.fromJson(pollJson);
      final actorIsMe = event['user_id'] == authService.currentUser?.id;
      var changed = false;
      for (var i = 0; i < messages.length; i++) {
        final m = messages[i];
        if (m.poll?.id != incoming.id) continue;
        messages[i] = m.copyWith(poll: m.poll!.mergedFromEvent(incoming, actorIsMe: actorIsMe));
        changed = true;
      }
      if (changed) {
        notifyListeners();
        _saveCache();
      }
    } else if (type == 'message.deleted') {
      final eventChatId = event['chat_id'] as int?;
      if (eventChatId != chatId) return;
      final msgId = event['message_id'] as int?;
      if (msgId == null) return;
      pin.onDeleted(msgId);
      if (_sinceRequest.active) _sinceRequest.removed.add(msgId);
      if (messages.any((m) => m.id == msgId)) {
        messages.removeWhere((m) => m.id == msgId);
        notifyListeners();
        cache.removeMessage(chatId!, msgId);
      }
    } else if (type == 'chat.pin.changed') {
      if ((event['chat_id'] as int?) != chatId) return;
      pin.applyRemote(ApiService.pinnedFrom(event));
    } else if (type == 'chat.deleted') {
      final eventChatId = event['chat_id'] as int?;
      if (eventChatId != chatId || chatDeleted) return;
      chatDeleted = true;
      notifyListeners();
    } else if (type == 'chat.left') {
      final eventChatId = event['chat_id'] as int?;
      final reason = event['reason'];
      if (eventChatId != chatId || leftReason != null || reason is! String) return;
      leftReason = reason;
      notifyListeners();
    }
  }

  Future<bool> editMessage(int messageId, String newText) async {
    final cid = chatId;
    if (cid == null) return false;
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return false;
    final original = messages[idx];
    messages[idx] = original.type == 'text'
        ? original.copyWith(content: newText, editedAt: DateTime.now())
        : original.copyWith(caption: newText, editedAt: DateTime.now());
    notifyListeners();
    try {
      await api.editMessage(cid, messageId, newText);
      await _saveCache();
      return true;
    } catch (_) {
      if (!_disposed) {
        final i = messages.indexWhere((m) => m.id == messageId);
        if (i != -1) messages[i] = original;
        notifyListeners();
      }
      return false;
    }
  }

  Future<bool> deleteMessage(int messageId) async {
    final cid = chatId;
    if (cid == null) return false;
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return false;
    final removed = messages[idx];
    messages.removeAt(idx);
    notifyListeners();
    try {
      final chatWasDeleted = await api.deleteMessage(cid, messageId);
      cache.removeMessage(cid, messageId);
      if (chatWasDeleted && !chatDeleted && !_disposed) {
        chatDeleted = true;
        notifyListeners();
      }
      return true;
    } catch (_) {
      if (!_disposed) {
        messages.insert(idx.clamp(0, messages.length), removed);
        notifyListeners();
      }
      return false;
    }
  }

  // Оптимистичный апдейт: сама простановка на бэкенде занимает единицы
  // миллисекунд (замерено), но ожидание полного сетевого круга ощущается на
  // мобильной сети как заметная задержка (в Telegram реакция подсвечивается
  // мгновенно). Поэтому UI обновляется сразу локально (Reaction.
  // applyOptimisticToggle — та же логика, что и на сервере), а ответ сервера
  // подтверждает/поправляет счёт (если, например, кто-то ещё отреагировал
  // почти одновременно). При ошибке — откат к снимку до изменения.
  Future<void> toggleReaction(int messageId, String emoji) async {
    final cid = chatId;
    if (cid == null) return;
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;

    final before = messages[idx].reactions;
    messages[idx] = messages[idx].copyWith(
      reactions: Reaction.applyOptimisticToggle(before, emoji),
    );
    notifyListeners();

    try {
      final reactions = await api.reactToMessage(cid, messageId, emoji);
      if (_disposed) return;
      final i = messages.indexWhere((m) => m.id == messageId);
      if (i == -1) return;
      messages[i] = messages[i].copyWith(reactions: reactions);
      notifyListeners();
      _saveCache();
    } catch (e) {
      if (_disposed) return;
      final i = messages.indexWhere((m) => m.id == messageId);
      if (i != -1) {
        messages[i] = messages[i].copyWith(reactions: before);
        notifyListeners();
      }
      _emitError(errorMessage(e));
    }
  }

  ({AuthorLook look, String? color}) _myLookHere(User me) {
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (m.senderId == me.id && m.id > 0) {
        return (
          look: (
            displayName: m.senderDisplayName,
            avatar: m.senderAvatar,
            avatarSizes: m.senderAvatarSizes,
            avatarDecoration: m.senderAvatarDecoration,
          ),
          color: m.senderColor,
        );
      }
    }
    return (
      look: (
        displayName: me.displayName,
        avatar: me.avatar,
        avatarSizes: me.avatarSizes,
        avatarDecoration: me.avatarDecoration,
      ),
      color: null,
    );
  }

  Message _makeTemp({
    required String type,
    String? content,
    String? localPath,
    String? caption,
    String? fileName,
    int? fileSize,
    String? geo,
    PollInfo? poll,
    String? sticker,
    int? replyToId,
    ReplyPreview? replyPreview,
  }) {
    final me = authService.currentUser!;
    final here = _myLookHere(me);
    return Message(
      id: _nextTempId--,
      chatId: chatId ?? 0,
      senderId: me.id,
      senderNickname: me.nickname,
      senderDisplayName: here.look.displayName,
      senderAvatar: here.look.avatar,
      senderAvatarSizes: here.look.avatarSizes,
      senderAvatarDecoration: here.look.avatarDecoration,
      senderColor: here.color,
      content: content,
      localPath: localPath,
      caption: caption,
      fileName: fileName,
      fileSize: fileSize,
      geo: geo,
      poll: poll,
      sticker: sticker,
      type: type,
      createdAt: DateTime.now(),
      replyToId: replyToId,
      replyTo: replyPreview,
      status: 'sending',
    );
  }

  void replaceTemp(int tempId, Message real) {
    final idx = messages.indexWhere((m) => m.id == tempId);
    if (idx != -1) { messages[idx] = real; notifyListeners(); }
    _sinceRequest.record(() => _restoreConfirmed(tempId, real));
  }

  void _restoreConfirmed(int tempId, Message real) {
    if (_sinceRequest.removed.contains(real.id) || messages.any((m) => m.id == real.id)) return;
    final idx = messages.indexWhere((m) => m.id == tempId);
    if (idx != -1) {
      messages[idx] = real;
      notifyListeners();
      return;
    }
    if (hasMoreNewer) return;
    final firstTemp = messages.indexWhere((m) => m.id < 0);
    messages.insert(firstTemp == -1 ? messages.length : firstTemp, real);
    _trimWindow(keepNewest: true);
    notifyListeners();
    cache.appendMessage(real.chatId, real);
  }

  void failTemp(int tempId) {
    final idx = messages.indexWhere((m) => m.id == tempId);
    if (idx != -1) { messages[idx] = messages[idx].copyWith(status: 'failed'); notifyListeners(); }
  }

  void _dropTemp(int tempId) {
    final before = messages.length;
    messages.removeWhere((m) => m.id == tempId);
    if (messages.length != before) notifyListeners();
  }

  Future<bool> ensureChatCreated() async {
    if (chatId != null) return true;
    try {
      final chat = await api.createPersonalChat(targetNickname!);
      chatId = chat.id;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _emitError(e.message);
      return false;
    }
  }

  Future<void> sendText(String text, {int? replyToId, ReplyPreview? replyPreview}) async {
    if (text.trim().isEmpty) return;
    if (!await ensureChatCreated()) return;
    wsService.sendTypingStop(chatId!);
    final temp = _makeTemp(type: 'text', content: text, replyToId: replyToId, replyPreview: replyPreview);
    _addOwnTemp(temp);
    sending = true;
    notifyListeners();
    try {
      final msg = await api.sendMessage(chatId!, type: 'text', text: text, replyToId: replyToId);
      replaceTemp(temp.id, msg);
    } catch (e) {
      failTemp(temp.id);
      _emitError(errorMessage(e));
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  Future<void> _send(Message temp, Future<Message> Function() upload) async {
    _addOwnTemp(temp);
    notifyListeners();
    try {
      final msg = await upload();
      if (_disposed) return;
      replaceTemp(temp.id, msg);
    } catch (e) {
      if (_disposed) return;
      if (e is UploadTooLarge) {
        _dropTemp(temp.id);
      } else {
        failTemp(temp.id);
      }
      _emitError(errorMessage(e));
    } finally {
      if (!_disposed) composer.clearProgress(temp.id);
    }
  }

  Future<void> _measureTemp(int tempId, XFile file, {required bool isVideo}) async {
    final size = isVideo ? await mediaService.videoSize(file) : await mediaService.imageSize(file);
    if (_disposed || size == null || size.h <= 0) return;
    final idx = messages.indexWhere((m) => m.id == tempId);
    if (idx == -1) return;
    messages[idx] = messages[idx].copyWith(localAspectRatio: size.w / size.h);
    notifyListeners();
  }

  Future<void> sendWithPhotos(List<XFile> photos, String? caption, {int? replyToId, ReplyPreview? replyPreview}) async {
    if (!await ensureChatCreated()) return;
    wsService.sendTypingStop(chatId!);

    final String tempType;
    final String localPath;
    if (photos.length == 1) {
      tempType  = mediaService.isVideo(photos[0]) ? 'video' : 'photo';
      localPath = photos[0].path;
    } else {
      tempType  = 'album';
      localPath = jsonEncode(photos.map((f) => f.path).toList());
    }
    final temp = _makeTemp(type: tempType, localPath: localPath, caption: caption, replyToId: replyToId, replyPreview: replyPreview);
    if (photos.length == 1) unawaited(_measureTemp(temp.id, photos[0], isVideo: tempType == 'video'));
    final cid = chatId!;

    await _send(temp, () async {
      final results = <MediaUploadResult>[];
      if (photos.length == 1) {
        results.add(await sendPipeline.uploadWithDims(
          photos[0],
          (compressed, mime, w, h, thumb) => api.uploadMediaFile(
            compressed, mime, w: w, h: h, thumb: thumb, chatId: cid,
            onProgress: (s, t) => composer.setProgress(temp.id, s, t),
          ),
        ));
      } else {
        final compressedList = await sendPipeline.compressAllForUpload(photos);
        final grandTotal = compressedList.fold<int>(0, (sum, m) => sum + m.size);
        var completedBytes = 0;
        var started = 0;
        try {
          for (final media in compressedList) {
            started++;
            final result = await sendPipeline.uploadCompressed(
              media,
              (compressed, mime, w, h, thumb) => api.uploadMediaFile(
                compressed, mime, w: w, h: h, thumb: thumb, chatId: cid,
                onProgress: (s, t) => composer.setProgress(temp.id, completedBytes + s, grandTotal),
              ),
            );
            completedBytes += media.size;
            results.add(result);
          }
        } finally {
          await sendPipeline.discardCompressed(compressedList.skip(started));
        }
      }
      if (results.length == 1) {
        final r = results[0];
        final isVideo = r.type == 'video';
        return api.sendMessage(cid,
          type: isVideo ? 'video' : 'photo',
          imageUrl: isVideo ? null : jsonEncode(r.asMap),
          videoUrl: isVideo ? jsonEncode(r.asMap) : null,
          caption: caption, replyToId: replyToId,
        );
      }
      final items = results.map((r) => {'type': r.type, ...r.asMap}).toList();
      return api.sendMessage(cid, type: 'album', imageUrl: jsonEncode(items), caption: caption, replyToId: replyToId);
    });
  }

  Future<void> sendWithFile(PendingFile pf, String? caption, {int? replyToId, ReplyPreview? replyPreview}) async {
    if (!await ensureChatCreated()) return;
    wsService.sendTypingStop(chatId!);
    final temp = _makeTemp(
      type: 'file', localPath: pf.file.path,
      fileName: pf.name, fileSize: pf.size,
      caption: caption, replyToId: replyToId, replyPreview: replyPreview,
    );
    final cid = chatId!;

    await _send(temp, () async {
      // validate → upload → create
      final result = await sendPipeline.uploadFile(
        pf,
        (f, mime, name) => api.uploadChatFile(cid, f, mime, name,
          onProgress: (s, t) => composer.setProgress(temp.id, s, t),
        ).then((r) => FileUploadResult(url: r.url, name: r.name, size: r.size, audio: r.audio)),
      );
      return api.sendMessage(cid,
        type: 'file',
        fileUrl: result.url,
        fileName: result.name,
        fileSize: result.size,
        fileAudio: result.audio,
        caption: caption, replyToId: replyToId,
      );
    });
  }

  // ── Отправка голосового сообщения ─────────────────────────────────────
  // Атомарно, как фото/видео/файл/альбом/гео: сначала загрузить голосовое, потом один
  // sendMessage с уже готовым voice_url — без создания сообщения на сервере в 2 шага.
  Future<void> sendVoice(PendingVoice pv, {int? replyToId, ReplyPreview? replyPreview}) async {
    if (!await ensureChatCreated()) return;
    wsService.sendTypingStop(chatId!);
    final temp = _makeTemp(type: 'voice', localPath: pv.file.path, replyToId: replyToId, replyPreview: replyPreview);
    final cid = chatId!;

    await _send(temp, () async {
      final result = await api.uploadChatVoice(cid, pv.file,
        onProgress: (s, t) => composer.setProgress(temp.id, s, t),
      );
      final voiceJson = jsonEncode({'url': result['url'], 'duration': double.parse(pv.duration.toStringAsFixed(2)), 'waveform': pv.waveform});
      return api.sendMessage(cid, type: 'voice', voiceUrl: voiceJson, fileSize: result['size'] as int, replyToId: replyToId);
    });
  }

  Future<void> sendVideoNote(PendingVideoNote pv, {int? replyToId, ReplyPreview? replyPreview}) async {
    if (!await ensureChatCreated()) return;
    wsService.sendTypingStop(chatId!);
    final temp = _makeTemp(type: 'video_note', localPath: pv.thumb.path, replyToId: replyToId, replyPreview: replyPreview);
    final cid = chatId!;

    await _send(temp, () async {
      final compressed = await sendPipeline.prepareVideoNote(pv.file);
      final result = await api.uploadChatVideoNote(cid, compressed, pv.thumb,
        onProgress: (s, t) => composer.setProgress(temp.id, s, t),
      );
      final json = jsonEncode({
        'url': result.url,
        'thumb': result.thumb,
        'duration': double.parse(pv.duration.toStringAsFixed(2)),
      });
      return api.sendMessage(cid, type: 'video_note', videoNote: json, fileSize: result.size, replyToId: replyToId);
    });
  }

  Future<void> sendPoll(PollDraft draft, {int? replyToId, ReplyPreview? replyPreview}) async {
    if (!await ensureChatCreated()) return;
    wsService.sendTypingStop(chatId!);
    final temp = _makeTemp(type: 'poll', poll: draft.toPreview(), replyToId: replyToId, replyPreview: replyPreview);
    _addOwnTemp(temp);
    notifyListeners();
    final cid = chatId!;

    () async {
      try {
        final msg = await api.sendMessage(cid, type: 'poll', poll: draft, replyToId: replyToId);
        if (_disposed) return;
        replaceTemp(temp.id, msg);
      } catch (e) {
        if (_disposed) return;
        failTemp(temp.id);
        _emitError(errorMessage(e));
      }
    }();
  }

  Future<bool> votePoll(int messageId, List<int> answerIds) async {
    final cid = chatId;
    if (cid == null) return false;
    try {
      final info = await api.votePoll(cid, messageId, answerIds);
      if (_disposed) return false;
      _applyPoll(info);
      return true;
    } catch (e) {
      if (_disposed) return false;
      _emitError(errorMessage(e));
      return false;
    }
  }

  Future<void> endPoll(int messageId) async {
    final cid = chatId;
    if (cid == null) return;
    try {
      await api.endPoll(cid, messageId);
    } catch (e) {
      if (_disposed) return;
      _emitError(errorMessage(e));
    }
  }

  void _applyPoll(PollInfo info) {
    var changed = false;
    for (var i = 0; i < messages.length; i++) {
      if (messages[i].poll?.id != info.id) continue;
      messages[i] = messages[i].copyWith(poll: info);
      changed = true;
    }
    if (changed) {
      notifyListeners();
      _saveCache();
    }
  }

  Future<void> sendSticker(Sticker sticker, {int? replyToId, ReplyPreview? replyPreview}) async {
    if (!await ensureChatCreated()) return;
    wsService.sendTypingStop(chatId!);
    final temp = _makeTemp(
      type: 'sticker',
      sticker: jsonEncode(sticker.toMessageJson()),
      replyToId: replyToId,
      replyPreview: replyPreview,
    );
    _addOwnTemp(temp);
    notifyListeners();
    final cid = chatId!;

    () async {
      try {
        final msg = await api.sendMessage(cid, type: 'sticker', stickerId: sticker.id, replyToId: replyToId);
        if (_disposed) return;
        replaceTemp(temp.id, msg);
      } catch (e) {
        if (_disposed) return;
        failTemp(temp.id);
        _emitError(errorMessage(e));
      }
    }();
  }

  Future<void> sendGeo(GeoResult geo, String? caption, {int? replyToId, ReplyPreview? replyPreview}) async {
    if (!await ensureChatCreated()) return;
    wsService.sendTypingStop(chatId!);
    final temp = _makeTemp(type: 'geo', caption: caption, geo: '${geo.lat},${geo.lon}', replyToId: replyToId, replyPreview: replyPreview);
    _addOwnTemp(temp);
    notifyListeners();
    final cid = chatId!;

    () async {
      try {
        final msg = await api.sendMessage(cid,
          type: 'geo',
          geo: '${geo.lat},${geo.lon}',
          caption: caption, replyToId: replyToId,
        );
        if (_disposed) return;
        replaceTemp(temp.id, msg);
      } catch (e) {
        if (_disposed) return;
        failTemp(temp.id);
        _emitError(errorMessage(e));
      }
    }();
  }
}
