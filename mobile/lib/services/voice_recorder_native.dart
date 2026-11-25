import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';

import 'media_platform_native.dart' show tempFilePath, deleteTempPath;


bool get voiceRecordingSupported => true;

/// «Мотор» один на всё приложение, а композеров одновременно может жить
/// несколько (в широкой раскладке экраны соседствуют, и у каждого своя строка
/// ввода). Этот геттер нужен ровно затем, чтобы закрытие соседнего экрана не
/// обрывало чужую запись — см. dispose в MessageComposer.
bool get voiceCaptureActive => _capturing;

final _recorder = FlutterSoundRecorder();
bool _opened = false;
bool _capturing = false;
// Путь к файлу ИДУЩЕЙ записи. После успешного stopVoiceCapture обнуляется:
// файл переходит во владение вызывающего (он его отправляет), и удалять его
// уже нельзя.
String? _path;
StreamController<double>? _levels;
StreamSubscription<RecordingDisposition>? _progressSub;
bool _releaseRequested = false;

Future<bool> requestMicPermission() async {
  final status = await Permission.microphone.request();
  return status.isGranted;
}

Stream<double>? get voiceAmplitudeStream => _levels?.stream;

Future<bool> startVoiceCapture() async {
  _releaseRequested = false;

  if (!_opened) {
    await _recorder.openRecorder();
    _opened = true;
  }
  if (_releaseRequested) {
    await _closeRecorder();
    return false;
  }

  final path = await tempFilePath('voice_${DateTime.now().millisecondsSinceEpoch}.m4a');
  if (path == null) return false;
  _path = path;

  await _recorder.setSubscriptionDuration(const Duration(milliseconds: 80));
  await _recorder.startRecorder(
    toFile: path,
    codec: Codec.aacMP4,
    bitRate: 64000,
    sampleRate: 44100,
    numChannels: 1,
  );
  if (_releaseRequested) {
    await cancelVoiceCapture();
    return false;
  }

  _capturing = true;
  final levels = StreamController<double>.broadcast();
  _levels = levels;
  _progressSub = _recorder.onProgress?.listen((e) {
    final db = e.decibels;
    if (db != null && !levels.isClosed) levels.add(db);
  });
  return true;
}

Future<XFile?> stopVoiceCapture() async {
  _capturing = false;
  await _stopLevels();
  try {
    final path = await _recorder.stopRecorder();
    _path = null;
    if (path == null) return null;
    return XFile(path);
  } catch (_) {
    return null;
  }
}

Future<void> cancelVoiceCapture() async {
  _capturing = false;
  await _stopLevels();
  try {
    await _recorder.stopRecorder();
  } catch (_) {}
  final path = _path;
  _path = null;
  if (path != null) await deleteTempPath(path);
}

/// Отпустить всё: вызывается из dispose композера, поэтому БЕЗ await у
/// вызывающего — ждать результата там всё равно некому.
Future<void> releaseVoiceCapture() async {
  _releaseRequested = true;
  await cancelVoiceCapture();
  await _closeRecorder();
}

Future<void> _closeRecorder() async {
  if (!_opened) return;
  _opened = false;
  try {
    await _recorder.closeRecorder();
  } catch (_) {}
}

Future<void> _stopLevels() async {
  await _progressSub?.cancel();
  _progressSub = null;
  await _levels?.close();
  _levels = null;
}
