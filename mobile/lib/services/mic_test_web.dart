import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_webrtc/dart_webrtc.dart' show MediaStreamTrackWeb;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:web/web.dart' as web;

import 'mic_chain_web.dart' show WebMicChain;
import 'mic_options.dart';
import 'mic_test.dart';
import 'voice_audio_web.dart' show outputDeviceSelectionSupported;


const bool micTestSupported = true;

Future<MicTest> openMicTest({
  required lk.AudioCaptureOptions capture,
  required MicProcessing processing,
  required double attenuationDb,
  String? outputDeviceId,
  required double volume,
  bool hear = true,
}) async {
  final test = _WebMicTest(WebMicChain(attenuationDb), hear: hear);
  try {
    await test._start(capture, processing, outputDeviceId, volume);
  } catch (_) {
    await test.stop();
    rethrow;
  }
  return test;
}

class _WebMicTest implements MicTest {
  final WebMicChain _chain;
  final bool _hear;

  _WebMicTest(this._chain, {required bool hear}) : _hear = hear;

  lk.LocalAudioTrack? _track;
  final web.HTMLAudioElement _audio = web.HTMLAudioElement();

  web.AudioContext? _meter;
  web.AnalyserNode? _analyser;
  web.MediaStreamAudioSourceNode? _meterSource;
  final JSFloat32Array _samples = Float32List(_meterSize).toJS;
  static const _meterSize = 1024;

  bool _stopped = false;

  Future<void> _queue = Future.value();

  Future<void> _enqueue(Future<void> Function() op) {
    final next = _queue.then((_) => _stopped ? null : op());
    _queue = next.catchError((Object _) {});
    return next;
  }

  Future<void> _start(
    lk.AudioCaptureOptions capture,
    MicProcessing processing,
    String? outputDeviceId,
    double volume,
  ) async {
    _track = await lk.LocalAudioTrack.create(capture);
    if (!_hear) {
      await _enqueue(() => _route(processing));
      return;
    }
    _audio.volume = volume;
    if (outputDeviceId != null) await setOutput(outputDeviceId);
    try {
      final meter = _meter = web.AudioContext();
      _analyser = meter.createAnalyser()..fftSize = _meterSize;
    } catch (_) {
      _meter = null;
      _analyser = null;
    }
    await _enqueue(() => _route(processing));
  }

  Future<void> _route(MicProcessing processing) async {
    final track = _track;
    if (track == null) return;
    final raw = (track.mediaStreamTrack as MediaStreamTrackWeb).jsTrack;
    final heard = await _chain.route(raw, processing);
    if (_stopped) {
      await _chain.destroy();
      return;
    }
    if (heard.id == _heardId || !_hear) return;
    _heardId = heard.id;
    final stream = web.MediaStream(<web.MediaStreamTrack>[heard].toJS);
    _audio.srcObject = stream;
    await _audio.play().toDart;
    _meterSource?.disconnect();
    _meterSource = null;
    final meter = _meter;
    final analyser = _analyser;
    if (meter != null && analyser != null) {
      try {
        _meterSource = meter.createMediaStreamSource(stream)..connect(analyser);
      } catch (_) {
        // Firefox не соединяет потоки с разной частотой — без полоски.
      }
    }
  }

  String? _heardId;

  @override
  double? get inputLevelDb => _chain.levelDb;

  @override
  Future<void> setProcessing(MicProcessing processing) => _enqueue(() => _route(processing));

  @override
  Future<void> setOutput(String deviceId) async {
    if (!outputDeviceSelectionSupported) return;
    await (_audio as JSObject).callMethod<JSPromise<JSAny?>>('setSinkId'.toJS, deviceId.toJS).toDart;
  }

  @override
  void setVolume(double volume) => _audio.volume = volume;

  @override
  double get level {
    final analyser = _analyser;
    if (analyser == null || _meterSource == null) return 0;
    analyser.getFloatTimeDomainData(_samples);
    final data = _samples.toDart;
    var sum = 0.0;
    for (final x in data) {
      sum += x * x;
    }
    final rms = math.sqrt(sum / data.length);
    if (rms <= 0) return 0;
    final db = 20 * math.log(rms) / math.ln10;
    return ((db + 60) / 60).clamp(0.0, 1.0).toDouble();
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _audio.pause();
    _audio.srcObject = null;
    _meterSource?.disconnect();
    _meterSource = null;
    final meter = _meter;
    _meter = null;
    _analyser = null;
    final track = _track;
    _track = null;
    try {
      await meter?.close().toDart;
    } catch (_) {}
    try {
      await _chain.destroy();
    } catch (_) {}
    if (track != null) {
      await track.stop();
      await track.dispose();
    }
  }
}
