import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class UserDisplayName extends StatelessWidget {
  final String displayName;
  final bool isGlitchPlus;
  final TextStyle style;
  final double badgeSize;

  final bool ellipsis;

  const UserDisplayName({
    super.key,
    required this.displayName,
    required this.isGlitchPlus,
    required this.style,
    this.badgeSize = 20,
    this.ellipsis = false,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultSelectionStyle.merge(
      mouseCursor: DefaultSelectionStyle.of(context).mouseCursor ?? SystemMouseCursors.basic,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ellipsis)
            Flexible(child: Text(displayName, style: style, maxLines: 1, overflow: TextOverflow.ellipsis))
          else
            Text(displayName, style: style),
          if (isGlitchPlus) ...[
            const SizedBox(width: 6),
            GlitchPlusBolt(size: badgeSize),
          ],
        ],
      ),
    );
  }
}

class GlitchPlusBolt extends StatelessWidget {
  final double size;

  const GlitchPlusBolt({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.bolt_rounded, color: GlitchColors.accentBlue, size: size);
}
