import 'package:flutter/widgets.dart';
import 'l10n.dart';
import '../models/presence.dart';

// Единая формула текста присутствия («в сети» / «N мин назад» / «в 14:32» /
// «вчера» / дата) — раньше жила только в ChatProvider.presenceText (шапка
// чата). У профиля контакта (contact_screen.dart) была своя, независимо
// написанная и куда более грубая версия: "isOnline" там значило "видели
// последние 5 минут" (не смотрела на настоящее серверное поле isOnline
// вообще), а текст — всего два варианта, "в сети"/"был(а) недавно", без
// веток "вчера"/даты. Из-за этого один и тот же человек мог одновременно
// показывать "в сети вчера" в шапке чата и "был(а) недавно" в профиле —
// два независимых алгоритма над одними и теми же данными физически не
// обязаны совпадать. Теперь оба места вызывают эту функцию.
String presenceText(BuildContext context, {required bool isOnline, required DateTime? lastSeen, PresenceStatus? status}) {
  final s = context.s;
  if (isOnline) {
    if (status == PresenceStatus.idle) return s.presenceIdle;
    if (status == PresenceStatus.dnd) return s.presenceDnd;
    return s.contactOnline;
  }
  final ls = lastSeen;
  if (ls == null) return '';
  final now = DateTime.now();
  final diff = now.difference(ls);
  if (diff.inMinutes < 1) return s.presenceJustNow;
  if (diff.inMinutes < 60) return s.presenceOnlineAgo(diff.inMinutes);
  if (ls.day == now.day) {
    final h = ls.hour.toString().padLeft(2, '0');
    final m = ls.minute.toString().padLeft(2, '0');
    return s.presenceOnlineAt('$h:$m');
  }
  if (diff.inDays < 2) return s.presenceOnlineYesterday;
  return s.presenceOnlineDate('${ls.day.toString().padLeft(2, '0')}.${ls.month.toString().padLeft(2, '0')}');
}

DateTime? unhideLastSeen(DateTime raw) => raw.year < 2010 ? null : raw;
