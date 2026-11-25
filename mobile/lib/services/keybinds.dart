import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener, AppLifecycleState;
import 'package:shared_preferences/shared_preferences.dart';

import 'desktop_shell.dart';
import 'error_reporter.dart';
import 'keybinds_platform_web.dart' if (dart.library.io) 'keybinds_platform_native.dart';

// Два хозяина хранения — по тому, КТО исполняет действие:
//   • действия Glitch (рация, микрофон, звук) — хранятся на устройстве
//     (`keybinds_v1`, не на сервере — клавиши свойство компьютера);
//   • действия программы для Windows (перезагрузка, масштаб,
//     [KeybindKind.program]) — хранит и ловит сама программа
//     (desktop/src/main/hotkeys.ts): они обязаны работать и при сломанной
//     странице. Здесь их только показывают и меняют, одним списком со своими.
//     В браузере это клавиши самого браузера — их показывают, но поменять
//     нельзя ([Keybinds.isEditable]).

enum KeybindKind {
  hold,

  press,

  program,
}

enum KeybindAction {
  pushToTalk('push_to_talk', KeybindKind.hold),
  toggleMute('toggle_mute', KeybindKind.press),
  toggleDeafen('toggle_deafen', KeybindKind.press),
  editLastMessage('edit_last_message', KeybindKind.press),
  reload('reload', KeybindKind.program),
  zoomIn('zoom-in', KeybindKind.program),
  zoomOut('zoom-out', KeybindKind.program),
  zoomReset('zoom-reset', KeybindKind.program);

  final String id;
  final KeybindKind kind;

  const KeybindAction(this.id, this.kind);

  bool get isProgram => kind == KeybindKind.program;

  static KeybindAction? fromId(Object? id) {
    for (final a in values) {
      if (a.id == id) return a;
    }
    return null;
  }
}

const int kMaxComboKeys = 4;

@immutable
class KeyCombo {
  final List<String> keys;

  KeyCombo(Iterable<String> keys) : keys = List.unmodifiable(_ordered(keys));

  static List<String> _ordered(Iterable<String> keys) {
    final set = keys.toSet();
    final rest = set.where((k) => !_modifierOrder.contains(k)).toList()..sort();
    return [..._modifierOrder.where(set.contains), ...rest];
  }

  static const _modifierOrder = ['Control', 'Shift', 'Alt', 'Meta'];

  bool get isEmpty => keys.isEmpty;

  Iterable<String> get _plain => keys.where((k) => !_modifierOrder.contains(k));

  bool get fitsProgram => _plain.length == 1 && !_plain.first.startsWith('Mouse');

  bool heldIn(Set<String> pressed) => keys.isNotEmpty && keys.every(pressed.contains);

  bool isStrictSubsetOf(KeyCombo other) => keys.length < other.keys.length && keys.every(other.keys.contains);

  String get label => keys.map(keyLabel).join(' + ');

  List<String> toJson() => keys;

  static KeyCombo? fromJson(Object? json) {
    if (json is! List) return null;
    final keys = json.whereType<String>().where(_known).toList();
    if (keys.isEmpty || keys.length != json.length || keys.length > kMaxComboKeys) return null;
    return KeyCombo(keys);
  }

  static bool _known(String key) => _codeKeys.contains(key) || _mouseCodes.contains(key);

  @override
  bool operator ==(Object other) => other is KeyCombo && listEquals(other.keys, keys);

  @override
  int get hashCode => Object.hashAll(keys);
}

@immutable
class Keybind {
  final KeybindAction action;
  final KeyCombo combo;

  const Keybind(this.action, this.combo);

  Map<String, Object> toJson() => {'action': action.id, 'keys': combo.toJson()};

  static Keybind? fromJson(Object? json) {
    if (json is! Map) return null;
    final action = KeybindAction.fromId(json['action']);
    final combo = KeyCombo.fromJson(json['keys']);
    return action == null || combo == null ? null : Keybind(action, combo);
  }

  @override
  bool operator ==(Object other) => other is Keybind && other.action == action && other.combo == combo;

  @override
  int get hashCode => Object.hash(action, combo);
}

enum KeybindProblem {
  reserved,

  taken,

  unsupported,
}

/// Сочетания перезагрузки и масштаба, когда поменять их нельзя: в браузере
/// (это его клавиши) и у программы старше версии 10. ⚠️ Те же, что
/// умолчания программы (desktop/src/main/hotkeys.ts, DEFAULT_HOTKEYS), —
/// менять вместе.
final List<Keybind> _fixedProgramBinds = [
  Keybind(KeybindAction.reload, KeyCombo(const ['Control', 'KeyR'])),
  Keybind(KeybindAction.zoomIn, KeyCombo(const ['Control', 'Equal'])),
  Keybind(KeybindAction.zoomIn, KeyCombo(const ['Control', 'NumpadAdd'])),
  Keybind(KeybindAction.zoomOut, KeyCombo(const ['Control', 'Minus'])),
  Keybind(KeybindAction.zoomOut, KeyCombo(const ['Control', 'NumpadSubtract'])),
  Keybind(KeybindAction.zoomReset, KeyCombo(const ['Control', 'Digit0'])),
  Keybind(KeybindAction.zoomReset, KeyCombo(const ['Control', 'Numpad0'])),
];

class Keybinds extends ChangeNotifier {
  static const _storageKey = 'keybinds_v1';

  List<Keybind> _own = const [];

  List<Keybind> _program = const [];

  List<Keybind> get binds => [..._own, ..._program];

  List<KeyCombo> combosOf(KeybindAction action) => [
        for (final b in binds)
          if (b.action == action) b.combo,
      ];

  bool get programEditable => desktopShell?.hasProgramHotkeys ?? false;

  bool isEditable(KeybindAction action) => !action.isProgram || programEditable;

  Future<void>? _loading;

  /// Прочитать назначенное и начать слушать клавиатуру и мышь. Зовётся при
  /// запуске приложения (main.dart); повторный вызов ничего не делает.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final own = <Keybind>[];
    try {
      final raw = jsonDecode(prefs.getString(_storageKey) ?? '[]');
      if (raw is List) {
        for (final item in raw) {
          final bind = Keybind.fromJson(item);
          if (bind != null &&
              !bind.action.isProgram &&
              !own.any((b) => b.combo == bind.combo || b.action == bind.action)) {
            own.add(bind);
          }
        }
      }
    } catch (_) {
    }
    if (!own.any((b) => b.action == KeybindAction.editLastMessage) &&
        !own.any((b) => b.combo == KeyCombo(const ['ArrowUp']))) {
      own.add(Keybind(KeybindAction.editLastMessage, KeyCombo(const ['ArrowUp'])));
    }
    _own = List.unmodifiable(own);
    _program = await _readProgram();
    _listen();
    _changed();
  }

  Future<List<Keybind>> _readProgram() async {
    final shell = desktopShell;
    if (shell == null || !shell.hasProgramHotkeys) return List.unmodifiable(_fixedProgramBinds);
    try {
      return _fromProgram(await shell.getProgramHotkeys());
    } catch (e, s) {
      errorReporter.report(e, stack: s, screen: 'keybinds:program');
      return List.unmodifiable(_fixedProgramBinds);
    }
  }

  static List<Keybind> _fromProgram(List<DesktopProgramHotkey> list) => List.unmodifiable([
        for (final h in list)
          if (KeybindAction.fromId(h.action) case final action? when action.isProgram)
            if (KeyCombo.fromJson(h.keys) case final combo?) Keybind(action, combo),
      ]);

  Future<void> _saveOwn() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode([for (final b in _own) b.toJson()]));
  }


  KeybindProblem? problemOf(KeybindAction action, KeyCombo combo) {
    if (action.isProgram && !combo.fitsProgram) return KeybindProblem.unsupported;
    for (final b in binds) {
      if (b.action == action) continue;
      if (b.combo == combo) return KeybindProblem.taken;
      if (b.action.isProgram && _swallows(b.combo, combo)) return KeybindProblem.reserved;
      if (action.isProgram && _swallows(combo, b.combo)) return KeybindProblem.reserved;
    }
    // Программа старше версии 10 о своих сочетаниях говорит только списком
    // занятых (сведения связи).
    if (_reserved.contains(combo)) return KeybindProblem.reserved;
    return null;
  }

  static bool _swallows(KeyCombo program, KeyCombo combo) {
    final key = program._plain.firstOrNull;
    if (key == null || !combo.keys.contains(key)) return false;
    for (final m in KeyCombo._modifierOrder) {
      if (program.keys.contains(m) != combo.keys.contains(m)) return false;
    }
    return true;
  }

  late final Set<KeyCombo> _reserved = programEditable
      ? const <KeyCombo>{}
      : {for (final keys in desktopShell?.reservedHotkeys ?? const <List<String>>[]) KeyCombo(keys)};


  Future<KeybindProblem?> assign(KeybindAction action, KeyCombo combo) async {
    await load();
    if (!isEditable(action)) return KeybindProblem.reserved;
    final current = combosOf(action);
    if (current.length == 1 && current.single == combo) return null;
    final problem = problemOf(action, combo);
    if (problem != null) return problem;
    List<Keybind> assigned(List<Keybind> list) => [
          for (final b in list)
            if (b.action != action) b,
          Keybind(action, combo),
        ];
    await _commit(
      own: action.isProgram ? null : assigned(_own),
      program: action.isProgram ? assigned(_program) : null,
    );
    return null;
  }

  Future<void> _commit({List<Keybind>? own, List<Keybind>? program}) async {
    if (own != null) _own = List.unmodifiable(own);
    final shell = desktopShell;
    if (program != null && shell != null && programEditable) {
      _program = List.unmodifiable(program);
      _changed();
      try {
        _program = _fromProgram(await shell.setProgramHotkeys([
          for (final b in program) (action: b.action.id, keys: b.combo.keys),
        ]));
      } catch (e, s) {
        errorReporter.report(e, stack: s, screen: 'keybinds:program');
        _program = await _readProgram();
      }
    }
    _changed();
    if (own != null) await _saveOwn();
  }

  void _changed() {
    _applyMouseBlock();
    _syncGlobal();
    _recompute();
    notifyListeners();
  }


  final Set<String> _keys = {};
  final Set<String> _mouse = {};

  final Map<KeybindAction, ValueNotifier<bool>> _held = {};
  final Map<KeybindAction, StreamController<void>> _presses = {};

  final Set<KeybindAction> _heldNow = {};

  ValueListenable<bool> heldOf(KeybindAction action) => _held.putIfAbsent(action, () => ValueNotifier(false));

  Stream<void> pressesOf(KeybindAction action) =>
      _presses.putIfAbsent(action, () => StreamController<void>.broadcast()).stream;

  bool matchesPress(KeybindAction action, KeyEvent event) {
    if (event is! KeyDownEvent || _recording != null) return false;
    final code = codeOfKey(event.physicalKey);
    if (code == null) return false;
    final pressed = {
      for (final key in HardwareKeyboard.instance.physicalKeysPressed)
        if (codeOfKey(key) case final name?) name,
      ..._mouse,
      code,
    };
    final held = [
      for (final bind in _own)
        if (bind.combo.heldIn(pressed)) bind,
    ];
    return held.any((bind) => bind.action == action && bind.combo.keys.contains(code) &&
        !held.any((other) => other.action != action && bind.combo.isStrictSubsetOf(other.combo)));
  }

  bool _listening = false;
  AppLifecycleListener? _lifecycle;
  StreamSubscription<Set<String>>? _globalSub;
  StreamSubscription<DesktopGlobalKeysStatus>? _globalStatusSub;

  void _listen() {
    if (_listening) return;
    _listening = true;
    HardwareKeyboard.instance.addHandler(_onKey);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    _lifecycle = AppLifecycleListener(onStateChange: (state) {
      if (state != AppLifecycleState.resumed) _releaseAll();
    });
    watchWindowFocusLoss(_releaseAll);
    _globalSub = desktopShell?.globalKeys.listen((keys) {
      _global = keys;
      _recompute();
    });
    _globalStatusSub = desktopShell?.globalKeysStatus.listen(_onGlobalStatus);
  }

  bool _onKey(KeyEvent event) {
    final consume = _recording != null;
    final code = codeOfKey(event.physicalKey);
    if (code == null) return consume;
    if (event is KeyDownEvent) {
      _keys.add(code);
      _recordAdd(code);
    } else if (event is KeyUpEvent) {
      _keys.remove(code);
    }
    _afterChange();
    return consume;
  }

  void _onPointer(PointerEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;
    if (event is! PointerDownEvent && event is! PointerUpEvent && event is! PointerMoveEvent && event is! PointerCancelEvent) {
      return;
    }
    final now = <String>{
      if (event is! PointerCancelEvent) ...[
        if (event.buttons & kMiddleMouseButton != 0) 'Mouse3',
        if (event.buttons & kBackMouseButton != 0) 'Mouse4',
        if (event.buttons & kForwardMouseButton != 0) 'Mouse5',
      ],
    };
    if (setEquals(now, _mouse)) return;
    for (final added in now.difference(_mouse)) {
      _recordAdd(added);
    }
    _mouse
      ..clear()
      ..addAll(now);
    _afterChange();
  }

  void _releaseAll() {
    _keys.clear();
    _mouse.clear();
    _finishRecording(null);
    _recompute();
  }

  void _afterChange() {
    if (_recording != null) {
      if (_keys.isEmpty && _mouse.isEmpty && _recordSeen.isNotEmpty) _finishRecording(KeyCombo(_recordSeen));
      return;
    }
    _recompute();
  }

  void _recompute() {
    final local = {..._keys, ..._mouse};
    final everywhere = {...local, ..._global};
    final recording = _recording != null;
    final held = recording
        ? const <Keybind>[]
        : [
            for (final b in _own)
              if (b.combo.heldIn(_armed.contains(b.action) ? everywhere : local)) b,
          ];
    final active = {
      for (final b in held)
        if (!held.any((other) => other.action != b.action && b.combo.isStrictSubsetOf(other.combo))) b.action,
    };
    final pressed = active.difference(_heldNow);
    _heldNow
      ..clear()
      ..addAll(active);
    for (final entry in _held.entries) {
      final on = active.contains(entry.key);
      if (entry.value.value != on) entry.value.value = on;
    }
    for (final action in pressed) {
      if (action.kind == KeybindKind.press) _presses[action]?.add(null);
    }
  }


  final Set<KeybindAction> _armed = {};

  Set<String> _global = const {};

  String _watching = '';

  void setArmed(KeybindAction action, bool on) {
    final changed = on ? _armed.add(action) : _armed.remove(action);
    if (!changed) return;
    _syncGlobal();
    _recompute();
  }

  void _syncGlobal() {
    final shell = desktopShell;
    if (shell == null) return;
    final keys = {
      for (final b in _own)
        if (_armed.contains(b.action)) ...b.combo.keys,
    }.toList()
      ..sort();
    final text = keys.join(' ');
    if (text == _watching) return;
    _watching = text;
    if (!shell.hasGlobalKeys) {
      if (keys.isNotEmpty) _reportGlobal('program is too old to hear keys over other windows');
      return;
    }
    shell.watchGlobalKeys(keys);
    _globalAnswer?.cancel();
    _globalAnswer = null;
    if (keys.isNotEmpty && shell.reportsGlobalKeysStatus) {
      _globalAnswer = Timer(_globalAnswerTimeout, () {
        _globalAnswer = null;
        _reportGlobal('no answer to watch request in ${_globalAnswerTimeout.inSeconds} s');
      });
    }
  }


  static const _globalAnswerTimeout = Duration(seconds: 5);

  static const _globalSilenceTimeout = Duration(minutes: 2);

  Timer? _globalAnswer;
  Timer? _globalSilence;


  void _onGlobalStatus(DesktopGlobalKeysStatus status) {
    switch (status.state) {
      case 'running':
        _globalAnswer?.cancel();
        _globalAnswer = null;
        _globalSilence?.cancel();
        _globalSilence = Timer(_globalSilenceTimeout, () {
          _globalSilence = null;
          _reportGlobal('hook is running but heard nothing in ${_globalSilenceTimeout.inMinutes} min');
        });
      case 'heard':
        _globalSilence?.cancel();
        _globalSilence = null;
      case 'stopped':
        _globalAnswer?.cancel();
        _globalAnswer = null;
        _globalSilence?.cancel();
        _globalSilence = null;
      case 'failed':
        _globalAnswer?.cancel();
        _globalAnswer = null;
        _reportGlobal('hook failed to start: ${status.detail}');
      case 'rejected':
        _reportGlobal('keys unknown to the hook: ${status.detail}');
    }
  }

  void _reportGlobal(String what) {
    final version = desktopShell?.appVersion ?? '?';
    errorReporter.report(
      StateError('desktop $version, global keys: $what (watching: $_watching)'),
      screen: 'keybinds:global',
    );
  }


  Completer<KeyCombo?>? _recording;
  final Set<String> _recordSeen = {};

  final ValueNotifier<KeyCombo?> recording = ValueNotifier(null);

  /// Записать сочетание: нажали клавиши, отпустили — оно и есть. null —
  /// запись отменили ([cancelRecording], уход из окна, новая запись).
  Future<KeyCombo?> record() async {
    await load();
    _finishRecording(null);
    final completer = _recording = Completer<KeyCombo?>();
    _recordSeen.clear();
    recording.value = KeyCombo(const []);
    desktopShell?.pauseProgramHotkeys(true);
    _recompute();
    return completer.future;
  }

  void cancelRecording() => _finishRecording(null);

  void _recordAdd(String code) {
    if (_recording == null || _recordSeen.length >= kMaxComboKeys) return;
    _recordSeen.add(code);
    recording.value = KeyCombo(_recordSeen);
  }

  void _finishRecording(KeyCombo? combo) {
    final completer = _recording;
    if (completer == null) return;
    _recording = null;
    _recordSeen.clear();
    recording.value = null;
    desktopShell?.pauseProgramHotkeys(false);
    completer.complete(combo);
    _recompute();
  }

  /// Боковая кнопка мыши назначена — в браузере её «назад/вперёд» гасится,
  /// иначе нажатие рации уводило бы страницу на прошлое место.
  void _applyMouseBlock() {
    setMouseNavigationBlocked(
      _own.any((b) => b.combo.keys.contains('Mouse4') || b.combo.keys.contains('Mouse5')),
    );
  }

  @override
  void dispose() {
    if (_listening) {
      HardwareKeyboard.instance.removeHandler(_onKey);
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
      _lifecycle?.dispose();
      _globalSub?.cancel();
      _globalStatusSub?.cancel();
      _globalAnswer?.cancel();
      _globalSilence?.cancel();
    }
    for (final c in _presses.values) {
      unawaited(c.close());
    }
    super.dispose();
  }
}

final keybinds = Keybinds();


String? codeOfKey(PhysicalKeyboardKey key) => _codeOf[key];

const _mouseCodes = {'Mouse3', 'Mouse4', 'Mouse5'};

const List<(PhysicalKeyboardKey, String)> _table = [
  (PhysicalKeyboardKey.controlLeft, 'Control'),
  (PhysicalKeyboardKey.controlRight, 'Control'),
  (PhysicalKeyboardKey.shiftLeft, 'Shift'),
  (PhysicalKeyboardKey.shiftRight, 'Shift'),
  (PhysicalKeyboardKey.altLeft, 'Alt'),
  (PhysicalKeyboardKey.altRight, 'Alt'),
  (PhysicalKeyboardKey.metaLeft, 'Meta'),
  (PhysicalKeyboardKey.metaRight, 'Meta'),
  (PhysicalKeyboardKey.keyA, 'KeyA'),
  (PhysicalKeyboardKey.keyB, 'KeyB'),
  (PhysicalKeyboardKey.keyC, 'KeyC'),
  (PhysicalKeyboardKey.keyD, 'KeyD'),
  (PhysicalKeyboardKey.keyE, 'KeyE'),
  (PhysicalKeyboardKey.keyF, 'KeyF'),
  (PhysicalKeyboardKey.keyG, 'KeyG'),
  (PhysicalKeyboardKey.keyH, 'KeyH'),
  (PhysicalKeyboardKey.keyI, 'KeyI'),
  (PhysicalKeyboardKey.keyJ, 'KeyJ'),
  (PhysicalKeyboardKey.keyK, 'KeyK'),
  (PhysicalKeyboardKey.keyL, 'KeyL'),
  (PhysicalKeyboardKey.keyM, 'KeyM'),
  (PhysicalKeyboardKey.keyN, 'KeyN'),
  (PhysicalKeyboardKey.keyO, 'KeyO'),
  (PhysicalKeyboardKey.keyP, 'KeyP'),
  (PhysicalKeyboardKey.keyQ, 'KeyQ'),
  (PhysicalKeyboardKey.keyR, 'KeyR'),
  (PhysicalKeyboardKey.keyS, 'KeyS'),
  (PhysicalKeyboardKey.keyT, 'KeyT'),
  (PhysicalKeyboardKey.keyU, 'KeyU'),
  (PhysicalKeyboardKey.keyV, 'KeyV'),
  (PhysicalKeyboardKey.keyW, 'KeyW'),
  (PhysicalKeyboardKey.keyX, 'KeyX'),
  (PhysicalKeyboardKey.keyY, 'KeyY'),
  (PhysicalKeyboardKey.keyZ, 'KeyZ'),
  (PhysicalKeyboardKey.digit0, 'Digit0'),
  (PhysicalKeyboardKey.digit1, 'Digit1'),
  (PhysicalKeyboardKey.digit2, 'Digit2'),
  (PhysicalKeyboardKey.digit3, 'Digit3'),
  (PhysicalKeyboardKey.digit4, 'Digit4'),
  (PhysicalKeyboardKey.digit5, 'Digit5'),
  (PhysicalKeyboardKey.digit6, 'Digit6'),
  (PhysicalKeyboardKey.digit7, 'Digit7'),
  (PhysicalKeyboardKey.digit8, 'Digit8'),
  (PhysicalKeyboardKey.digit9, 'Digit9'),
  (PhysicalKeyboardKey.f1, 'F1'),
  (PhysicalKeyboardKey.f2, 'F2'),
  (PhysicalKeyboardKey.f3, 'F3'),
  (PhysicalKeyboardKey.f4, 'F4'),
  (PhysicalKeyboardKey.f5, 'F5'),
  (PhysicalKeyboardKey.f6, 'F6'),
  (PhysicalKeyboardKey.f7, 'F7'),
  (PhysicalKeyboardKey.f8, 'F8'),
  (PhysicalKeyboardKey.f9, 'F9'),
  (PhysicalKeyboardKey.f10, 'F10'),
  (PhysicalKeyboardKey.f11, 'F11'),
  (PhysicalKeyboardKey.f12, 'F12'),
  (PhysicalKeyboardKey.f13, 'F13'),
  (PhysicalKeyboardKey.f14, 'F14'),
  (PhysicalKeyboardKey.f15, 'F15'),
  (PhysicalKeyboardKey.f16, 'F16'),
  (PhysicalKeyboardKey.f17, 'F17'),
  (PhysicalKeyboardKey.f18, 'F18'),
  (PhysicalKeyboardKey.f19, 'F19'),
  (PhysicalKeyboardKey.f20, 'F20'),
  (PhysicalKeyboardKey.f21, 'F21'),
  (PhysicalKeyboardKey.f22, 'F22'),
  (PhysicalKeyboardKey.f23, 'F23'),
  (PhysicalKeyboardKey.f24, 'F24'),
  (PhysicalKeyboardKey.space, 'Space'),
  (PhysicalKeyboardKey.tab, 'Tab'),
  (PhysicalKeyboardKey.capsLock, 'CapsLock'),
  (PhysicalKeyboardKey.backquote, 'Backquote'),
  (PhysicalKeyboardKey.minus, 'Minus'),
  (PhysicalKeyboardKey.equal, 'Equal'),
  (PhysicalKeyboardKey.bracketLeft, 'BracketLeft'),
  (PhysicalKeyboardKey.bracketRight, 'BracketRight'),
  (PhysicalKeyboardKey.backslash, 'Backslash'),
  (PhysicalKeyboardKey.intlBackslash, 'IntlBackslash'),
  (PhysicalKeyboardKey.semicolon, 'Semicolon'),
  (PhysicalKeyboardKey.quote, 'Quote'),
  (PhysicalKeyboardKey.comma, 'Comma'),
  (PhysicalKeyboardKey.period, 'Period'),
  (PhysicalKeyboardKey.slash, 'Slash'),
  (PhysicalKeyboardKey.enter, 'Enter'),
  (PhysicalKeyboardKey.backspace, 'Backspace'),
  (PhysicalKeyboardKey.escape, 'Escape'),
  (PhysicalKeyboardKey.insert, 'Insert'),
  (PhysicalKeyboardKey.delete, 'Delete'),
  (PhysicalKeyboardKey.home, 'Home'),
  (PhysicalKeyboardKey.end, 'End'),
  (PhysicalKeyboardKey.pageUp, 'PageUp'),
  (PhysicalKeyboardKey.pageDown, 'PageDown'),
  (PhysicalKeyboardKey.arrowUp, 'ArrowUp'),
  (PhysicalKeyboardKey.arrowDown, 'ArrowDown'),
  (PhysicalKeyboardKey.arrowLeft, 'ArrowLeft'),
  (PhysicalKeyboardKey.arrowRight, 'ArrowRight'),
  (PhysicalKeyboardKey.printScreen, 'PrintScreen'),
  (PhysicalKeyboardKey.scrollLock, 'ScrollLock'),
  (PhysicalKeyboardKey.pause, 'Pause'),
  (PhysicalKeyboardKey.contextMenu, 'ContextMenu'),
  (PhysicalKeyboardKey.numLock, 'NumLock'),
  (PhysicalKeyboardKey.numpad0, 'Numpad0'),
  (PhysicalKeyboardKey.numpad1, 'Numpad1'),
  (PhysicalKeyboardKey.numpad2, 'Numpad2'),
  (PhysicalKeyboardKey.numpad3, 'Numpad3'),
  (PhysicalKeyboardKey.numpad4, 'Numpad4'),
  (PhysicalKeyboardKey.numpad5, 'Numpad5'),
  (PhysicalKeyboardKey.numpad6, 'Numpad6'),
  (PhysicalKeyboardKey.numpad7, 'Numpad7'),
  (PhysicalKeyboardKey.numpad8, 'Numpad8'),
  (PhysicalKeyboardKey.numpad9, 'Numpad9'),
  (PhysicalKeyboardKey.numpadAdd, 'NumpadAdd'),
  (PhysicalKeyboardKey.numpadSubtract, 'NumpadSubtract'),
  (PhysicalKeyboardKey.numpadMultiply, 'NumpadMultiply'),
  (PhysicalKeyboardKey.numpadDivide, 'NumpadDivide'),
  (PhysicalKeyboardKey.numpadDecimal, 'NumpadDecimal'),
  (PhysicalKeyboardKey.numpadEnter, 'NumpadEnter'),
];

final Map<PhysicalKeyboardKey, String> _codeOf = {for (final (key, code) in _table) key: code};

final Set<String> _codeKeys = {for (final (_, code) in _table) code};

String keyLabel(String code) {
  final named = _labels[code];
  if (named != null) return named;
  if (code.startsWith('Key') && code.length == 4) return code.substring(3);
  if (code.startsWith('Digit') && code.length == 6) return code.substring(5);
  if (code.startsWith('Numpad') && code.length == 7) return 'NUM ${code.substring(6)}';
  if (code.startsWith('Mouse')) return 'MOUSE ${code.substring(5)}';
  return code.toUpperCase();
}

const Map<String, String> _labels = {
  'Control': 'CTRL',
  'Shift': 'SHIFT',
  'Alt': 'ALT',
  'Meta': 'WIN',
  'Space': 'SPACE',
  'Tab': 'TAB',
  'CapsLock': 'CAPS LOCK',
  'Backquote': '`',
  'Minus': '-',
  'Equal': '=',
  'BracketLeft': '[',
  'BracketRight': ']',
  'Backslash': r'\',
  'IntlBackslash': r'\',
  'Semicolon': ';',
  'Quote': "'",
  'Comma': ',',
  'Period': '.',
  'Slash': '/',
  'Enter': 'ENTER',
  'Backspace': 'BACKSPACE',
  'Escape': 'ESC',
  'Insert': 'INSERT',
  'Delete': 'DELETE',
  'Home': 'HOME',
  'End': 'END',
  'PageUp': 'PAGE UP',
  'PageDown': 'PAGE DOWN',
  'ArrowUp': '↑',
  'ArrowDown': '↓',
  'ArrowLeft': '←',
  'ArrowRight': '→',
  'PrintScreen': 'PRINT SCREEN',
  'ScrollLock': 'SCROLL LOCK',
  'Pause': 'PAUSE',
  'ContextMenu': 'MENU',
  'NumLock': 'NUM LOCK',
  'NumpadAdd': 'NUM +',
  'NumpadSubtract': 'NUM -',
  'NumpadMultiply': 'NUM *',
  'NumpadDivide': 'NUM /',
  'NumpadDecimal': 'NUM .',
  'NumpadEnter': 'NUM ENTER',
};
