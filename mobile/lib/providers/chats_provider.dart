import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/changes_since_request.dart';
import '../models/chat.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/user_updates.dart';
import '../services/websocket_service.dart';

class ChatsProvider extends ChangeNotifier {
  List<ChatListItem> chats = [];
  bool loading = true;

  Timer? _debounce;
  int _loadSeq = 0; // счётчик для отмены устаревших запросов

  final _sinceRequest = ChangesSinceRequest();
  bool _disposed = false;

  StreamSubscription<int>? _userSub;

  void init() {
    wsService.addListener(_onWsEvent);
    wsService.addReconnectListener(_onReconnect);
    _userSub = userUpdates.changes.listen((_) => _scheduleLoad());
    load();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    wsService.removeListener(_onWsEvent);
    wsService.removeReconnectListener(_onReconnect);
    _userSub?.cancel();
    super.dispose();
  }

  void _onReconnect() => load();

  Future<void> load() async {
    final seq = ++_loadSeq; // уникальный номер этого запроса
    _sinceRequest.begin(seq);
    if (chats.isEmpty) {
      final cached = cache.loadChats();
      if (cached != null) {
        chats = cached;
        loading = false;
        notifyListeners();
      }
    }
    try {
      final loaded = await api.getChats();
      if (_disposed || seq != _loadSeq) return; // устаревший ответ — пришёл более свежий
      await cache.saveChats(loaded);
      if (_disposed) return;
      chats = loaded;
      _sinceRequest.replay(seq);
      loading = false;
      notifyListeners();
    } catch (_) {
      if (_disposed || seq != _loadSeq) return;
      _sinceRequest.drop(seq);
      loading = false;
      notifyListeners();
    }
  }

  void _setUnread(int chatId, int count) {
    _sinceRequest.record(() => _setUnread(chatId, count));
    final idx = chats.indexWhere((c) => c.id == chatId);
    if (idx == -1 || chats[idx].unreadCount == count) return;
    final updated = List<ChatListItem>.from(chats);
    updated[idx] = updated[idx].copyWith(unreadCount: count);
    chats = updated;
    notifyListeners();
    cache.updateUnread(chatId, count);
  }

  static String chatName(ChatListItem chat) {
    if (chat.type == 'group') return chat.name ?? 'Группа';
    return chat.name ?? 'Чат';
  }

  void _onWsEvent(Map<String, dynamic> event) {
    final type = event['type'];
    if (type == 'chat.read.self') {
      final chatId = event['chat_id'];
      final unread = event['unread_count'];
      if (chatId is int && unread is int) {
        _setUnread(chatId, unread);
      } else {
        _scheduleLoad();
      }
      return;
    }
    if (event['in_room'] == true) return;
    if (type == 'block.changed' || type == 'message.new' ||
        type == 'message.edited' || type == 'message.deleted' ||
        type == 'chat.deleted' || type == 'chat.hidden' ||
        type == 'chat.left' || type == 'chat.read') {
      _scheduleLoad();
    }
  }

  // Debounce: ждём 300 мс после последнего события перед запросом
  void _scheduleLoad() {
    if (_disposed) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), load);
  }
}
