import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class CountBadge extends StatelessWidget {
  final int count;

  final Color? outline;

  const CountBadge({super.key, required this.count, this.outline});

  static const double _height = 18;
  static const double _outlineWidth = 3;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final ring = outline;
    return Container(
      constraints: const BoxConstraints(minWidth: _height),
      height: _height,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: GlitchColors.badge,
        borderRadius: BorderRadius.circular(_height / 2 + (ring != null ? _outlineWidth : 0)),
        border: ring != null
            ? Border.all(color: ring, width: _outlineWidth, strokeAlign: BorderSide.strokeAlignOutside)
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}
