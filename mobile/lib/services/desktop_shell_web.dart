import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:dart_webrtc/dart_webrtc.dart' show MediaStreamWeb;
import 'package:web/web.dart' as web;

import 'desktop_shell.dart';

DesktopShell? findDesktopShell() {
  final js = globalContext.getProperty<JSObject?>('glitchDesktop'.toJS);
  if (js == null) return null;
  final apiVersion = js.getProperty<JSNumber?>('apiVersion'.toJS)?.toDartInt ?? 0;
  if (apiVersion < 1) return null;
  final popout = DesktopPopout.fromWire(js.getProperty<JSString?>('popout'.toJS)?.toDart);
  return _WebDesktopShell(js, apiVersion, popout);
}

class _WebDesktopShell implements DesktopShell {
  final JSObject _js;

  final int _apiVersion;

  @override
  final DesktopPopout? popout;

  _WebDesktopShell(this._js, this._apiVersion, this.popout) {
    if (popout != null) {
      _js.callMethod<JSAny?>(
        'onPopoutData'.toJS,
        ((JSString data) => _popoutData.add(data.toDart)).toJS,
      );
      return;
    }
    if (_v6) {
      _js.callMethod<JSAny?>(
        'onPopoutReady'.toJS,
        ((JSString kind) {
          final parsed = DesktopPopout.fromWire(kind.toDart);
          if (parsed != null) _popoutReadies.add(parsed);
        }).toJS,
      );
      _js.callMethod<JSAny?>(
        'onPopoutClosed'.toJS,
        ((JSString kind) {
          final parsed = DesktopPopout.fromWire(kind.toDart);
          if (parsed != null) _popoutClosings.add(parsed);
        }).toJS,
      );
    }
    if (hasThemeEditor) {
      _js.callMethod<JSAny?>('onThemeEditorAction'.toJS, ((JSString data) {
        _themeEditorActions.add(data.toDart);
      }).toJS);
    }
    if (_v8) {
      _js.callMethod<JSAny?>(
        'onGlobalKeys'.toJS,
        ((JSArray<JSString> keys) => _globalKeys.add({for (final k in keys.toDart) k.toDart})).toJS,
      );
    }
    if (_v9) {
      _js.callMethod<JSAny?>(
        'onGlobalKeysStatus'.toJS,
        ((JSObject status) => _globalKeysStatus.add((
              state: status.getProperty<JSString?>('state'.toJS)?.toDart ?? '',
              detail: status.getProperty<JSString?>('detail'.toJS)?.toDart,
            ))).toJS,
      );
    }
    if (_v11) {
      _js.callMethod<JSAny?>(
        'onRunningGames'.toJS,
        ((JSArray<JSObject> games) => _runningGames.add([
              for (final g in games.toDart)
                if (g.getProperty<JSNumber?>('id'.toJS) case final id?)
                  if (g.getProperty<JSNumber?>('startedAt'.toJS) case final at?)
                    (
                      id: id.toDartInt,
                      startedAt: DateTime.fromMillisecondsSinceEpoch(at.toDartDouble.round(), isUtc: true),
                    ),
            ])).toJS,
      );
    }
    if (!_v2) return;
    _js.callMethod<JSAny?>(
      'onNotificationClick'.toJS,
      ((JSNumber? chatId, JSString? tag) =>
          _clicks.add((tag: tag?.toDart, chatId: chatId?.toDartInt))).toJS,
    );
    _js.callMethod<JSAny?>(
      'onTrayCommand'.toJS,
      ((JSString command) {
        final parsed = switch (command.toDart) {
          'toggle-mic' => DesktopTrayCommand.toggleMic,
          'toggle-deafen' => DesktopTrayCommand.toggleDeafen,
          _ => null,
        };
        if (parsed != null) _tray.add(parsed);
      }).toJS,
    );
    if (!_v3) return;
    _js.callMethod<JSAny?>(
      'onOpenLink'.toJS,
      ((JSString url) {
        final uri = Uri.tryParse(url.toDart);
        if (uri != null) _links.add(uri);
      }).toJS,
    );
  }

  bool get _v1 => popout == null;
  bool get _v2 => _v1 && _apiVersion >= 2;
  bool get _v3 => _v1 && _apiVersion >= 3;
  bool get _v4 => _v1 && _apiVersion >= 4;
  bool get _v5 => _v1 && _apiVersion >= 5;
  bool get _v6 => _v1 && _apiVersion >= 6;
  bool get _v7 => _v1 && _apiVersion >= 7;
  bool get _v8 => _v1 && _apiVersion >= 8;
  bool get _v9 => _v1 && _apiVersion >= 9;
  bool get _v10 => _v1 && _apiVersion >= 10;
  bool get _v11 => _v1 && _apiVersion >= 11;

  final _clicks = StreamController<DesktopNotificationClick>.broadcast();
  final _tray = StreamController<DesktopTrayCommand>.broadcast();
  final _links = StreamController<Uri>.broadcast();
  final _popoutReadies = StreamController<DesktopPopout>.broadcast();
  final _popoutClosings = StreamController<DesktopPopout>.broadcast();
  final _popoutData = StreamController<String>.broadcast();
  final _themeEditorActions = StreamController<String>.broadcast();
  final _globalKeys = StreamController<Set<String>>.broadcast();
  final _globalKeysStatus = StreamController<DesktopGlobalKeysStatus>.broadcast();
  final _runningGames = StreamController<List<DesktopRunningGame>>.broadcast();

  String _string(String name) => _js.getProperty<JSString?>(name.toJS)?.toDart ?? '';

  @override
  String get appVersion => _string('appVersion');

  @override
  String get chromeVersion => _string('chromeVersion');

  @override
  double get titleBarHeight => _js.getProperty<JSNumber?>('titleBarHeight'.toJS)?.toDartDouble ?? 0;

  @override
  void ready() {
    if (_v1) _js.callMethod<JSAny?>('ready'.toJS);
  }

  @override
  void setTheme(String background, String foreground, {required String visibleForeground}) {
    if (!_v1) return;
    if (_apiVersion >= 13) {
      _js.callMethod<JSAny?>('setTheme'.toJS, background.toJS, foreground.toJS, visibleForeground.toJS);
    } else {
      _js.callMethod<JSAny?>('setTheme'.toJS, background.toJS, foreground.toJS);
    }
  }

  @override
  void setLocale(String code) {
    if (_v1) _js.callMethod<JSAny?>('setLocale'.toJS, code.toJS);
  }

  @override
  Future<List<ScreenSource>> listScreenSources() async {
    if (!_v1) return const [];
    final list = await _js.callMethod<JSPromise<JSArray<JSObject>>>('listScreenSources'.toJS).toDart;
    return [
      for (final source in list.toDart)
        ScreenSource(
          id: source.getProperty<JSString>('id'.toJS).toDart,
          name: source.getProperty<JSString?>('name'.toJS)?.toDart ?? '',
          isScreen: source.getProperty<JSString?>('kind'.toJS)?.toDart == 'screen',
          thumbnail: source.getProperty<JSString?>('thumbnail'.toJS)?.toDart,
          icon: source.getProperty<JSString?>('icon'.toJS)?.toDart,
        ),
    ];
  }

  @override
  Future<bool> chooseScreenSource(String id, {required bool withAudio}) async {
    if (!_v1) return false;
    final ok = await _js
        .callMethod<JSPromise<JSBoolean>>('chooseScreenSource'.toJS, id.toJS, withAudio.toJS)
        .toDart;
    return ok.toDart;
  }

  @override
  Future<DesktopScreenCapture?> captureDxgiScreen({required int fps, required int? width, required int? height}) async {
    if (!_v1 || _apiVersion < 15 || !_js.has('captureDxgiVideo')) return null;
    final body = web.document.body;
    if (body == null) return null;
    final element = web.HTMLVideoElement()
      ..id = 'glitch-dxgi-${++_dxgiElement}'
      ..setAttribute('hidden', '');
    body.appendChild(element);
    try {
      final settings = {'fps': fps, 'maxWidth': width, 'maxHeight': height}.jsify();
      final String? outcome;
      if (_apiVersion >= 16) {
        final result = await _js.callMethod<JSPromise<JSString?>>(
          'captureDxgiStream'.toJS, element.id.toJS, settings,
        ).toDart;
        outcome = result?.toDart;
      } else {
        final ready = await _js.callMethod<JSPromise<JSBoolean>>(
          'captureDxgiVideo'.toJS, element.id.toJS, settings,
        ).toDart;
        outcome = ready.toDart ? 'video' : null;
      }
      final stream = element.srcObject;
      if (outcome == null || stream == null) return null;
      return (stream: MediaStreamWeb(stream as web.MediaStream, 'local'), soundDropped: outcome == 'sound-dropped');
    } catch (_) {
      return null;
    } finally {
      element.srcObject = null;
      element.remove();
    }
  }

  int _dxgiElement = 0;

  @override
  Future<DesktopCaptureTimings?> screenCaptureTimings(String publicationId, {String? trackId}) async {
    if (!_v1) return null;
    // В обычной оболочке (в том числе прежних версий) мост DXGI недоступен,
    // поэтому её дорожка создаётся штатным Chromium.
    final fallback = _js.has('captureDxgiVideo') ? null : const DesktopCaptureSource(backend: 'chromium');
    JSObject? data;
    try {
      if (_apiVersion >= 14) {
        data = await _js.callMethod<JSPromise<JSObject?>>(
          'screenCaptureTimings'.toJS,
          publicationId.toJS,
          trackId?.toJS,
        ).toDart;
      }
    } catch (_) {} // Ошибка замера не прерывает показ.
    final result = data;
    if (result == null && fallback == null) return null;
    int? n(String key) => result?.getProperty<JSNumber?>(key.toJS)?.toDartInt;
    return (
      attemptsPerSecond: n('attemptsPerSecond'),
      acquireMs: n('acquireMs'),
      prepareMs: n('prepareMs'),
      intervalMs: n('intervalMs'),
      configuredFps: n('configuredFps'),
      source: DesktopCaptureSource.fromJson(result?.getProperty<JSObject?>('details'.toJS)?.dartify()) ?? fallback,
    );
  }

  @override
  Future<DesktopDownloadResult> download(String url, String fileName) async {
    if (!_v1) return DesktopDownloadResult.failed;
    final result = await _js
        .callMethod<JSPromise<JSString>>('download'.toJS, url.toJS, fileName.toJS)
        .toDart;
    switch (result.toDart) {
      case 'saved':
        return DesktopDownloadResult.saved;
      case 'cancelled':
        return DesktopDownloadResult.cancelled;
      default:
        return DesktopDownloadResult.failed;
    }
  }


  @override
  void showNotification({
    required String tag,
    required String title,
    required String body,
    int? chatId,
    Uint8List? icon,
  }) {
    if (!_v2) return;
    final n = JSObject()
      ..setProperty('tag'.toJS, tag.toJS)
      ..setProperty('title'.toJS, title.toJS)
      ..setProperty('body'.toJS, body.toJS);
    if (chatId != null) n.setProperty('chatId'.toJS, chatId.toJS);
    if (icon != null) n.setProperty('icon'.toJS, icon.toJS);
    _js.callMethod<JSAny?>('notify'.toJS, n);
  }

  @override
  void closeNotification(String tag) {
    if (_v2) _js.callMethod<JSAny?>('closeNotification'.toJS, tag.toJS);
  }

  @override
  void clearNotifications() {
    if (_v2) _js.callMethod<JSAny?>('clearNotifications'.toJS);
  }

  @override
  void requestAttention() {
    if (_v2) _js.callMethod<JSAny?>('requestAttention'.toJS);
  }

  @override
  void setUnread(int count) {
    if (_v2) _js.callMethod<JSAny?>('setUnread'.toJS, count.toJS);
  }

  @override
  void setVoiceState(DesktopVoiceState? state) {
    if (!_v2) return;
    if (state == null) {
      _js.callMethod<JSAny?>('setVoice'.toJS, null);
      return;
    }
    final js = JSObject()
      ..setProperty('micOff'.toJS, state.micOff.toJS)
      ..setProperty('deafOff'.toJS, state.deafOff.toJS);
    _js.callMethod<JSAny?>('setVoice'.toJS, js);
  }

  @override
  bool get hasTaggedNotifications => _v5;

  @override
  Stream<DesktopNotificationClick> get notificationClicks => _clicks.stream;

  @override
  Stream<DesktopTrayCommand> get trayCommands => _tray.stream;

  @override
  Stream<Uri> get openLinks => _links.stream;


  @override
  bool get hasSystemSettings => _v4;

  @override
  Future<DesktopSystemSettings> getSystemSettings() => _system('getSystemSettings');

  @override
  Future<DesktopSystemSettings> setOpenAtLogin(bool on) => _system('setOpenAtLogin', on);

  @override
  Future<DesktopSystemSettings> setCloseToTray(bool on) => _system('setCloseToTray', on);

  Future<DesktopSystemSettings> _system(String method, [bool? on]) async {
    if (!_v4) throw StateError('desktop: нет раздела «Система» (версия $_apiVersion)');
    final call = on == null
        ? _js.callMethod<JSPromise<JSObject>>(method.toJS)
        : _js.callMethod<JSPromise<JSObject>>(method.toJS, on.toJS);
    final js = await call.toDart;
    return DesktopSystemSettings(
      openAtLogin: js.getProperty<JSBoolean?>('openAtLogin'.toJS)?.toDart ?? false,
      closeToTray: js.getProperty<JSBoolean?>('closeToTray'.toJS)?.toDart ?? true,
    );
  }


  @override
  bool get hasPopouts => _v6;

  @override
  void openPopout(DesktopPopout kind) {
    if (_v6) _js.callMethod<JSAny?>('openPopout'.toJS, kind.wire.toJS);
  }

  @override
  void closePopout(DesktopPopout kind) {
    if (_v6) _js.callMethod<JSAny?>('closePopout'.toJS, kind.wire.toJS);
  }

  @override
  void postToPopout(DesktopPopout kind, String data) {
    if (_v6) _js.callMethod<JSAny?>('postToPopout'.toJS, kind.wire.toJS, data.toJS);
  }

  @override
  Stream<DesktopPopout> get popoutReadies => _popoutReadies.stream;

  @override
  Stream<DesktopPopout> get popoutClosings => _popoutClosings.stream;

  @override
  void popoutReady() {
    if (popout != null) _js.callMethod<JSAny?>('popoutReady'.toJS);
  }

  @override
  Stream<String> get popoutData => _popoutData.stream;

  @override
  bool get hasThemeEditor => _v1 && _apiVersion >= 12;

  @override
  void sendThemeEditorAction(String data) {
    if (popout == DesktopPopout.themeEditor && _apiVersion >= 12) {
      _js.callMethod<JSAny?>('sendThemeEditorAction'.toJS, data.toJS);
    }
  }

  @override
  Stream<String> get themeEditorActions => _themeEditorActions.stream;


  @override
  late final List<List<String>> reservedHotkeys = _v7 ? _readReservedHotkeys() : const [];

  List<List<String>> _readReservedHotkeys() {
    final list = _js.getProperty<JSArray<JSArray<JSString>>?>('reservedHotkeys'.toJS);
    if (list == null) return const [];
    return [
      for (final combo in list.toDart) [for (final key in combo.toDart) key.toDart],
    ];
  }

  @override
  bool get hasGlobalKeys => _v8;

  @override
  void watchGlobalKeys(List<String> keys) {
    if (_v8) _js.callMethod<JSAny?>('watchGlobalKeys'.toJS, [for (final k in keys) k.toJS].toJS);
  }

  @override
  Stream<Set<String>> get globalKeys => _globalKeys.stream;

  @override
  bool get reportsGlobalKeysStatus => _v9;

  @override
  Stream<DesktopGlobalKeysStatus> get globalKeysStatus => _globalKeysStatus.stream;


  @override
  bool get hasProgramHotkeys => _v10;

  @override
  Future<List<DesktopProgramHotkey>> getProgramHotkeys() async {
    if (!_v10) return const [];
    final list = await _js.callMethod<JSPromise<JSArray<JSObject>>>('getProgramHotkeys'.toJS).toDart;
    return _readProgramHotkeys(list);
  }

  @override
  Future<List<DesktopProgramHotkey>> setProgramHotkeys(List<DesktopProgramHotkey> hotkeys) async {
    if (!_v10) return const [];
    final js = <JSObject>[
      for (final h in hotkeys)
        JSObject()
          ..setProperty('action'.toJS, h.action.toJS)
          ..setProperty('keys'.toJS, [for (final k in h.keys) k.toJS].toJS),
    ].toJS;
    final list = await _js.callMethod<JSPromise<JSArray<JSObject>>>('setProgramHotkeys'.toJS, js).toDart;
    return _readProgramHotkeys(list);
  }

  @override
  void pauseProgramHotkeys(bool paused) {
    if (_v10) _js.callMethod<JSAny?>('pauseProgramHotkeys'.toJS, paused.toJS);
  }


  @override
  bool get hasRunningGames => _v11;

  @override
  void watchGames(List<DesktopWatchedGame> games) {
    if (!_v11) return;
    final js = <JSObject>[
      for (final g in games)
        JSObject()
          ..setProperty('id'.toJS, g.id.toJS)
          ..setProperty('executables'.toJS, [for (final e in g.executables) e.toJS].toJS),
    ].toJS;
    _js.callMethod<JSAny?>('watchGames'.toJS, js);
  }

  @override
  Stream<List<DesktopRunningGame>> get runningGames => _runningGames.stream;

  List<DesktopProgramHotkey> _readProgramHotkeys(JSArray<JSObject> list) => [
        for (final h in list.toDart)
          (
            action: h.getProperty<JSString?>('action'.toJS)?.toDart ?? '',
            keys: _strings(h.getProperty<JSArray<JSString>?>('keys'.toJS)),
          ),
      ];

  static List<String> _strings(JSArray<JSString>? list) => [for (final s in list?.toDart ?? const <JSString>[]) s.toDart];
}
