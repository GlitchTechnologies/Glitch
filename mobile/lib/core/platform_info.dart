import 'package:flutter/foundation.dart';

import '../services/desktop_shell.dart';
import 'windows_version_web.dart' if (dart.library.io) 'windows_version_native.dart' as windows_version;

// Эти значения отправляются при входе и должны совпадать с допустимыми значениями на сервере.
const String platformAndroid = 'android';
const String platformWeb = 'web';
const String platformDesktop = 'desktop';

String get currentPlatform {
  if (kIsWeb) return isDesktopApp ? platformDesktop : platformWeb;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return platformAndroid;
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
      return platformDesktop;
    default:
      return platformAndroid;
  }
}


bool get isWebPlatform => kIsWeb;

bool get isDesktopApp => desktopShell != null;

bool get isAndroidPlatform => currentPlatform == platformAndroid;

bool get isDesktopPlatform => currentPlatform == platformDesktop;


bool get hasSystemBack => isAndroidPlatform;

bool get hasPointerInput => !isAndroidPlatform;

bool get hasFileSystem => !isWebPlatform;

bool get hasBrowserTabs => isWebPlatform && !isDesktopApp;

Future<bool> get isWindowsBefore11 => _windowsBefore11 ??= windows_version.windowsBefore11();
Future<bool>? _windowsBefore11;
