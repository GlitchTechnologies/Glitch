import 'package:flutter/foundation.dart';

import '../models/list_page.dart';
import '../services/api_service.dart' show errorMessage;

/// ⚠️ ЗАЩИТА ОТ УСТАРЕВШИХ ОТВЕТОВ — счётчик [_seq], как у [CursorPager] и
/// `ChatsProvider._loadSeq`: быстро нажатые «2», «3», «4» не должны показать
/// страницу, чей ответ пришёл последним, а не ту, что выбрана последней.
class NumberedPager<T> extends ChangeNotifier {
  final Future<ListPage<T>> Function(int offset, int limit) _fetch;

  NumberedPager(this._fetch, {required int pageSize}) : _pageSize = pageSize;

  List<T> items = [];

  int total = 0;

  bool loading = true;
  String? error;

  int _page = 1;
  int _pageSize;

  int get page => _page;
  int get pageSize => _pageSize;

  int get pageCount => total <= 0 ? 1 : (total + _pageSize - 1) ~/ _pageSize;

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

  Future<void> load() async {
    final seq = ++_seq;
    loading = true;
    error = null;
    if (_started) _notify();
    _started = true;
    try {
      final res = await _fetch((_page - 1) * _pageSize, _pageSize);
      if (_disposed || seq != _seq) return;
      total = res.total ?? res.items.length;
      if (res.items.isEmpty && total > 0 && _page > pageCount) {
        _page = pageCount;
        load();
        return;
      }
      items = res.items;
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

  void replace(bool Function(T) where, T item) {
    final i = items.indexWhere(where);
    if (i < 0) return;
    items = [...items]..[i] = item;
    _notify();
  }

  void goTo(int page) {
    final p = page.clamp(1, pageCount);
    if (p == _page) return;
    _page = p;
    load();
  }

  void setPageSize(int size) {
    if (size == _pageSize || size <= 0) return;
    final firstIndex = (_page - 1) * _pageSize;
    _pageSize = size;
    _page = firstIndex ~/ size + 1;
    load();
  }

  void restart() {
    _page = 1;
    load();
  }
}
