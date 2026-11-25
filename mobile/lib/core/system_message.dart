import '../models/system_info.dart';
import 'l10n.dart';
import 'record_ids.dart';


class SystemPart {
  final String text;

  final SystemPerson? person;

  const SystemPart(this.text, [this.person]);
}

List<SystemPart>? systemMessageParts(
  S s, {
  required SystemInfo? system,
  required int messageId,
  required SystemPerson actor,
}) {
  if (system == null) return null;
  final target = system.target;
  String? template;
  switch (system.event) {
    case 'group_created':
      template = s.systemGroupCreated(_actorMark);
    case 'member_added':
      if (target != null) template = s.systemMemberAdded(_actorMark, _targetMark);
    case 'member_removed':
      if (target != null) template = s.systemMemberRemoved(_actorMark, _targetMark);
    case 'group_joined':
      template = s.systemGroupJoined(_actorMark);
    case 'group_left':
      template = s.systemGroupLeft(_actorMark);
    case 'server_joined':
      template = _welcome(s, messageId);
    case 'server_left':
      template = s.systemServerLeft(_actorMark);
  }
  if (template == null) return null;
  final parts = <SystemPart>[];
  final buffer = StringBuffer();
  for (final rune in template.runes) {
    final char = String.fromCharCode(rune);
    final person = char == _actorMark ? actor : (char == _targetMark ? target : null);
    if (person == null) {
      buffer.write(char);
      continue;
    }
    if (buffer.isNotEmpty) parts.add(SystemPart(buffer.toString()));
    buffer.clear();
    parts.add(SystemPart(person.displayName, person));
  }
  if (buffer.isNotEmpty) parts.add(SystemPart(buffer.toString()));
  return parts;
}

String? systemMessageText(
  S s, {
  required SystemInfo? system,
  required int messageId,
  required String actorName,
}) {
  final parts = systemMessageParts(
    s,
    system: system,
    messageId: messageId,
    actor: SystemPerson(id: 0, nickname: '', displayName: actorName),
  );
  return parts?.map((p) => p.text).join();
}

const String _actorMark = '\u0001';
const String _targetMark = '\u0002';

String _welcome(S s, int messageId) {
  final phrases = <String Function(String)>[
    s.systemWelcome1, s.systemWelcome2, s.systemWelcome3, s.systemWelcome4,
    s.systemWelcome5, s.systemWelcome6, s.systemWelcome7, s.systemWelcome8,
  ];
  final index = createdAtOfId(messageId).millisecondsSinceEpoch % phrases.length;
  return phrases[index](_actorMark);
}
