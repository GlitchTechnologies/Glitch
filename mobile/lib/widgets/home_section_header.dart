import 'package:flutter/material.dart';

import '../core/adaptive_open.dart';
import '../core/shell_controller.dart';
import '../core/shell_metrics.dart';
import '../screens/home_section_screen.dart';
import '../theme/app_theme.dart';
import 'count_badge.dart';
import 'glitch_hover_row.dart';
import 'glitch_pressable.dart';
import 'glitch_icon_button.dart';

class HomeSectionHeader extends StatelessWidget {
  final HomeSection section;
  final List<Widget> tabs;

  const HomeSectionHeader({super.key, required this.section, required this.tabs});

  @override
  Widget build(BuildContext context) {
    final inCenter = ShellPlace.slotForBuild(context) == ShellSlot.main;
    return Container(
      height: kShellBarHeight,
      padding: EdgeInsets.fromLTRB(inCenter ? 20 : 4, 0, 12, 0),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: GlitchColors.border))),
      child: Row(
        children: [
          if (inCenter) ...[
            Icon(homeSectionIcon(section), size: 22, color: GlitchColors.textPrimary),
            const SizedBox(width: 10),
            Text(
              homeSectionTitle(context, section),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(color: GlitchColors.textHint, shape: BoxShape.circle),
              ),
            ),
          ] else
            GlitchIconButton(
              icon: Icon(Icons.arrow_back_rounded, color: GlitchColors.textPrimary),
              onTap: () => closeAdaptive(context),
            ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: tabs),
            ),
          ),
        ],
      ),
    );
  }
}

class HomeSectionTab extends StatelessWidget {
  final String label;
  final bool selected;
  final bool primary;
  final int badge;
  final VoidCallback onTap;

  const HomeSectionTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.primary = false,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: GlitchHoverArea(
          onTap: onTap,
          builder: (context, hover) {
            final Color bg;
            final Color fg;
            if (primary) {
              bg = selected ? Colors.transparent : GlitchColors.accentBlue;
              fg = selected ? GlitchColors.accentBlue : Colors.white;
            } else {
              bg = GlitchHoverRow.highlight(context, active: hover, selected: selected);
              fg = selected || hover ? GlitchColors.textPrimary : GlitchColors.textNavIdle;
            }
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(GlitchHoverRow.radius)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: fg)),
                  if (badge > 0) ...[
                    const SizedBox(width: 6),
                    CountBadge(count: badge),
                  ],
                ],
              ),
            );
          },
        ),
      );
}
