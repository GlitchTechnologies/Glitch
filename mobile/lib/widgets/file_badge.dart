import 'package:flutter/material.dart';

class FileBadge extends StatelessWidget {
  final String name;
  final double size;

  const FileBadge(this.name, {super.key, this.size = 44});

  static String label(String name) {
    if (!name.contains('.')) return '?';
    final ext = name.split('.').last.toUpperCase();
    return ext.length > 4 ? ext.substring(0, 4) : ext;
  }

  static const _colors = {
    'pdf': Color(0xFFe84545),
    'doc': Color(0xFF2b7af2), 'docx': Color(0xFF2b7af2),
    'xls': Color(0xFF2e9e5b), 'xlsx': Color(0xFF2e9e5b), 'csv': Color(0xFF2e9e5b),
    'ppt': Color(0xFFf07427), 'pptx': Color(0xFFf07427),
    'zip': Color(0xFFe6a817), 'rar': Color(0xFFe6a817), '7z': Color(0xFFe6a817),
    'txt': Color(0xFF7a7a7a), 'md': Color(0xFF7a7a7a),
    'mp3': Color(0xFF8b5cf6), 'wav': Color(0xFF8b5cf6), 'ogg': Color(0xFF8b5cf6),
    'm4a': Color(0xFF8b5cf6), 'flac': Color(0xFF8b5cf6), 'opus': Color(0xFF8b5cf6), 'oga': Color(0xFF8b5cf6),
  };

  static const _fallback = Color(0xFF5a7ea8);

  static Color colorOf(String name) =>
      _colors[name.split('.').last.toLowerCase()] ?? _fallback;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: colorOf(name), borderRadius: BorderRadius.circular(12)),
      alignment: Alignment.center,
      child: Text(
        label(name),
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}
