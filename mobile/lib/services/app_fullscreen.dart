import 'package:flutter/foundation.dart';

import 'app_fullscreen_web.dart' if (dart.library.io) 'app_fullscreen_native.dart';

class AppFullscreen extends ValueNotifier<bool> {
  AppFullscreen() : super(false) {
    bindSystemFullscreenExit(() => value = false);
  }

  Future<void> enter() async {
    value = true;
    await enterSystemFullscreen();
  }

  Future<void> exit() async {
    value = false;
    await exitSystemFullscreen();
  }
}

final appFullscreen = AppFullscreen();
