import 'dart:ui' as ui;
import 'package:camera/camera.dart' show CameraPreview, FlashMode;
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import '../core/l10n.dart';
import '../core/platform_info.dart';
import '../theme/app_theme.dart';
import '../providers/message_composer.dart';
import '../services/api_service.dart' show errorMessage;
import '../services/camera_service.dart';
import '../services/clipboard_paste_web.dart' if (dart.library.io) '../services/clipboard_paste_native.dart';
import '../services/file_drop_web.dart' if (dart.library.io) '../services/file_drop_native.dart';
import '../services/video_note_camera_service.dart';
import 'glitch_pressable.dart';
import 'glitch_toast.dart';
import 'mic_button.dart';
import 'record_lock_indicator.dart';
import 'recording_chip.dart';
import 'theme_workspace.dart';
import 'glitch_icon_button.dart';
import 'video_note_player.dart' show VideoNoteRingPainter;

class ComposerInputBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final MessageComposer composer;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onAttach;
  final ValueChanged<BuildContext>? onContentPicker;

  final bool contentPickerOpen;
  final bool disableAttachments;
  final bool sending;
  final bool forceSendButton;
  final VoidCallback onSend;

  final KeyEventResult Function(KeyEvent event)? onKey;
  final Future<void> Function() onRecordStart;
  final Future<void> Function() onRecordEnd;
  final Future<void> Function() onRecordCancel;
  final bool allowVideoNote;

  const ComposerInputBar({
    super.key,
    required this.controller,
    this.focusNode,
    required this.composer,
    required this.hintText,
    this.onChanged,
    required this.onAttach,
    this.onContentPicker,
    this.contentPickerOpen = false,
    this.disableAttachments = false,
    this.sending = false,
    this.forceSendButton = false,
    required this.onSend,
    this.onKey,
    required this.onRecordStart,
    required this.onRecordEnd,
    required this.onRecordCancel,
    this.allowVideoNote = false,
  });

  @override
  State<ComposerInputBar> createState() => _ComposerInputBarState();
}

class _ComposerInputBarState extends State<ComposerInputBar> {
  final _micKey = GlobalKey();
  double _dragFraction = 0;
  double _lockFraction = 0;

  static const double _lockIndicatorBottom = 70;

  static const double _barBottomPadding = 14;

  void Function()? _unlistenPaste;

  void Function()? _unlistenDrop;

  OverlayEntry? _dropHintEntry;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onExternalChange);
    widget.composer.addListener(_onExternalChange);
    _unlistenPaste = listenPastedMedia(_onPastedMedia);
    _unlistenDrop = listenFileDrop(_onFilesDropped, _onDragActiveChanged);
  }

  // widget.composer читается в момент вставки, а не запоминается при подписке —
  // иначе после смены композера (didUpdateWidget) вставка уходила бы в старый.
  void _onPastedMedia(List<XFile> files) {
    if (!mounted) return;
    widget.composer.attachPastedMedia(context, files);
  }

  void _onDragActiveChanged(bool active) {
    if (!mounted || widget.disableAttachments) return;
    if (active) {
      _showDropHint();
    } else {
      _hideDropHint();
    }
  }

  void _showDropHint() {
    if (_dropHintEntry != null) return;
    _dropHintEntry = OverlayEntry(builder: (_) => const _DropHintOverlay());
    // rootOverlay: true — та же причина, что и у меню-троеточия
    // (glitch_menu.dart): подсказка обязана лечь поверх ВСЕГО окна, а не в
    // оверлей вложенной навигации панели/колонки каркаса, иначе на широком
    // экране она уедет за границы своей узкой колонки и станет невидимой.
    Overlay.of(context, rootOverlay: true).insert(_dropHintEntry!);
  }

  void _hideDropHint() {
    _dropHintEntry?.remove();
    _dropHintEntry = null;
  }

  void _onFilesDropped(DroppedAttachment attachment) {
    if (!mounted || widget.disableAttachments) return;
    if (attachment.media.isNotEmpty) {
      widget.composer.attachPastedMedia(context, attachment.media);
    } else if (attachment.file != null) {
      final f = attachment.file!;
      widget.composer.stageFile(context, f);
    }
    if (attachment.skipped > 0) {
      GlitchToast.show(
        context,
        context.s.dropFilesSkipped(attachment.skipped),
        type: ToastType.info,
      );
    }
  }

  KeyEventResult _onComposerKey(FocusNode node, KeyEvent event) {
    if (widget.onKey?.call(event) == KeyEventResult.handled) return KeyEventResult.handled;
    if (!hasPointerInput) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.enter && key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) return KeyEventResult.ignored;
    if (widget.controller.value.composing.isValid) return KeyEventResult.ignored;
    widget.onSend();
    return KeyEventResult.handled;
  }

  @override
  void didUpdateWidget(covariant ComposerInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onExternalChange);
      widget.controller.addListener(_onExternalChange);
    }
    if (oldWidget.composer != widget.composer) {
      oldWidget.composer.removeListener(_onExternalChange);
      widget.composer.addListener(_onExternalChange);
    }
  }

  @override
  void dispose() {
    _removePreviewOverlay();
    _hideDropHint();
    _unlistenPaste?.call();
    _unlistenDrop?.call();
    widget.controller.removeListener(_onExternalChange);
    widget.composer.removeListener(_onExternalChange);
    super.dispose();
  }

  void _onExternalChange() {
    if (mounted) setState(() {});
    if (_shouldShowPreview != (_previewEntry != null)) _schedulePreviewSync();
  }

  OverlayEntry? _previewEntry;

  bool get _shouldShowPreview =>
      widget.composer.isRecording && widget.composer.captureMode == CaptureMode.video;

  void _schedulePreviewSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _removePreviewOverlay();
        return;
      }
      if (_shouldShowPreview) {
        if (_previewEntry == null) {
          _previewEntry = OverlayEntry(builder: (_) => _VideoNotePreview(composer: widget.composer));
          Overlay.of(context).insert(_previewEntry!);
        }
      } else {
        _removePreviewOverlay();
      }
    });
  }

  void _removePreviewOverlay() {
    _previewEntry?.remove();
    _previewEntry = null;
  }

  bool get _hasTextOrAttachment =>
      widget.controller.text.trim().isNotEmpty ||
      widget.composer.selectedPhotos.isNotEmpty ||
      widget.composer.pendingFile != null ||
      widget.composer.pendingGeo != null;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, _barBottomPadding),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            children: [
              if (widget.composer.isRecording) ...[
                const SizedBox(width: 4),
                Expanded(child: _buildRecordingHint()),
                const SizedBox(width: 16),
              ] else ...[
                if (widget.onAttach != null)
                  GlitchIconButton(
                    icon: Icon(
                      Icons.attach_file_rounded,
                      color: widget.composer.hasAttachment() ? GlitchColors.accentBlue : GlitchColors.textSecond,
                      size: 24,
                    ),
                    onTap: widget.onAttach,
                  )
                else
                  const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44, maxHeight: 120),
                    decoration: BoxDecoration(
                      color: ThemeWorkspace.surface(context, GlitchColors.bgInput, tint: 0.30),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: ThemeWorkspace.outline(context, GlitchColors.borderCard)),
                    ),
                    padding: EdgeInsets.only(left: 16, right: widget.onContentPicker != null ? 6 : 16, top: 10, bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Focus(
                          canRequestFocus: false,
                          skipTraversal: true,
                          onKeyEvent: _onComposerKey,
                          child: TextField(
                            controller: widget.controller,
                            focusNode: widget.focusNode,
                            maxLines: null,
                            style: TextStyle(color: GlitchColors.textPrimary, fontSize: 15.5),
                            decoration: InputDecoration(
                              hintText: widget.hintText,
                              hintStyle: TextStyle(color: GlitchColors.textHint),
                              border: InputBorder.none,
                              fillColor: Colors.transparent,
                              filled: false,
                              contentPadding: EdgeInsets.zero,
                              isDense: true,
                            ),
                            onChanged: widget.onChanged,
                            textInputAction: TextInputAction.newline,
                            onSubmitted: (_) => widget.onSend(),
                          ),
                          ),
                        ),
                        if (widget.onContentPicker != null)
                          Builder(
                            builder: (button) => GlitchPressable(
                              onTap: () => widget.onContentPicker!(button),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Icon(
                                  widget.contentPickerOpen ? Icons.keyboard_outlined : Icons.emoji_emotions_outlined,
                                  color: GlitchColors.textSecond,
                                  size: 23,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              _buildSendOrMicButton(),
            ],
          ),
          Positioned(
            right: 0,
            bottom: _lockIndicatorBottom,
            child: RecordLockIndicator(
              visible: widget.composer.isRecording && !widget.composer.isRecordingLocked,
              progress: _lockFraction,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSendOrMicButton() {
    if (!widget.composer.canRecord) {
      final hasContent = _hasTextOrAttachment || widget.forceSendButton;
      final canSend = hasContent && !widget.sending;
      return GlitchPressable(
        onTap: canSend ? widget.onSend : null,
        child: Opacity(
          opacity: hasContent ? 1.0 : 0.4,
          child: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: GlitchColors.gradientAccent),
            child: widget.sending
                ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 22),
          ),
        ),
      );
    }

    if ((_hasTextOrAttachment || widget.forceSendButton || widget.disableAttachments)
        && !widget.composer.isRecording) {
      return GlitchPressable(
        onTap: widget.sending ? null : widget.onSend,
        child: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: GlitchColors.gradientAccent),
          child: widget.sending
              ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 22),
        ),
      );
    }
    return MicButton(
      key: _micKey,
      isRecording: widget.composer.isRecording,
      isLocked: widget.composer.isRecordingLocked,
      videoMode: widget.composer.captureMode == CaptureMode.video,
      onQuickTap: widget.allowVideoNote && widget.composer.canRecordVideoNote
          ? widget.composer.toggleCaptureMode
          : null,
      amplitude: widget.composer.normalizedAmplitude,
      onStart: () => widget.onRecordStart(),
      onEnd: () => widget.onRecordEnd(),
      onCancel: () => widget.onRecordCancel(),
      onLock: widget.composer.lockRecording,
      onDragFraction: (f) => setState(() => _dragFraction = f),
      onLockFraction: (f) => setState(() => _lockFraction = f),
    );
  }

  Widget _buildRecordingHint() {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Container(width: 9, height: 9, decoration: const BoxDecoration(shape: BoxShape.circle, color: GlitchColors.error)),
          const SizedBox(width: 8),
          Text(
            widget.composer.recordingTimeLabel,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary),
          ),
          const Spacer(),
          if (widget.composer.isRecordingLocked)
            GlitchPressable(
              key: const ValueKey('recording-cancel'),
              onTap: () => widget.onRecordCancel(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Text(
                  context.s.recordingCancel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: GlitchColors.accentBlue,
                  ),
                ),
              ),
            )
          else
            Opacity(
              key: const ValueKey('recording-slide-hint'),
              opacity: (1.0 - _dragFraction).clamp(0.0, 1.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chevron_left_rounded, color: GlitchColors.textHint, size: 16),
                  Text(context.s.recordingSlideToCancel, style: TextStyle(fontSize: 13, color: GlitchColors.textPrimary)),
                  const SizedBox(width: 8),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _VideoNotePreview extends StatefulWidget {
  final MessageComposer composer;

  const _VideoNotePreview({required this.composer});

  @override
  State<_VideoNotePreview> createState() => _VideoNotePreviewState();
}

class _VideoNotePreviewState extends State<_VideoNotePreview> {
  static const double _widthFactor = 0.78;
  static const double _maxSize = 340;

  final GlobalKey _previewBoundaryKey = GlobalKey();
  ui.Image? _frozenFrame;

  @override
  void initState() {
    super.initState();
    cameraService.addListener(_onCameraChanged);
  }

  @override
  void dispose() {
    cameraService.removeListener(_onCameraChanged);
    _frozenFrame?.dispose();
    super.dispose();
  }

  void _onCameraChanged() {
    if (!mounted) return;
    if (cameraService.isReady && _frozenFrame != null) {
      final stale = _frozenFrame;
      setState(() => _frozenFrame = null);
      stale?.dispose();
    } else {
      setState(() {});
    }
  }

  Future<void> _freezeCurrentFrame() async {
    final boundary = _previewBoundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return;
    try {
      final image = await boundary.toImage(pixelRatio: 1.0);
      if (!mounted) {
        image.dispose();
        return;
      }
      _frozenFrame?.dispose();
      setState(() => _frozenFrame = image);
    } catch (_) {
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = cameraService.controller;
    final ready = cameraService.isReady && controller != null;
    final frozen = _frozenFrame; // локальная копия — устойчива к промоушену null-safety ниже
    final screen = MediaQuery.of(context).size;
    final double size = (screen.width * _widthFactor).clamp(160.0, _maxSize).toDouble();

    return Stack(
      children: [
        IgnorePointer(
          child: Stack(
            children: [
              Positioned.fill(
                child: Center(
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black,
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 24, offset: const Offset(0, 8)),
                      ],
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: RepaintBoundary(
                            key: _previewBoundaryKey,
                            child: ClipOval(
                              child: ready
                                  ? FittedBox(
                                      fit: BoxFit.cover,
                                      child: SizedBox(
                                        width: controller.value.previewSize!.height,
                                        height: controller.value.previewSize!.width,
                                        child: CameraPreview(controller),
                                      ),
                                    )
                                  : (frozen != null
                                      ? ImageFiltered(
                                          imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                                          child: RawImage(image: frozen, fit: BoxFit.cover),
                                        )
                                      : const Center(
                                          child: SizedBox(
                                            width: 26, height: 26,
                                            child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
                                          ),
                                        )),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: AnimatedBuilder(
                            animation: widget.composer,
                            builder: (_, __) {
                              final double elapsed = widget.composer.recordingDuration.inMilliseconds / 1000.0;
                              final double progress = (elapsed / videoNoteMaxSeconds).clamp(0.0, 1.0).toDouble();
                              return CustomPaint(
                                painter: VideoNoteRingPainter(
                                  progress: progress,
                                  color: Colors.white,
                                  trackColor: Colors.white.withOpacity(0.22),
                                  stroke: 4,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: 12,
          bottom: _ComposerInputBarState._lockIndicatorBottom +
              _ComposerInputBarState._barBottomPadding +
              MediaQuery.of(context).padding.bottom,
          child: _CaptureControls(composer: widget.composer, onBeforeFlip: _freezeCurrentFrame),
        ),
      ],
    );
  }
}

class _CaptureControls extends StatefulWidget {
  final MessageComposer composer;
  final Future<void> Function() onBeforeFlip;

  const _CaptureControls({required this.composer, required this.onBeforeFlip});

  @override
  State<_CaptureControls> createState() => _CaptureControlsState();
}

class _CaptureControlsState extends State<_CaptureControls> {
  @override
  void initState() {
    super.initState();
    cameraService.addListener(_onCameraChanged);
  }

  @override
  void dispose() {
    cameraService.removeListener(_onCameraChanged);
    super.dispose();
  }

  void _onCameraChanged() {
    if (mounted) setState(() {});
  }

  bool get _torchOn => cameraService.flashMode == FlashMode.torch;

  IconData get _flashIcon => _torchOn ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded;

  Future<void> _toggleFlash() async {
    if (!cameraService.hasFlash) return;
    try {
      await cameraService.setFlashMode(_torchOn ? FlashMode.off : FlashMode.torch);
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canFlip = cameraService.canToggleCamera;
    final showFlash = cameraService.hasFlash;
    if (!canFlip && !showFlash) return const SizedBox.shrink();

    return RecordingChip(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canFlip)
            _button(
              icon: Icons.flip_camera_ios_rounded,
              color: GlitchColors.textSecond,
              onTap: () async {
                await widget.onBeforeFlip();
                await cameraService.toggleCamera();
                await videoNoteCamera.remember(cameraService.currentLens);
              },
            ),
          if (showFlash)
            _button(
              icon: _flashIcon,
              color: _torchOn ? GlitchColors.accentBlue : GlitchColors.textSecond,
              onTap: _toggleFlash,
            ),
        ],
      ),
    );
  }

  Widget _button({required IconData icon, required Color color, VoidCallback? onTap}) => GlitchPressable(
        onTap: onTap,
        child: SizedBox(
          width: RecordingChip.slotWidth,
          height: RecordingChip.height,
          child: Icon(icon, color: color, size: 22),
        ),
      );
}

class _DropHintOverlay extends StatelessWidget {
  const _DropHintOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withOpacity(0.55),
          child: const Center(
            child: Icon(Icons.file_upload_outlined, color: Colors.white, size: 72),
          ),
        ),
      ),
    );
  }
}
