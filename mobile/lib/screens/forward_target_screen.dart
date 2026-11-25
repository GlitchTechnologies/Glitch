import 'package:flutter/material.dart';
import '../core/forward_send.dart';
import '../core/l10n.dart';
import '../models/bubble_data.dart';
import '../models/search.dart';
import '../theme/app_theme.dart';
import '../widgets/adaptive_sheet.dart';
import '../widgets/content_picker.dart' show openEmojiPicker;
import '../widgets/glitch_action_button.dart';
import '../widgets/glitch_form_field.dart';
import '../widgets/forwarded_frame.dart';
import '../widgets/glitch_icon_button.dart';
import '../widgets/message_interactions.dart' show bubblePreviewText;
import '../widgets/place_picker.dart';
import '../widgets/settings_window.dart' show SettingsDivider;

Future<void> openForwardWindow(BuildContext context, List<BubbleData> bubbles) async {
  final choice = await openAdaptivePicker<_ForwardChoice>(
    context,
    title: context.s.forwardTitle,
    narrowBuilder: (_) => _ForwardPage(bubbles: bubbles),
    wideWidth: 520,
    wideBodyBuilder: (ctx, _) => SizedBox(height: 620, child: _ForwardBody(bubbles: bubbles)),
  );
  if (choice == null || !context.mounted) return;
  await forwardTo(context, targets: choice.targets, bubbles: bubbles, note: choice.note);
}

Future<SearchHit?> pickShareTarget(BuildContext context) => openAdaptivePicker<SearchHit>(
      context,
      title: context.s.share,
      narrowBuilder: (_) => _Page(
        title: context.s.share,
        child: _picker(fieldPadding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            onChoose: (ctx, hit) => Navigator.pop<SearchHit>(ctx, hit)),
      ),
      wideBodyBuilder: (ctx, _) => SizedBox(
        height: 480,
        child: _picker(fieldPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            onChoose: (c, hit) => Navigator.pop<SearchHit>(c, hit)),
      ),
    );

class _ForwardChoice {
  final List<SearchHit> targets;
  final String note;

  const _ForwardChoice(this.targets, this.note);
}

const Set<SearchKind> _kinds = {SearchKind.person, SearchKind.group, SearchKind.room};

bool _accepts(SearchHit hit) => switch (hit.kind) {
      SearchKind.room => !hit.room!.isVoice && hit.room!.canSend,
      _ => true,
    };

String _keyOf(SearchHit hit) => switch (hit.kind) {
      SearchKind.person => 'person:${hit.person!.id}',
      SearchKind.group => 'chat:${hit.group!.id}',
      SearchKind.room => 'room:${hit.room!.id}',
      SearchKind.server => 'server:${hit.server!.id}',
    };

Widget _picker({
  required EdgeInsetsGeometry fieldPadding,
  required void Function(BuildContext context, SearchHit hit) onChoose,
}) =>
    Builder(
      builder: (context) => PlacePicker(
        hint: context.s.forwardSearchHint,
        kinds: _kinds,
        accepts: _accepts,
        fieldPadding: fieldPadding,
        onChoose: (hit) => onChoose(context, hit),
      ),
    );

class _ForwardBody extends StatefulWidget {
  final List<BubbleData> bubbles;

  const _ForwardBody({required this.bubbles});

  @override
  State<_ForwardBody> createState() => _ForwardBodyState();
}

class _ForwardBodyState extends State<_ForwardBody> {
  final List<SearchHit> _targets = [];
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool _checked(SearchHit hit) => _targets.any((t) => _keyOf(t) == _keyOf(hit));

  void _toggle(SearchHit hit) {
    final key = _keyOf(hit);
    final at = _targets.indexWhere((t) => _keyOf(t) == key);
    setState(() {
      if (at >= 0) {
        _targets.removeAt(at);
      } else if (_targets.length < kMaxForwardTargets) {
        _targets.add(hit);
      }
    });
  }

  void _send() {
    if (_targets.isEmpty) return;
    Navigator.pop(context, _ForwardChoice(List.of(_targets), _note.text));
  }

  void _insertEmoji(String emoji) {
    final value = _note.value;
    final sel = value.selection.isValid ? value.selection : TextSelection.collapsed(offset: value.text.length);
    final text = value.text.replaceRange(sel.start, sel.end, emoji);
    _note.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: sel.start + emoji.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final bubbles = widget.bubbles;
    final preview = bubbles.length == 1
        ? bubblePreviewText(context, bubbles.first.type, bubbles.first.previewText)
        : s.forwardPreviewMany(bubbles.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text(s.forwardSubtitle, style: TextStyle(fontSize: 14, color: GlitchColors.textSecond)),
        ),
        Expanded(
          child: PlacePicker(
            hint: s.forwardSearchHint,
            kinds: _kinds,
            accepts: _accepts,
            checked: _checked,
            canCheckMore: _targets.length < kMaxForwardTargets,
            fieldPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            onChoose: _toggle,
          ),
        ),
        const SettingsDivider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ForwardedFrame(
                child: Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, height: 1.35, color: GlitchColors.textPrimary)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: GlitchFormField(
                      controller: _note,
                      placeholder: s.forwardNoteHint,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      suffix: Builder(
                        builder: (anchor) => GlitchIconButton(
                          icon: const Icon(Icons.emoji_emotions_outlined),
                          size: 32,
                          extent: 40,
                          onTap: () => openEmojiPicker(anchor, onEmoji: _insertEmoji),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 140,
                    child: GlitchActionButton(
                      label: s.forward,
                      height: 52,
                      onTap: _targets.isEmpty ? null : _send,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ForwardPage extends StatelessWidget {
  final List<BubbleData> bubbles;

  const _ForwardPage({required this.bubbles});

  @override
  Widget build(BuildContext context) => _Page(title: context.s.forwardTitle, child: _ForwardBody(bubbles: bubbles));
}

class _Page extends StatelessWidget {
  final String title;
  final Widget child;

  const _Page({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GlitchColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 14, 8),
              child: Row(
                children: [
                  GlitchIconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded, color: GlitchColors.accentBlue, size: 22),
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 2),
                  Text(title,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary)),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
