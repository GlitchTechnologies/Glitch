import 'package:flutter/material.dart';
import '../core/copy_actions.dart';
import '../core/l10n.dart';
import '../theme/app_theme.dart';
import '../services/recent_reactions_service.dart';
import 'glitch_menu.dart';
import 'glitch_dialog.dart' show glitchWindowShape;
import 'glitch_pressable.dart' show ClickableCursor;
import 'reaction_emoji.dart';
import 'message_action_icons.dart';
import 'glitch_icon_button.dart';

Future<void> showMessageActionMenu({
  required BuildContext context,
  required Offset position,
  // Видимый текст сообщения (текст или подпись к вложению). Пустой — пункта
  // «Копировать» нет (голосовое, стикер, звонок, опрос, вложение без подписи;
  // 2026-10-20, как у Discord): пункт, который кладёт в буфер пустоту,
  // выглядит сломанным.
  required String copyText,
  required int messageId,
  String? messageLink,
  // Удаление ЦЕЛИКОМ, без подтверждения (`deleteMessageByUser` —
  // собирает вызывающий в `_actionsFor`, тот же путь у кнопки панели). null —
  // пункта нет.
  VoidCallback? onDelete,
  VoidCallback? onEdit,
  VoidCallback? onReply,
  VoidCallback? onForward,
  VoidCallback? onPin,
  bool isPinned = false,
  VoidCallback? onEndPoll,
  required String? currentUserReaction,
  required Future<void> Function(String emoji) onReact,
  bool allowReactions = true,
}) {
  return showGlitchContextMenuAt<String>(
    context,
    position,
    [
      if (onPin != null)
        GlitchMenuItem(
          value: 'pin',
          child: Row(children: [
            Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined, color: GlitchColors.textPrimary, size: 18),
            const SizedBox(width: 10),
            Text(isPinned ? context.s.unpin : context.s.pin,
                style: TextStyle(color: GlitchColors.textPrimary, fontSize: 15)),
          ]),
        ),
      if (onReply != null)
        GlitchMenuItem(
          value: 'reply',
          child: Row(children: [
            ReplyIcon(color: GlitchColors.textPrimary, size: 18),
            const SizedBox(width: 10),
            Text(context.s.reply, style: TextStyle(color: GlitchColors.textPrimary, fontSize: 15)),
          ]),
        ),
      if (onForward != null)
        GlitchMenuItem(
          value: 'forward',
          child: Row(children: [
            Icon(kForwardIcon, color: GlitchColors.textPrimary, size: 18),
            const SizedBox(width: 10),
            Text(context.s.forward, style: TextStyle(color: GlitchColors.textPrimary, fontSize: 15)),
          ]),
        ),
      if (onEdit != null)
        GlitchMenuItem(
          value: 'edit',
          child: Row(children: [
            Icon(kEditIcon, color: GlitchColors.textPrimary, size: 18),
            const SizedBox(width: 10),
            Text(context.s.edit, style: TextStyle(color: GlitchColors.textPrimary, fontSize: 15)),
          ]),
        ),
      if (onEndPoll != null)
        GlitchMenuItem(value: 'endPoll', child: glitchMenuRow(Icons.stop_circle_outlined, context.s.pollEnd)),
      if (copyText.trim().isNotEmpty)
        GlitchMenuItem(
          value: 'copy',
          child: Row(children: [
            Icon(Icons.copy_rounded, color: GlitchColors.textPrimary, size: 18),
            const SizedBox(width: 10),
            Text(context.s.copy, style: TextStyle(color: GlitchColors.textPrimary, fontSize: 15)),
          ]),
        ),
      if (onDelete != null)
        GlitchMenuItem(
          value: 'delete',
          child: Row(children: [
            Icon(kDeleteIcon, color: GlitchColors.textPrimary, size: 18),
            const SizedBox(width: 10),
            Text(context.s.delete, style: TextStyle(color: GlitchColors.textPrimary, fontSize: 15)),
          ]),
        ),
      if (messageLink != null)
        GlitchMenuItem(value: 'copyLink', child: glitchMenuRow(Icons.link_rounded, context.s.copyMessageLink)),
      GlitchMenuItem(value: 'copyId', child: copyIdMenuRow(context, IdKind.message)),
    ],
    (value) {
      if (value == 'pin') {
        onPin?.call();
      } else if (value == 'reply') {
        onReply?.call();
      } else if (value == 'forward') {
        onForward?.call();
      } else if (value == 'edit') {
        onEdit?.call();
      } else if (value == 'endPoll') {
        onEndPoll?.call();
      } else if (value == 'copy') {
        copyMessageText(context, copyText);
      } else if (value == 'delete') {
        onDelete?.call();
      } else if (value == 'copyLink' && messageLink != null) {
        copyMessageLink(context, messageLink);
      } else if (value == 'copyId') {
        copyId(context, messageId);
      }
    },
    headerBuilder: !allowReactions ? null : (close) => _ReactionQuickRow(
      current: currentUserReaction,
      onPick: (emoji) async {
        recentReactions.recordUsed(emoji);
        await close();
        await onReact(emoji);
      },
    ),
  );
}


// Куратированный набор для развёрнутой сетки (не полный Unicode — свой список,
// без пакета: раньше здесь стоял emoji_picker_flutter, но у него всегда есть
// категории+поиск, а нужен именно плоский грид без них, точь-в-точь как в
// Telegram-реакциях). Расширить список — просто дописать сюда, без завязки на
// внешний датасет.
const List<String> _kFullReactions = [
  '❤️', '👍', '👎', '🔥', '🤩', '👏', '😄', '😂', '😭', '😍',
  '🙏', '👌', '💯', '✅', '❌', '🎉', '💔', '💀', '🤔', '😱',
  '😳', '😎', '🥳', '😡', '😢', '🤗', '🙄', '😴', '🤝', '👀',
  '💪', '🤣', '😅', '😇', '🥰', '😘', '😜', '🤪', '😬', '😏',
  '🤨', '😒', '🙃', '😤', '🤯', '🥶', '🥵', '😷', '🤮', '👻',
  '💩', '🙈', '🐸', '🎊', '⚡', '✨', '🌹', '🌚', '🍕', '☕',
];

class _ReactionQuickRow extends StatefulWidget {
  final String? current;
  final ValueChanged<String> onPick;
  const _ReactionQuickRow({required this.current, required this.onPick});

  @override
  State<_ReactionQuickRow> createState() => _ReactionQuickRowState();
}

class _ReactionQuickRowState extends State<_ReactionQuickRow> {
  bool _expanded = false;

  Widget _emojiCircle(String emoji, {double fontSize = 19, double padding = 4}) {
    final selected = widget.current == emoji;
    return ClickableCursor(
      child: GestureDetector(
      onTap: () => widget.onPick(emoji),
      child: Container(
        alignment: Alignment.center,
        margin: const EdgeInsets.all(1),
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? GlitchColors.accentBlue.withOpacity(0.25) : Colors.transparent,
        ),
        child: ReactionEmoji(emoji, size: fontSize),
      ),
      ),
    );
  }

  static const _headerWidth = 236.0;

  Widget _collapsedRow() {
    return SizedBox(
      width: _headerWidth,
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              children: [for (final emoji in recentReactions.current) _emojiCircle(emoji)],
            ),
          ),
          GlitchIconButton(
            icon: Icon(Icons.keyboard_arrow_down_rounded, size: 18),
            onTap: () => setState(() => _expanded = true),
            size: 26,
            extent: 26,
          ),
        ],
      ),
    );
  }

  Widget _expandedGrid() {
    return SizedBox(
      width: _headerWidth,
      height: 261,
      child: GridView.builder(
        padding: const EdgeInsets.all(5),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7),
        itemCount: _kFullReactions.length,
        itemBuilder: (context, i) => Center(child: _emojiCircle(_kFullReactions[i], fontSize: 20, padding: 3)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GlitchColors.bgMenu,
      shape: glitchWindowShape(radius: _expanded ? 20 : 28),
      elevation: 8,
      clipBehavior: Clip.antiAlias,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: _expanded ? _expandedGrid() : _collapsedRow(),
      ),
    );
  }
}
