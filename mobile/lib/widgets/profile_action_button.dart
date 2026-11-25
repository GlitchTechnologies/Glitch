import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'glitch_pressable.dart';

class ProfileActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final LinearGradient? gradient;
  final Color textColor;
  final VoidCallback onTap;

  const ProfileActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.gradient,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlitchPressable(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          gradient: gradient,
          color: gradient == null ? GlitchColors.bgCard : null,
          border: gradient == null ? Border.all(color: GlitchColors.border) : null,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: textColor, size: 20),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(color: textColor, fontSize: 13.5, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
