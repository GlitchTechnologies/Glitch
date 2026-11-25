import 'package:flutter/material.dart';

import '../theme/glitch_ink.dart';

class GlitchDivider extends StatelessWidget {
  final Axis axis;

  const GlitchDivider({super.key, this.axis = Axis.horizontal});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: axis == Axis.horizontal ? 1 : null,
        width: axis == Axis.vertical ? 1 : null,
        child: CustomPaint(
          painter: _DividerPainter(GlitchInk.of(context).borderMenu, axis),
          child: const Center(),
        ),
      );
}

class _DividerPainter extends CustomPainter {
  final Color color;
  final Axis axis;

  const _DividerPainter(this.color, this.axis);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0
      ..isAntiAlias = false;
    if (axis == Axis.horizontal) {
      canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), paint);
    } else {
      canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_DividerPainter oldDelegate) => color != oldDelegate.color || axis != oldDelegate.axis;
}
