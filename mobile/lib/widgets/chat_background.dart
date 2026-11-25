import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'theme_workspace.dart';

class ChatBackground extends StatelessWidget {
  final Widget child;
  const ChatBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: ThemeWorkspace.surface(context, GlitchColors.bg),
      child: child,
    );
  }
}
