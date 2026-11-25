import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SettingsTwoPane extends StatelessWidget {
  final Widget left;
  final Widget right;

  final bool windowed;

  final Widget? rightTop;

  const SettingsTwoPane({
    super.key,
    required this.left,
    required this.right,
    this.windowed = false,
    this.rightTop,
  });

  static const double sideWidth = 232;
  static const double contentMaxWidth = 740;

  static const double topPad = 56;

  static const double windowTopPad = 24;

  @override
  Widget build(BuildContext context) {
    if (windowed) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: GlitchColors.bgCard,
            child: SizedBox(width: sideWidth + 16, child: left),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (rightTop != null) rightTop!,
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: contentMaxWidth),
                      child: SizedBox.expand(child: right),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: ColoredBox(
            color: GlitchColors.bgCard,
            child: Align(
              alignment: Alignment.topRight,
              child: SizedBox(width: sideWidth + 16, child: left),
            ),
          ),
        ),
        Expanded(
          flex: 5,
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: contentMaxWidth),
              child: SizedBox.expand(child: right),
            ),
          ),
        ),
      ],
    );
  }
}
