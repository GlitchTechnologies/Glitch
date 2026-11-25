import 'push_service.dart';
import 'websocket_service.dart';

class NotificationDismissal {
  /// Начать слушать. Повторный вызов не дублирует подписку.
  void attach() {
    wsService.removeListener(_onWsEvent);
    wsService.addListener(_onWsEvent);
  }

  void _onWsEvent(Map<String, dynamic> event) {
    final type = event['type'];
    final chatId = event['chat_id'];
    if (chatId is! int) return;
    final gone = type == 'chat.deleted' || type == 'chat.hidden' || type == 'chat.left' ||
        type == 'server.room.deleted';
    final readToEnd = type == 'chat.read.self' && event['unread_count'] == 0;
    if (gone || readToEnd) pushService.clearNotification(chatId);
  }
}

final notificationDismissal = NotificationDismissal();
