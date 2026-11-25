import 'package:flutter/material.dart';
import '../services/recent_reactions_service.dart';
import '../theme/app_theme.dart';
import 'glitch_hover_row.dart';
import 'glitch_divider.dart';
import '../core/l10n.dart';
import 'glitch_tooltip.dart';
import 'reaction_emoji.dart';
import 'message_action_icons.dart';
import 'glitch_icon_button.dart';

const int kToolbarReactionCount = 3;

class MessageToolbar extends StatelessWidget {
  final String? currentReaction;

  final void Function(String emoji)? onReact;

  final void Function(BuildContext anchor) onPickReaction;
  final VoidCallback? onReply;
  final VoidCallback? onForward;
  final VoidCallback? onEdit;

  final void Function(Offset globalPosition) onMore;

  const MessageToolbar({
    super.key,
    required this.currentReaction,
    required this.onReact,
    required this.onPickReaction,
    required this.onReply,
    required this.onForward,
    required this.onEdit,
    required this.onMore,
  });

  static const double buttonSize = 32;

  static const double _pad = 2;

  static const double _radius = 12;

  Widget _icon(String key, IconData icon, String tip, VoidCallback onTap) => _button(key, Icon(icon), tip, onTap);

  Widget _button(String key, Widget glyph, String tip, VoidCallback onTap) => GlitchTooltip(
        key: ValueKey(key),
        message: tip,
        child: GlitchIconButton(
          size: buttonSize,
          extent: buttonSize,
          iconSize: 19,
          onTap: onTap,
          icon: glyph,
        ),
      );

  Widget _emoji(BuildContext context, String emoji) {
    final mine = currentReaction == emoji;
    final mineColor = GlitchColors.accentBlue.withOpacity(0.25);
    return GlitchTooltip(
      key: ValueKey('reaction:$emoji'),
      message: context.s.tipReact,
      child: GlitchIconButton(
        size: buttonSize,
        extent: buttonSize,
        onTap: () {
          recentReactions.recordUsed(emoji);
          onReact!(emoji);
        },
        icon: Container(
          alignment: Alignment.center,
          decoration: mine
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(GlitchHoverRow.radius),
                  color: mineColor,
                )
              : null,
          width: buttonSize,
          height: buttonSize,
          child: ReactionEmoji(emoji, size: 18),
        ),
      ),
    );
  }

  Widget _separator() => Container(
        key: const ValueKey('separator'),
        width: 1,
        height: 20,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: const GlitchDivider(axis: Axis.vertical),
      );

  @override
  Widget build(BuildContext context) {
    final reactions = onReact == null
        ? const <String>[]
        : recentReactions.current.take(kToolbarReactionCount).toList();
    return SelectionContainer.disabled(
      child: Material(
        color: GlitchColors.bgToolbar,
        elevation: 4,
        borderRadius: BorderRadius.circular(_radius),
        child: Padding(
          padding: const EdgeInsets.all(_pad),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final e in reactions) _emoji(context, e),
              if (reactions.isNotEmpty) _separator(),
              if (onReact != null)
                Builder(
                  key: const ValueKey('add-reaction'),
                  builder: (button) => _icon('add-reaction', Icons.add_reaction_outlined, context.s.tipAddReaction,
                      () => onPickReaction(button)),
                ),
              if (onReply != null) _button('reply', const ReplyIcon(), context.s.reply, onReply!),
              if (onForward != null) _icon('forward', kForwardIcon, context.s.forward, onForward!),
              if (onEdit != null) _icon('edit', kEditIcon, context.s.edit, onEdit!),
              Builder(
                key: const ValueKey('more'),
                builder: (button) => _icon('more', Icons.more_horiz_rounded, context.s.tipMore, () {
                  final box = button.findRenderObject() as RenderBox?;
                  if (box == null || !box.attached) return;
                  onMore(box.localToGlobal(box.size.center(Offset.zero)));
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
