library;

Map<String, String>? parseAvatarSizes(dynamic raw) {
  if (raw is! Map) return null;
  final out = <String, String>{};
  raw.forEach((key, value) {
    if (value is String && value.isNotEmpty) out['$key'] = value;
  });
  return out.isEmpty ? null : out;
}

String? pickAvatarUrl({
  required String? original,
  required Map<String, String>? sizes,
  required double logicalSize,
  required double devicePixelRatio,
}) {
  if (sizes == null || sizes.isEmpty) return original;

  final needed = logicalSize * devicePixelRatio * 1.1;

  final available = <int, String>{};
  sizes.forEach((key, url) {
    final size = int.tryParse(key);
    if (size != null && size > 0) available[size] = url;
  });
  if (available.isEmpty) return original;

  final keys = available.keys.toList()..sort();
  for (final size in keys) {
    if (size >= needed) return available[size];
  }
  return available[keys.last];
}
