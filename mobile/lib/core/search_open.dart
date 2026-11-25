import 'package:flutter/widgets.dart';

import '../models/chat_arrival.dart';
import '../models/search.dart';
import '../services/api_service.dart';
import '../widgets/glitch_toast.dart';
import '../widgets/search_window.dart';
import '../widgets/server_rail.dart' show revealServerInRail;
import 'chat_open.dart';
import 'personal_chat_open.dart';

Future<void> openSearchWindow(BuildContext context) async {
  final hit = await showSearchWindow(context);
  if (hit == null || !context.mounted) return;
  await openSearchHit(context, hit);
}

Future<void> openSearchHit(BuildContext context, SearchHit hit, {ChatArrival? arrival}) async {
  switch (hit.kind) {
    case SearchKind.person:
      final p = hit.person!;
      await openPersonalChat(
        context,
        nickname: p.nickname,
        displayName: p.displayName,
        avatar: p.avatar,
        avatarSizes: p.avatarSizes,
        arrival: arrival,
      );
    case SearchKind.group:
      try {
        await openChatById(context, hit.group!.id, arrival: arrival);
      } catch (e) {
        if (context.mounted) GlitchToast.show(context, errorMessage(e));
      }
    case SearchKind.room:
      final r = hit.room!;
      revealServerInRail(Navigator.of(context, rootNavigator: true), r.serverId, roomId: r.id, arrival: arrival);
    case SearchKind.server:
      revealServerInRail(Navigator.of(context, rootNavigator: true), hit.server!.id);
  }
}
