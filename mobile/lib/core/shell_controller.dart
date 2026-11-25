import 'dart:async';

import 'package:flutter/widgets.dart';


enum ShellSlot {
  list,

  main,

  details,
}

class ShellPlace extends InheritedWidget {
  final ShellSlot slot;

  final bool visible;

  const ShellPlace({
    super.key,
    required this.slot,
    required this.visible,
    required super.child,
  });

  static ShellPlace? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShellPlace>();

  static bool visibleHere(BuildContext context) => of(context)?.visible ?? true;

  static ShellSlot? slotOf(BuildContext context) => of(context)?.slot;

  /// [slotOf] читает метку без подписки — он для обработчиков событий (см.
  /// [of]). Здесь подписка есть (`dependOn…`): если место однажды сменится,
  /// виджет перестроится сам, а не останется нарисованным по старому ответу.
  static ShellSlot? slotForBuild(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellPlace>()?.slot;

  static bool visibleForBuild(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellPlace>()?.visible ?? true;

  @override
  bool updateShouldNotify(ShellPlace old) =>
      old.visible != visible || old.slot != slot;
}

class _MainEntry {
  Widget content;
  final Object? scope;
  final Completer<void> done = Completer<void>();
  _MainEntry(this.content, [this.scope]);
}

class ShellController extends ChangeNotifier {
  Widget? _list;
  Widget? _details;

  final List<_MainEntry> _mainStack = [];

  int _detailsDepth = 0;

  double? _detailsWidth;

  Object? _detailsScope;

  Widget? get list => _list;

  Widget? get main => _mainStack.isEmpty ? null : _mainStack.last.content;

  /// Вся стопка снизу вверх. Каркас держит нижние уровни в дереве живыми
  /// (скрытыми), иначе возврат «назад» терял бы их состояние — прокрутку
  /// ленты, загруженные посты.
  List<Widget> get mainStack => [for (final e in _mainStack) e.content];

  Object? get mainKey {
    if (_mainStack.isEmpty) return null;
    final key = _mainStack.first.content.key;
    return key is ValueKey ? key.value : null;
  }

  Object? get mainScope => _mainStack.isEmpty ? null : _mainStack.first.scope;

  Widget? get details => _details;

  Object? get detailsKey {
    final key = _details?.key;
    return key is ValueKey ? key.value : null;
  }

  double? get detailsWidth => _detailsWidth;

  final Map<ShellSlot, Completer<void>> _done = {};

  void _finish(ShellSlot slot) {
    final completer = _done.remove(slot);
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  /// **`list` И `details` — ОСОБЫЙ СЛУЧАЙ, места со своей вложенной
  /// навигацией.** У `list` это профиль → настройки → сессии/безопасность, у
  /// `details` — профиль группы → настройки → участники/админы
  /// (добавлено 2026-08-24, тем же приёмом, что уже был у `list`). На
  /// телефоне это обычная цепочка `Navigator.push`. Чтобы та же цепочка
  /// работала и здесь, `openAdaptive` заворачивает содержимое ОБОИХ мест в
  /// СВОЙ маленький `Navigator` (см. adaptive_open.dart) — все дальнейшие
  /// переходы внутри них остаются обычным Flutter-кодом без единой правки,
  /// они просто попадают в этот вложенный стек, а не в корневой. Именно
  /// поэтому экраны настроек не пришлось трогать вообще.
  Future<void> show(
    ShellSlot slot,
    Widget content, {
    double? detailsWidth,
    Object? scope,
  }) {
    if (slot == ShellSlot.main) {
      // Новая сборка содержимого при этом ОТДАЁТСЯ месту (2026-10-30): ключ
      // тот же, поэтому состояние живёт дальше (прокрутка, набранное), а
      // экран получает её в `didUpdateWidget` — как любой виджет Flutter,
      // который перестроили с новыми данными. Так в уже открытую переписку
      // доходит то, с чем её открыли снова («Сообщение для…», «Поделиться» —
      // models/chat_arrival.dart); выброшенная сборка теряла это молча.
      final key = content.key;
      if (_mainStack.isNotEmpty && key is ValueKey && key.value == mainKey) {
        _mainStack.first.content = content;
        while (_mainStack.length > 1) {
          final above = _mainStack.removeLast();
          if (!above.done.isCompleted) above.done.complete();
        }
        if (_details != null && _detailsDepth > _mainStack.length) {
          _details = null;
          _detailsWidth = null;
          _detailsScope = null;
          _detailsDepth = 0;
          _finish(ShellSlot.details);
        }
        notifyListeners();
        return _mainStack.first.done.future;
      }
      final entry = _MainEntry(content, scope);
      // Обе области обязаны быть непустыми: два `null` — это «оба относятся к
      // своей переписке», и совпадением их считать нельзя, иначе панель
      // перестала бы гаснуть вообще никогда.
      final keepDetails = _details != null &&
          _detailsScope != null &&
          scope != null &&
          _detailsScope == scope;
      _clearMainStack();
      _mainStack.add(entry);
      if (keepDetails) {
        _detailsDepth = _mainStack.length;
      } else {
        _details = null;
        _detailsWidth = null;
        _detailsScope = null;
        _detailsDepth = 0;
        _finish(ShellSlot.details);
      }
      notifyListeners();
      return entry.done.future;
    }

    _finish(slot);
    final completer = Completer<void>();
    _done[slot] = completer;
    switch (slot) {
      case ShellSlot.main:
        break; // разобрано выше
      case ShellSlot.details:
        _details = content;
        _detailsWidth = detailsWidth;
        _detailsScope = scope;
        _detailsDepth = _mainStack.length; // к этому уровню центра она и относится
      case ShellSlot.list:
        _list = content;
    }
    notifyListeners();
    return completer.future;
  }

  Future<void> pushMain(Widget content) {
    final entry = _MainEntry(content);
    _mainStack.add(entry);
    notifyListeners();
    return entry.done.future;
  }

  void _clearMainStack() {
    for (final entry in _mainStack.reversed) {
      if (!entry.done.isCompleted) entry.done.complete();
    }
    _mainStack.clear();
  }

  void close(ShellSlot slot) {
    switch (slot) {
      case ShellSlot.main:
        if (_mainStack.isNotEmpty) {
          final entry = _mainStack.removeLast();
          if (!entry.done.isCompleted) entry.done.complete();
        }
        if (_details != null && _detailsDepth > _mainStack.length) {
          _details = null;
          _detailsWidth = null;
          _detailsScope = null;
          _finish(ShellSlot.details);
        }
        notifyListeners();
        return;
      case ShellSlot.details:
        _details = null;
        _detailsWidth = null;
        _detailsScope = null;
        _detailsDepth = 0;
      case ShellSlot.list:
        _list = null;
    }
    _finish(slot);
    notifyListeners();
  }

  void closeAll(ShellSlot slot) {
    if (slot != ShellSlot.main) {
      close(slot);
      return;
    }
    _clearMainStack();
    if (_details != null) {
      _details = null;
      _detailsWidth = null;
      _detailsScope = null;
      _detailsDepth = 0;
      _finish(ShellSlot.details);
    }
    notifyListeners();
  }

  void reset() {
    _list = null;
    _details = null;
    _detailsWidth = null;
    _detailsScope = null;
    _detailsDepth = 0;
    _mainStack.clear();
    _done.clear();
    notifyListeners();
  }

  bool get hasDetails => _details != null;
  bool get hasMain => _mainStack.isNotEmpty;
  bool get hasListOverride => _list != null;
}

final shellController = ShellController();
