import 'package:flutter/foundation.dart';

import '../models/server.dart';
import '../providers/server_provider.dart';
import '../screens/home_section_screen.dart' show HomeSection, homeSlotKey;
import '../services/auth_service.dart';
import '../services/center_place.dart';
import 'adaptive_open.dart';
import 'shell_controller.dart';

sealed class CurrentPlace {
  const CurrentPlace();
}

final class InServer extends CurrentPlace {
  final ServerListItem server;

  const InServer(this.server);
}

final class InApp extends CurrentPlace {
  final AppPlace place;

  const InApp(this.place);
}

enum AppPlace { directMessages, friends, messageRequests, shop, catalog }

CurrentPlace? currentPlace({required bool wide}) {
  if (authService.currentUser == null) return null;
  final space = serverRail.space;
  if (space is CatalogScope) return const InApp(AppPlace.catalog);
  final serverId = serverIdOfScope(space);
  if (serverId != null) {
    for (final s in serverRail.servers) {
      if (s.id == serverId) return InServer(s);
    }
    return null;
  }
  final layers = centerPlace.layers(wide: wide);
  final top = layers.isEmpty ? null : layers.first.slotKey;
  return InApp(switch (top) {
    _ when top == homeSlotKey(HomeSection.friends) => AppPlace.friends,
    _ when top == homeSlotKey(HomeSection.messageRequests) => AppPlace.messageRequests,
    _ when top == homeSlotKey(HomeSection.shop) => AppPlace.shop,
    _ => AppPlace.directMessages,
  });
}

final Listenable currentPlaceChanges = Listenable.merge([
  authService.currentUserListenable,
  serverRail,
  shellController,
  centerPlace,
]);
