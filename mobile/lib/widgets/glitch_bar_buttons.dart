import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'glitch_pressable.dart';


class GlitchFilledButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final bool destructive;

  const GlitchFilledButton({
    super.key,
    required this.label,
    required this.onTap,
    this.loading = false,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) => GlitchPressable(
        onTap: loading ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: destructive ? GlitchColors.error : GlitchColors.accentBlue,
            borderRadius: BorderRadius.circular(8),
          ),
          child: loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(
                  label,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                ),
        ),
      );
}

class GlitchPlainButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  const GlitchPlainButton({super.key, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) => GlitchPressable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Text(
            label,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color ?? GlitchColors.textPrimary),
          ),
        ),
      );
}
