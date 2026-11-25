import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:dart_webrtc/dart_webrtc.dart' show MediaStreamTrackWeb;
import 'package:web/web.dart' as web;

import 'voice_audio_web.dart' show waitAudioContextRunning;

/// Нейросеть DeepFilterNet3 (бесплатная, MIT/Apache) работает в звуковом
/// потоке страницы (AudioWorklet + WebAssembly): сырой микрофон → фильтр →
/// очищенная дорожка, и медиасерверу уходит ОНА. Файлы фильтра лежат на
/// нашем же сайте (mobile/web/noise_filter/, откуда и почему — README там):
/// чужой CDN заблокирован заголовками изоляции страницы (COEP), да и
/// зависеть от него незачем.

const _assetDir = 'noise_filter';

final bool noiseFilterSupported = _detectSupport();

bool _detectSupport() {
  try {
    final window = web.window as JSObject;
    return window.has('AudioWorkletNode') && window.has('WebAssembly');
  } catch (_) {
    return false;
  }
}

class WebNoiseFilter {
  final JSObject _js;
  String? _sourceId;
  MediaStreamTrackWeb? _output;

  WebNoiseFilter._(this._js);

  static Future<WebNoiseFilter> create(double attenuationDb) async =>
      WebNoiseFilter._(await _createJs(attenuationDb));

  Future<void> listen(web.MediaStreamTrack input) async {
    if (_sourceId != input.id) {
      final args = JSObject()..setProperty('track'.toJS, input);
      final method = _sourceId == null ? 'init' : 'restart';
      await _js.callMethod<JSPromise<JSAny?>>(method.toJS, args).toDart;
      _sourceId = input.id;
    }
    final context = _js.getProperty<web.AudioContext?>('audioContext'.toJS);
    if (context == null || !await waitAudioContextRunning(context)) {
      throw StateError('noise filter audio context is ${context?.state}');
    }
  }

  MediaStreamTrackWeb get output => _output ??= _outputOf(_js);

  Future<void> destroy() => _js.callMethod<JSPromise<JSAny?>>('destroy'.toJS).toDart;
}

MediaStreamTrackWeb _outputOf(JSObject js) {
  final track = js.getProperty<web.MediaStreamTrack?>('processedTrack'.toJS);
  if (track == null) throw StateError('noise filter has no processed track');
  return MediaStreamTrackWeb(track);
}

Future<JSObject> _createJs(double attenuationDb) async {
  final module = await importModule(_assetUrl('deepfilter.js').toJS).toDart;
  final factory = module.getProperty<JSFunction>('DeepFilterNoiseFilter'.toJS);
  final assets = JSObject()..setProperty('cdnUrl'.toJS, _assetUrl('').toJS);
  final options = JSObject()
    ..setProperty('noiseReductionLevel'.toJS, attenuationDb.toJS)
    ..setProperty('enabled'.toJS, true.toJS)
    ..setProperty('assetConfig'.toJS, assets);
  return factory.callAsFunction(null, options) as JSObject;
}

String _assetUrl(String path) {
  final base = Uri.parse(web.document.baseURI);
  return base.resolve(path.isEmpty ? _assetDir : '$_assetDir/$path').toString();
}
