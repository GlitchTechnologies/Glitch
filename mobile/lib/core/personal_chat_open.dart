import 'package:flutter/material.dart';

import '../models/chat_arrival.dart';
import '../screens/chat_screen.dart';
import '../services/api_service.dart';
import '../widgets/glitch_avatar.dart';
import '../widgets/glitch_toast.dart';
import 'adaptive_open.dart';
import 'shell_controller.dart' show ShellSlot;

Future<void> openPersonalChat(
  BuildContext context, {
  required String nickname,
  required String displayName,
  String? avatar,
  Map<String, String>? avatarSizes,
  ChatArrival? arrival,
}) async {
  try {
    final existing = await api.findPersonalChat(nickname);
    if (!context.mounted) return;
    final chatId = existing?.id;
    openAdaptive(
      context,
      slot: ShellSlot.main,
      slotKey: chatSlotKey(chatId ?? nickname),
      builder: (_) => ChatScreen(
        chatId: chatId,
        targetNickname: chatId == null ? nickname : null,
        chatName: displayName,
        colorIndex: GlitchAvatar.colorFromNickname(nickname),
        isGroup: false,
        otherNickname: nickname,
        avatarUrl: avatar != null ? api.mediaUrl(avatar) : null,
        avatarSizes: avatarSizes,
        arrival: arrival,
      ),
    );
  } catch (e) {
    if (context.mounted) GlitchToast.show(context, errorMessage(e));
  }
}
