import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../theme/app_theme.dart';
import 'glitch_action_button.dart';
import 'glitch_plus_badge.dart';
import 'glitch_plus_perks.dart';

class ShopGlitchPlusCard extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;
  final bool loading;

  const ShopGlitchPlusCard({super.key, required this.isActive, required this.onTap, this.loading = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: GlitchColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: GlitchColors.border),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [GlitchColors.accentBlue.withOpacity(0.12), GlitchColors.bgCard],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 20,
              runSpacing: 12,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const GlitchPlusBolt(size: 30),
                    const SizedBox(width: 8),
                    Text('Glitch+', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: GlitchColors.textPrimary)),
                  ],
                ),
                GlitchActionButton(
                  label: isActive ? context.s.settings : context.s.glitchPlusSubscribeButton,
                  compact: true,
                  loading: loading,
                  onTap: onTap,
                ),
              ],
            ),
            const SizedBox(height: 20),
            const GlitchPlusPerks(compact: true),
          ],
        ),
      );
}
