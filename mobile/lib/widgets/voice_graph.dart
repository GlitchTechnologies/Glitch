import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class VoiceGraph extends StatelessWidget {
  final List<int?> samples;
  final int keep;
  final int step;
  final int? badFrom;

  const VoiceGraph({super.key, required this.samples, required this.keep, required this.step, this.badFrom});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: GlitchColors.bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: CustomPaint(
          painter: _VoiceGraphPainter(
            samples: samples,
            keep: keep,
            step: step,
            badFrom: badFrom,
            line: GlitchColors.accentBlue,
            bad: GlitchColors.error,
            grid: GlitchColors.borderMenu,
            label: GlitchColors.textHint,
          ),
        ),
      );
}

class _VoiceGraphPainter extends CustomPainter {
  final List<int?> samples;
  final int keep;
  final int step;
  final int? badFrom;
  final Color line;
  final Color bad;
  final Color grid;
  final Color label;

  _VoiceGraphPainter({
    required this.samples,
    required this.keep,
    required this.step,
    required this.badFrom,
    required this.line,
    required this.bad,
    required this.grid,
    required this.label,
  });

  static const double _pad = 8;
  static const double _labelsWidth = 34;

  @override
  void paint(Canvas canvas, Size size) {
    final peak = samples.fold<int>(0, (m, v) => v == null ? m : math.max(m, v));
    final top = (math.max(1, (peak / step).ceil()) * step).toDouble();
    final plot = Rect.fromLTRB(_pad, _pad, size.width - _labelsWidth, size.height - _pad);

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final value in [top, top / 2, 0.0]) {
      final y = plot.bottom - plot.height * value / top;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      final text = TextPainter(
        text: TextSpan(text: value.round().toString(), style: TextStyle(fontSize: 10, color: label)),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset(plot.right + 6, y - text.height / 2));
    }

    if (samples.length < 2) return;
    final stepX = plot.width / (keep - 1);
    final path = Path();
    var drawing = false;
    for (var i = 0; i < samples.length; i++) {
      final v = samples[i];
      if (v == null) {
        drawing = false;
        continue;
      }
      final x = plot.right - (samples.length - 1 - i) * stepX;
      final y = plot.bottom - plot.height * math.min(v, top) / top;
      if (drawing) {
        path.lineTo(x, y);
      } else {
        path.moveTo(x, y);
        drawing = true;
      }
    }
    final last = samples.last;
    final isBad = badFrom != null && last != null && last >= badFrom!;
    canvas.drawPath(
      path,
      Paint()
        ..color = isBad ? bad : line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_VoiceGraphPainter old) =>
      !identical(old.samples, samples) ||
      old.keep != keep ||
      old.step != step ||
      old.badFrom != badFrom ||
      old.line != line ||
      old.bad != bad ||
      old.grid != grid ||
      old.label != label;
}
