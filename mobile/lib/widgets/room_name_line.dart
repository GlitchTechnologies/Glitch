import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class RoomNameLine extends StatelessWidget {
  final String name;

  final String? category;
  final TextStyle style;

  const RoomNameLine({super.key, required this.name, this.category, required this.style});

  @override
  Widget build(BuildContext context) {
    final size = style.fontSize ?? 14;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.tag_rounded, size: size + 4, color: GlitchColors.textHint),
        const SizedBox(width: 6),
        Flexible(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: name, style: style),
              if (category != null)
                TextSpan(
                  text: '  ${category!.toUpperCase()}',
                  style: TextStyle(
                    fontSize: size - 2,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: GlitchColors.textHint,
                  ),
                ),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
