import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'l10n.dart';

import '../providers/locale_provider.dart';

String formatDay(DateTime d) => DateFormat.yMMMd(localeProvider.locale.languageCode).format(d);

String formatTime(DateTime d) => DateFormat.Hm(localeProvider.locale.languageCode).format(d);

String formatDayLong(DateTime d) => DateFormat.yMMMMd(localeProvider.locale.languageCode).format(d);

String formatMessageStamp(BuildContext context, DateTime d) {
  final now = DateTime.now();
  final day = DateTime(d.year, d.month, d.day);
  final today = DateTime(now.year, now.month, now.day);
  final time = formatTime(d);
  if (day == today) return context.s.messageStampToday(time);
  if (day == DateTime(now.year, now.month, now.day - 1)) return context.s.messageStampYesterday(time);
  return '${DateFormat.yMd(localeProvider.locale.languageCode).format(d)} $time';
}
