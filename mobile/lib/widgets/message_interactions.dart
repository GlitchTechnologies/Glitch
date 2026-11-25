import 'dart:async';
import 'package:flutter/material.dart';
import '../core/l10n.dart';
import '../theme/app_theme.dart';
import '../models/bubble_data.dart';
import '../models/mention.dart';
import '../models/message.dart' show ReplyPreview;
import 'glitch_dialog.dart';
import 'glitch_toast.dart';
import 'mention_input.dart';
import 'message_action_icons.dart';
import 'glitch_icon_button.dart';



mixin MessageEditing<T, W extends StatefulWidget> on State<W> {
  T? editing;
  MentionDraft? _draftBeforeEdit;

  MentionTextController get editTextController;

  FocusNode get composerFocus;

  String? editableContentOf(T item);

  List<Mention> editableMentionsOf(T item) => const [];

  Future<bool> submitEdit(T item, String text);

  Future<void> onEditEmptied(T item) async {}

  void startEditing(T item) {
    if (editing == null) _draftBeforeEdit = editTextController.snapshot();
    setState(() => editing = item);
    editTextController.setFromWire(editableContentOf(item) ?? '', editableMentionsOf(item));
    composerFocus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(editing, item)) composerFocus.requestFocus();
    });
  }

  void cancelEditing() {
    if (editing == null) return;
    setState(() => editing = null);
    final draft = _draftBeforeEdit;
    if (draft != null) {
      editTextController.restore(draft);
    } else {
      editTextController.clear();
    }
    _draftBeforeEdit = null;
  }

  Future<void> applyEdit() async {
    final item = editing;
    if (item == null) return;
    final text = editTextController.wireText.trim();
    if (text.isEmpty) { await onEditEmptied(item); return; }
    if (text == (editableContentOf(item) ?? '')) { cancelEditing(); return; }
    final ok = await submitEdit(item, text);
    if (!mounted) return;
    if (ok) {
      cancelEditing();
    } else {
      GlitchToast.show(context, context.s.errorLoad);
    }
  }

  Widget buildEditBanner() {
    final item = editing;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      decoration: BoxDecoration(
        color: GlitchColors.bg,
        border: Border(bottom: BorderSide(color: GlitchColors.borderSoft)),
      ),
      child: Row(
        children: [
          Icon(kEditIcon, color: GlitchColors.accentBlue, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.s.editingTitle,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: GlitchColors.accentBlue)),
                const SizedBox(height: 1),
                Text(item == null ? '' : (editableContentOf(item) ?? ''),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, color: GlitchColors.textSecond)),
              ],
            ),
          ),
          GlitchIconButton(
            icon: Icon(Icons.close_rounded, size: 22),
            onTap: cancelEditing,
          ),
        ],
      ),
    );
  }
}


class ComposerContextBanner extends StatelessWidget {
  final Widget icon;
  final String title;
  final String subtitle;
  final VoidCallback onClose;
  const ComposerContextBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      decoration: BoxDecoration(
        color: GlitchColors.bg,
        border: Border(bottom: BorderSide(color: GlitchColors.borderSoft)),
      ),
      child: Row(
        children: [
          IconTheme(
            data: IconThemeData(color: GlitchColors.accentBlue, size: 20),
            child: icon,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: GlitchColors.accentBlue)),
                const SizedBox(height: 1),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, color: GlitchColors.textSecond)),
              ],
            ),
          ),
          GlitchIconButton(
            icon: Icon(Icons.close_rounded, size: 22),
            onTap: onClose,
          ),
        ],
      ),
    );
  }
}

String bubblePreviewText(BuildContext context, String type, String? text) {
  final t = (text != null && text.isNotEmpty) ? text : null;
  switch (type) {
    case 'poll': return t != null ? context.s.pollPreview(t) : context.s.attachPoll;
    case 'poll_result': return t != null ? context.s.pollEndedPreview(t) : context.s.pollEndedLabel;
  }
  if (t != null) return t;
  switch (type) {
    case 'photo': return context.s.attachPhoto;
    case 'album': return context.s.attachAlbum;
    case 'video': return context.s.attachVideo;
    case 'file':  return context.s.file;
    case 'voice': return context.s.attachVoice;
    case 'geo':   return context.s.attachGeo;
    case 'video_note': return context.s.videoNote;
    case 'sticker': return context.s.sticker;
    case 'call':  return context.s.callTitle;
    case 'text':
    case 'system': return '';
    default:      return context.s.messageUnsupportedShort;
  }
}


Future<bool> confirmDeleteMessage(BuildContext context, {required String title, required String body}) =>
    glitchConfirm(context, title: title, body: body, confirmLabel: context.s.delete);

Future<void> deleteMessageByUser(BuildContext context, Future<bool> Function() delete) async {
  final ok = await delete();
  if (!ok && context.mounted) GlitchToast.show(context, context.s.errorLoad);
}

Future<(bool, bool)> confirmDeleteWithOption(
  BuildContext context, {
  required String title,
  required String body,
  String? optionLabel,
  Widget? leading,
}) =>
    glitchConfirmWithOption(context,
        title: title,
        body: body,
        confirmLabel: context.s.delete,
        optionLabel: optionLabel,
        leading: leading);


Color get jumpHighlightColor => GlitchColors.accentBlue.withOpacity(0.12);

mixin MessageJump<W extends StatefulWidget> on State<W> {
  int? highlightedId;
  Timer? _highlightTimer;

  Map<int, GlobalKey> get messageKeys;

  Future<void> scrollOffscreenIntoView(int id);

  double get jumpAlignment => 0.4;

  ScrollController get jumpScrollController;

  int jumpIndexFromBottom(int id);

  bool _jumping = false;

  static const int _revealMaxSteps = 48;

  Future<bool> revealMessage(int id) async {
    for (var step = 0; step < _revealMaxSteps; step++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return false;
      if (messageKeys[id]?.currentContext != null) {
        centerOnMessage(id);
        return true;
      }
      final target = jumpIndexFromBottom(id);
      if (target < 0) return false; // записи нет (удалили, пока шли)
      final ctrl = jumpScrollController;
      if (!ctrl.hasClients) return false;
      final pos = ctrl.position;
      final up = _targetIsAboveBuilt(target);
      final next = up
          ? (pos.pixels + pos.viewportDimension * 0.8).clamp(0.0, pos.maxScrollExtent)
          : (pos.pixels - pos.viewportDimension * 0.8).clamp(0.0, pos.maxScrollExtent);
      if (next == pos.pixels) return false;
      ctrl.jumpTo(next);
    }
    return false;
  }

  bool _targetIsAboveBuilt(int target) {
    for (final entry in messageKeys.entries) {
      if (entry.value.currentContext == null) continue;
      final built = jumpIndexFromBottom(entry.key);
      if (built >= 0) return target > built;
    }
    return true;
  }

  void highlightMessage(int id) {
    setState(() => highlightedId = id);
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => highlightedId = null);
    });
  }

  void centerOnMessage(int id) {
    final ctx = messageKeys[id]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
        duration: const Duration(milliseconds: 350), curve: Curves.easeOut, alignment: jumpAlignment);
    }
  }

  Future<void> jumpToMessageId(int id) async {
    if (_jumping) return; // прошлый прыжок ещё идёт — см. [_jumping]
    highlightMessage(id);
    if (messageKeys[id]?.currentContext != null) {
      centerOnMessage(id);
      return;
    }
    _jumping = true;
    try {
      await scrollOffscreenIntoView(id);
    } finally {
      _jumping = false;
    }
  }

  /// Звать в dispose() экрана.
  void disposeMessageJump() {
    _highlightTimer?.cancel();
  }
}


mixin MessageReply<W extends StatefulWidget> on State<W> {
  BubbleData? replyingTo;

  FocusNode get composerFocus;

  void startReply(BubbleData b) {
    setState(() => replyingTo = b);
    composerFocus.requestFocus();
  }

  ReplyPreview replyPreviewOf(BubbleData b) => ReplyPreview(
    id: b.id, senderId: b.senderId, senderDisplayName: b.senderDisplayName,
    senderAvatar: b.senderAvatar, senderAvatarSizes: b.senderAvatarSizes, senderColor: b.senderColor,
    type: b.type,
    preview: b.previewText,
  );

  (int?, ReplyPreview?) consumeReply() {
    final r = replyingTo;
    if (r == null) return (null, null);
    setState(() => replyingTo = null);
    return (r.id, replyPreviewOf(r));
  }

  void pruneReplyIfGone(Iterable<int> existingIds) {
    if (replyingTo != null && !existingIds.contains(replyingTo!.id)) {
      replyingTo = null;
    }
  }

  Widget replyComposerBanner(BuildContext context) => ComposerContextBanner(
    icon: const ReplyIcon(),
    title: replyingTo!.senderDisplayName,
    subtitle: bubblePreviewText(context, replyingTo!.type, replyingTo!.previewText),
    onClose: () => setState(() => replyingTo = null),
  );
}
