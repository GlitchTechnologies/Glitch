import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/platform_info.dart';
import '../theme/glitch_palette.dart';
import 'glitch_action_button.dart';
import 'glitch_pressable.dart';

class StreamWatchPreview extends StatelessWidget {
  final Widget background;
  final VoidCallback? onWatch;
  final bool hoverOnly;

  const StreamWatchPreview({
    super.key,
    required this.background,
    required this.onWatch,
    this.hoverOnly = false,
  });

  @override
  Widget build(BuildContext context) => GlitchHoverArea(
        onTap: onWatch,
        hoverWhenDisabled: true,
        builder: (context, active) {
          final show = !hoverOnly || active || !hasPointerInput;
          return Stack(
            fit: StackFit.expand,
            children: [
              background,
              const ColoredBox(color: Color(0x59000000)),
              Center(
                child: Visibility(
                  visible: show,
                  child: GlitchActionButton(
                    label: context.s.voiceWatchStream,
                    soft: true,
                    compact: true,
                    softInk: GlitchPalette.dark(Colors.transparent).textPrimary,
                    onTap: onWatch,
                  ),
                ),
              ),
            ],
          );
        },
      );
}
