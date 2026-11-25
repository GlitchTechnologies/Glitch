import 'dart:async';

import '../core/file_size.dart';
import '../core/l10n.dart';
import 'api_service.dart';

class UploadLimits {
  Map<UploadKind, int>? _limits;
  int? _maxAttachments;
  Future<void>? _loading;

  int _generation = 0;

  /// Загрузить пределы. Повторный вызов во время загрузки ждёт ту же.
  /// Ошибка не бросается: без пределов проверяет сервер.
  Future<void> load() {
    return _loading ??= _fetch().whenComplete(() => _loading = null);
  }

  Future<void> _fetch() async {
    final gen = _generation;
    try {
      final raw = await api.getUploadLimits();
      if (gen != _generation) return;
      _limits = {
        for (final kind in UploadKind.values)
          if (raw.bytes[kind.serverKey] != null) kind: raw.bytes[kind.serverKey]!,
      };
      _maxAttachments = raw.maxAttachments;
    } catch (_) {
    }
  }

  void reset() {
    _generation++;
    _limits = null;
    _maxAttachments = null;
    _loading = null;
  }

  /// Предел вида в байтах; null — неизвестен (ещё не загружен).
  int? limitOf(UploadKind kind) => _limits?[kind];

  int? get maxAttachments => _maxAttachments;

  Future<void> ensureFits(UploadKind kind, int bytes) async {
    if (_limits == null) await load();
    final limit = limitOf(kind);
    if (limit != null && bytes > limit) throw UploadTooLarge(kind, limit);
  }
}

final uploadLimits = UploadLimits();

enum UploadKind {
  photo('photo'),
  video('video'),
  file('file'),
  voice('voice'),
  videoNote('video_note'),
  avatar('avatar'),
  banner('banner'),

  sticker('sticker_source'),

  streamPreview('stream_preview');

  final String serverKey;
  const UploadKind(this.serverKey);
}

class UploadTooLarge implements LocalizedError {
  final UploadKind kind;
  final int limit;
  const UploadTooLarge(this.kind, this.limit);

  @override
  String describe(S s) => s.uploadTooLarge(formatBytes(s, limit));

  @override
  String toString() => 'UploadTooLarge(${kind.serverKey}, $limit)';
}
