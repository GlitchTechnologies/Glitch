import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../theme/app_theme.dart';
import 'chat_metrics.dart' show kMessageRowPadLeft, kMessageRowPadRight;
import 'glitch_action_button.dart';
import 'selection_contrast_text.dart';

class RoomWelcomeHeader extends StatelessWidget {
  final String roomName;
  final VoidCallback? onSetup;

  final bool setupLoading;

  const RoomWelcomeHeader({super.key, required this.roomName, this.onSetup, this.setupLoading = false});

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kMessageRowPadLeft, 16, kMessageRowPadRight, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(color: GlitchColors.bgChip, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(Icons.tag_rounded, size: 40, color: GlitchColors.textPrimary),
          ),
          const SizedBox(height: 12),
          Text(
            s.roomWelcomeTitle(roomName),
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: GlitchColors.textPrimary, height: 1.2),
          ),
          const SizedBox(height: 6),
          SelectionContrastText(
            Text(
              s.roomWelcomeBody(roomName),
              style: TextStyle(fontSize: 14.5, color: GlitchColors.textSecond),
            ),
          ),
          if (onSetup != null) ...[
            const SizedBox(height: 14),
            SelectionContainer.disabled(
              child: GlitchActionButton(
                label: s.roomWelcomeSetup,
                icon: Icons.edit_rounded,
                soft: true,
                compact: true,
                loading: setupLoading,
                onTap: onSetup,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
