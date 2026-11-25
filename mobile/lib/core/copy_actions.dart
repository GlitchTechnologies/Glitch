import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glitch_link.dart';
import 'l10n.dart';
import '../widgets/glitch_menu.dart' show glitchMenuRow;
import '../widgets/glitch_toast.dart';


Future<void> copyToClipboard(BuildContext context, String text, String message) async {
  if (text.isEmpty) return;
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  GlitchToast.show(context, message, type: ToastType.success);
}

Future<void> copyNickname(BuildContext context, String nickname) =>
    copyToClipboard(context, nickname.isEmpty ? '' : '@$nickname', context.s.nicknameCopied);

Future<void> copyInviteLink(BuildContext context, String code) =>
    copyToClipboard(context, inviteLinkShort(code), context.s.linkCopied);

Future<void> copyMessageLink(BuildContext context, String link) =>
    copyToClipboard(context, link, context.s.linkCopied);

Future<void> copyMessageText(BuildContext context, String text) =>
    copyToClipboard(context, text, context.s.messageCopied);

enum IdKind { user, group, server, channel, category, role, message }

Future<void> copyId(BuildContext context, int id) =>
    copyToClipboard(context, '$id', context.s.idCopied);

Widget copyIdMenuRow(BuildContext context, IdKind kind) {
  final s = context.s;
  final label = switch (kind) {
    IdKind.user => s.copyIdUser,
    IdKind.group => s.copyIdGroup,
    IdKind.server => s.copyIdServer,
    IdKind.channel => s.copyIdChannel,
    IdKind.category => s.copyIdCategory,
    IdKind.role => s.copyIdRole,
    IdKind.message => s.copyIdMessage,
  };
  return glitchMenuRow(Icons.numbers_rounded, label);
}
