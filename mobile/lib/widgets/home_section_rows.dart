import 'package:flutter/material.dart';
import '../core/shell_controller.dart';
import '../providers/friends.dart';
import '../screens/home_section_screen.dart';
import '../theme/app_theme.dart';
import 'count_badge.dart';
import 'glitch_hover_row.dart';

class HomeSectionRows extends StatelessWidget {
  const HomeSectionRows({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([shellController, friends]),
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final section in HomeSection.values) _row(context, section),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, HomeSection section) {
    return GlitchHoverRow(
      onTap: () => openHomeSection(context, section),
      selected: shellController.mainKey == homeSlotKey(section),
      builder: (active) {
        final color = active ? GlitchColors.textPrimary : GlitchColors.textNavIdle;
        return Row(
          children: [
            Icon(homeSectionIcon(section), size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                homeSectionTitle(context, section),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, color: color),
              ),
            ),
            if (section == HomeSection.friends) CountBadge(count: friends.incomingCount),
          ],
        );
      },
    );
  }
}
