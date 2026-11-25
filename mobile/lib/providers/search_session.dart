import 'dart:async';

import 'package:flutter/foundation.dart';

/// СЕАНС ПОИСКА — состояние одного поля поиска на сервере (2026-10-11). Ядро
/// без экрана: ЛЮБОЕ поле, которое ищет на сервере, берёт этот класс, а не
/// пишет свою паузу и защиту от устаревших ответов. Потребители: поиск «по
/// всему Glitch» (`PlacePicker` — окно «Найти или начать беседу», «Переслать»;
/// `api.searchEverything`) и выбор игр сообщества (`GamePicker`,
/// `api.searchGames`, с 2026-11-07).
///
/// ЧТО искать — [search], его даёт место; что кому видно, решает сервер.
/// Здесь — только:
/// • пауза в наборе ([debounce]): запрос уходит, когда человек замер, а не на
///   каждую букву;
/// • ⚠️ защита от устаревших ответов — счётчик [_seq], тот же приём, что у
///   `CursorPager`/`NumberedPager`: ответ на старый запрос (человек успел
///   допечатать) не перетирает свежий;
/// • загрузка и ошибка — для показа.
class SearchSession<T> extends ChangeNotifier {
  final Future<List<T>> Function(String query) search;
  final Duration debounce;

  SearchSession({required this.search, this.debounce = const Duration(milliseconds: 200)});

  String _query = '';
  String get query => _query;

  List<T> _hits = const [];

  List<T> get hits => _hits;

  bool _loading = false;
  bool get loading => _loading;

  bool _failed = false;
  bool get failed => _failed;

  bool get isEmpty => _query.trim().isEmpty;

  Timer? _timer;
  int _seq = 0;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void setQuery(String value) {
    if (value == _query) return;
    _query = value;
    _timer?.cancel();
    final seq = ++_seq;
    if (isEmpty) {
      _hits = const [];
      _loading = false;
      _failed = false;
      _notify();
      return;
    }
    _loading = true;
    _notify();
    _timer = Timer(debounce, () => _run(seq));
  }

  void retry() {
    if (isEmpty) return;
    _timer?.cancel();
    final seq = ++_seq;
    _loading = true;
    _failed = false;
    _notify();
    _run(seq);
  }

  Future<void> _run(int seq) async {
    try {
      final hits = await search(_query);
      if (_disposed || seq != _seq) return;
      _hits = hits;
      _failed = false;
    } catch (_) {
      if (_disposed || seq != _seq) return;
      _failed = true;
    }
    _loading = false;
    _notify();
  }
}
