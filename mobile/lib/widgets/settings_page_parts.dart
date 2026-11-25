import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'glitch_pressable.dart' show ClickableCursor;


class SettingsBlockTitle extends StatelessWidget {
  final String text;
  const SettingsBlockTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary)),
      );
}

class SettingsLineRow extends StatelessWidget {
  final String label;
  final String? value;
  final String? link;
  final VoidCallback? onLink;
  final Widget? action;

  final VoidCallback? onTap;

  const SettingsLineRow({
    super.key,
    required this.label,
    this.value,
    this.link,
    this.onLink,
    this.action,
    this.onTap,
  }) : assert(action == null || onTap == null);

  @override
  Widget build(BuildContext context) {
    final value = this.value ?? '';
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14.5, color: GlitchColors.textPrimary),
            ),
          ),
          if (link != null) ...[
            const SizedBox(width: 6),
            ClickableCursor(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onLink,
                child: Text(link!, style: TextStyle(fontSize: 14.5, color: GlitchColors.accentBlue)),
              ),
            ),
          ],
          if (action != null) ...[const SizedBox(width: 14), action!],
          if (onTap != null) ...[
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, color: GlitchColors.textPrimary, size: 22),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return ClickableCursor(
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: row),
    );
  }
}
