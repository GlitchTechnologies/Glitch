import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:dart_webrtc/dart_webrtc.dart' show MediaStreamTrackWeb;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:web/web.dart' as web;

import 'error_reporter.dart';
import 'mic_options.dart';
import 'noise_filter_web.dart' show WebNoiseFilter;
import 'voice_audio_web.dart' show voicePlaybackAllowed, waitAudioContextRunning;

export 'noise_filter_web.dart' show noiseFilterSupported;


const bool micVolumeSupported = true;
const bool micGateSupported = true;

class WebMicChain {
  final double _attenuationDb;

  WebMicChain(this._attenuationDb);

  WebNoiseFilter? _filter;
  _ShapeStage? _shape;

  /// Ступень громкости и чувствительности не завелась в этом браузере
  /// (Firefox не соединяет звуковые потоки с разной частотой) — больше не
  /// пробуем: само не пройдёт. Звук идёт без неё, остальная цепочка работает.
  bool _shapeBroken = false;

  double? get levelDb => _shape?.levelDb;

  Future<web.MediaStreamTrack> route(web.MediaStreamTrack raw, MicProcessing processing) async {
    var out = raw;
    if (processing.noise) {
      final filter = _filter ??= await WebNoiseFilter.create(_attenuationDb);
      await filter.listen(raw);
      out = filter.output.jsTrack;
    } else {
      await _dropFilter();
    }
    if ((processing.volume < 1 || processing.gate != null) && !_shapeBroken) {
      try {
        final stage = _shape ??= await _ShapeStage.create();
        await stage.listen(out);
        stage.configure(processing.volume, processing.gate);
        out = stage.output;
      } catch (e, s) {
        errorReporter.report(e, stack: s, screen: 'voice:micShape');
        _shapeBroken = true;
        await _dropShape();
      }
    } else {
      await _dropShape();
    }
    return out;
  }

  Future<void> _dropFilter() async {
    final filter = _filter;
    _filter = null;
    await filter?.destroy();
  }

  Future<void> _dropShape() async {
    final stage = _shape;
    _shape = null;
    await stage?.destroy();
  }

  Future<void> destroy() async {
    try {
      await _dropFilter();
    } finally {
      await _dropShape();
    }
  }
}

/// Работает в звуковом потоке страницы (AudioWorklet), а не таймером: таймеры
/// фоновой вкладки браузер замедляет до раза в секунду, и отсекание
/// опаздывало бы на целые слова. Замер громкости ступень присылает сама,
/// 20 раз в секунду ([levelDb]).
class _ShapeStage {
  final web.AudioContext _context;
  final web.AudioWorkletNode _node;
  final web.MediaStreamAudioDestinationNode _destination;
  web.MediaStreamAudioSourceNode? _source;
  String? _sourceId;

  double levelDb = kMicSilenceDb;

  _ShapeStage._(this._context, this._node, this._destination) {
    _node.connect(_destination);
    _node.port.onmessage = ((web.MessageEvent event) {
      final data = event.data;
      if (data.isA<JSNumber>()) levelDb = (data as JSNumber).toDartDouble;
    }).toJS;
  }

  static Future<_ShapeStage> create() async {
    final context = web.AudioContext();
    try {
      final url = web.URL.createObjectURL(
        web.Blob(<web.BlobPart>[_workletCode.toJS].toJS, web.BlobPropertyBag(type: 'application/javascript')),
      );
      try {
        await context.audioWorklet.addModule(url).toDart;
      } finally {
        web.URL.revokeObjectURL(url);
      }
      final node = web.AudioWorkletNode(
        context,
        _workletName,
        web.AudioWorkletNodeOptions(
          numberOfInputs: 1,
          numberOfOutputs: 1,
          outputChannelCount: <JSNumber>[1.toJS].toJS,
        ),
      );
      return _ShapeStage._(context, node, context.createMediaStreamDestination());
    } catch (_) {
      await context.close().toDart;
      rethrow;
    }
  }

  web.MediaStreamTrack get output => _destination.stream.getAudioTracks().toDart.first;

  void configure(double volume, MicGate? gate) {
    final message = JSObject()..setProperty('volume'.toJS, volume.toJS);
    if (gate != null) {
      message.setProperty(
        'gate'.toJS,
        JSObject()
          ..setProperty('auto'.toJS, gate.auto.toJS)
          ..setProperty('db'.toJS, gate.thresholdDb.toJS),
      );
    }
    _node.port.postMessage(message);
  }

  Future<void> listen(web.MediaStreamTrack input) async {
    if (_sourceId != input.id) {
      _source?.disconnect();
      _source = _context.createMediaStreamSource(web.MediaStream(<web.MediaStreamTrack>[input].toJS))
        ..connect(_node);
      _sourceId = input.id;
    }
    if (!await waitAudioContextRunning(_context)) {
      throw StateError('mic shape audio context is ${_context.state}');
    }
  }

  Future<void> destroy() async {
    _node.port.onmessage = null;
    _source?.disconnect();
    _source = null;
    await _context.close().toDart;
  }
}

const _workletName = 'glitch-mic-shape';

final String _workletCode = """
const SILENCE = $kMicSilenceDb;
const HOLD_MS = $kMicGateHoldMs;
const MARGIN = $kMicGateAutoMarginDb;
const AUTO_MIN = $kMicGateAutoMinDb;
const AUTO_MAX = $kMicGateAutoMaxDb;
const FLOOR_PARTS = 8;
const FLOOR_PART_SAMPLES = Math.round(sampleRate * $kMicGateFloorWindowMs / 1000 / FLOOR_PARTS);
const REPORT_SAMPLES = Math.round(sampleRate * 0.05);
const OPEN_STEP = 1 / (sampleRate * 0.005);
const CLOSE_STEP = 1 / (sampleRate * 0.05);

class GlitchMicShape extends AudioWorkletProcessor {
  constructor() {
    super();
    this.volume = 1;
    this.gate = null;
    this.gain = 1;
    this.hold = 0;
    this.parts = [];
    this.partMin = 0;
    this.partLeft = 0;
    this.peak = SILENCE;
    this.reportLeft = REPORT_SAMPLES;
    this.port.onmessage = (event) => {
      const data = event.data;
      this.volume = data.volume;
      this.gate = data.gate || null;
    };
  }

  floorDb(db, n) {
    if (this.partLeft <= 0) {
      this.partMin = db;
      this.partLeft = FLOOR_PART_SAMPLES;
    } else if (db < this.partMin) {
      this.partMin = db;
    }
    this.partLeft -= n;
    if (this.partLeft <= 0) {
      this.parts.push(this.partMin);
      if (this.parts.length > FLOOR_PARTS) this.parts.shift();
    }
    let floor = this.partMin;
    for (const part of this.parts) if (part < floor) floor = part;
    return floor;
  }

  process(inputs, outputs) {
    const out = outputs[0];
    const n = out[0].length;
    const input = inputs[0] && inputs[0][0];
    if (!input) {
      for (const channel of out) channel.fill(0);
      return true;
    }
    let sum = 0;
    for (let i = 0; i < n; i++) {
      const x = input[i] * this.volume;
      sum += x * x;
    }
    const rms = Math.sqrt(sum / n);
    const db = rms > 0 ? Math.min(0, Math.max(SILENCE, 20 * Math.log10(rms))) : SILENCE;

    if (db > this.peak) this.peak = db;
    this.reportLeft -= n;
    if (this.reportLeft <= 0) {
      this.port.postMessage(this.peak);
      this.peak = SILENCE;
      this.reportLeft = REPORT_SAMPLES;
    }

    const floor = this.floorDb(db, n);
    let open = true;
    const gate = this.gate;
    if (gate) {
      const threshold = gate.auto ? Math.min(AUTO_MAX, Math.max(AUTO_MIN, floor + MARGIN)) : gate.db;
      if (db >= threshold) {
        this.hold = sampleRate * HOLD_MS / 1000;
      } else {
        this.hold = Math.max(0, this.hold - n);
      }
      open = this.hold > 0;
    }

    const target = open ? 1 : 0;
    for (let i = 0; i < n; i++) {
      if (this.gain < target) this.gain = Math.min(target, this.gain + OPEN_STEP);
      else if (this.gain > target) this.gain = Math.max(target, this.gain - CLOSE_STEP);
      const y = input[i] * this.volume * this.gain;
      for (const channel of out) channel[i] = y;
    }
    return true;
  }
}

registerProcessor('$_workletName', GlitchMicShape);
""";


WebMicChain? _chain;

Future<void> _queue = Future.value();

Future<void> _enqueue(Future<void> Function() op) {
  final next = _queue.then((_) => op());
  _queue = next.catchError((Object _) {});
  return next;
}

Future<void> syncMicChain(lk.Room room, MicProcessing processing, {required double attenuationDb}) =>
    _enqueue(() => _sync(room, processing, attenuationDb));

Future<void> releaseMicChain() => _enqueue(_release);

Future<double?> micChainLevel() async => _chain?.levelDb;

bool _processes(MicProcessing p) => p.noise || p.volume < 1 || p.gate != null;

Future<void> _sync(lk.Room room, MicProcessing processing, double attenuationDb) async {
  final track = room.localParticipant?.getTrackPublicationBySource(lk.TrackSource.microphone)?.track;
  final transceiver = track?.transceiver;
  final sender = transceiver?.sender;
  if (!_processes(processing)) {
    if (track != null && sender != null && _chain != null) await sender.replaceTrack(track.mediaStreamTrack);
    await _release();
    return;
  }
  if (track == null || sender == null || track.muted) return;
  final raw = track.mediaStreamTrack;
  if (raw is! MediaStreamTrackWeb || raw.jsTrack.readyState != 'live') return;
  if (!voicePlaybackAllowed()) {
    await sender.replaceTrack(raw);
    return;
  }

  final chain = _chain ??= WebMicChain(attenuationDb);
  final out = await chain.route(raw.jsTrack, processing);
  if (track.muted || !identical(track.transceiver, transceiver) || !identical(track.mediaStreamTrack, raw)) return;
  if (sender.track?.id == out.id) return;
  await sender.replaceTrack(identical(out, raw.jsTrack) ? raw : MediaStreamTrackWeb(out));
}

Future<void> _release() async {
  final chain = _chain;
  _chain = null;
  await chain?.destroy();
}
