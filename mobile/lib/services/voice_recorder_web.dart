import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:web/web.dart' as web;

/// ПОЧЕМУ НЕ flutter_sound, КОТОРЫЙ И ТАК ЕСТЬ В ПРОЕКТЕ. У него есть
/// веб-половина, но по его же документации рекордер **не работает в Safari
/// вовсе**, а на вебе у него открытые баги вплоть до зацикливания старта. Нужен
/// же здесь ровно один браузерный механизм — `MediaRecorder`, — и обратиться к
/// нему напрямую надёжнее и понятнее, чем через прослойку. Приём тот же, что
/// уже собрался и выкачен в media_actions_web.dart и media_platform_web.dart:
/// package:web, без новых пакетов.

/// webm/opus — то, что предлагает Firefox, — здесь НЕ используется, хотя
/// технически браузер его пишет: файл с чужим содержимым лёг бы в S3 под именем
/// `.m4a` и с заявленным типом `audio/m4a`, и его перестали бы проигрывать и
/// старые APK, и Safari (webm он не играет). Поддержка webm — отдельная задача
/// с согласованной правкой allow-list на боевом сервере; до неё Firefox просто
/// не показывает кнопку записи (`voiceRecordingSupported == false`) — ровно
/// так же, как до 2026-08-29 её не показывал весь веб.
const List<String> _mimeCandidates = <String>[
  'audio/mp4;codecs=mp4a.40.2',
  'audio/mp4',
];

const double _floorDb = -60.0;

const Duration _levelTick = Duration(milliseconds: 80);

web.MediaStream? _stream;
web.MediaRecorder? _recorder;
web.AudioContext? _audioCtx;
web.MediaStreamAudioSourceNode? _source;
web.AnalyserNode? _analyser;
JSUint8Array? _analyserBuffer;
Timer? _levelTimer;
StreamController<double>? _levels;
final List<web.Blob> _chunks = <web.Blob>[];
String _mimeType = 'audio/mp4';
Completer<void>? _stopped;

bool get voiceRecordingSupported => _pickMimeType() != null;

/// «Мотор» один на всё приложение, а композеров одновременно может жить
/// несколько (в широкой раскладке экраны соседствуют, и у каждого своя строка
/// ввода). Этот геттер нужен ровно затем, чтобы закрытие соседнего экрана не
/// обрывало чужую запись — см. dispose в MessageComposer.
bool get voiceCaptureActive => _recorder != null;

String? _pickMimeType() {
  try {
    if (!(web.window.navigator as JSObject).has('mediaDevices')) return null;
    for (final mime in _mimeCandidates) {
      if (web.MediaRecorder.isTypeSupported(mime)) return mime;
    }
  } catch (_) {
  }
  return null;
}

Future<bool> requestMicPermission() async {
  if (_stream != null) return true;
  try {
    _stream = await web.window.navigator.mediaDevices
        .getUserMedia(web.MediaStreamConstraints(audio: true.toJS))
        .toDart;
    return true;
  } catch (_) {
    return false;
  }
}

Stream<double>? get voiceAmplitudeStream => _levels?.stream;

Future<bool> startVoiceCapture() async {
  final mime = _pickMimeType();
  if (mime == null) {
    await _teardown();
    return false;
  }
  if (!await requestMicPermission()) return false;
  final stream = _stream;
  if (stream == null) return false;

  _mimeType = mime;
  _chunks.clear();

  try {
    final rec = web.MediaRecorder(
      stream,
      web.MediaRecorderOptions(mimeType: mime, audioBitsPerSecond: 64000),
    );
    final stopped = Completer<void>();

    rec.addEventListener(
      'dataavailable',
      ((web.BlobEvent event) {
        final blob = event.data;
        if (blob.size > 0) _chunks.add(blob);
      }).toJS,
    );
    rec.addEventListener(
      'stop',
      ((web.Event _) {
        if (!stopped.isCompleted) stopped.complete();
      }).toJS,
    );

    rec.start();
    _recorder = rec;
    _stopped = stopped;
  } catch (_) {
    await _teardown();
    return false;
  }

  _startLevelMeter(stream);
  return true;
}

Future<XFile?> stopVoiceCapture() async {
  final rec = _recorder;
  if (rec == null) {
    await _teardown();
    return null;
  }
  try {
    rec.stop();
    await _stopped?.future.timeout(const Duration(seconds: 5));
  } catch (_) {
  }

  Uint8List? bytes;
  try {
    if (_chunks.isNotEmpty) {
      final parts = <JSAny>[for (final chunk in _chunks) chunk].toJS;
      final blob = web.Blob(parts, web.BlobPropertyBag(type: _mimeType));
      final buffer = await blob.arrayBuffer().toDart;
      bytes = buffer.toDart.asUint8List();
    }
  } catch (_) {
    bytes = null;
  }

  await _teardown();
  if (bytes == null || bytes.isEmpty) return null;

  return XFile.fromData(
    bytes,
    name: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
    mimeType: 'audio/mp4',
    length: bytes.length,
  );
}

Future<void> cancelVoiceCapture() async {
  try {
    _recorder?.stop();
  } catch (_) {}
  await _teardown();
}

Future<void> releaseVoiceCapture() => cancelVoiceCapture();

void _startLevelMeter(web.MediaStream stream) {
  try {
    final ctx = web.AudioContext();
    final analyser = ctx.createAnalyser();
    analyser.fftSize = 1024;
    final source = ctx.createMediaStreamSource(stream);
    source.connect(analyser);

    final levels = StreamController<double>.broadcast();
    _audioCtx = ctx;
    _source = source;
    _analyser = analyser;
    _analyserBuffer = Uint8List(analyser.fftSize).toJS;
    _levels = levels;

    _levelTimer = Timer.periodic(_levelTick, (_) {
      final a = _analyser;
      final buf = _analyserBuffer;
      if (a == null || buf == null || levels.isClosed) return;
      a.getByteTimeDomainData(buf);
      levels.add(_rmsDecibels(buf.toDart));
    });
  } catch (_) {
  }
}

double _rmsDecibels(Uint8List samples) {
  if (samples.isEmpty) return _floorDb;
  var sum = 0.0;
  for (var i = 0; i < samples.length; i++) {
    final v = (samples[i] - 128) / 128.0;
    sum += v * v;
  }
  final rms = math.sqrt(sum / samples.length);
  if (rms <= 0) return _floorDb;
  final db = 20 * math.log(rms) / math.ln10;
  return db.clamp(_floorDb, 0.0);
}

Future<void> _teardown() async {
  _levelTimer?.cancel();
  _levelTimer = null;
  await _levels?.close();
  _levels = null;
  _analyser = null;
  _source = null;
  _analyserBuffer = null;

  final ctx = _audioCtx;
  _audioCtx = null;
  if (ctx != null) {
    try {
      await ctx.close().toDart;
    } catch (_) {}
  }

  _recorder = null;
  _stopped = null;
  _chunks.clear();

  final stream = _stream;
  _stream = null;
  if (stream != null) {
    try {
      for (final track in stream.getTracks().toDart) {
        track.stop();
      }
    } catch (_) {}
  }
}
