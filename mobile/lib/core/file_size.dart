import 'package:intl/intl.dart';

import 'l10n.dart';

String formatBytes(S s, int bytes) {
  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;
  final number = NumberFormat('0.#', s.localeName);
  if (bytes < kb) return s.sizeBytes('$bytes');
  if (bytes < mb) return s.sizeKb(number.format(bytes / kb));
  if (bytes < gb) return s.sizeMb(number.format(bytes / mb));
  return s.sizeGb(number.format(bytes / gb));
}
