import 'package:flutter/material.dart';
import '../core/shell_metrics.dart';
import '../core/adaptive_open.dart';
import '../core/l10n.dart';
import '../core/shell_controller.dart';
import '../providers/theme_provider.dart' show ThemeAwareState;
import '../theme/app_theme.dart';
import 'friends_screen.dart';
import 'shop_screen.dart';
import '../widgets/glitch_icon_button.dart';

enum HomeSection { friends, messageRequests, shop }

String homeSlotKey(HomeSection section) => 'home:${section.name}';

IconData homeSectionIcon(HomeSection section) => switch (section) {
      HomeSection.friends => Icons.people_alt_rounded,
      HomeSection.messageRequests => Icons.mail_rounded,
      HomeSection.shop => Icons.storefront_rounded,
    };

String homeSectionTitle(BuildContext context, HomeSection section) => switch (section) {
      HomeSection.friends => context.s.homeFriends,
      HomeSection.messageRequests => context.s.homeMessageRequests,
      HomeSection.shop => context.s.homeShop,
    };

Future<void> openHomeSection(
  BuildContext context,
  HomeSection section, {
  FriendsTab? friendsTab,
  ShopTab? shopTab,
}) {
  final friendsRequest = friendsTab != null ? FriendsTabRequest(friendsTab) : null;
  final shopRequest = shopTab != null ? ShopTabRequest(shopTab) : null;
  return openAdaptive(
    context,
    slotKey: homeSlotKey(section),
    builder: (_) => homeSectionScreen(section, friendsRequest: friendsRequest, shopRequest: shopRequest),
  );
}

Widget homeSectionScreen(HomeSection section, {FriendsTabRequest? friendsRequest, ShopTabRequest? shopRequest}) =>
    switch (section) {
      HomeSection.friends => FriendsScreen(request: friendsRequest),
      HomeSection.shop => ShopScreen(request: shopRequest),
      _ => HomeSectionScreen(section: section),
    };

class HomeSectionScreen extends StatefulWidget {
  final HomeSection section;

  const HomeSectionScreen({super.key, required this.section});

  @override
  State<HomeSectionScreen> createState() => _HomeSectionScreenState();
}

class _HomeSectionScreenState extends State<HomeSectionScreen>
    with ThemeAwareState<HomeSectionScreen> {
  @override
  Widget build(BuildContext context) {
    final title = homeSectionTitle(context, widget.section);
    final inCenter = ShellPlace.slotForBuild(context) == ShellSlot.main;
    return Scaffold(
      backgroundColor: GlitchColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: kShellBarHeight,
              padding: EdgeInsets.fromLTRB(inCenter ? 20 : 4, 0, 16, 0),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: GlitchColors.border)),
              ),
              child: Row(
                children: [
                  if (inCenter)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Icon(homeSectionIcon(widget.section), size: 22, color: GlitchColors.textPrimary),
                    )
                  else
                    GlitchIconButton(
                      icon: Icon(Icons.arrow_back_rounded, color: GlitchColors.textPrimary),
                      onTap: () => closeAdaptive(context),
                    ),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: GlitchColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(homeSectionIcon(widget.section), size: 56, color: GlitchColors.textHint),
                      const SizedBox(height: 16),
                      Text(
                        context.s.homeSectionSoon,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15, color: GlitchColors.textPrimary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
