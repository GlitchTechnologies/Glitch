import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStream;

import 'desktop_shell_web.dart' if (dart.library.io) 'desktop_shell_native.dart';

/// Программа для Windows запускает веб-версию Glitch в Electron. Это та же
/// браузерная сборка, что на сайте; всё, чего браузер не умеет, он просит у
/// программы через объект `window.glitchDesktop`, который ставит её
/// предзагрузка (`desktop/src/preload/app-preload.ts`).
final DesktopShell? desktopShell = findDesktopShell();

abstract class DesktopShell {
  String get appVersion;

  String get chromeVersion;

  double get titleBarHeight;

  void ready();

  void setTheme(String background, String foreground, {required String visibleForeground});

  void setLocale(String code);

  Future<List<ScreenSource>> listScreenSources();

  Future<bool> chooseScreenSource(String id, {required bool withAudio});

  /// Захват выбранного монитора. При отказе WASAPI возвращает
  /// картинку с признаком снятого звука. null — применить обычный захват.
  Future<DesktopScreenCapture?> captureDxgiScreen({required int fps, required int? width, required int? height});

  Future<DesktopCaptureTimings?> screenCaptureTimings(String publicationId, {String? trackId});

  Future<DesktopDownloadResult> download(String url, String fileName);


  void showNotification({
    required String tag,
    required String title,
    required String body,
    int? chatId,
    Uint8List? icon,
  });

  bool get hasTaggedNotifications;

  void closeNotification(String tag);

  void clearNotifications();

  void requestAttention();

  void setUnread(int count);

  void setVoiceState(DesktopVoiceState? state);

  Stream<DesktopNotificationClick> get notificationClicks;

  Stream<DesktopTrayCommand> get trayCommands;


  Stream<Uri> get openLinks;


  bool get hasSystemSettings;

  Future<DesktopSystemSettings> getSystemSettings();

  Future<DesktopSystemSettings> setOpenAtLogin(bool on);

  Future<DesktopSystemSettings> setCloseToTray(bool on);


  DesktopPopout? get popout;

  bool get hasPopouts;

  void openPopout(DesktopPopout kind);

  void closePopout(DesktopPopout kind);

  void postToPopout(DesktopPopout kind, String data);

  Stream<DesktopPopout> get popoutReadies;

  Stream<DesktopPopout> get popoutClosings;

  void popoutReady();

  Stream<String> get popoutData;

  bool get hasThemeEditor;
  void sendThemeEditorAction(String data);
  Stream<String> get themeEditorActions;


  List<List<String>> get reservedHotkeys;


  bool get hasGlobalKeys;

  void watchGlobalKeys(List<String> keys);

  Stream<Set<String>> get globalKeys;

  /// Сообщает ли программа, что с перехватом (версия 9 и новее): у старой
  /// ответа ждать нечего.
  bool get reportsGlobalKeysStatus;

  Stream<DesktopGlobalKeysStatus> get globalKeysStatus;

  // ── Горячие клавиши программы (программа версии 10 и новее) ──────────────
  // Перезагрузка и масштаб — клавиши самой программы (desktop/src/main/
  // hotkeys.ts): работают и при сломанной странице, поэтому хранит и
  // исполняет их программа. Glitch их показывает и меняет одним списком со
  // своими (services/keybinds.dart). У программы старше — не поменять.

  bool get hasProgramHotkeys;

  Future<List<DesktopProgramHotkey>> getProgramHotkeys();

  Future<List<DesktopProgramHotkey>> setProgramHotkeys(List<DesktopProgramHotkey> hotkeys);

  void pauseProgramHotkeys(bool paused);


  bool get hasRunningGames;

  void watchGames(List<DesktopWatchedGame> games);

  Stream<List<DesktopRunningGame>> get runningGames;
}

typedef DesktopScreenCapture = ({MediaStream stream, bool soundDropped});

typedef DesktopCaptureTimings = ({
  int? attemptsPerSecond,
  int? acquireMs,
  int? prepareMs,
  int? intervalMs,
  int? configuredFps,
  DesktopCaptureSource? source,
});

class DesktopCaptureSource {
  final String backend;
  final String? mode;
  final String? audio;
  final int? inputFps;
  final int? preparedFps;
  final int? sentFps;
  final int? noSlot;
  final int? replaced;
  final int? pacedOut;
  final int? sendDropped;
  final int? avgPrepareMs;
  final int? maxFrameGapMs;

  const DesktopCaptureSource({
    required this.backend,
    this.mode,
    this.audio,
    this.inputFps,
    this.preparedFps,
    this.sentFps,
    this.noSlot,
    this.replaced,
    this.pacedOut,
    this.sendDropped,
    this.avgPrepareMs,
    this.maxFrameGapMs,
  });

  static DesktopCaptureSource? fromJson(Object? raw, [String prefix = '']) {
    if (raw is! Map) return null;
    String? t(String key) => raw['$prefix$key'] is String ? raw['$prefix$key'] as String : null;
    int? n(String key) {
      final value = raw['$prefix$key'];
      return value is num && value.isFinite && value >= 0 ? value.round() : null;
    }
    final backend = t('backend');
    if (backend != 'chromium' && backend != 'dxgi') return null;
    return DesktopCaptureSource(
      backend: backend!,
      mode: t('mode'),
      audio: t('audio'),
      inputFps: n('inputFps'),
      preparedFps: n('preparedFps'),
      sentFps: n('sentFps'),
      noSlot: n('noSlot'),
      replaced: n('replaced'),
      pacedOut: n('pacedOut'),
      sendDropped: n('sendDropped'),
      avgPrepareMs: n('avgPrepareMs'),
      maxFrameGapMs: n('maxFrameGapMs'),
    );
  }

  Map<String, Object> toJson(String prefix) {
    final fields = {
      'backend': backend,
      'mode': mode,
      'audio': audio,
      'inputFps': inputFps,
      'preparedFps': preparedFps,
      'sentFps': sentFps,
      'noSlot': noSlot,
      'replaced': replaced,
      'pacedOut': pacedOut,
      'sendDropped': sendDropped,
      'avgPrepareMs': avgPrepareMs,
      'maxFrameGapMs': maxFrameGapMs,
    };
    return {
      for (final entry in fields.entries)
        if (entry.value case final Object value) '$prefix${entry.key}': value,
    };
  }
}

typedef DesktopWatchedGame = ({int id, List<String> executables});

typedef DesktopRunningGame = ({int id, DateTime startedAt});

typedef DesktopProgramHotkey = ({String action, List<String> keys});

typedef DesktopGlobalKeysStatus = ({String state, String? detail});

enum DesktopPopout {
  voiceDebug('voice-debug'),
  themeEditor('theme-editor');

  final String wire;

  const DesktopPopout(this.wire);

  static DesktopPopout? fromWire(String? wire) {
    for (final kind in values) {
      if (kind.wire == wire) return kind;
    }
    return null;
  }
}

class DesktopSystemSettings {
  final bool openAtLogin;

  final bool closeToTray;

  const DesktopSystemSettings({required this.openAtLogin, required this.closeToTray});
}

class DesktopVoiceState {
  final bool micOff;
  final bool deafOff;

  const DesktopVoiceState({required this.micOff, required this.deafOff});
}

enum DesktopTrayCommand { toggleMic, toggleDeafen }

class ScreenSource {
  final String id;
  final String name;

  final bool isScreen;

  final String? thumbnail;

  final String? icon;

  const ScreenSource({
    required this.id,
    required this.name,
    required this.isScreen,
    required this.thumbnail,
    required this.icon,
  });
}

enum DesktopDownloadResult { saved, cancelled, failed }

typedef DesktopNotificationClick = ({String? tag, int? chatId});
