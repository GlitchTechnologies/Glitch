import 'package:flutter/widgets.dart';
import 'l10n.dart';
import '../models/server.dart' show ServerDetail, ServerGoneReason;
import '../providers/server_provider.dart' show serverRail;
import '../services/api_service.dart';
import '../widgets/glitch_dialog.dart';
import '../widgets/glitch_toast.dart';

Future<void> confirmLeaveServer(BuildContext context, ServerDetail server) async {
  final s = context.s;
  final agreed = await glitchConfirm(
    context,
    title: s.serverLeaveTitle(server.name),
    body: server.isPublic ? s.serverLeaveBodyPublic : s.serverLeaveBodyPrivate,
    confirmLabel: s.serverLeave,
  );
  if (!agreed) return;
  try {
    await api.leaveServer(server.id);
    serverRail.forget(server.id, ServerGoneReason.left);
  } catch (e) {
    if (context.mounted) GlitchToast.show(context, errorMessage(e));
  }
}
