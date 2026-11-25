import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/message.dart' show Reaction;
import 'glitch_pressable.dart' show ClickableCursor;
import 'reaction_emoji.dart';

class ReactionPills extends StatelessWidget {
  final List<Reaction> reactions;
  final ValueChanged<String> onTap;
  const ReactionPills({super.key, required this.reactions, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        children: reactions.map((r) {
          final mine = r.reactedByMe;
          final bg = mine ? GlitchColors.accentBlue : GlitchColors.accentBlue.withOpacity(0.156);
          final fg = mine ? Colors.white : GlitchColors.textPrimary;
          return ClickableCursor(
            child: GestureDetector(
            onTap: () => onTap(r.emoji),
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 29,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ReactionEmoji(r.emoji, size: 17),
                  const SizedBox(width: 5),
                  Text('${r.count}', style: TextStyle(fontSize: 14, color: fg, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
