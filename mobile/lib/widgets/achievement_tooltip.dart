import 'package:flutter/material.dart';

import '../models/achievement.dart';
import '../theme/app_theme.dart';
import 'achievement_picture.dart';
import 'glitch_tooltip.dart';

class AchievementTooltip extends StatelessWidget {
  final Achievement achievement;
  final Widget child;

  const AchievementTooltip({super.key, required this.achievement, required this.child});

  @override
  Widget build(BuildContext context) => AchievementTooltipContent(
        name: achievement.name,
        description: achievement.description,
        picture: AchievementPicture(achievement: achievement, size: 80 * kTooltipScale),
        child: child,
      );
}

class AchievementTooltipContent extends StatelessWidget {
  final String name;
  final String description;
  final Widget picture;
  final Widget child;

  const AchievementTooltipContent({super.key, required this.name, required this.description,
    required this.picture, required this.child});

  @override
  Widget build(BuildContext context) => GlitchTooltip.rich(
        content: SizedBox(
          width: 200 * kTooltipScale,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10 * kTooltipScale),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: picture,
                ),
                const SizedBox(height: 14 * kTooltipScale),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14 * kTooltipScale, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary),
                ),
                const SizedBox(height: 6 * kTooltipScale),
                Flexible(
                  child: Text(
                    description,
                    textAlign: TextAlign.center,
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12 * kTooltipScale, fontWeight: FontWeight.w400, height: 1.35, color: GlitchColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ),
        child: child,
      );
}
