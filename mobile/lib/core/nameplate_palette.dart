import 'package:flutter/material.dart';

import '../providers/theme_provider.dart';

/// ЦВЕТ ПЛАШКИ ИМЕНИ (2026-10-24, как у Discord) — заливка под картинкой
/// плашки. Набор и названия — сервера (`app/core/collectible.NAMEPLATE_PALETTES`,
/// как `palette` в API Discord); здесь — сами цвета: у каждого вариант для
/// тёмной темы (глубокий) и для светлой (мягкий), чтобы имя на заливке
/// читалось в обеих. Неизвестное название (новый цвет на сервере, старая
/// сборка) — без заливки.
const Map<String, ({Color dark, Color light})> _palettes = {
  'crimson': (dark: Color(0xFF8F1D2C), light: Color(0xFFF4B4BC)),
  'berry': (dark: Color(0xFF7A1F55), light: Color(0xFFEBB3D3)),
  'bubble_gum': (dark: Color(0xFFA33D7A), light: Color(0xFFF9C4E1)),
  'violet': (dark: Color(0xFF5B2E9E), light: Color(0xFFD3BFF5)),
  'cobalt': (dark: Color(0xFF1F3E99), light: Color(0xFFB5C6F5)),
  'sky': (dark: Color(0xFF1F6E9E), light: Color(0xFFB3DDF5)),
  'teal': (dark: Color(0xFF136B66), light: Color(0xFFA9E3DE)),
  'forest': (dark: Color(0xFF1F5130), light: Color(0xFFB6D8BE)),
  'clover': (dark: Color(0xFF2F7A2A), light: Color(0xFFC2EBB5)),
  'lemon': (dark: Color(0xFF8A7A12), light: Color(0xFFF5E9A3)),
  'white': (dark: Color(0xFFC9CDD4), light: Color(0xFFE6E8EC)),
};

const double kNameplateFillStrength = 0.525;

Color? nameplateColor(String? palette) {
  final pair = _palettes[palette];
  if (pair == null) return null;
  return themeProvider.isLight ? pair.light : pair.dark;
}
