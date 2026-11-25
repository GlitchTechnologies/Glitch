sealed class PushTarget {
  const PushTarget();
}

class ChatPushTarget extends PushTarget {
  final int chatId;
  const ChatPushTarget(this.chatId);
}

class RoomPushTarget extends PushTarget {
  final int serverId;
  final int roomId;
  const RoomPushTarget({required this.serverId, required this.roomId});
}

class FriendsPushTarget extends PushTarget {
  final bool pending;
  const FriendsPushTarget({required this.pending});
}

const friendRequestPushType = 'friend_request';
const friendAcceptPushType = 'friend_accept';

const _friendsPayload = 'friends:pending';
const _friendsAllPayload = 'friends:all';
const _roomPayloadPrefix = 'room:';

PushTarget? pushTargetFromData(Map<String, dynamic> data) {
  if (data['call_event'] != null) return null;
  switch (data['type']) {
    case friendRequestPushType:
      return const FriendsPushTarget(pending: true);
    case friendAcceptPushType:
      return const FriendsPushTarget(pending: false);
  }
  return messagePushTarget(data['chat_id'], data['server_id']);
}

PushTarget? messagePushTarget(dynamic rawChatId, dynamic rawServerId) {
  final chatId = int.tryParse('${rawChatId ?? ''}');
  if (chatId == null) return null;
  final serverId = int.tryParse('${rawServerId ?? ''}');
  return serverId != null ? RoomPushTarget(serverId: serverId, roomId: chatId) : ChatPushTarget(chatId);
}

String pushTargetPayload(PushTarget target) => switch (target) {
      ChatPushTarget(:final chatId) => '$chatId',
      RoomPushTarget(:final serverId, :final roomId) => '$_roomPayloadPrefix$serverId:$roomId',
      FriendsPushTarget(:final pending) => pending ? _friendsPayload : _friendsAllPayload,
    };

PushTarget? pushTargetFromPayload(String? payload) {
  if (payload == _friendsPayload) return const FriendsPushTarget(pending: true);
  if (payload == _friendsAllPayload) return const FriendsPushTarget(pending: false);
  if (payload != null && payload.startsWith(_roomPayloadPrefix)) {
    final parts = payload.substring(_roomPayloadPrefix.length).split(':');
    return parts.length == 2 ? messagePushTarget(parts[1], parts[0]) : null;
  }
  final chatId = int.tryParse(payload ?? '');
  return chatId != null ? ChatPushTarget(chatId) : null;
}
