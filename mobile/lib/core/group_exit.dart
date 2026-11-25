import 'package:flutter/widgets.dart';
import 'adaptive_open.dart' show closeAdaptiveAll;
import 'l10n.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/glitch_dialog.dart';
import '../widgets/glitch_toast.dart';


Future<void> leaveGroup(int chatId) async {
  final me = authService.currentUser;
  if (me == null) return;
  await api.removeMember(chatId, me.id);
}

Future<void> confirmLeaveGroup(BuildContext context, int chatId) async {
  final s = context.s;
  final agreed = await glitchConfirm(context, title: s.groupLeaveTitle, confirmLabel: s.logout);
  if (!agreed || !context.mounted) return;
  await _run(context, () => leaveGroup(chatId));
}

Future<void> confirmDeleteGroup(BuildContext context, int chatId) async {
  final s = context.s;
  final agreed = await glitchConfirm(context,
      title: s.groupDeleteTitle, body: s.groupDeleteBody, confirmLabel: s.delete);
  if (!agreed || !context.mounted) return;
  await _run(context, () => api.deleteChat(chatId));
}

Future<void> _run(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
    if (context.mounted) closeAdaptiveAll(context);
  } catch (e) {
    if (context.mounted) GlitchToast.show(context, errorMessage(e));
  }
}
