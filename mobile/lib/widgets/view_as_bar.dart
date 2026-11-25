import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../main.dart' show navigatorKey;
import '../models/server.dart';
import '../providers/server_provider.dart';
import '../screens/server_settings_screen.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'glitch_dialog.dart' show GlitchCheckMark;
import 'glitch_menu.dart';
import 'glitch_pressable.dart';
import 'glitch_toast.dart';
import 'role_picker.dart' show RoleIcon;

/// ⚠️ Дерево под полосой ОДНО И ТО ЖЕ при включённом и выключенном режиме
/// (колонка из двух детей, второй всегда тот же) — иначе включение режима
/// пересоздало бы всё приложение с потерей состояния. Полоса стоит НАД
/// навигатором, поэтому её попап открывается в слое навигатора, а меню
/// пересчитывают координаты в этот слой сами (glitch_menu.dart, `glitchOverlayPoint`).
class ViewAsFrame extends StatelessWidget {
  final Widget child;

  const ViewAsFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: serverRail,
      child: child,
      builder: (context, app) {
        final active = serverRail.viewAs != null;
        final media = MediaQuery.of(context);
        return Column(
          children: [
            if (active) const _ViewAsBar() else const SizedBox.shrink(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => MediaQuery(
                  data: media.copyWith(
                    size: box.biggest,
                    padding: active ? media.padding.copyWith(top: 0) : media.padding,
                    viewPadding: active ? media.viewPadding.copyWith(top: 0) : media.viewPadding,
                  ),
                  child: app!,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ViewAsBar extends StatelessWidget {
  const _ViewAsBar();

  Future<void> _backToRoles() async {
    final v = serverRail.viewAs;
    if (v == null) return;
    serverRail.stopViewAs();
    try {
      final server = await api.getServer(v.serverId);
      final ctx = navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      await openServerSettings(ctx, server, section: ServerSettingsSection.roles);
    } catch (e) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) GlitchToast.show(ctx, errorMessage(e));
    }
  }

  void _pickRoles(BuildContext anchor) {
    openGlitchPopup(
      anchor,
      width: 268,
      builder: (close, maxHeight) => _RolesPopup(maxHeight: maxHeight),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final v = serverRail.viewAs!;
    final count = v.selected.length;
    final text = count == 0 ? s.viewAsBannerEveryone : s.viewAsBanner(count);
    final narrow = MediaQuery.of(context).size.width < 700;

    final back = _BarButton(icon: Icons.arrow_back_rounded, label: s.viewAsBack, onTap: _backToRoles);
    final pick = Builder(
      builder: (anchor) => _BarButton(
        label: s.viewAsPick,
        trailing: Icons.expand_more_rounded,
        onTap: () => _pickRoles(anchor),
      ),
    );
    final off = _BarButton(label: s.viewAsOff, onTap: serverRail.stopViewAs);
    final label = Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Colors.white),
    );

    return Material(
      color: GlitchColors.accentBlue,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: narrow
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    label,
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [back, pick, off],
                    ),
                  ],
                )
              : Row(
                  children: [
                    back,
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [Flexible(child: label), const SizedBox(width: 12), pick],
                      ),
                    ),
                    off,
                  ],
                ),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  final IconData? icon;
  final IconData? trailing;
  final String label;
  final VoidCallback onTap;

  const _BarButton({this.icon, this.trailing, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GlitchPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 15, color: Colors.white), const SizedBox(width: 6)],
            Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white)),
            if (trailing != null) ...[const SizedBox(width: 4), Icon(trailing, size: 16, color: Colors.white)],
          ],
        ),
      ),
    );
  }
}

class _RolesPopup extends StatelessWidget {
  final double maxHeight;

  const _RolesPopup({required this.maxHeight});

  @override
  Widget build(BuildContext context) {
    return GlitchPopupCard(
      maxHeight: maxHeight,
      child: ListenableBuilder(
        listenable: serverRail,
        builder: (context, _) {
          final v = serverRail.viewAs;
          if (v == null) return const SizedBox.shrink();
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 6),
            children: [
              for (final ServerRole r in v.roles)
                ClickableCursor(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      final next = {...v.selected};
                      if (!next.remove(r.id)) next.add(r.id);
                      serverRail.setViewAsRoles(next);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      child: Row(
                        children: [
                          RoleIcon(color: r.color),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              r.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14.5, color: GlitchColors.textPrimary),
                            ),
                          ),
                          GlitchCheckMark(value: v.selected.contains(r.id)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
