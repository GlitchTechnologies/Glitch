import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/l10n.dart';
import '../services/api_service.dart';
import '../services/camera_service.dart';
import '../widgets/glitch_toast.dart';
import '../widgets/glitch_icon_button.dart';

class CameraCaptureResult {
  // XFile, а не File: тип, понятный обеим платформам. Плагин камеры и так
  // отдаёт именно его — раньше код заворачивал результат во File и терял
  // совместимость с браузером.
  final XFile file;
  final bool isVideo;
  final int? durationSeconds; // только для видео
  const CameraCaptureResult({required this.file, required this.isVideo, this.durationSeconds});
}

class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  static const _maxVideoSeconds = 60;

  bool _recording = false;
  bool _busy = false; // идёт съёмка фото / остановка видео — блокируем повторный тап
  bool _stopRequested = false;
  DateTime? _recordStart;
  int _elapsedSeconds = 0;
  Timer? _tickTimer;
  Timer? _maxDurationTimer;

  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _zoom = 1.0;
  double _baseZoom = 1.0;

  @override
  void initState() {
    super.initState();
    cameraService.addListener(_onCameraChange);
    cameraService.acquire();
  }

  @override
  void dispose() {
    cameraService.removeListener(_onCameraChange);
    _tickTimer?.cancel();
    _maxDurationTimer?.cancel();
    if (_zoom != _minZoom) cameraService.setZoomLevel(_minZoom).catchError((_) {});
    cameraService.release();
    super.dispose();
  }

  void _onCameraChange() {
    if (!mounted) return;
    setState(() {});
    if (cameraService.isReady) _loadZoomRange();
  }

  Future<void> _loadZoomRange() async {
    try {
      final min = await cameraService.getMinZoomLevel();
      final max = await cameraService.getMaxZoomLevel();
      if (!mounted) return;
      setState(() { _minZoom = min; _maxZoom = max; _zoom = min; });
    } catch (_) {}
  }

  void _onScaleStart(ScaleStartDetails details) {
    _baseZoom = _zoom;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2 || _maxZoom <= _minZoom) return;
    final newZoom = (_baseZoom * details.scale).clamp(_minZoom, _maxZoom);
    if (newZoom == _zoom) return;
    _zoom = newZoom;
    cameraService.setZoomLevel(newZoom);
  }

  Future<void> _onTap() async {
    if (_busy || _recording || !cameraService.isReady) return;
    setState(() => _busy = true);
    try {
      final xfile = await cameraService.takePicture();
      if (!mounted) return;
      Navigator.pop(context, CameraCaptureResult(file: xfile, isVideo: false));
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        GlitchToast.show(context, errorMessage(e));
      }
    }
  }

  Future<void> _onLongPressStart(LongPressStartDetails details) async {
    if (_busy || _recording || !cameraService.isReady) return;
    _stopRequested = false;
    try {
      await cameraService.startVideoRecording();
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
      return;
    }
    if (!mounted) return;
    _recordStart = DateTime.now();
    setState(() { _recording = true; _elapsedSeconds = 0; });
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
    _maxDurationTimer = Timer(const Duration(seconds: _maxVideoSeconds), _stopRecording);
    if (_stopRequested) _stopRecording();
  }

  static const _flashOrder = [FlashMode.off, FlashMode.always, FlashMode.torch];

  IconData _flashIcon(FlashMode mode) => switch (mode) {
        FlashMode.off => Icons.flash_off_rounded,
        FlashMode.always => Icons.flash_on_rounded,
        FlashMode.torch => Icons.flashlight_on_rounded,
        FlashMode.auto => Icons.flash_auto_rounded,
      };

  Future<void> _onToggleFlash() async {
    if (_recording || !cameraService.hasFlash) return;
    final idx = _flashOrder.indexOf(cameraService.flashMode);
    final next = _flashOrder[(idx + 1) % _flashOrder.length];
    try {
      await cameraService.setFlashMode(next);
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    }
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    _stopRequested = true;
    _stopRecording();
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    _stopRequested = false;
    _tickTimer?.cancel();
    _maxDurationTimer?.cancel();
    final secs = _recordStart != null ? DateTime.now().difference(_recordStart!).inSeconds : _elapsedSeconds;
    setState(() { _recording = false; _busy = true; });
    try {
      final xfile = await cameraService.stopVideoRecording();
      if (!mounted) return;
      Navigator.pop(context, CameraCaptureResult(file: xfile, isVideo: true, durationSeconds: secs));
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        GlitchToast.show(context, errorMessage(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              key: const ValueKey('preview'),
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              child: _buildPreview(),
            ),
            Positioned(
              key: const ValueKey('close'),
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              child: GlitchIconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onTap: () => Navigator.pop(context),
              ),
            ),
            if (cameraService.canToggleCamera)
              Positioned(
                key: const ValueKey('flip'),
                top: MediaQuery.of(context).padding.top + 8,
                right: 8,
                child: GlitchIconButton(
                  icon: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white),
                  onTap: _recording ? null : cameraService.toggleCamera,
                ),
              ),
            if (cameraService.hasFlash)
              Positioned(
                key: const ValueKey('flash'),
                top: MediaQuery.of(context).padding.top + 8,
                right: cameraService.canToggleCamera ? 56 : 8,
                child: GlitchIconButton(
                  icon: Icon(_flashIcon(cameraService.flashMode), color: Colors.white),
                  onTap: _recording ? null : _onToggleFlash,
                ),
              ),
            if (_recording)
              Positioned(
                key: const ValueKey('badge'),
                top: MediaQuery.of(context).padding.top + 12,
                left: 0, right: 0,
                child: Center(child: _RecordingBadge(seconds: _elapsedSeconds)),
              ),
            Positioned(
              key: const ValueKey('shutter'),
              bottom: 36, left: 0, right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _onTap,
                  onLongPressStart: _onLongPressStart,
                  onLongPressEnd: _onLongPressEnd,
                  child: _ShutterButton(recording: _recording),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    if (cameraService.isReady) {
      final controller = cameraService.controller!;
      final size = controller.value.previewSize!;
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: size.height,
            height: size.width,
            child: CameraPreview(controller),
          ),
        ),
      );
    }
    if (cameraService.state == CameraServiceState.permissionDenied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            context.s.cameraPermissionDenied,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (cameraService.state == CameraServiceState.error) {
      return const Center(child: Icon(Icons.error_outline_rounded, color: Colors.white38, size: 40));
    }
    return const Center(child: CircularProgressIndicator(color: Colors.white54));
  }
}

class _ShutterButton extends StatefulWidget {
  final bool recording;
  const _ShutterButton({required this.recording});

  @override
  State<_ShutterButton> createState() => _ShutterButtonState();
}

class _ShutterButtonState extends State<_ShutterButton> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween<double>(begin: 1.0, end: 0.96).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _opacity = Tween<double>(begin: 1.0, end: 0.85).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _ctrl.forward(),
      onPointerUp: (_) => _ctrl.reverse(),
      onPointerCancel: (_) => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) => Transform.scale(
          scale: _scale.value,
          child: Opacity(opacity: _opacity.value, child: child),
        ),
        child: Container(
          width: 72, height: 72,
          padding: const EdgeInsets.all(4),
          decoration: const BoxDecoration(shape: BoxShape.circle, border: Border.fromBorderSide(BorderSide(color: Colors.white, width: 3))),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: widget.recording ? Colors.redAccent : Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordingBadge extends StatelessWidget {
  final int seconds;
  const _RecordingBadge({required this.seconds});

  String get _label {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(14)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(_label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
