import 'dart:js_interop';

import 'package:web/web.dart' as web;

DateTime? _hiddenAt;
bool _bound = false;

void bindWsWakeup(void Function(Duration hidden) onWake) {
  if (_bound) return;
  _bound = true;

  web.document.addEventListener(
    'visibilitychange',
    ((web.Event _) {
      if (web.document.hidden) {
        _hiddenAt = DateTime.now();
        return;
      }
      final hiddenFor =
          _hiddenAt == null ? Duration.zero : DateTime.now().difference(_hiddenAt!);
      _hiddenAt = null;
      onWake(hiddenFor);
    }).toJS,
  );

  web.window.addEventListener(
    'online',
    ((web.Event _) => onWake(Duration.zero)).toJS,
  );
}
