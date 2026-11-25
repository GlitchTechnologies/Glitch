import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../theme/app_theme.dart';
import 'glitch_action_button.dart';
import 'glitch_pressable.dart';


class SettingsCard extends StatelessWidget {
  final Widget child;

  const SettingsCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: GlitchColors.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: GlitchColors.borderSoft),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
}

class SettingsBackLine extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const SettingsBackLine({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GlitchPressable(
        onTap: onTap,
        child: Row(
          children: [
            Icon(Icons.chevron_left_rounded, size: 22, color: GlitchColors.textPrimary),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: GlitchColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      );
}

class SettingsNotice extends StatelessWidget {
  final String text;
  final IconData icon;
  final Widget? trailing;

  const SettingsNotice({
    super.key,
    required this.text,
    this.icon = Icons.lock_outline_rounded,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: GlitchColors.bgInput,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: GlitchColors.textSecond),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: 13, height: 1.3, color: GlitchColors.textPrimary),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          ],
        ),
      );
}

class SettingsRetry extends StatelessWidget {
  final String text;
  final VoidCallback onRetry;

  const SettingsRetry({super.key, required this.text, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: GlitchColors.textPrimary),
              ),
              const SizedBox(height: 12),
              GlitchActionButton(
                label: context.s.retry,
                onTap: onRetry,
                soft: true,
              ),
            ],
          ),
        ),
      );
}

class SettingsNavTile extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String subtitle;

  final bool subtitleStrong;
  final VoidCallback onTap;

  final Widget? trailing;

  const SettingsNavTile({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    required this.subtitle,
    this.subtitleStrong = false,
    required this.onTap,
    this.trailing,
  }) : assert((icon == null) != (leading == null), 'нужен ровно один: icon или leading');

  static const double tileSize = 40;
  static const double tileGap = 14;

  @override
  Widget build(BuildContext context) => ClickableCursor(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                leading ??
                    Container(
                      width: tileSize,
                      height: tileSize,
                      decoration: BoxDecoration(color: GlitchColors.bgChip, borderRadius: BorderRadius.circular(10)),
                      child: Icon(icon, size: 20, color: GlitchColors.textPrimary),
                    ),
                const SizedBox(width: tileGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: subtitleStrong ? GlitchColors.textPrimary : GlitchColors.textSecond,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                trailing ?? Icon(Icons.chevron_right_rounded, size: 24, color: GlitchColors.textSecond),
              ],
            ),
          ),
        ),
      );
}
