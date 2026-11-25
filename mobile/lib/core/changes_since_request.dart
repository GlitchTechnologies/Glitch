/// Повторно применяет изменения, полученные во время загрузки списка.
/// Изменения должны давать тот же результат при повторном применении.
class ChangesSinceRequest {
  List<void Function()>? _log;
  int _seq = 0;

  final Set<int> removed = {};

  bool get active => _log != null;

  void begin(int seq) {
    _log = [];
    _seq = seq;
    removed.clear();
  }

  void record(void Function() change) => _log?.add(change);

  void replay(int seq) {
    if (seq != _seq) return;
    final log = _log;
    _log = null;
    for (final change in log ?? const <void Function()>[]) {
      change();
    }
    removed.clear();
  }

  /// При сбое оставляем уже применённые изменения на экране.
  void drop(int seq) {
    if (seq != _seq) return;
    _log = null;
    removed.clear();
  }
}
