import 'package:flutter/material.dart';

import '../providers/server_provider.dart';
import '../screens/home_section_screen.dart';
import '../screens/shop_screen.dart';
import 'collectibles.dart';
import 'shell_controller.dart';

Future<void> openShop(BuildContext context, {CollectibleKind? kind}) {
  final rootNavigator = Navigator.of(context, rootNavigator: true);
  rootNavigator.popUntil((route) => route.isFirst);
  if (shellController.hasListOverride) shellController.close(ShellSlot.list);
  serverRail.select(null);
  return openHomeSection(
    rootNavigator.context,
    HomeSection.shop,
    shopTab: kind != null ? shopTabOf(kind) : null,
  );
}
