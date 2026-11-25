import 'dart:async';
import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import '../core/platform_info.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart' show ResolutionPreset, FlashMode;
import '../models/attach_result.dart';
import '../models/poll.dart' show PollDraft;
import 'composer_drafts.dart';
import '../widgets/attach_open_web.dart' if (dart.library.io) '../widgets/attach_open_native.dart';
import '../services/camera_service.dart';
import 'call_provider.dart' show callProvider;
import '../services/video_note_camera_service.dart';
import '../services/media_service.dart';
import '../services/upload_limits.dart';
import '../core/l10n.dart';
import '../widgets/glitch_toast.dart';
import '../services/media_platform_web.dart' if (dart.library.io) '../services/media_platform_native.dart';
import '../services/voice_recorder_web.dart' if (dart.library.io) '../services/voice_recorder_native.dart';
import '../theme/app_theme.dart';
import '../widgets/voice_message_player.dart' show kVoiceWaveformBars;

class PendingVoice {
  final XFile file;
  final double duration; // секунды
  final List<double> waveform; // kVoiceWaveformBars значений 0..1
  PendingVoice({required this.file, required this.duration, this.waveform = const []});
}

class PendingVideoNote {
  final XFile file;
  final XFile thumb;
  final double duration; // секунды
  PendingVideoNote({required this.file, required this.thumb, required this.duration});
}

enum CaptureMode { voice, video }

/// Предел длительности кружка. Должен совпадать с MAX_VIDEO_NOTE_SECONDS на
/// бэкенде (app/core/upload_constants.py): сервер проверяет длительность из
/// присланного JSON и отклонит запись, которая длиннее.
const int videoNoteMaxSeconds = 60;

const ResolutionPreset videoNotePreset = ResolutionPreset.medium;

class MessageComposer extends ChangeNotifier {
  List<XFile> selectedPhotos = [];
  Map<String, int> videoDurations = {};
  PendingFile? pendingFile;
  GeoResult? pendingGeo;

  CaptureMode captureMode = CaptureMode.voice;

  /// До 2026-08-29 в браузере было «нет» — запись умела только писать в файл по
  /// пути, которого в браузере не существует. Теперь у веба своя половина пары
  /// (voice_recorder_web.dart, MediaRecorder), и ответ даёт она: «да» во всех
  /// браузерах, которые пишут звук в MP4/AAC — том же формате, что и телефон.
  /// Firefox так не умеет, и там ответ по-прежнему «нет» (подробный разбор — в
  /// шапке voice_recorder_web.dart).
  bool get canRecord => voiceRecordingSupported;

  bool get canRecordVideoNote => hasFileSystem && !callProvider.cameraOn;

  Future<void> toggleCaptureMode() async {
    if (isRecording) return; // посреди записи режим не меняем
    _cancelToken++;
    captureMode = captureMode == CaptureMode.voice ? CaptureMode.video : CaptureMode.voice;
    notifyListeners();
    if (captureMode == CaptureMode.video) {
      await cameraService.setPreset(videoNotePreset);
      await cameraService.selectLens(videoNoteCamera.current);
      if (_disposed) return;
      await cameraService.acquire();
      if (_disposed) await cameraService.release();
    } else {
      await cameraService.release();
    }
    if (!_disposed) notifyListeners();
  }

  bool isRecording = false;
  bool isRecordingLocked = false;
  bool _stopping = false;
  int _cancelToken = 0;
  Duration recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  DateTime? _recordingStart;
  double recordingDecibels = -50.0;
  StreamSubscription<double>? _amplitudeSub;
  final List<double> _rawAmplitudes = [];
  static const _maxRawAmplitudeSamples = 20000;
  static const _ampWarmupTicks = 4;
  int _ampWarmupTicksLeft = _ampWarmupTicks;

  final Map<int, double> uploadProgress = {};
  final Map<int, (int, int)> uploadBytes = {};

  bool _disposed = false;

  Future<PollDraft?> openAttach(BuildContext context, {required bool allowFiles, required bool allowPoll}) async {
    final result = await showAttachPicker(context, allowFiles: allowFiles, allowPoll: allowPoll);
    if (_disposed) return null;
    if (result == null) return null;

    if (result is PollResult) return result.draft;
    if (result is FileResult) {
      if (context.mounted) await stageFile(context, result.file);
      return null;
    }
    if (result is PhotosResult && result.files.isNotEmpty) {
      if (context.mounted) _stagePhotos(context, result.files, durations: result.durations);
      return null;
    }
    if (result is GeoResult) {
      pendingGeo = result;
      selectedPhotos = [];
      videoDurations = {};
      pendingFile = null;
    }
    notifyListeners();
    return null;
  }


  Future<bool> startRecording() async {
    if (isRecording) return false;
    final token = _cancelToken;
    final granted = await requestMicPermission();
    if (_disposed || token != _cancelToken) {
      await cancelVoiceCapture();
      return false;
    }
    if (!granted) return false;

    _recordingStart = DateTime.now();
    recordingDuration = Duration.zero;
    isRecordingLocked = false;
    _rawAmplitudes.clear();
    _ampWarmupTicksLeft = _ampWarmupTicks;

    if (!await startVoiceCapture()) return false;
    if (_disposed || token != _cancelToken) {
      await cancelVoiceCapture();
      return false;
    }

    _amplitudeSub = voiceAmplitudeStream?.listen((db) {
      if (_ampWarmupTicksLeft > 0) {
        _ampWarmupTicksLeft--;
      } else {
        recordingDecibels = db;
        if (_rawAmplitudes.length < _maxRawAmplitudeSamples) {
          _rawAmplitudes.add(db);
        }
      }
      notifyListeners();
    });

    _recordingTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      recordingDuration = DateTime.now().difference(_recordingStart!);
      notifyListeners();
    });

    isRecording = true;
    notifyListeners();
    return true;
  }


  Timer? _videoLimitTimer;
  VoidCallback? onVideoNoteLimit;

  Future<bool> startVideoNote() async {
    if (isRecording) return false;
    final token = _cancelToken;
    // acquire идемпотентен: обычно камера уже прогрета из toggleCaptureMode,
    // но режим могли включить и до выдачи разрешения.
    // Тот же порядок, что в toggleCaptureMode: сначала параметры, потом подъём.
    // Оба вызова идемпотентны — обычно всё уже сделано при переключении режима,
    // и контроллер не пересобирается. Нужны на случай, когда режим включили
    // раньше, чем пользователь выдал разрешение на камеру.
    await cameraService.setPreset(videoNotePreset);
    await cameraService.selectLens(videoNoteCamera.current);
    if (_disposed || token != _cancelToken) return false;
    await cameraService.acquire();
    if (_disposed || token != _cancelToken || !cameraService.isReady) return false;

    try {
      await cameraService.startVideoRecording();
    } catch (_) {
      return false;
    }
    if (_disposed || token != _cancelToken) {
      try {
        final x = await cameraService.stopVideoRecording();
        await deleteTempFile(x);
      } catch (_) {}
      return false;
    }

    _recordingStart = DateTime.now();
    recordingDuration = Duration.zero;
    isRecording = true;
    isRecordingLocked = false;
    _recordingTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      recordingDuration = DateTime.now().difference(_recordingStart!);
      notifyListeners();
    });
    _videoLimitTimer = Timer(
      const Duration(seconds: videoNoteMaxSeconds),
      () { if (!_disposed) onVideoNoteLimit?.call(); },
    );
    notifyListeners();
    return true;
  }

  Future<PendingVideoNote?> stopVideoNote() async {
    if (_stopping || !isRecording) return null;
    _stopping = true;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _videoLimitTimer?.cancel();
    _videoLimitTimer = null;

    try {
      final xfile = await cameraService.stopVideoRecording();
      await _turnOffFlashAfterRecording();
      final duration = recordingDuration.inMilliseconds / 1000.0;

      isRecording = false;
      isRecordingLocked = false;
      recordingDuration = Duration.zero;
      _recordingStart = null;
      if (!_disposed) notifyListeners();

      final raw = xfile;   // плагин камеры и так отдаёт нужный тип
      int rawSize;
      try {
        rawSize = await raw.length();
      } catch (_) {
        return null;   // файла нет — как раньше давал exists() == false
      }
      if (rawSize == 0) return null;
      if (duration < 0.5) {
        await deleteTempFile(raw);
        return null;
      }

      final file = raw;
      final Uint8List? data = await videoFrameBytes(file, maxWidth: 480, quality: 70);
      if (data == null) {
        await deleteTempFile(file);
        return null;
      }
      final thumb = await saveTempBytes(data, 'note_${DateTime.now().millisecondsSinceEpoch}.jpg');
      if (thumb == null) {
        await deleteTempFile(file);
        return null;
      }

      return PendingVideoNote(file: file, thumb: thumb, duration: duration);
    } catch (_) {
      // _turnOffFlashAfterRecording ещё раз, на случай если само
      // stopVideoRecording() и бросило исключение (тогда строка 361 не
      // выполнилась, а свет мог остаться гореть) — идемпотентно, лишний
      // вызов при уже потушенной вспышке ничего не делает.
      await _turnOffFlashAfterRecording();
      isRecording = false;
      isRecordingLocked = false;
      recordingDuration = Duration.zero;
      _recordingStart = null;
      if (!_disposed) notifyListeners();
      return null;
    } finally {
      _stopping = false;
    }
  }

  Future<void> _turnOffFlashAfterRecording() async {
    if (cameraService.flashMode != FlashMode.off) {
      await cameraService.setFlashMode(FlashMode.off);
    }
  }

  // Уборка камеры после закрытия экрана. Отдельным методом, потому что dispose
  // синхронный, а тут нужны два await подряд: сначала корректно остановить
  // запись (иначе камера продолжит писать в файл, который уже никто не заберёт),
  // потом отпустить контроллер.
  Future<void> _releaseCameraOnDispose() async {
    try {
      if (isRecording) {
        final x = await cameraService.stopVideoRecording();
        await deleteTempFile(x);
      }
    } catch (_) {}
    await cameraService.release();
  }

  Future<void> cancelVideoNote() async {
    _cancelToken++; // см. поле: обрывает старт, который ещё не завершился
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _videoLimitTimer?.cancel();
    _videoLimitTimer = null;

    try {
      final xfile = await cameraService.stopVideoRecording();
      await deleteTempFile(xfile);
    } catch (_) {}
    await _turnOffFlashAfterRecording();

    isRecording = false;
    isRecordingLocked = false;
    recordingDuration = Duration.zero;
    _recordingStart = null;
    if (!_disposed) notifyListeners();
  }

  void lockRecording() {
    if (!isRecording || isRecordingLocked) return;
    isRecordingLocked = true;
    notifyListeners();
  }

  Future<PendingVoice?> stopRecording() async {
    if (_stopping || !isRecording) return null;
    _stopping = true;

    _recordingTimer?.cancel();
    _recordingTimer = null;
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    recordingDecibels = -50.0;

    try {
      final file = await stopVoiceCapture();
      final duration = recordingDuration.inMilliseconds / 1000.0;

      isRecording = false;
      isRecordingLocked = false;
      recordingDuration = Duration.zero;
      _recordingStart = null;
      if (!_disposed) notifyListeners();

      if (file == null) return null;
      int size;
      try {
        size = await file.length();
      } catch (_) {
        return null;   // файла нет — то же, что раньше давал exists() == false
      }
      if (size == 0) return null;
      if (duration < 0.5) {
        await deleteTempFile(file);
        return null;
      }
      final waveform = _normalizeToRange(_resampleRaw(_rawAmplitudes, kVoiceWaveformBars));
      _rawAmplitudes.clear();
      return PendingVoice(file: file, duration: duration, waveform: waveform);
    } catch (_) {
      isRecording = false;
      isRecordingLocked = false;
      recordingDuration = Duration.zero;
      _recordingStart = null;
      if (!_disposed) notifyListeners();
      return null;
    } finally {
      _stopping = false;
    }
  }

  Future<void> cancelRecording() async {
    _cancelToken++; // см. поле: обрывает старт, который ещё не завершился
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    recordingDecibels = -50.0;
    _rawAmplitudes.clear();

    await cancelVoiceCapture();

    isRecording = false;
    isRecordingLocked = false;
    recordingDuration = Duration.zero;
    _recordingStart = null;
    if (!_disposed) notifyListeners();
  }

  void _stagePhotos(BuildContext context, List<XFile> files,
      {Map<String, int> durations = const {}, bool append = false}) {
    if (_disposed) return;
    var next = append ? [...selectedPhotos, ...files] : List<XFile>.of(files);
    final max = uploadLimits.maxAttachments;
    if (max != null && next.length > max) {
      next = next.take(max).toList();
      GlitchToast.show(context, context.s.attachTooMany(max));
    }
    selectedPhotos = next;
    videoDurations = {
      if (append) ...videoDurations,
      for (final f in next)
        if (durations[f.path] != null) f.path: durations[f.path]!,
    };
    pendingFile = null;
    pendingGeo = null;
    notifyListeners();
  }

  void stageSharedPhotos(BuildContext context, List<XFile> files) => _stagePhotos(context, files);

  void attachPastedMedia(BuildContext context, List<XFile> files) {
    if (files.isEmpty) return;
    _stagePhotos(context, files, append: true);
  }

  Future<void> stageFile(BuildContext context, PendingFile file) async {
    try {
      await uploadLimits.ensureFits(UploadKind.file, await file.file.length());
    } on UploadTooLarge catch (e) {
      if (context.mounted) GlitchToast.show(context, e.describe(context.s));
      return;
    }
    if (_disposed) return;
    pendingFile = file;
    selectedPhotos = [];
    videoDurations = {};
    pendingGeo = null;
    notifyListeners();
  }

  void clearAttachments() {
    selectedPhotos = [];
    videoDurations = {};
    pendingFile = null;
    pendingGeo = null;
    notifyListeners();
  }

  void removePhoto(int index) {
    selectedPhotos = List.from(selectedPhotos)..removeAt(index);
    notifyListeners();
  }

  void setProgress(int tempId, int sent, int total) {
    if (_disposed) return;
    final int clampedSent = total > 0 ? sent.clamp(0, total).toInt() : sent;
    uploadProgress[tempId] = total > 0 ? clampedSent / total : 0;
    uploadBytes[tempId] = (clampedSent, total);
    notifyListeners();
  }

  void clearProgress(int tempId) {
    if (_disposed) return;
    uploadProgress.remove(tempId);
    uploadBytes.remove(tempId);
    notifyListeners();
  }

  void restoreAttachments(String key) {
    final d = composerDrafts.of(key);
    selectedPhotos = d.photos;
    videoDurations = d.videoDurations;
    pendingFile = d.file;
    pendingGeo = d.geo;
  }

  void stashAttachments(String key) => composerDrafts.put(key, AttachmentDraft(
        photos: selectedPhotos,
        videoDurations: videoDurations,
        file: pendingFile,
        geo: pendingGeo,
      ));

  bool hasAttachment() =>
      selectedPhotos.isNotEmpty || pendingFile != null || pendingGeo != null;

  bool isVideo(XFile f) => mediaService.isVideo(f);
  String mimeType(XFile f) => mediaService.mimeType(f);

  String get recordingTimeLabel {
    final ms = recordingDuration.inMilliseconds;
    final totalSeconds = ms ~/ 1000;
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    final d = (ms % 1000) ~/ 100; // десятые доли секунды
    return '$m:${s.toString().padLeft(2, '0')},$d';
  }

  double get normalizedAmplitude {
    if (_rawAmplitudes.isEmpty) return 0.0;
    final min = _rawAmplitudes.reduce((a, b) => a < b ? a : b);
    final max = _rawAmplitudes.reduce((a, b) => a > b ? a : b);
    if (max - min < 3.0) return 0.5;
    return ((recordingDecibels - min) / (max - min)).clamp(0.0, 1.0);
  }

  List<double> _resampleRaw(List<double> raw, int targetCount) {
    if (raw.isEmpty) return const [];
    final result = <double>[];
    for (int i = 0; i < targetCount; i++) {
      final start = (i * raw.length / targetCount).floor();
      final end = ((i + 1) * raw.length / targetCount).floor().clamp(start + 1, raw.length);
      final slice = raw.sublist(start, end);
      result.add(slice.reduce((a, b) => a + b) / slice.length);
    }
    return result;
  }

  List<double> _normalizeToRange(List<double> dbValues) {
    if (dbValues.isEmpty) return const [];
    final min = dbValues.reduce((a, b) => a < b ? a : b);
    final max = dbValues.reduce((a, b) => a > b ? a : b);
    if (max - min < 1.0) {
      return List<double>.filled(dbValues.length, 0.5);
    }
    return dbValues
        .map((db) => double.parse(((db - min) / (max - min)).clamp(0.0, 1.0).toStringAsFixed(2)))
        .toList();
  }

  @override
  void dispose() {
    _disposed = true;
    _recordingTimer?.cancel();
    _videoLimitTimer?.cancel();
    _amplitudeSub?.cancel();
    // Камера удерживается ref-count'ом, пока включён режим кружка — экран
    // могли закрыть прямо в нём (в том числе посреди записи «на замке»).
    // Не отпустив её здесь, мы навсегда оставили бы занятый контроллер.
    // Без await: dispose синхронный, ждать результата всё равно некому.
    if (captureMode == CaptureMode.video) _releaseCameraOnDispose();
    // Экран закрыли посреди записи — с «замком» это штатный сценарий, а не
    // экзотика: палец кнопку больше не держит, и системная «назад» означает
    // «отменить запись и выйти». Раньше запись просто обрывалась вместе с
    // рекордером, а недописанный временный файл оставался в кэше навсегда.
    // Останов, уборка недописанного файла и закрытие сессии записи — всё
    // внутри пары; без await, потому что dispose синхронный и ждать здесь
    // результата всё равно некому.
    //
    // Условие — не перестраховка. «Мотор» записи ОДИН на всё приложение, а
    // композеров одновременно живёт столько, сколько открыто экранов со строкой
    // ввода (в широкой раскладке это сразу несколько). Отпускаем его, только
    // если пишем мы сами или не пишет никто; идёт чужая запись «на замке» —
    // закрытие соседнего экрана её не трогает.
    if (isRecording || !voiceCaptureActive) releaseVoiceCapture();
    super.dispose();
  }
}
