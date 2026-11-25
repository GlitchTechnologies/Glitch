import 'dart:async';

import '../widgets/voice_controls.dart';
import 'keybinds.dart';

class KeybindCommands {
  KeybindCommands._();

  final List<StreamSubscription<void>> _subs = [];

  static const _actions = [KeybindAction.toggleMute, KeybindAction.toggleDeafen];

  /// Человек вошёл в аккаунт. Повторный вызов ничего не делает.
  void startSession() {
    if (_subs.isNotEmpty) return;
    for (final action in _actions) {
      keybinds.setArmed(action, true);
      _subs.add(keybinds.pressesOf(action).listen((_) => _run(action)));
    }
  }

  void endSession() {
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
    for (final action in _actions) {
      keybinds.setArmed(action, false);
    }
  }

  void _run(KeybindAction action) {
    switch (action) {
      case KeybindAction.toggleMute:
        voiceControls.toggleMic();
      case KeybindAction.toggleDeafen:
        voiceControls.toggleDeafen();
      default:
        break;
    }
  }
}

final keybindCommands = KeybindCommands._();
