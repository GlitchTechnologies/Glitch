import 'package:flutter/services.dart';


Future<void> enterSystemFullscreen() => SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

Future<void> exitSystemFullscreen() => SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

void bindSystemFullscreenExit(void Function() onExit) {}
