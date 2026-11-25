import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum EdgePillState {
  none,

  unread,

  hover,

  selected,
}

class EdgePill extends StatelessWidget {
  final EdgePillState state;

  const EdgePill({super.key, required this.state});

  static const double width = 4;

  static double heightOf(EdgePillState state) => switch (state) {
        EdgePillState.none => 0,
        EdgePillState.unread => 8,
        EdgePillState.hover => 20,
        EdgePillState.selected => 40,
      };

  static const Duration _kGrow = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: _kGrow,
        curve: Curves.easeOut,
        width: width,
        height: heightOf(state),
        decoration: BoxDecoration(
          color: GlitchColors.textPrimary,
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(width)),
        ),
      );
}
