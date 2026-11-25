import 'package:flutter/material.dart';

import '../core/adaptive_open.dart' show isWideLayout;
import '../core/current_place.dart';
import '../core/l10n.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../services/app_fullscreen.dart';
import '../services/desktop_shell.dart';
import '../services/desktop_window.dart';
import 'avatar_shape.dart';
import 'glitch_avatar.dart';
import 'glitch_glyph.dart';
import 'theme_workspace.dart';

class DesktopTitleBarFrame extends StatelessWidget {
  final Widget child;

  final bool showPlace;

  const DesktopTitleBarFrame({super.key, required this.child, this.showPlace = true});

  @override
  Widget build(BuildContext context) {
    final shell = desktopShell;
    if (shell == null) return child;
    final height = shell.titleBarHeight;
    final media = MediaQuery.of(context);
    return Column(
      children: [
        ListenableBuilder(
          listenable: Listenable.merge([themeProvider, appFullscreen]),
          builder: (context, _) => appFullscreen.value
              ? const SizedBox.shrink()
              : _TitleBar(height: height, showPlace: showPlace),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => MediaQuery(
              data: media.copyWith(
                size: box.biggest,
                padding: media.padding.copyWith(top: 0),
                viewPadding: media.viewPadding.copyWith(top: 0),
              ),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}

class _TitleBar extends StatelessWidget {
  final double height;
  final bool showPlace;

  const _TitleBar({required this.height, required this.showPlace});

  static const double _sideRoom = 150;

  static TextStyle _label() => TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: themeProvider.palette.textSecond,
      );

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ThemeWorkspace.frameSurface(context, desktopTitleBarColor()),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(
              key: const ValueKey('window-brand'),
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  children: [
                    GlitchGlyph(size: 14, color: themeProvider.palette.textSecond),
                    const SizedBox(width: 8),
                    Text('Glitch', style: _label()),
                  ],
                ),
              ),
            ),
            if (showPlace)
              Positioned.fill(
                key: const ValueKey('window-place'),
                left: _sideRoom,
                right: _sideRoom,
                child: Center(
                  child: ListenableBuilder(
                    listenable: currentPlaceChanges,
                    builder: (context, _) => _PlaceLabel(place: currentPlace(wide: isWideLayout(context))),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlaceLabel extends StatelessWidget {
  final CurrentPlace? place;

  const _PlaceLabel({required this.place});

  static const double _icon = 18;

  static const double _glyph = 16;

  @override
  Widget build(BuildContext context) {
    final p = place;
    if (p == null) return const SizedBox.shrink();
    final s = context.s;
    final (Widget icon, String name) = switch (p) {
      InServer(:final server) => (
          GlitchAvatar(
            initials: GlitchAvatar.initialsFromName(server.name),
            size: _icon,
            colorIndex: GlitchAvatar.colorFromNickname(server.name),
            imageUrl: server.avatar != null ? api.mediaUrl(server.avatar!) : null,
            avatarSizes: server.avatarSizes,
            shape: AvatarShape.community,
          ),
          server.name,
        ),
      InApp(:final place) => (
          GlitchGlyph(size: _glyph, color: themeProvider.palette.textPrimary),
          switch (place) {
            AppPlace.directMessages => s.tipDirectMessages,
            AppPlace.friends => s.homeFriends,
            AppPlace.messageRequests => s.homeMessageRequests,
            AppPlace.shop => s.homeShop,
            AppPlace.catalog => s.catalogTitle,
          },
        ),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: themeProvider.palette.textPrimary),
          ),
        ),
      ],
    );
  }
}
