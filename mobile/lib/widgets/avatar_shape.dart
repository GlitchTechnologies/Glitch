import 'dart:math' as math;

import 'package:flutter/material.dart';

enum AvatarShape {
  circle,
  roundedSquare;

  static const person = circle;

  static const group = circle;

  static const community = roundedSquare;

  static const double _squareRadiusFactor = 14 / 44;

  double radius(double size) => switch (this) {
        AvatarShape.circle => size / 2,
        AvatarShape.roundedSquare => size * _squareRadiusFactor,
      };

  BorderRadius borderRadius(double size) => BorderRadius.circular(radius(size));

  BorderRadius ringRadius(double size, double ring) =>
      BorderRadius.circular(radius(size) + ring);

  double cornerPoint(double size) {
    final r = radius(size);
    return size - r * (1 - math.sqrt1_2);
  }

  Widget clip({required double size, required Widget child}) =>
      ClipRRect(borderRadius: borderRadius(size), child: child);

  Path outline(Rect rect) => Path()
    ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius(rect.shortestSide))));
}
