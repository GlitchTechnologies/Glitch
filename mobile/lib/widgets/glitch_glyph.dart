import 'package:flutter/material.dart';

class GlitchGlyph extends StatelessWidget {
  final double size;
  final Color color;

  const GlitchGlyph({super.key, required this.size, required this.color});

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _GlitchGlyphPainter(color)),
      );
}

class _GlitchGlyphPainter extends CustomPainter {
  final Color color;

  const _GlitchGlyphPainter(this.color);

  static const List<List<Offset>> _pieces = [
    [
      Offset(0.2, 0.8721), Offset(0.2559, 0.9135), Offset(0.3243, 0.9459),
      Offset(0.3946, 0.9658), Offset(0.5009, 0.9784), Offset(0.6198, 0.9766),
      Offset(0.7297, 0.9604), Offset(0.8234, 0.9297), Offset(0.9333, 0.8721),
    ],
    [
      Offset(0.0018, 0.4559), Offset(0.0036, 0.573), Offset(0.0216, 0.6649),
      Offset(0.0559, 0.7532), Offset(0.0937, 0.8144), Offset(0.1225, 0.8486),
      Offset(0.9712, 0.8486), Offset(0.9982, 0.8306), Offset(0.9982, 0.445),
      Offset(0.5568, 0.445), Offset(0.555, 0.4559), Offset(0.5027, 0.4559),
      Offset(0.5027, 0.627), Offset(0.6955, 0.6288), Offset(0.6955, 0.7135),
      Offset(0.6144, 0.7568), Offset(0.5459, 0.7748), Offset(0.5045, 0.773),
      Offset(0.4631, 0.7604), Offset(0.4144, 0.7297), Offset(0.3838, 0.6955),
      Offset(0.3622, 0.6523), Offset(0.3459, 0.5874), Offset(0.3405, 0.5351),
      Offset(0.3423, 0.445), Offset(0.0559, 0.445), Offset(0.0541, 0.4559),
    ],
    [
      Offset(0.9766, 0.1586), Offset(0.9387, 0.1135), Offset(0.8901, 0.0757),
      Offset(0.8306, 0.0468), Offset(0.7856, 0.0342), Offset(0.6847, 0.0216),
      Offset(0.5189, 0.0198), Offset(0.445, 0.0252), Offset(0.355, 0.0432),
      Offset(0.3027, 0.0631), Offset(0.245, 0.0955), Offset(0.1964, 0.1333),
      Offset(0.1514, 0.182), Offset(0.1189, 0.2306), Offset(0.0901, 0.2901),
      Offset(0.0685, 0.3604), Offset(0.0595, 0.4216), Offset(0.3459, 0.4216),
      Offset(0.3622, 0.3477), Offset(0.3946, 0.2901), Offset(0.4432, 0.2486),
      Offset(0.4685, 0.236), Offset(0.5081, 0.2252), Offset(0.5856, 0.2252),
      Offset(0.6216, 0.2342), Offset(0.6505, 0.2486), Offset(0.6865, 0.2829),
      Offset(0.7099, 0.3297), Offset(0.982, 0.2829), Offset(0.9856, 0.2793),
      Offset(0.9658, 0.2234), Offset(0.9297, 0.1604),
    ],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = Paint()..color = color;
    for (final piece in _pieces) {
      canvas.drawPath(Path()..addPolygon([for (final p in piece) p * s], true), paint);
    }
  }

  @override
  bool shouldRepaint(_GlitchGlyphPainter old) => old.color != color;
}
