import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'glitch_dialog.dart' show glitchWindowShape;

class MessageCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  final Color? color;

  const MessageCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(12, 10, 12, 10),
    this.color,
  });

  static const double radius = 12;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: ShapeDecoration(
        color: color ?? GlitchColors.bgCard,
        shape: glitchWindowShape(radius: radius, outline: GlitchColors.borderMessageCard),
      ),
      child: child,
    );
  }
}
