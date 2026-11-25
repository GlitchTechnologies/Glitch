import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../theme/app_theme.dart';
import 'message_action_icons.dart';

class ForwardedFrame extends StatelessWidget {
  final Widget child;

  const ForwardedFrame({super.key, required this.child});

  static const double _stripe = 4;
  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: _gap),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: GlitchColors.border, width: _stripe)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(kForwardIcon, size: 14, color: GlitchColors.textSecond),
              const SizedBox(width: 4),
              Text(
                context.s.forwarded,
                style: TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic, color: GlitchColors.textSecond),
              ),
            ]),
          ),
          child,
        ],
      ),
    );
  }
}
