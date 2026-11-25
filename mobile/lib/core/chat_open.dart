import 'package:flutter/widgets.dart';

import '../models/chat_arrival.dart';
import '../screens/chat_screen.dart';
import '../services/api_service.dart';
import '../services/user_presences.dart';
import '../services/auth_service.dart';
import '../widgets/glitch_avatar.dart';
import 'adaptive_open.dart';

Future<void> openChatById(BuildContext context, int chatId, {int? messageId, ChatArrival? arrival}) async {
  final chat = await api.getChat(chatId);
  if (!context.mounted) return;
  final myId = authService.currentUser?.id ?? 0;
  final name = chat.displayName(myId);
  final isGroup = chat.type == 'group';
  final otherMember = !isGroup ? chat.members.where((m) => m.id != myId).firstOrNull : null;
  final avatarUrl = isGroup
      ? (chat.avatar != null ? api.mediaUrl(chat.avatar!) : null)
      : (otherMember?.avatar != null ? api.mediaUrl(otherMember!.avatar!) : null);
  final avatarSizes = isGroup ? chat.avatarSizes : otherMember?.avatarSizes;
  await openAdaptiveFromLink(
    context,
    builder: (_) => ChatScreen(
      chatId: chat.id,
      initialMessageId: messageId,
      chatName: name,
      colorIndex: GlitchAvatar.colorFromNickname(name),
      isGroup: isGroup,
      otherNickname: otherMember?.nickname,
      avatarUrl: avatarUrl,
      avatarSizes: avatarSizes,
      initialIsOnline: otherMember?.isOnline,
      initialPresenceStatus: otherMember == null ? null : userPresences.personalStatusOf(
          otherMember.id, otherMember.presenceStatus, serverLastSeen: otherMember.lastSeen),
      initialLastSeen: otherMember == null ? null : userPresences.personalLastSeenOf(
          otherMember.id, otherMember.lastSeen),
      arrival: arrival,
    ),
    slotKey: chatSlotKey(chat.id),
  );
}
