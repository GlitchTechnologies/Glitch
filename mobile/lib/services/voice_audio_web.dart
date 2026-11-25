import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:dart_webrtc/dart_webrtc.dart' show MediaStreamTrackWeb;
import 'package:flutter/foundation.dart' show ChangeNotifier, Listenable;
import 'package:flutter/services.dart' show rootBundle;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:web/web.dart' as web;

import 'voice_cue.dart';


const _libraryContainerId = 'livekit_audio_container';
const _libraryElementPrefix = 'livekit_audio_';

/// Выбор устройства вывода есть там, где браузер умеет setSinkId и у
/// звуковой цепочки (голоса), и у элемента (звуки входа, проверка
/// микрофона): Chrome и Edge; Firefox и Safari — нет. Спрашиваем
/// возможность, а не браузер.
final bool outputDeviceSelectionSupported = _detectSinkId();

bool _detectSinkId() {
  try {
    final context = (web.window as JSObject).getProperty<JSObject?>('AudioContext'.toJS);
    final proto = context?.getProperty<JSObject?>('prototype'.toJS);
    return proto != null && proto.has('setSinkId') && (web.HTMLAudioElement() as JSObject).has('setSinkId');
  } catch (_) {
    return false;
  }
}

const bool outputVolumeSupported = true;


web.AudioContext? _context;
web.GainNode? _master;

double _volume = 1;
String? _outputDeviceId;

class _Voice {
  final web.MediaStreamAudioSourceNode? source;
  final web.GainNode? gain;
  final String? elementId;
  double level;

  _Voice.chain(web.MediaStreamAudioSourceNode this.source, web.GainNode this.gain, this.level) : elementId = null;
  _Voice.element(String this.elementId, this.level)
      : source = null,
        gain = null;
}

final Map<String, _Voice> _voices = {};
web.MutationObserver? _libraryObserver;

void prepareVoicePlayback() {
  _probe ??= _probePlaysWithoutGesture();
  if (_libraryObserver != null) return;
  var container = web.document.getElementById(_libraryContainerId);
  if (container == null) {
    final div = web.HTMLDivElement()..id = _libraryContainerId;
    div.style.display = 'none';
    web.document.body?.append(div);
    container = div;
  }
  final observer = web.MutationObserver(
      ((JSArray<web.MutationRecord> _, web.MutationObserver __) => _syncLibraryElements()).toJS);
  observer.observe(container, web.MutationObserverInit(childList: true));
  _libraryObserver = observer;
  _syncLibraryElements();
}

bool? _playsWithoutGesture;
Future<void>? _probe;

Future<void> _probePlaysWithoutGesture() async {
  web.AudioContext? probe;
  try {
    probe = web.AudioContext();
    _playsWithoutGesture = await waitAudioContextRunning(probe);
  } catch (_) {
    _playsWithoutGesture = false;
  } finally {
    final opened = probe;
    if (opened != null) unawaited(opened.close().toDart.then((_) {}, onError: (Object _) {}));
  }
  _playbackChanges.changed();
}


final Listenable voicePlaybackChanges = _playbackChanges;
final _PlaybackChanges _playbackChanges = _PlaybackChanges();

class _PlaybackChanges extends ChangeNotifier {
  void changed() => notifyListeners();
}

const _audioStartTimeout = Duration(seconds: 1);

Future<bool> waitAudioContextRunning(web.AudioContext context) async {
  if (context.state == 'running') return true;
  final changed = Completer<void>();
  final listener = ((web.Event _) {
    if (!changed.isCompleted) changed.complete();
  }).toJS;
  context.addEventListener('statechange', listener);
  final timer = Timer(_audioStartTimeout, () {
    if (!changed.isCompleted) changed.complete();
  });
  try {
    await changed.future;
  } finally {
    timer.cancel();
    context.removeEventListener('statechange', listener);
  }
  return context.state == 'running';
}

void _syncLibraryElements() {
  final container = web.document.getElementById(_libraryContainerId);
  if (container == null) return;
  final fallback = {
    for (final v in _voices.values)
      if (v.elementId != null) v.elementId!: v.level,
  };
  final children = container.children;
  for (var i = 0; i < children.length; i++) {
    final el = children.item(i);
    if (el == null || !el.instanceOfString('HTMLAudioElement')) continue;
    final audio = el as web.HTMLAudioElement;
    final level = fallback[audio.id];
    if (level == null) {
      audio.muted = true;
    } else {
      audio.muted = false;
      audio.volume = (level * _volume).clamp(0.0, 1.0);
    }
  }
}

web.AudioContext _ensureContext() {
  final existing = _context;
  if (existing != null) return existing;
  // 48 кГц — частота самого голоса: так браузеру не нужно её пересчитывать
  // (Firefox при несовпадении отказывается соединять поток с цепочкой).
  final context = web.AudioContext(web.AudioContextOptions(sampleRate: 48000, latencyHint: 'interactive'.toJS));
  final master = context.createGain();
  master.gain.value = _volume;
  master.connect(context.destination);
  _context = context;
  _master = master;
  context.addEventListener('statechange', ((web.Event _) => _playbackChanges.changed()).toJS);
  final device = _outputDeviceId;
  if (device != null) unawaited(_setContextSink(context, device));
  return context;
}

/// Начать играть дорожку [track] с громкостью [level] (0…2). [key] — имя
/// голоса для [setRemoteAudioLevel]/[stopRemoteAudio]; повторный вызов с
/// тем же именем заменяет дорожку (подписку пересоздали).
void playRemoteAudio(String key, lk.Track track, double level) {
  stopRemoteAudio(key);
  final raw = track.mediaStreamTrack;
  if (raw is! MediaStreamTrackWeb) return;
  try {
    final context = _ensureContext();
    final source = context.createMediaStreamSource(web.MediaStream(<web.MediaStreamTrack>[raw.jsTrack].toJS));
    final gain = context.createGain();
    gain.gain.value = level;
    source.connect(gain);
    gain.connect(_master!);
    _voices[key] = _Voice.chain(source, gain, level);
  } catch (_) {
    _voices[key] = _Voice.element('$_libraryElementPrefix${track.getCid()}', level);
  }
  _syncLibraryElements();
}

void setRemoteAudioLevel(String key, double level) {
  final voice = _voices[key];
  if (voice == null) return;
  voice.level = level;
  final gain = voice.gain;
  if (gain != null) {
    gain.gain.value = level;
  } else {
    _syncLibraryElements();
  }
}

void stopRemoteAudio(String key) {
  final voice = _voices.remove(key);
  if (voice == null) return;
  voice.source?.disconnect();
  voice.gain?.disconnect();
  if (voice.elementId != null) _syncLibraryElements();
}

void stopAllRemoteAudio() {
  for (final key in _voices.keys.toList()) {
    stopRemoteAudio(key);
  }
  final context = _context;
  _context = null;
  _master = null;
  if (context != null) unawaited(context.close().toDart.then((_) {}, onError: (Object _) {}));
}

void applyOutputVolume(double volume) {
  _volume = volume;
  _master?.gain.value = volume;
  _syncLibraryElements();
}

Future<void> setVoiceOutputDevice(String deviceId) async {
  _outputDeviceId = deviceId;
  final context = _context;
  if (context != null) await _setContextSink(context, deviceId);
}

Future<void> _setContextSink(web.AudioContext context, String deviceId) async {
  if (!outputDeviceSelectionSupported) return;
  await (context as JSObject).callMethod<JSPromise<JSAny?>>('setSinkId'.toJS, deviceId.toJS).toDart;
}

/// Разрешил ли браузер странице играть звук. Браузеры запрещают это, пока на
/// странице не было ни одного действия человека (клик, клавиша), — а после
/// первого разрешают до конца жизни страницы («sticky activation»).
/// `navigator.userActivation` есть в Chrome, Edge, Safari 16.4+, Firefox 120+;
/// где его нет — считаем, что можно (иначе подсказка висела бы вечно).
bool voicePlaybackAllowed() {
  if (_context?.state == 'suspended') return false;
  if (_playsWithoutGesture == true) return true;
  try {
    final activation = (web.window.navigator as JSObject).getProperty<JSObject?>('userActivation'.toJS);
    if (activation == null) return true;
    return activation.getProperty<JSBoolean?>('hasBeenActive'.toJS)?.toDart ?? true;
  } catch (_) {
    return true;
  }
}

Future<void> resumeVoicePlayback() async {
  try {
    await _context?.resume().toDart;
  } catch (_) {
  }
  final container = web.document.getElementById(_libraryContainerId);
  if (container == null) return;
  final children = container.children;
  for (var i = 0; i < children.length; i++) {
    final el = children.item(i);
    if (el != null && el.instanceOfString('HTMLAudioElement')) {
      try {
        await (el as web.HTMLAudioElement).play().toDart;
      } catch (_) {
      }
    }
  }
}

final Map<VoiceCue, String> _cueUrls = {};

web.HTMLAudioElement? _cueElement;

Future<void> playVoiceCue(VoiceCue cue, {required double volume, String? outputDeviceId}) async {
  try {
    var url = _cueUrls[cue];
    if (url == null) {
      final data = await rootBundle.load(cue.asset);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: cue.mimeType));
      url = web.URL.createObjectURL(blob);
      _cueUrls[cue] = url;
    }
    _cueElement?.pause();
    final el = web.HTMLAudioElement()
      ..src = url
      ..volume = volume;
    _cueElement = el;
    if (outputDeviceId != null && outputDeviceId.isNotEmpty && outputDeviceSelectionSupported) {
      await (el as JSObject).callMethod<JSPromise>('setSinkId'.toJS, outputDeviceId.toJS).toDart;
    }
    await el.play().toDart;
  } catch (_) {
  }
}
