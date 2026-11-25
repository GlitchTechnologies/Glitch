import 'chat_viewing.dart';
import 'voice_connection.dart';
import 'voice_cue.dart';
import 'websocket_service.dart';

class MessageCue {
  void attach() {
    wsService.removeListener(_onWsEvent);
    wsService.addListener(_onWsEvent);
  }

  void _onWsEvent(Map<String, dynamic> event) {
    if (event['type'] != 'notification.message') return;
    final chatId = (event['chat_id'] as num?)?.toInt();
    if (chatId == null || chatViewing.isWatching(chatId)) return;
    voiceConnection.playCue(VoiceCue.message);
  }
}

final messageCue = MessageCue();
