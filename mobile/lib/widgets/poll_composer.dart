import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/poll_limits.dart';
import '../models/poll.dart';
import '../theme/app_theme.dart';
import 'adaptive_sheet.dart';
import 'content_picker.dart';
import 'glitch_action_button.dart';
import 'glitch_bar_buttons.dart';
import 'glitch_dialog.dart' show GlitchCheckMark;
import 'glitch_form_field.dart';
import 'glitch_pressable.dart';
import 'glitch_select_field.dart';
import 'poll_card.dart' show pollDurationLabel;
import 'reaction_emoji.dart';
import 'glitch_icon_button.dart';

Future<PollDraft?> openPollComposer(BuildContext context) => showAdaptiveSheet<PollDraft>(
      context,
      title: context.s.pollCreateTitle,
      bodyBuilder: (ctx, _) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
        child: PollComposerForm(onSubmit: (draft) => Navigator.pop(ctx, draft)),
      ),
    );

class PollComposerForm extends StatefulWidget {
  final ValueChanged<PollDraft> onSubmit;

  const PollComposerForm({super.key, required this.onSubmit});

  @override
  State<PollComposerForm> createState() => _PollComposerFormState();
}

class _AnswerDraft {
  final TextEditingController text = TextEditingController();
  String? emoji;
}

class _PollComposerFormState extends State<PollComposerForm> {
  final _question = TextEditingController();
  final List<_AnswerDraft> _answers = [for (var i = 0; i < kPollAnswersMin; i++) _AnswerDraft()];
  int _hours = kPollDefaultDurationHours;
  bool _multi = false;

  @override
  void dispose() {
    _question.dispose();
    for (final a in _answers) {
      a.text.dispose();
    }
    super.dispose();
  }

  List<_AnswerDraft> get _filled => _answers.where((a) => a.text.text.trim().isNotEmpty).toList();

  bool get _valid => _question.text.trim().isNotEmpty && _filled.length >= kPollAnswersMin;

  void _addAnswer() {
    if (_answers.length >= kPollAnswersMax) return;
    setState(() => _answers.add(_AnswerDraft()));
  }

  void _removeAnswer(_AnswerDraft a) {
    if (_answers.length <= kPollAnswersMin) return;
    setState(() => _answers.remove(a));
    WidgetsBinding.instance.addPostFrameCallback((_) => a.text.dispose());
  }

  void _pickEmoji(BuildContext anchor, _AnswerDraft a) => openEmojiPicker(
        anchor,
        growRight: true,
        onEmoji: (emoji) {
          if (mounted) setState(() => a.emoji = emoji);
        },
      );

  void _submit() {
    if (!_valid) return;
    widget.onSubmit(PollDraft(
      question: _question.text.trim(),
      answers: [for (final a in _filled) (text: a.text.text.trim(), emoji: a.emoji)],
      allowMultiselect: _multi,
      durationHours: _hours,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlitchFormField(
          label: s.pollQuestion,
          controller: _question,
          placeholder: s.pollQuestionHint,
          maxLength: kPollQuestionMax,
          maxLines: 3,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 18),
        GlitchFormLabel(label: s.pollAnswers),
        for (final a in _answers) ...[
          Row(
            children: [
              Builder(
                builder: (anchor) => GlitchPressable(
                  onTap: () => _pickEmoji(anchor, a),
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Center(
                      child: a.emoji != null
                          ? ReactionEmoji(a.emoji!, size: 20)
                          : Icon(Icons.sentiment_satisfied_alt_rounded, size: 22, color: GlitchColors.textSecond),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: GlitchFormField(
                  controller: a.text,
                  placeholder: s.pollAnswerHint,
                  maxLength: kPollAnswerMax,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 2),
              GlitchIconButton(
                icon: Icon(Icons.delete_outline_rounded, size: 22),
                onTap: _answers.length > kPollAnswersMin ? () => _removeAnswer(a) : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (_answers.length < kPollAnswersMax)
          Align(
            alignment: Alignment.centerRight,
            child: GlitchActionButton(
              label: s.pollAddAnswer,
              icon: Icons.add_rounded,
              soft: true,
              compact: true,
              onTap: _addAnswer,
            ),
          ),
        const SizedBox(height: 18),
        GlitchFormLabel(label: s.pollDuration),
        GlitchSelectField<int>(
          value: _hours,
          options: kPollDurationsHours,
          label: (h) => pollDurationLabel(context, h),
          onChanged: (h) => setState(() => _hours = h),
          expand: true,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: GlitchPressable(
                onTap: () => setState(() => _multi = !_multi),
                child: Row(
                  children: [
                    GlitchCheckMark(value: _multi),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(s.pollAllowMultiple,
                          style: TextStyle(fontSize: 14.5, color: GlitchColors.textPrimary)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Opacity(
              opacity: _valid ? 1 : 0.5,
              child: GlitchFilledButton(label: s.pollPublish, onTap: _valid ? _submit : null),
            ),
          ],
        ),
      ],
    );
  }
}
