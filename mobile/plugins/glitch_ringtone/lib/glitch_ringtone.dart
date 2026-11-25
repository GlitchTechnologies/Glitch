library glitch_ringtone;

import 'package:flutter/services.dart';

enum IncomingNotice {
  first,

  ringing,

  handled,
}

class GlitchRingtone {
  static const _channel = MethodChannel('glitch/ringtone');

  static Future<void> playIncoming({required int callId, bool silent = false}) =>
      _invoke('playIncoming', {'callId': callId, 'silent': silent});

  static Future<void> playOutgoing() => _invoke('playOutgoing');

  static Future<void> stop() => _invoke('stop');

  static Future<void> playCue(String name) => _invoke('playCue', {'name': name});

  static Future<IncomingNotice> claimIncoming(int callId) async {
    final answer = await _call<String>('claimIncoming', {'callId': callId});
    return switch (answer) {
      'ringing' => IncomingNotice.ringing,
      'handled' => IncomingNotice.handled,
      _ => IncomingNotice.first,
    };
  }

  static Future<bool> finishRinging(int callId) async =>
      await _call<bool>('finishRinging', {'callId': callId}) ?? true;

  static Future<void> _invoke(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod(method, arguments);
    } catch (_) {
    }
  }

  static Future<T?> _call<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } catch (_) {
      return null;
    }
  }
}

/// Системные настройки, от которых зависит, дойдёт ли звонок.
class GlitchCallSettings {
  static const _channel = MethodChannel('glitch/ringtone');

  static Future<bool> isBackgroundAllowed() async =>
      await _call<bool>('isIgnoringBatteryOptimizations') ?? false;

  static Future<void> requestBackground() => _call<void>('requestIgnoreBatteryOptimizations');

  static Future<bool> isFullScreenAllowed() async =>
      await _call<bool>('canUseFullScreenIntent') ?? true;

  static Future<bool> hasFullScreenSetting() async =>
      await _call<bool>('hasFullScreenSetting') ?? false;

  static Future<void> openFullScreenSettings() => _call<void>('openFullScreenIntentSettings');

  static Future<bool> hasLockScreenSettings() async =>
      await _call<bool>('hasLockScreenPermissionScreen') ?? false;

  static Future<void> openLockScreenSettings() =>
      _call<void>('openLockScreenPermissionSettings');

  static Future<bool> hasAutostartSettings() async =>
      await _call<bool>('hasAutostartSettings') ?? false;

  static Future<void> openAutostartSettings() => _call<void>('openAutostartSettings');

  static Future<T?> _call<T>(String method) async {
    try {
      return await _channel.invokeMethod<T>(method);
    } catch (_) {
      return null;
    }
  }
}

enum TelecomEvent {
  answer,

  reject,

  disconnect,

  rejectedBySystem,

  muted,
  unmuted,

  showIncomingUi,
}

/// ЗАЧЕМ. Даёт три вещи, которых иначе не получить никак: кнопку «ответить»
/// на гарнитуре, мирное сосуществование с обычным телефонным звонком и
/// правильный поток громкости во время разговора.
class GlitchTelecom {
  static const _channel = MethodChannel('glitch/ringtone');

  static Future<bool> register() async =>
      await _invoke<bool>('telecomRegister') ?? false;

  static Future<bool> reportIncoming(String callerName) async =>
      await _invoke<bool>('telecomIncoming', callerName) ?? false;

  static Future<bool> reportOutgoing(String calleeName) async =>
      await _invoke<bool>('telecomOutgoing', calleeName) ?? false;

  static Future<void> setActive() => _invoke<void>('telecomActive');

  static Future<bool> setSpeaker(bool on) async =>
      await _invoke<bool>('telecomSpeaker', on) ?? false;

  static Future<void> setEnded() => _invoke<void>('telecomEnded');

  static void listen(void Function(TelecomEvent event) onEvent) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'telecom') return null;
      final event = switch (call.arguments as String?) {
        'answer' => TelecomEvent.answer,
        'reject' => TelecomEvent.reject,
        'disconnect' => TelecomEvent.disconnect,
        'rejectedBySystem' => TelecomEvent.rejectedBySystem,
        'muted' => TelecomEvent.muted,
        'unmuted' => TelecomEvent.unmuted,
        'showIncomingUi' => TelecomEvent.showIncomingUi,
        _ => null,
      };
      if (event != null) onEvent(event);
      return null;
    });
    _invoke<void>('telecomListen');
  }

  static Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } catch (_) {
      return null;
    }
  }
}
