import 'dart:convert';

class IncomingCallPayload {
  final int callId;
  final int chatId;

  const IncomingCallPayload({required this.callId, required this.chatId});

  String encode() => jsonEncode({'call_id': callId, 'chat_id': chatId});

  /// null — payload чужой (например, от уведомления о сообщении: там лежит
  /// просто число chat_id) или битый. Разбор без исключений: этот код
  /// выполняется в фоновом изоляте, где падение никто не увидит.
  static IncomingCallPayload? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final callId = (map['call_id'] as num?)?.toInt();
      final chatId = (map['chat_id'] as num?)?.toInt();
      if (callId == null || chatId == null) return null;
      return IncomingCallPayload(callId: callId, chatId: chatId);
    } catch (_) {
      return null;
    }
  }
}
