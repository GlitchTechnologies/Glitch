import 'dart:js_interop';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:web/web.dart' as web;


Future<void> enterSystemFullscreen() async {
  if (web.document.fullscreenElement != null) return;
  try {
    await web.document.documentElement?.requestFullscreen().toDart;
  } catch (e) {
    debugPrint('enterSystemFullscreen: $e');
  }
}

Future<void> exitSystemFullscreen() async {
  if (web.document.fullscreenElement == null) return;
  try {
    await web.document.exitFullscreen().toDart;
  } catch (e) {
    debugPrint('exitSystemFullscreen: $e');
  }
}

void bindSystemFullscreenExit(void Function() onExit) {
  web.document.addEventListener(
    'fullscreenchange',
    ((web.Event _) {
      if (web.document.fullscreenElement == null) onExit();
    }).toJS,
  );
}
