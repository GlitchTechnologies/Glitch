library glitch_noise_filter;

import 'package:flutter/services.dart';

class GlitchNoiseFilter {
  static const _channel = MethodChannel('glitch/noise_filter');

  /// Поставить фильтр в обработку звука WebRTC. Повторный вызов ничего не
  /// меняет. Ошибка — [PlatformException]: библиотеки нет под процессор
  /// устройства или звук WebRTC ещё не заведён.
  static Future<void> start({required double attenuationDb}) =>
      _channel.invokeMethod<void>('start', {'attenuationDb': attenuationDb});

  static Future<void> stop() => _channel.invokeMethod<void>('stop');

  static Future<void> setGate({required bool auto, required double thresholdDb}) =>
      _channel.invokeMethod<void>('setGate', {'auto': auto, 'thresholdDb': thresholdDb});

  static Future<void> clearGate() => _channel.invokeMethod<void>('clearGate');

  static Future<double?> level() => _channel.invokeMethod<double>('level');
}
