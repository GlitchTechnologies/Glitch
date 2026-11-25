import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../theme/app_theme.dart';

class GlitchPlusPerks extends StatelessWidget {
  final bool compact;

  const GlitchPlusPerks({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final perks = [
      (Icons.gif_box_rounded, s.glitchPlusPerkGifTitle, s.glitchPlusPerkGifDesc),
      (Icons.workspace_premium_rounded, s.glitchPlusPerkBadgeTitle, s.glitchPlusPerkBadgeDesc),
      (Icons.sticky_note_2_rounded, s.glitchPlusPerkStickersTitle, s.glitchPlusPerkStickersDesc),
      if (!compact) (Icons.cloud_upload_outlined, s.glitchPlusPerkLimitsTitle, s.soon),
    ];
    if (compact) {
      return LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: 24,
          runSpacing: 16,
          children: [
            for (final (icon, title, subtitle) in perks)
              SizedBox(
                key: ValueKey(icon),
                width: constraints.maxWidth < 240 ? constraints.maxWidth : 240,
                child: _perkRow(icon, title, subtitle),
              ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.glitchPlusPerksTitle, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary)),
        const SizedBox(height: 14),
        for (final (icon, title, subtitle) in perks)
          Padding(
            key: ValueKey(icon),
            padding: const EdgeInsets.only(bottom: 16),
            child: _perkRow(icon, title, subtitle),
          ),
      ],
    );
  }

  Widget _perkRow(IconData icon, String title, String subtitle) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: compact ? 32 : 42,
            height: compact ? 32 : 42,
            decoration: BoxDecoration(gradient: GlitchColors.gradientAccent, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: compact ? 18 : 21),
          ),
          SizedBox(width: compact ? 10 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 13, color: GlitchColors.textPrimary)),
              ],
            ),
          ),
        ],
      );
}
