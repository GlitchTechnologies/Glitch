import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class RecordingChip extends StatelessWidget {
  final Widget child;

  final double? width;

  static const double height = 52;

  static const double slotWidth = 44;

  static const double _radius = 18;

  const RecordingChip({super.key, required this.child, this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: GlitchColors.bgCard,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: GlitchColors.borderCard),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
