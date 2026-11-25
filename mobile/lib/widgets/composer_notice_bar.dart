import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'chat_metrics.dart';
import 'theme_workspace.dart';

class ComposerNoticeBar extends StatelessWidget {
  final IconData icon;
  final String text;

  final Color color;

  const ComposerNoticeBar({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: ThemeWorkspace.surface(context, GlitchColors.bg, tint: ThemeWorkspace.barTint),
        border: Border(
          top: BorderSide(color: ThemeWorkspace.surface(context, GlitchColors.borderSoft)),
        ),
      ),
      child: ChatContentWidth(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 17),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
