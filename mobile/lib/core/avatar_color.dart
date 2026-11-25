library;

import 'dart:ui' show Color;

final _hexColor = RegExp(r'^#([0-9a-fA-F]{6})$');

Color? parseAvatarColor(dynamic raw) {
  if (raw is! String) return null;
  final match = _hexColor.firstMatch(raw.trim());
  if (match == null) return null;
  return Color(0xFF000000 | int.parse(match.group(1)!, radix: 16));
}

String? avatarColorToJson(Color? color) {
  if (color == null) return null;
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0')}';
}
