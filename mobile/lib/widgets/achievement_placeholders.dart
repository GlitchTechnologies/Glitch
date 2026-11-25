import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../core/l10n.dart';
import 'achievement_tooltip.dart';
import 'glitch_tooltip.dart' show kTooltipScale;

class AchievementPlaceholders extends StatelessWidget {
  final double size;
  final double gap;
  const AchievementPlaceholders({super.key, required this.size, required this.gap});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Align(
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < 3; index++)
                  Padding(
                    padding: EdgeInsets.only(right: index < 2 ? gap : 0),
                    child: AchievementTooltipContent(
                      name: context.s.achievementPossible,
                      description: context.s.achievementPatience,
                      picture: CustomPaint(
                        size: const Size.square(80 * kTooltipScale),
                        painter: _PlaceholderPainter(index, GlitchColors.textSecond.withOpacity(0.65)),
                      ),
                      child: CustomPaint(
                        size: Size.square(size),
                        painter: _PlaceholderPainter(index, GlitchColors.textSecond.withOpacity(0.65)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}

class _PlaceholderPainter extends CustomPainter {
  final int kind;
  final Color color;
  const _PlaceholderPainter(this.kind, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 40, size.height / 40);
    final paths = <Path>[];
    if (kind == 0) {
      paths.add(Path()
        ..moveTo(11, 6)..lineTo(29, 6)..lineTo(28, 17)
        ..cubicTo(27, 23, 23, 26, 20, 26)
        ..cubicTo(17, 26, 13, 23, 12, 17)..close());
      paths.add(Path()..moveTo(11, 9)..lineTo(5, 9)
        ..cubicTo(5, 18, 8, 21, 13, 21));
      paths.add(Path()..moveTo(29, 9)..lineTo(35, 9)
        ..cubicTo(35, 18, 32, 21, 27, 21));
      paths.add(Path()..moveTo(20, 26)..lineTo(20, 31));
      paths.add(Path()..moveTo(14, 31)..lineTo(26, 31)
        ..lineTo(28, 35)..lineTo(12, 35)..close());
    } else if (kind == 1) {
      paths.add(Path()..moveTo(20, 5)..lineTo(33, 12)..lineTo(33, 28)
        ..lineTo(20, 35)..lineTo(7, 28)..lineTo(7, 12)..close());
    } else {
      paths.add(Path()..moveTo(20, 5)..lineTo(33, 10)..lineTo(32, 23)
        ..quadraticBezierTo(30, 30, 20, 35)
        ..quadraticBezierTo(10, 30, 8, 23)..lineTo(7, 10)..close());
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final path in paths) {
      for (final metric in path.computeMetrics()) {
        for (double distance = 0; distance < metric.length; distance += 5) {
          canvas.drawPath(metric.extractPath(distance, (distance + 2.5).clamp(0, metric.length)), paint);
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PlaceholderPainter oldDelegate) => oldDelegate.kind != kind || oldDelegate.color != color;
}
