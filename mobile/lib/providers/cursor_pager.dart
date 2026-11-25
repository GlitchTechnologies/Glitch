import 'package:flutter/foundation.dart';

import '../models/list_page.dart';
import '../services/api_service.dart' show errorMessage;

/// ⚠️ ЗАЩИТА ОТ УСТАРЕВШИХ ОТВЕТОВ — счётчик [_seq], тот же приём, что
/// `_loadSeq` в `ChatsProvider`. Без неё при быстром вводе в поиск ответ на
/// «ал» мог прийти ПОСЛЕ ответа на «алиса» и подменить список. Догрузка
/// номер не увеличивает, а сверяет: [reload] посреди догрузки делает её
/// устаревшей, и хвост старого поиска не приклеится к новому.
class CursorPager<T> extends ChangeNotifier {
  final Future<ListPage<T>> Function(int? before) _fetch;

  CursorPager(this._fetch);

  List<T> items = [];

  int? total;

  bool loading = true;

  bool loadingMore = false;

  String? error;

  String? moreError;

  int? _next;
  bool get hasMore => _next != null;

  int _seq = 0;
  bool _disposed = false;

  bool _started = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> reload() async {
    final seq = ++_seq;
    loading = true;
    loadingMore = false;
    error = null;
    moreError = null;
    if (_started) _notify();
    _started = true;
    try {
      final page = await _fetch(null);
      // Единственный гвард — после всей сети; устаревший ответ молча
      // выбрасывается.
      if (_disposed || seq != _seq) return;
      items = page.items;
      total = page.total;
      _next = page.nextCursor;
    } catch (e) {
      if (_disposed || seq != _seq) return;
      error = errorMessage(e);
    } finally {
      if (!_disposed && seq == _seq) {
        loading = false;
        _notify();
      }
    }
  }

  /// Догрузить следующую порцию. Повторный вызов, пока идёт загрузка, —
  /// ничего не делает (прокрутка зовёт его много раз подряд).
  Future<void> loadMore() async {
    final cursor = _next;
    if (cursor == null || loading || loadingMore) return;
    final seq = _seq;
    loadingMore = true;
    moreError = null;
    _notify();
    try {
      final page = await _fetch(cursor);
      if (_disposed || seq != _seq) return;
      items = [...items, ...page.items];
      total = page.total ?? total;
      _next = page.nextCursor;
    } catch (e) {
      if (_disposed || seq != _seq) return;
      moreError = errorMessage(e);
    } finally {
      if (!_disposed && seq == _seq) {
        loadingMore = false;
        _notify();
      }
    }
  }

  void removeWhere(bool Function(T item) test) {
    final kept = items.where((e) => !test(e)).toList();
    final removed = items.length - kept.length;
    if (removed == 0) return;
    items = kept;
    final t = total;
    if (t != null) total = t - removed;
    _notify();
  }
}
