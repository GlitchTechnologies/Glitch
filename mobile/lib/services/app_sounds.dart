import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'voice_cue.dart';

class AppSounds extends ChangeNotifier {
  static const _storageKey = 'sounds_off_v1';

  Set<VoiceCue> _off = const {};

  Future<void>? _loading;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    _off = _read(await SharedPreferences.getInstance());
    notifyListeners();
  }

  static Set<VoiceCue> _read(SharedPreferences prefs) {
    final byName = VoiceCue.values.asNameMap();
    return {
      for (final name in prefs.getStringList(_storageKey) ?? const <String>[])
        if (byName[name] case final cue?) cue,
    };
  }

  bool isOn(VoiceCue cue) => !_off.contains(cue);

  Future<void> setOn(VoiceCue cue, bool on) async {
    await load();
    if (isOn(cue) == on) return;
    _off = on ? ({..._off}..remove(cue)) : {..._off, cue};
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_storageKey, [for (final c in _off) c.name]);
  }

  static Future<bool> isOnStored(VoiceCue cue) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return !_read(prefs).contains(cue);
    } catch (_) {
      return true;
    }
  }
}

final appSounds = AppSounds();
