import '../screens/user_profile_screen.dart';
import 'package:flutter/material.dart';

import 'adaptive_open.dart';
import 'glitch_link.dart';
import 'l10n.dart';
import 'server_join.dart';
import '../models/chat.dart' show Chat, GroupInvitePreview;
import '../models/invite.dart';
import '../models/server.dart' show ServerDetail;
import '../services/api_service.dart';
import '../screens/chat_screen.dart';
import '../widgets/glitch_avatar.dart';
import '../widgets/glitch_dialog.dart';
import '../widgets/glitch_toast.dart';

Future<void> openGlitchLink(
  BuildContext context,
  GlitchLinkTarget target, {
  VoidCallback? onNotFound,
}) async {
  switch (target) {
    case ProfileLinkTarget(:final nickname):
      await _openProfile(context, nickname, onNotFound);
    case InviteLinkTarget(:final code):
      await _openInvite(context, code, onNotFound);
  }
}

Future<void> _openProfile(BuildContext context, String nickname, VoidCallback? onNotFound) async {
  try {
    await api.getUser(nickname);
  } catch (e) {
    if (_isNotFound(e)) {
      onNotFound?.call();
    } else {
      _showLinkError(context, e);
    }
    return;
  }
  if (!context.mounted) return;
  await showUserProfile(context, nickname: nickname);
}

Future<void> _openInvite(BuildContext context, String code, VoidCallback? onNotFound) async {
  final InvitePreview preview;
  try {
    preview = await api.getInvitePreview(code);
  } catch (e) {
    if (_isNotFound(e)) {
      onNotFound?.call();
    } else {
      _showLinkError(context, e);
    }
    return;
  }
  if (!context.mounted) return;

  final server = preview.server;
  if (server != null) {
    await joinServerAndShow(context, server, () async => _serverOf(await api.joinInvite(code)));
    return;
  }

  final group = preview.group;
  if (group == null) return;
  try {
    final Chat chat;
    if (group.alreadyMember) {
      chat = await api.getChat(group.id);
    } else {
      final agreed = await _confirmJoinGroup(context, group);
      if (!agreed) return;
      chat = _chatOf(await api.joinInvite(code));
    }
    if (!context.mounted) return;
    final chatName = chat.name ?? context.s.group;
    await openAdaptiveFromLink(context,
        slotKey: chatSlotKey(chat.id),
        builder: (_) => ChatScreen(
              chatId: chat.id,
              chatName: chatName,
              colorIndex: GlitchAvatar.colorFromNickname(chatName),
              isGroup: true,
              avatarUrl: chat.avatar != null ? api.mediaUrl(chat.avatar!) : null,
              avatarSizes: chat.avatarSizes,
            ));
  } catch (e) {
    _showLinkError(context, e);
  }
}

/// Ответ на вступление обязан нести то место, куда звала карточка. Иначе —
/// поломка сервера, и показывать её нужно понятной ошибкой, а не падением
/// на `!` дальше по коду.
ServerDetail _serverOf(InviteJoinResult r) =>
    r.server ?? (throw StateError('Сервер не вернул сообщество после вступления'));

Chat _chatOf(InviteJoinResult r) =>
    r.chat ?? (throw StateError('Сервер не вернул группу после вступления'));

bool _isNotFound(Object e) => e is ApiException && e.statusCode == 404;

void _showLinkError(BuildContext context, Object e) {
  if (context.mounted) GlitchToast.show(context, errorMessage(e));
}

Future<bool> _confirmJoinGroup(BuildContext context, GroupInvitePreview preview) async {
  final name = preview.name ?? context.s.group;
  return glitchConfirm(
    context,
    title: context.s.groupJoinTitle(name),
    body: context.s.membersCount(preview.memberCount),
    confirmLabel: context.s.groupJoinButton,
    destructive: false,
    leading: GlitchAvatar(
      initials: GlitchAvatar.initialsFromName(name),
      size: 44,
      colorIndex: GlitchAvatar.colorFromNickname(name),
      imageUrl: preview.avatar != null ? api.mediaUrl(preview.avatar!) : null,
      avatarSizes: preview.avatarSizes,
    ),
  );
}
