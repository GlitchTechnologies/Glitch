import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'glitch_palette.dart';

class CustomTheme {
  static const maxColors = 5;

  final bool light;
  final List<Color> colors;
  final int angle;
  final int intensity;

  CustomTheme({required this.light, required List<Color> colors, required this.angle, required this.intensity})
      : assert(colors.isNotEmpty && colors.length <= maxColors),
        assert(angle >= 0 && angle <= 360),
        assert(intensity >= 0 && intensity <= 100),
        colors = List.unmodifiable(colors);

  GlitchThemePreset get base => light ? GlitchThemePreset.light : GlitchThemePreset.dark;

  GlitchPalette palette(Color accent) {
    final preset = base.palette(accent);
    return light
        ? preset.copyWith(
            hoverTint: const Color(0x12000000),
            textSecond: const Color(0xFF444444),
            textHint: const Color(0xFF515151),
            textDim: const Color(0xFF4B4B4B),
            textNavIdle: const Color(0xFF3E3E3E),
          )
        : preset.copyWith(
            hoverTint: const Color(0x1AFFFFFF),
            textSecond: const Color(0xFFD3D3D3),
            textHint: const Color(0xFFC4C4C4),
            textDim: const Color(0xFFCDCDCD),
            textNavIdle: const Color(0xFFD7D7D7),
          );
  }

  CustomTheme copyWith({bool? light, List<Color>? colors, int? angle, int? intensity}) => CustomTheme(
        light: light ?? this.light,
        colors: colors ?? this.colors,
        angle: angle ?? this.angle,
        intensity: intensity ?? this.intensity,
      );

  static List<Color> _stops(List<Color> colors) => colors.length == 1 ? [colors.single, colors.single] : colors;

  LinearGradient get swatch => LinearGradient(colors: _stops(colors));

  LinearGradient background(GlitchPalette palette, Size size) {
    final ink = palette.textHint.computeLuminance();
    final stops = _stops([
      for (final color in colors) _readableStop(Color.lerp(palette.bg, color, intensity / 100)!, ink),
    ]);
    if (size.isEmpty) return LinearGradient(colors: stops);

    final radians = angle * math.pi / 180;
    final dx = -math.sin(radians);
    final dy = math.cos(radians);
    final span = size.width * dx.abs() + size.height * dy.abs();
    final end = Alignment(dx * span / size.width, dy * span / size.height);
    return LinearGradient(begin: Alignment(-end.x, -end.y), end: end, colors: stops);
  }

  Color _readableStop(Color stop, double ink) {
    const minContrast = 4.5;
    bool readable(Color color) {
      if (!light) return (ink + 0.05) / (color.computeLuminance() + 0.05) >= minContrast;
      final floor = math.min(color.red, math.min(color.green, color.blue));
      final luminance = Color.fromARGB(255, floor, floor, floor).computeLuminance();
      return (luminance + 0.05) / (ink + 0.05) >= minContrast;
    }

    if (readable(stop)) return stop;
    final neutral = light ? Colors.white : Colors.black;
    var safe = 0.0;
    var unsafe = 1.0;
    for (var step = 0; step < 9; step++) {
      final fraction = (safe + unsafe) / 2;
      if (readable(Color.lerp(neutral, stop, fraction)!)) {
        safe = fraction;
      } else {
        unsafe = fraction;
      }
    }
    return Color.lerp(neutral, stop, safe)!;
  }

  Map<String, Object> toJson() => {
        'light': light,
        'colors': [for (final color in colors) color.value & 0xFFFFFF],
        'angle': angle,
        'intensity': intensity,
      };

  static CustomTheme? fromJson(Object? value) {
    if (value is! Map) return null;
    final light = value['light'];
    final colors = value['colors'];
    final angle = value['angle'];
    final intensity = value['intensity'];
    if (light is! bool || colors is! List || colors.isEmpty || colors.length > maxColors ||
        angle is! int || angle < 0 || angle > 360 ||
        intensity is! int || intensity < 0 || intensity > 100) return null;
    final decoded = <Color>[];
    for (final color in colors) {
      if (color is! int || color < 0 || color > 0xFFFFFF) return null;
      decoded.add(Color(0xFF000000 | color));
    }
    return CustomTheme(light: light, colors: decoded, angle: angle, intensity: intensity);
  }
}
