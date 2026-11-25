import '../core/time_json.dart';

class PollAnswer {
  final int id;
  final String text;
  final String? emoji;
  final int votes;

  const PollAnswer({required this.id, required this.text, this.emoji, this.votes = 0});

  factory PollAnswer.fromJson(Map<String, dynamic> j) => PollAnswer(
    id: (j['id'] as num).toInt(),
    text: j['text'] as String? ?? '',
    emoji: j['emoji'] as String?,
    votes: (j['votes'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'emoji': emoji, 'votes': votes};
}

class PollInfo {
  final int id;
  final int messageId;
  final String question;
  final List<PollAnswer> answers;
  final bool allowMultiselect;
  final DateTime expiresAt;
  /// Закрыт ли на момент ответа сервера. Срок мог выйти и после — поэтому
  /// спрашивать только [isClosed].
  final bool ended;
  final int voters;
  final List<int> myAnswerIds;

  const PollInfo({
    required this.id,
    required this.messageId,
    required this.question,
    required this.answers,
    required this.allowMultiselect,
    required this.expiresAt,
    required this.ended,
    required this.voters,
    required this.myAnswerIds,
  });

  factory PollInfo.fromJson(Map<String, dynamic> j) => PollInfo(
    id: (j['id'] as num).toInt(),
    messageId: (j['message_id'] as num).toInt(),
    question: j['question'] as String? ?? '',
    answers: [for (final a in (j['answers'] as List? ?? const [])) PollAnswer.fromJson(a as Map<String, dynamic>)],
    allowMultiselect: j['allow_multiselect'] == true,
    expiresAt: parseUtcLocal(j['expires_at']),
    ended: j['ended'] == true,
    voters: (j['voters'] as num?)?.toInt() ?? 0,
    myAnswerIds: [for (final id in (j['my_answer_ids'] as List? ?? const [])) (id as num).toInt()],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'message_id': messageId,
    'question': question,
    'answers': [for (final a in answers) a.toJson()],
    'allow_multiselect': allowMultiselect,
    'expires_at': utcIso(expiresAt),
    'ended': ended,
    'voters': voters,
    'my_answer_ids': myAnswerIds,
  };

  bool isClosed(DateTime now) => ended || !now.isBefore(expiresAt);

  bool get hasMyVote => myAnswerIds.isNotEmpty;

  int get topVotes => answers.fold(0, (m, a) => a.votes > m ? a.votes : m);

  double shareOf(PollAnswer a) => voters == 0 ? 0 : a.votes / voters;

  PollInfo mergedFromEvent(PollInfo incoming, {required bool actorIsMe}) =>
      actorIsMe ? incoming : incoming.withMyAnswers(myAnswerIds);

  PollInfo withMyAnswers(List<int> ids) => PollInfo(
    id: id, messageId: messageId, question: question, answers: answers,
    allowMultiselect: allowMultiselect, expiresAt: expiresAt, ended: ended,
    voters: voters, myAnswerIds: ids,
  );
}

class PollDraft {
  final String question;
  final List<({String text, String? emoji})> answers;
  final bool allowMultiselect;
  final int durationHours;

  const PollDraft({
    required this.question,
    required this.answers,
    required this.allowMultiselect,
    required this.durationHours,
  });

  Map<String, dynamic> toJson() => {
    'question': question,
    'answers': [for (final a in answers) {'text': a.text, if (a.emoji != null) 'emoji': a.emoji}],
    'allow_multiselect': allowMultiselect,
    'duration_hours': durationHours,
  };

  PollInfo toPreview() => PollInfo(
    id: 0,
    messageId: 0,
    question: question,
    answers: [
      for (var i = 0; i < answers.length; i++)
        PollAnswer(id: i + 1, text: answers[i].text, emoji: answers[i].emoji),
    ],
    allowMultiselect: allowMultiselect,
    expiresAt: DateTime.now().add(Duration(hours: durationHours)),
    ended: false,
    voters: 0,
    myAnswerIds: const [],
  );
}
