import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AuthorTag extends StatelessWidget {
  final String label;

  const AuthorTag(this.label, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: GlitchColors.accentBlue,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            height: 1.2,
          ),
        ),
      );
}
