import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/avatar_color.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/voice_controls.dart';
import 'desktop_shell.dart';
import 'unread_summary.dart';

class DesktopWindow {
  bool _started = false;
  bool _inSession = false;
  (String, String, String)? _lastTheme;
  StreamSubscription<DesktopTrayCommand>? _traySub;

  void start() {
    final shell = desktopShell;
    if (shell == null || _started) return;
    _started = true;
    themeProvider.addListener(_syncTheme);
    localeProvider.addListener(_syncLocale);
    _syncTheme();
    _syncLocale();
  }

  void signalReadyAfterFirstFrame() {
    final shell = desktopShell;
    if (shell == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => shell.ready());
  }

  /// Человек вошёл в аккаунт. Повторный вызов ничего не делает.
  void startSession() {
    final shell = desktopShell;
    if (shell == null || _inSession) return;
    _inSession = true;
    unreadSummary.addListener(_syncUnread);
    _syncUnread();
    voiceControls.changes.addListener(_syncVoice);
    _syncVoice();
    _traySub = shell.trayCommands.listen(_onTrayCommand);
  }

  void endSession() {
    final shell = desktopShell;
    if (shell == null || !_inSession) return;
    _inSession = false;
    unreadSummary.removeListener(_syncUnread);
    voiceControls.changes.removeListener(_syncVoice);
    unawaited(_traySub?.cancel());
    _traySub = null;
    shell.setUnread(0);
    shell.setVoiceState(null);
  }

  void _syncUnread() => desktopShell?.setUnread(unreadSummary.count);

  void _syncVoice() => desktopShell?.setVoiceState(
        DesktopVoiceState(micOff: voiceControls.micOff, deafOff: voiceControls.deafOff),
      );

  void _onTrayCommand(DesktopTrayCommand command) {
    switch (command) {
      case DesktopTrayCommand.toggleMic:
        voiceControls.toggleMic();
      case DesktopTrayCommand.toggleDeafen:
        voiceControls.toggleDeafen();
    }
  }

  void _syncTheme() {
    final background = avatarColorToJson(desktopTitleBarColor(saved: true));
    final foreground = avatarColorToJson(themeProvider.savedPalette.textPrimary);
    final visibleForeground = avatarColorToJson(themeProvider.palette.textPrimary);
    if (background == null || foreground == null || visibleForeground == null) return;
    final colors = (background, foreground, visibleForeground);
    if (_lastTheme == colors) return;
    _lastTheme = colors;
    desktopShell?.setTheme(background, foreground, visibleForeground: visibleForeground);
  }

  void _syncLocale() => desktopShell?.setLocale(localeProvider.locale.languageCode);
}

Color desktopTitleBarColor({bool saved = false}) => (saved ? themeProvider.savedPalette : themeProvider.palette).bgCard;

final desktopWindow = DesktopWindow();
