import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'recording_chip.dart';

class RecordLockIndicator extends StatelessWidget {
  final bool visible;
  final double progress;

  static const double width = RecordingChip.slotWidth;
  static const double height = RecordingChip.height;

  const RecordLockIndicator({
    super.key,
    required this.visible,
    this.progress = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    final tint = Color.lerp(GlitchColors.textSecond, GlitchColors.accentBlue, p)!;

    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 150),
        child: AnimatedScale(
          scale: visible ? 1.0 : 0.7,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutBack,
          child: Transform.translate(
            offset: Offset(0, -p * 8),
            child: RecordingChip(
              width: width,
              child: Icon(
                p > 0.75 ? Icons.lock_rounded : Icons.lock_open_rounded,
                color: tint,
                size: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
