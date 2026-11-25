import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/chat.dart' show ChatListItem;
import 'api_service.dart';
import 'websocket_service.dart';

class UnreadSummary extends ChangeNotifier {
  int get count => _count;
  int _count = 0;

  ChatListItem? get latest => _latest;
  ChatListItem? _latest;

  bool _attached = false;
  Timer? _debounce;

  /// Номер запроса: ответ на устаревший запрос (пришёл позже нового) не
  /// применяется — тот же приём, что у списка чатов (ChatsProvider._loadSeq).
  int _seq = 0;

  static const _events = {
    'message.new',
    'message.deleted',
    'chat.read.self',
    'chat.notifications.changed',
    'chat.hidden',
    'chat.deleted',
    'chat.left',
  };

  static const _debounceDelay = Duration(milliseconds: 600);

  /// Начать следить (сессия аккаунта началась). Повторный вызов ничего не
  /// делает.
  void attach() {
    if (_attached) return;
    _attached = true;
    wsService.removeListener(_onWsEvent);
    wsService.addListener(_onWsEvent);
    wsService.addReconnectListener(_onReconnect);
    unawaited(_load());
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    _debounce?.cancel();
    _debounce = null;
    _seq++;
    wsService.removeListener(_onWsEvent);
    wsService.removeReconnectListener(_onReconnect);
    _set(0, null);
  }

  void _onWsEvent(Map<String, dynamic> event) {
    if (!_events.contains(event['type'])) return;
    if (event['in_room'] == true) return;
    _schedule();
  }

  void _onReconnect() => _schedule();

  void _schedule() {
    if (!_attached) return;
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () => unawaited(_load()));
  }

  Future<void> _load() async {
    final seq = ++_seq;
    try {
      final summary = await api.getUnreadSummary();
      if (!_attached || seq != _seq) return;
      _set(summary.count, summary.latest);
    } catch (_) {
    }
  }

  void _set(int count, ChatListItem? latest) {
    _count = count;
    _latest = latest;
    notifyListeners();
  }
}

final unreadSummary = UnreadSummary();
