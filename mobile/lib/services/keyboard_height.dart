import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

class KeyboardHeight {
  static const _prefsKey = 'keyboard_height_v1';

  static const double _minReal = 120;
  static const Duration _settle = Duration(milliseconds: 250);

  double? _value;
  bool _loaded = false;
  Timer? _pending;

  double? get value => _value;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _value ??= prefs.getDouble(_prefsKey);
    } catch (_) {
    }
  }

  void note(double height) {
    _pending?.cancel();
    if (height < _minReal) return;
    _pending = Timer(_settle, () {
      if ((_value ?? 0) == height) return;
      _value = height;
      SharedPreferences.getInstance()
          .then((prefs) => prefs.setDouble(_prefsKey, height))
          .catchError((_) => false);
    });
  }
}

final keyboardHeight = KeyboardHeight();
