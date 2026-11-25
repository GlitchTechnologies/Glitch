import 'dart:async' show unawaited;

import 'package:flutter/gestures.dart' show kPrimaryMouseButton, kSecondaryMouseButton, kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import '../core/name_color.dart';
import '../core/date_text.dart';
import '../core/l10n.dart';
import '../core/platform_info.dart';
import '../core/system_message.dart';
import '../models/bubble_data.dart';
import '../models/system_info.dart';
import '../models/message.dart' show ReplyPreview, ReactionListX;
import '../services/api_service.dart';
import '../services/recent_reactions_service.dart';
import '../theme/app_theme.dart';
import 'author_tag.dart';
import 'chat_metrics.dart';
import 'content_picker.dart' show openEmojiPicker;
import 'glitch_avatar.dart';
import 'glitch_hover_row.dart';
import '../core/collectibles.dart';
import 'glitch_pressable.dart';
import 'horizontal_drag.dart';
import 'message_interactions.dart' show bubblePreviewText, jumpHighlightColor;
import 'message_toolbar.dart';
import 'reaction_pills.dart';
import 'selectable_content.dart';
import 'selection_contrast_text.dart';
import 'theme_workspace.dart';
import 'forwarded_frame.dart';
import 'message_action_icons.dart';


const Duration kMessageGroupGap = Duration(minutes: 7);

bool startsMessageGroup(BubbleData b, BubbleData? above, {required bool dividerAbove}) {
  if (above == null || dividerAbove) return true;
  if (b.type == 'system' || above.type == 'system') return true;
  if (b.replyTo != null) return true;
  if (above.senderId != b.senderId) return true;
  if (b.fromWebhook && (above.senderDisplayName != b.senderDisplayName || above.senderAvatar != b.senderAvatar)) {
    return true;
  }
  return b.createdAt.difference(above.createdAt) > kMessageGroupGap;
}

bool needsDateSeparator(DateTime current, DateTime? older) =>
    older == null ||
    older.day != current.day ||
    older.month != current.month ||
    older.year != current.year;

class DateDivider extends StatelessWidget {
  final DateTime date;
  const DateDivider(this.date, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = ThemeWorkspace.dividerColor(context);
    Widget line() => Expanded(child: Container(height: 1, color: color));
    return SelectableContent(
      fillWidth: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(kMessageRowPadLeft, 16, kMessageRowPadRight, 4),
        child: Row(
          children: [
            line(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: SelectionContrastText(
                Text(
                  formatDayLong(date),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: GlitchColors.textHint),
                ),
              ),
            ),
            line(),
          ],
        ),
      ),
    );
  }
}

class SystemMessageText extends StatelessWidget {
  final BubbleData data;
  final void Function(BuildContext anchor, SystemPerson person) onPersonTap;

  const SystemMessageText({super.key, required this.data, required this.onPersonTap});

  static const double _fontSize = 14;

  @override
  Widget build(BuildContext context) {
    final parts = systemMessageParts(
      context.s,
      system: data.system,
      messageId: data.id,
      actor: SystemPerson(id: data.senderId, nickname: data.senderNickname, displayName: data.senderDisplayName),
    );
    final textStyle = TextStyle(fontSize: _fontSize, color: GlitchColors.textSecond, height: 1.3);
    return SelectionContrastText(
      Text.rich(
        TextSpan(style: textStyle, children: [
          if (parts == null)
            TextSpan(text: data.content ?? '')
          else
            for (final part in parts)
              if (part.person == null)
                TextSpan(text: part.text)
              else
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: _name(part.text, part.person!),
                ),
          TextSpan(
            text: '  ${formatMessageStamp(context, data.createdAt)}',
            style: TextStyle(fontSize: 12, color: GlitchColors.textHint),
          ),
        ]),
      ),
    );
  }

  Widget _name(String text, SystemPerson person) => Builder(
        builder: (anchor) => ClickableCursor(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onPersonTap(anchor, person),
            child: Text(
              text,
              style: TextStyle(
                fontSize: _fontSize,
                height: 1.3,
                fontWeight: FontWeight.w600,
                color: GlitchColors.textPrimary,
              ),
            ),
          ),
        ),
      );
}

const double _kSwipeReplyThreshold = 64.0;
const double _kSwipeReplyMaxDrag = 88.0;
const Duration _kSwipeSnapBackDuration = Duration(milliseconds: 200);

const Set<String> _ownSendingView = {'photo', 'album', 'video', 'file', 'voice', 'video_note'};

class MessageRow extends StatefulWidget {
  final BubbleData data;

  final bool startsGroup;

  final bool highlighted;

  final Future<void> Function(Offset globalPosition)? onMenu;

  final void Function(String emoji)? onQuickReact;
  final VoidCallback? onReply;
  final VoidCallback? onForward;
  final VoidCallback? onEdit;

  final VoidCallback? onSwipeReply;

  final void Function(BuildContext anchorContext)? onAuthorTap;

  final void Function(int sourceMessageId)? onReplyTap;

  final void Function(String emoji)? onReactTap;

  final Widget child;

  const MessageRow({
    super.key,
    required this.data,
    required this.startsGroup,
    required this.child,
    this.highlighted = false,
    this.onMenu,
    this.onQuickReact,
    this.onReply,
    this.onForward,
    this.onEdit,
    this.onSwipeReply,
    this.onAuthorTap,
    this.onReplyTap,
    this.onReactTap,
  });

  @override
  State<MessageRow> createState() => _MessageRowState();
}

class _MessageRowState extends State<MessageRow> with SingleTickerProviderStateMixin {
  late final AnimationController _snapCtrl =
      AnimationController(vsync: this, duration: _kSwipeSnapBackDuration);
  double _dragExtent = 0; // всегда <= 0 — свайп только влево
  double _snapFrom = 0; // значение _dragExtent в момент отпускания пальца
  bool _hapticFired = false;

  Offset? _secondaryDown;
  Offset? _authorDown;

  final _toolbarLink = LayerLink();
  final _toolbar = OverlayPortalController();
  bool _rowHovered = false;
  bool _toolbarHovered = false;
  bool _menuOpen = false;

  bool get _active => _rowHovered || _toolbarHovered || _menuOpen;

  bool get _system => widget.data.type == 'system';

  void _syncToolbar() {
    final want = hasPointerInput && widget.onMenu != null && _active;
    if (want == _toolbar.isShowing) return;
    want ? _toolbar.show() : _toolbar.hide();
  }

  // mounted — страховка: событие мыши может прийти, когда строку уже убрали
  // из ленты (удалили сообщение под курсором), а панель в слое ещё снимается.
  void _setRowHovered(bool v) {
    if (!mounted) return;
    setState(() => _rowHovered = v);
    _syncToolbar();
  }

  void _setToolbarHovered(bool v) {
    if (!mounted) return;
    setState(() => _toolbarHovered = v);
    _syncToolbar();
  }

  Future<void> _openMenu(Offset position) async {
    final onMenu = widget.onMenu;
    if (onMenu == null) return;
    await _holdWhile(() => onMenu(position));
  }

  void _pickReaction(BuildContext anchor) {
    final react = widget.onQuickReact;
    if (react == null) return;
    unawaited(_holdWhile(() => openEmojiPicker(anchor, onEmoji: (emoji) {
      recentReactions.recordUsed(emoji);
      react(emoji);
    })));
  }

  Future<void> _holdWhile(Future<void> Function() open) async {
    setState(() => _menuOpen = true);
    _syncToolbar();
    try {
      await open();
    } finally {
      if (mounted) {
        setState(() => _menuOpen = false);
        _syncToolbar();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _snapCtrl.addListener(() {
      if (!mounted) return;
      final t = Curves.easeOutCubic.transform(_snapCtrl.value);
      setState(() => _dragExtent = _snapFrom * (1 - t));
    });
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails _) {
    _snapCtrl.stop();
    _hapticFired = false;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragExtent = (_dragExtent + details.delta.dx).clamp(-_kSwipeReplyMaxDrag, 0.0);
      if (!_hapticFired && _dragExtent.abs() >= _kSwipeReplyThreshold) {
        _hapticFired = true;
        HapticFeedback.mediumImpact();
      }
    });
  }

  void _onDragEnd(DragEndDetails _) {
    final crossed = _dragExtent.abs() >= _kSwipeReplyThreshold;
    _snapFrom = _dragExtent;
    _snapCtrl.forward(from: 0);
    if (crossed) widget.onSwipeReply?.call();
  }

  Widget _gestures(Widget child) {
    final onMenu = widget.onMenu;
    if (hasPointerInput) {
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => _secondaryDown = e.buttons == kSecondaryMouseButton ? e.position : null,
        onPointerUp: (e) {
          final down = _secondaryDown;
          _secondaryDown = null;
          if (onMenu == null || down == null) return;
          if ((e.position - down).distance > kTouchSlop) return; // тянули, а не нажали
          _openMenu(e.position);
        },
        onPointerCancel: (_) => _secondaryDown = null,
        child: child,
      );
    }
    final swipe = widget.onSwipeReply != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: onMenu == null
          ? null
          : (d) {
              HapticFeedback.selectionClick();
              _openMenu(d.globalPosition);
            },
      child: SideDragDetector(
        enabled: swipe,
        side: DragSide.left,
        onStart: _onDragStart,
        onUpdate: _onDragUpdate,
        onEnd: _onDragEnd,
        child: child,
      ),
    );
  }

  Widget _avatar() {
    final d = widget.data;
    return Builder(
      builder: (anchor) => ClickableCursor(
        enabled: widget.onAuthorTap != null,
        child: GestureDetector(
          onTap: widget.onAuthorTap == null ? null : () => widget.onAuthorTap!(anchor),
          child: GlitchAvatar(
            initials: GlitchAvatar.initialsFromName(d.senderDisplayName),
            size: kMessageAvatarSize,
            colorIndex: GlitchAvatar.colorFromNickname(d.senderNickname),
            imageUrl: d.senderAvatar != null ? api.mediaUrl(d.senderAvatar!) : null,
            avatarSizes: d.senderAvatarSizes,
            // Украшение оживает при наведении на сообщение (как у Discord;
            // правило списков — core/collectibles.dart).
            decoration: d.senderAvatarDecoration,
            animateDecoration: animateInList(_rowHovered || _toolbarHovered),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final d = widget.data;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: Builder(
              builder: (anchor) {
                final name = Text(
                  d.senderDisplayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: nameColor(d.senderColor)),
                );
                return ClickableCursor(
                  enabled: widget.onAuthorTap != null,
                  child: hasPointerInput
                      ? Listener(
                          onPointerDown: (e) => _authorDown = e.buttons == kPrimaryMouseButton ? e.position : null,
                          onPointerUp: (e) {
                            final down = _authorDown;
                            _authorDown = null;
                            if (down != null && (e.position - down).distance <= kTouchSlop) {
                              widget.onAuthorTap?.call(anchor);
                            }
                          },
                          onPointerCancel: (_) => _authorDown = null,
                          child: name,
                        )
                      : GestureDetector(
                          onTap: widget.onAuthorTap == null ? null : () => widget.onAuthorTap!(anchor),
                          child: name,
                        ),
                );
              },
            ),
          ),
          if (d.fromWebhook) ...[
            const SizedBox(width: 6),
            AuthorTag(context.s.authorTagWebhook),
          ],
          const SizedBox(width: 8),
          SelectionContrastText(
            Text(
              formatMessageStamp(context, d.createdAt),
              style: TextStyle(fontSize: 12, color: GlitchColors.textHint),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gutter(bool active) {
    if (_system) {
      return Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Icon(Icons.arrow_forward_rounded, size: 18, color: GlitchColors.textSecond),
      );
    }
    if (widget.startsGroup) return SelectionContainer.disabled(child: _avatar());
    if (!active) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Align(
        alignment: Alignment.topCenter,
        child: SelectionContrastText(
          Text(
            formatTime(widget.data.createdAt),
            style: TextStyle(fontSize: 11, color: GlitchColors.textHint),
          ),
        ),
      ),
    );
  }

  Widget _failedLine(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline_rounded, size: 14, color: GlitchColors.error),
        const SizedBox(width: 4),
        Text(context.s.sendFailed, style: TextStyle(fontSize: 12.5, color: GlitchColors.error)),
      ]),
    );
  }

  Widget _body(BuildContext context, bool active) {
    final d = widget.data;
    final reply = d.replyTo;
    final dimmed = d.status == 'sending' && !_ownSendingView.contains(d.type);
    final content = Opacity(opacity: dimmed ? 0.5 : 1, child: widget.child);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (reply != null && widget.startsGroup)
          _ReplyLine(reply: reply, onTap: widget.onReplyTap == null ? null : () => widget.onReplyTap!(reply.id)),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: kMessageAvatarSize, child: _gutter(active)),
            const SizedBox(width: kMessageAvatarGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.startsGroup && !_system) _header(context),
                  if (d.forwardedFrom != null) ForwardedFrame(child: content) else content,
                  SelectionContainer.disabled(
                    child: ReactionPills(
                      reactions: d.reactions,
                      onTap: (emoji) => widget.onReactTap?.call(emoji),
                    ),
                  ),
                  if (d.status == 'failed') _failedLine(context),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _mentionLayer(Widget child) => widget.data.mentionsMe
      ? DecoratedBox(
          decoration: BoxDecoration(
            color: GlitchColors.accentBlue.withOpacity(0.08),
            border: Border(left: BorderSide(color: GlitchColors.accentBlue, width: 2)),
          ),
          child: child,
        )
      : child;

  @override
  Widget build(BuildContext context) {
    final row = GlitchHoverArea(
      onTap: null,
      hoverWhenDisabled: true,
      onHoverChanged: _setRowHovered,
      builder: (context, hovered) {
        final content = _mentionLayer(DecoratedBox(
          decoration: BoxDecoration(
            color: GlitchHoverRow.feedHighlight(context, active: hovered || _toolbarHovered || _menuOpen),
            borderRadius: BorderRadius.circular(GlitchHoverRow.radius),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            padding: EdgeInsets.fromLTRB(
              kMessageRowPadLeft, widget.startsGroup ? 6 : 2, kMessageRowPadRight, 2),
            decoration: BoxDecoration(
              color: widget.highlighted ? jumpHighlightColor : Colors.transparent,
              borderRadius: BorderRadius.circular(GlitchHoverRow.radius),
            ),
            child: _body(context, hovered || _toolbarHovered || _menuOpen),
          ),
        ));
        return widget.data.type == 'text'
            ? SelectableContent(fillWidth: true, child: content)
            : content;
      },
    );

    final withToolbar = hasPointerInput && widget.onMenu != null
        ? CompositedTransformTarget(
            link: _toolbarLink,
            child: OverlayPortal(
              controller: _toolbar,
              overlayChildBuilder: (_) => Positioned(
                left: 0,
                top: 0,
                child: CompositedTransformFollower(
                  link: _toolbarLink,
                  showWhenUnlinked: false,
                  targetAnchor: Alignment.topRight,
                  followerAnchor: Alignment.centerRight,
                  offset: const Offset(-12, 0),
                  child: GlitchHoverArea(
                    onTap: null,
                    hoverWhenDisabled: true,
                    onHoverChanged: _setToolbarHovered,
                    builder: (_, __) => MessageToolbar(
                      currentReaction: widget.data.reactions.mine,
                      onReact: widget.onQuickReact,
                      onPickReaction: _pickReaction,
                      onReply: widget.onReply,
                      onForward: widget.onForward,
                      onEdit: widget.onEdit,
                      onMore: _openMenu,
                    ),
                  ),
                ),
              ),
              child: row,
            ),
          )
        : row;

    final spaced = Padding(
      padding: EdgeInsets.only(top: widget.startsGroup ? 10 : 0),
      child: withToolbar,
    );

    if (widget.onSwipeReply == null || hasPointerInput) return _gestures(spaced);

    final progress = (_dragExtent.abs() / _kSwipeReplyThreshold).clamp(0.0, 1.0);
    return _gestures(Stack(
      alignment: Alignment.centerRight,
      children: [
        Positioned(
          right: 14,
          child: Opacity(
            opacity: progress,
            child: Transform.scale(
              scale: 0.7 + 0.3 * progress,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: GlitchColors.accentBlue.withOpacity(0.15),
                ),
                child: ReplyIcon(size: 18, color: GlitchColors.accentBlue),
              ),
            ),
          ),
        ),
        Transform.translate(offset: Offset(_dragExtent, 0), child: spaced),
      ],
    ));
  }
}

class _ReplyLine extends StatelessWidget {
  final ReplyPreview reply;
  final VoidCallback? onTap;
  const _ReplyLine({required this.reply, required this.onTap});

  static const double _height = 22;
  static const double _miniAvatar = 16;

  @override
  Widget build(BuildContext context) {
    final avatar = reply.senderAvatar;
    return ClickableCursor(
      enabled: onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: _height,
          child: Row(
            children: [
              SizedBox(
                width: kMessageGutter,
                height: _height,
                child: CustomPaint(painter: _ReplySpinePainter(color: GlitchColors.border)),
              ),
              GlitchAvatar(
                initials: GlitchAvatar.initialsFromName(reply.senderDisplayName),
                size: _miniAvatar,
                colorIndex: GlitchAvatar.colorFromNickname(reply.senderDisplayName),
                imageUrl: avatar != null ? api.mediaUrl(avatar) : null,
                avatarSizes: reply.senderAvatarSizes,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: reply.senderDisplayName,
                      style: TextStyle(fontWeight: FontWeight.w600, color: nameColor(reply.senderColor)),
                    ),
                    const TextSpan(text: '  '),
                    TextSpan(
                      text: bubblePreviewText(context, reply.type, reply.preview),
                      style: TextStyle(color: GlitchColors.textSecond),
                    ),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReplySpinePainter extends CustomPainter {
  final Color color;
  const _ReplySpinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const r = 6.0;
    final x = kMessageAvatarSize / 2;
    final y = size.height / 2;
    final path = Path()
      ..moveTo(x, size.height)
      ..lineTo(x, y + r)
      ..quadraticBezierTo(x, y, x + r, y)
      ..lineTo(size.width - 4, y);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ReplySpinePainter old) => old.color != color;
}
