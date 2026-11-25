import 'dart:async';

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../models/list_page.dart';
import '../models/poll.dart';
import '../models/server.dart' show ServerUser;
import '../providers/cursor_pager.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'adaptive_sheet.dart';
import 'content_picker.dart' show ContentPicker;
import 'glitch_bar_buttons.dart';
import 'glitch_dialog.dart' show GlitchCheckMark;
import 'glitch_pressable.dart';
import 'load_more_trigger.dart';
import 'message_card.dart';
import 'reaction_emoji.dart';
import 'server_user_avatar.dart';
import 'settings_parts.dart' show SettingsRetry;


String pollDurationLabel(BuildContext context, int hours) {
  final s = context.s;
  if (hours % 168 == 0) return s.pollWeeks(hours ~/ 168);
  if (hours >= 48 && hours % 24 == 0) return s.pollDays(hours ~/ 24);
  return s.pollHours(hours);
}

String _timeLeftLabel(BuildContext context, Duration left) {
  final s = context.s;
  if (left.inDays >= 1) return s.pollDays(left.inDays);
  if (left.inHours >= 1) return s.pollHours(left.inHours);
  return s.pollMinutes(left.inMinutes < 1 ? 1 : left.inMinutes);
}

String _percent(double share) => '${(share * 100).round()}%';

class PollCard extends StatefulWidget {
  final PollInfo poll;
  final double maxWidth;

  final Future<bool> Function(List<int> answerIds)? onVote;

  final void Function(PollAnswer answer)? onShowVoters;

  const PollCard({
    super.key,
    required this.poll,
    required this.maxWidth,
    required this.onVote,
    required this.onShowVoters,
  });

  @override
  State<PollCard> createState() => _PollCardState();
}

class _PollCardState extends State<PollCard> {
  final Set<int> _picked = {};
  bool _showResults = false;
  bool _busy = false;

  /// Перерисовка «Осталось: …» и смена вида в момент окончания срока. Свой
  /// таймер у карточки (как у строки «бан до…» в разделе «Баны»): строки
  /// ленты строятся только на экране, их немного. Снимается в dispose.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _scheduleTick();
  }

  @override
  void didUpdateWidget(PollCard old) {
    super.didUpdateWidget(old);
    if (old.poll.id != widget.poll.id) {
      _picked.clear();
      _showResults = false;
    }
    _scheduleTick();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _scheduleTick() {
    _tick?.cancel();
    _tick = null;
    final left = widget.poll.expiresAt.difference(DateTime.now());
    if (widget.poll.ended || left.isNegative) return;
    const minute = Duration(minutes: 1);
    _tick = Timer(left < minute ? left : minute, () {
      if (!mounted) return;
      setState(() {});
      _scheduleTick();
    });
  }

  void _toggle(PollAnswer a) {
    setState(() {
      if (widget.poll.allowMultiselect) {
        if (!_picked.remove(a.id)) _picked.add(a.id);
      } else {
        _picked
          ..clear()
          ..add(a.id);
      }
    });
  }

  Future<void> _send(List<int> ids) async {
    final vote = widget.onVote;
    if (vote == null || _busy) return;
    setState(() => _busy = true);
    final ok = await vote(ids);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) {
        _picked.clear();
        _showResults = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final poll = widget.poll;
    final closed = poll.isClosed(DateTime.now());
    final results = closed || poll.hasMyVote || _showResults;
    final canVote = widget.onVote != null && !closed;

    final status = closed
        ? s.pollEndedLabel
        : _timeLeftLabel(context, poll.expiresAt.difference(DateTime.now()));

    final List<Widget> actions;
    if (!results) {
      actions = [
        GlitchPlainButton(label: s.pollShowResults, onTap: () => setState(() => _showResults = true)),
        Opacity(
          opacity: _picked.isEmpty || !canVote ? 0.5 : 1,
          child: GlitchFilledButton(
            label: s.pollVote,
            loading: _busy,
            onTap: _picked.isEmpty || !canVote ? null : () => _send(_picked.toList()..sort()),
          ),
        ),
      ];
    } else if (!closed && poll.hasMyVote && canVote) {
      actions = [GlitchPlainButton(label: s.pollRemoveVote, onTap: _busy ? null : () => _send(const []))];
    } else if (!closed && _showResults) {
      actions = [GlitchPlainButton(label: s.pollBackToVote, onTap: () => setState(() => _showResults = false))];
    } else {
      actions = const [];
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.maxWidth),
      child: MessageCard(
        color: ContentPicker.background(context),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(poll.question,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary)),
            const SizedBox(height: 4),
            Text(poll.allowMultiselect ? s.pollChooseMany : s.pollChooseOne,
                style: TextStyle(fontSize: 13, color: GlitchColors.textHint)),
            const SizedBox(height: 10),
            for (final a in poll.answers) ...[
              results
                  ? _ResultRow(
                      answer: a,
                      share: poll.shareOf(a),
                      mine: poll.myAnswerIds.contains(a.id),
                      winner: closed && poll.topVotes > 0 && a.votes == poll.topVotes,
                      onTap: a.votes > 0 && widget.onShowVoters != null ? () => widget.onShowVoters!(a) : null,
                    )
                  : _VoteRow(
                      answer: a,
                      multi: poll.allowMultiselect,
                      picked: _picked.contains(a.id),
                      onTap: canVote && !_busy ? () => _toggle(a) : null,
                    ),
              const SizedBox(height: 6),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: s.pollVotes(poll.voters),
                        style: TextStyle(fontWeight: FontWeight.w600, color: GlitchColors.textPrimary),
                      ),
                      TextSpan(text: '  ·  $status'),
                    ]),
                    style: TextStyle(fontSize: 13, color: GlitchColors.textHint),
                  ),
                ),
                for (final action in actions) ...[
                  const SizedBox(width: 6),
                  SelectionContainer.disabled(child: action),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Widget _answerLabel(PollAnswer a, {required FontWeight weight, Color? color}) => Row(
      children: [
        if (a.emoji != null) ...[
          ReactionEmoji(a.emoji!, size: 18),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(a.text,
              style: TextStyle(fontSize: 14.5, fontWeight: weight, color: color ?? GlitchColors.textPrimary)),
        ),
      ],
    );

class _VoteRow extends StatelessWidget {
  final PollAnswer answer;
  final bool multi;
  final bool picked;
  final VoidCallback? onTap;

  const _VoteRow({required this.answer, required this.multi, required this.picked, required this.onTap});

  @override
  Widget build(BuildContext context) => SelectionContainer.disabled(
        child: GlitchPressable(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: GlitchColors.bgInput,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: picked ? GlitchColors.accentBlue : Colors.transparent, width: 1.5),
            ),
            child: Row(
              children: [
                Expanded(child: _answerLabel(answer, weight: FontWeight.w600)),
                const SizedBox(width: 10),
                multi ? GlitchCheckMark(value: picked) : _RadioMark(value: picked),
              ],
            ),
          ),
        ),
      );
}

class _RadioMark extends StatelessWidget {
  final bool value;

  const _RadioMark({required this.value});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: value ? GlitchColors.accentBlue : GlitchColors.textHint, width: value ? 6 : 1.6),
        ),
      );
}

class _ResultRow extends StatelessWidget {
  final PollAnswer answer;
  final double share;
  final bool mine;
  final bool winner;
  final VoidCallback? onTap;

  const _ResultRow({
    required this.answer,
    required this.share,
    required this.mine,
    required this.winner,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: GlitchColors.bgInput,
        child: Stack(
          children: [
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: share.clamp(0, 1).toDouble(),
                child: Container(color: GlitchColors.accentBlue.withOpacity(mine || winner ? 0.32 : 0.16)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Expanded(child: _answerLabel(answer, weight: winner ? FontWeight.w700 : FontWeight.w600)),
                  if (mine) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.check_circle_rounded, size: 18, color: GlitchColors.accentBlue),
                  ],
                  const SizedBox(width: 10),
                  Text(_percent(share),
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: winner ? FontWeight.w700 : FontWeight.w600,
                          color: GlitchColors.textPrimary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return onTap == null ? row : SelectionContainer.disabled(child: GlitchPressable(onTap: onTap, child: row));
  }
}

class PollResultCard extends StatelessWidget {
  final PollInfo? poll;
  final double maxWidth;
  final VoidCallback? onOpen;

  const PollResultCard({super.key, required this.poll, required this.maxWidth, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final poll = this.poll;
    final Widget outcome;
    if (poll == null) {
      outcome = Text(s.pollDeleted, style: TextStyle(fontSize: 14, color: GlitchColors.textHint));
    } else {
      final top = poll.topVotes;
      final leaders = top == 0 ? const <PollAnswer>[] : poll.answers.where((a) => a.votes == top).toList();
      if (leaders.isEmpty) {
        outcome = Text(s.pollNoVotes, style: TextStyle(fontSize: 14, color: GlitchColors.textHint));
      } else if (leaders.length > 1) {
        outcome = Text(s.pollTie, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary));
      } else {
        final w = leaders.single;
        outcome = Row(
          children: [
            Icon(Icons.emoji_events_rounded, size: 18, color: GlitchColors.accentBlue),
            const SizedBox(width: 8),
            Expanded(child: _answerLabel(w, weight: FontWeight.w700)),
            const SizedBox(width: 10),
            Text(_percent(poll.shareOf(w)),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary)),
          ],
        );
      }
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: MessageCard(
        color: ContentPicker.background(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(Icons.poll_outlined, size: 18, color: GlitchColors.textHint),
              const SizedBox(width: 8),
              Text(s.pollEndedLabel, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: GlitchColors.textHint)),
            ]),
            if (poll != null) ...[
              const SizedBox(height: 6),
              Text(poll.question,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary)),
            ],
            const SizedBox(height: 8),
            outcome,
            if (poll != null && onOpen != null) ...[
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerLeft, child: SelectionContainer.disabled(
                child: GlitchPlainButton(label: s.pollOpen, onTap: onOpen),
              )),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> showPollVoters(BuildContext context, {required int chatId, required int messageId, required PollAnswer answer}) {
  return showAdaptiveSheet<void>(
    context,
    title: answer.text,
    bodyBuilder: (ctx, _) => _PollVotersList(chatId: chatId, messageId: messageId, answerId: answer.id),
  );
}

class _PollVotersList extends StatefulWidget {
  final int chatId;
  final int messageId;
  final int answerId;

  const _PollVotersList({required this.chatId, required this.messageId, required this.answerId});

  @override
  State<_PollVotersList> createState() => _PollVotersListState();
}

class _PollVotersListState extends State<_PollVotersList> {
  late final CursorPager<ServerUser> _pager;

  @override
  void initState() {
    super.initState();
    _pager = CursorPager<ServerUser>((before) => _fetch(before))..addListener(_onChange);
    _pager.reload();
  }

  Future<ListPage<ServerUser>> _fetch(int? before) =>
      api.getPollVoters(widget.chatId, widget.messageId, widget.answerId, before: before);

  @override
  void dispose() {
    _pager.removeListener(_onChange);
    _pager.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_pager.loading) {
      body = const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)));
    } else if (_pager.error != null) {
      body = SettingsRetry(text: _pager.error!, onRetry: _pager.reload);
    } else if (_pager.items.isEmpty) {
      body = Center(
        child: Text(context.s.pollVotersEmpty, style: TextStyle(fontSize: 14, color: GlitchColors.textHint)),
      );
    } else {
      final more = _pager.moreError != null
          ? SettingsRetry(text: _pager.moreError!, onRetry: _pager.loadMore)
          : _pager.hasMore
              ? LoadMoreTrigger(key: ValueKey(_pager.items.length), onVisible: _pager.loadMore)
              : null;
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          for (final u in _pager.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                ServerUserAvatar(user: u, name: u.displayName, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(u.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary)),
                ),
              ]),
            ),
          if (more != null) more,
        ],
      );
    }
    return SizedBox(height: 360, child: body);
  }
}
