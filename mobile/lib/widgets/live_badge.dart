import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class LiveBadge extends StatelessWidget {
  final String label;

  final double scale;

  const LiveBadge(this.label, {super.key, this.scale = 1});

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 2 * scale),
        decoration: BoxDecoration(
          color: GlitchColors.live,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label, style: liveBadgeTextStyleOf(scale)),
      );
}

TextStyle liveBadgeTextStyleOf(double scale) =>
    scale == 1 ? liveBadgeTextStyle : liveBadgeTextStyle.copyWith(fontSize: liveBadgeTextStyle.fontSize! * scale);

const TextStyle liveBadgeTextStyle = TextStyle(
  color: Colors.white,
  fontSize: 10,
  fontWeight: FontWeight.w800,
  letterSpacing: 0.3,
  height: 1.2,
);
