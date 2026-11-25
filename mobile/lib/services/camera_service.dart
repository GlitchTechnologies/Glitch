import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';

enum CameraServiceState { idle, initializing, ready, permissionDenied, error }

class CameraService extends ChangeNotifier with WidgetsBindingObserver {
  CameraService._();
  static final CameraService instance = CameraService._();

  CameraController? controller;
  CameraServiceState state = CameraServiceState.idle;
  String? errorMessage;

  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  int _refCount = 0;
  bool _observerRegistered = false;
  bool _initInFlight = false;
  FlashMode _flashMode = FlashMode.off;

  bool _switching = false;

  bool get isReady =>
      state == CameraServiceState.ready &&
      controller != null &&
      controller!.value.isInitialized &&
      !_switching;
  bool get canToggleCamera => _cameras.length > 1;
  FlashMode get flashMode => _flashMode;
  bool get hasFlash => _cameras.isNotEmpty && _cameras[_effectiveIndex].lensDirection == CameraLensDirection.back;

  // Идемпотентно — можно смело звать и из плашки, и из экрана съёмки: если
  // камера уже готова (или готовится) прямо сейчас, повторная инициализация не идёт.
  Future<void> acquire() async {
    _refCount++;
    if (_refCount == 1) {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
    if (!_observerRegistered) {
      WidgetsBinding.instance.addObserver(this);
      _observerRegistered = true;
    }
    if (isReady || state == CameraServiceState.initializing) return;
    await _init();
  }

  Future<void> release() async {
    if (_refCount > 0) _refCount--;
    if (_refCount == 0) {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      _preset = _defaultPreset;
      _desiredLens = null;
      _flashMode = FlashMode.off;
      await _teardown(keepRefCount: false);
    }
  }

  Future<void> toggleCamera() async {
    if (_cameras.length < 2) return;
    final next = (_effectiveIndex + 1) % _cameras.length;
    _desiredLens = null;
    _cameraIndex = next;

    final c = controller;
    if (c != null && c.value.isInitialized) {
      _switching = true;
      notifyListeners(); // потребители сразу показывают заглушку вместо кадра
      final sizeBefore = c.value.previewSize;
      try {
        await c.setDescription(_cameras[next]);
        try { await c.setFlashMode(_flashMode); } catch (_) {}
        final deadline = DateTime.now().add(const Duration(milliseconds: 700));
        while (c.value.previewSize == sizeBefore && DateTime.now().isBefore(deadline)) {
          await Future.delayed(const Duration(milliseconds: 16)); // ~кадр
        }
        await Future.delayed(const Duration(milliseconds: 80));
        return;
      } catch (_) {
      } finally {
        _switching = false;
        notifyListeners();
      }
    }
    await _teardown(keepRefCount: true);
    await _init();
  }

  static const ResolutionPreset _defaultPreset = ResolutionPreset.high;
  ResolutionPreset _preset = _defaultPreset;

  Future<void> setPreset(ResolutionPreset preset) async {
    if (_preset == preset) return;
    _preset = preset;
    if (controller == null && state != CameraServiceState.initializing) return;
    await _teardown(keepRefCount: true);
    await _init();
  }

  CameraLensDirection? _desiredLens;

  int get _effectiveIndex {
    if (_desiredLens != null) {
      final i = _cameras.indexWhere((c) => c.lensDirection == _desiredLens);
      if (i >= 0) return i;
    }
    return _cameraIndex.clamp(0, _cameras.length - 1);
  }

  CameraLensDirection? get currentLens =>
      _cameras.isEmpty ? null : _cameras[_effectiveIndex].lensDirection;

  Future<void> selectLens(CameraLensDirection? dir) async {
    if (_desiredLens == dir) return;
    final before = currentLens;
    _desiredLens = dir;
    if (controller == null && state != CameraServiceState.initializing) return;
    if (currentLens == before) return;
    await _teardown(keepRefCount: true);
    await _init();
  }

  Future<XFile> takePicture() async {
    if (!isReady) throw StateError('Камера не готова');
    return controller!.takePicture();
  }

  Future<void> startVideoRecording() async {
    if (!isReady) throw StateError('Камера не готова');
    await Permission.microphone.request();
    await controller!.startVideoRecording();
  }

  Future<XFile> stopVideoRecording() async {
    if (!isReady) throw StateError('Камера не готова');
    return controller!.stopVideoRecording();
  }

  Future<double> getMinZoomLevel() async {
    if (!isReady) throw StateError('Камера не готова');
    return controller!.getMinZoomLevel();
  }

  Future<double> getMaxZoomLevel() async {
    if (!isReady) throw StateError('Камера не готова');
    return controller!.getMaxZoomLevel();
  }

  Future<void> setZoomLevel(double zoom) async {
    if (!isReady) return; // best effort — во время быстрого пинча камера могла успеть переинициализироваться
    await controller!.setZoomLevel(zoom);
  }

  Future<void> setFlashMode(FlashMode mode) async {
    if (isReady) await controller!.setFlashMode(mode);
    _flashMode = mode;
    notifyListeners();
  }

  Future<void> _init() async {
    if (_initInFlight) return;
    _initInFlight = true;
    state = CameraServiceState.initializing;
    errorMessage = null;
    notifyListeners();
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        state = CameraServiceState.permissionDenied;
        notifyListeners();
        return;
      }
      if (_cameras.isEmpty) {
        final all = await availableCameras();
        final seen = <CameraLensDirection>{};
        _cameras = [for (final c in all) if (seen.add(c.lensDirection)) c];
      }
      if (_cameras.isEmpty) {
        state = CameraServiceState.error;
        errorMessage = 'Камера не найдена';
        notifyListeners();
        return;
      }
      final desc = _cameras[_effectiveIndex];
      final c = CameraController(desc, _preset, enableAudio: true);
      await c.initialize();
      if (_refCount == 0) {
        try { await c.dispose(); } catch (_) {}
        state = CameraServiceState.idle;
        return;
      }
      final stale = controller;
      controller = c;
      if (stale != null && !identical(stale, c)) {
        try { await stale.dispose(); } catch (_) {}
      }
      state = CameraServiceState.ready;
      if (desc.lensDirection == CameraLensDirection.back) {
        try { await c.setFlashMode(_flashMode); } catch (_) {}
      }
    } catch (e) {
      state = CameraServiceState.error;
      errorMessage = e.toString();
    } finally {
      _initInFlight = false;
    }
    notifyListeners();
  }

  Future<void> _teardown({required bool keepRefCount}) async {
    final c = controller;
    controller = null;
    state = CameraServiceState.idle;
    if (!keepRefCount) {
      _refCount = 0;
      if (_observerRegistered) {
        WidgetsBinding.instance.removeObserver(this);
        _observerRegistered = false;
      }
    }
    notifyListeners();
    if (c != null) {
      try { await c.dispose(); } catch (_) {}
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.paused || lifecycleState == AppLifecycleState.inactive) {
      if (controller != null) _teardown(keepRefCount: true);
    } else if (lifecycleState == AppLifecycleState.resumed) {
      if (_refCount > 0 && controller == null) _init();
    }
  }
}

final cameraService = CameraService.instance;
