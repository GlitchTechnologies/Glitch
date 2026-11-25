
String normalizeTextQuery(String query) {
  var q = query.trim();
  if (q.startsWith('@')) q = q.substring(1).trimLeft();
  return q.toLowerCase();
}

bool matchesQuery(String query, Iterable<String?> fields) {
  final q = normalizeTextQuery(query);
  if (q.isEmpty) return true;
  for (final f in fields) {
    if (f != null && f.toLowerCase().contains(q)) return true;
  }
  return false;
}

int? matchRank(String query, Iterable<String?> fields) {
  final q = normalizeTextQuery(query);
  if (q.isEmpty) return 2;
  int? best;
  for (final f in fields) {
    if (f == null) continue;
    final v = f.toLowerCase();
    final r = v == q ? 0 : v.startsWith(q) ? 1 : v.contains(q) ? 2 : null;
    if (r != null && (best == null || r < best)) best = r;
    if (best == 0) break;
  }
  return best;
}
