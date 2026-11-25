import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import 'glitch_pressable.dart';

enum _DragAxis { horizontal, vertical }

class MicButton extends StatefulWidget {
  final bool isRecording;
  final bool isLocked;
  final bool videoMode;
  final double amplitude; // 0.0..1.0 — нормализованная громкость
  final VoidCallback onStart;
  final VoidCallback onEnd;
  final VoidCallback onCancel;
  final VoidCallback onLock;
  final VoidCallback? onQuickTap;
  final ValueChanged<double>? onDragFraction;
  final ValueChanged<double>? onLockFraction;

  const MicButton({
    super.key,
    required this.isRecording,
    this.isLocked = false,
    this.videoMode = false,
    required this.onStart,
    required this.onEnd,
    required this.onCancel,
    required this.onLock,
    this.onQuickTap,
    this.amplitude = 0.0,
    this.onDragFraction,
    this.onLockFraction,
  });

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton> with SingleTickerProviderStateMixin {
  int? _pointer;
  Timer? _holdTimer;
  bool _startFired = false;
  double _startX = 0;
  double _startY = 0;
  bool _cancelled = false;
  bool _locked = false;
  _DragAxis? _axis;
  double _dragX = 0;
  double _dragY = 0;

  static const double _cancelThreshold = -80.0;
  static const double _lockThreshold = -72.0;
  static const double _axisSlop = 12.0;
  static const double _axisSwitchRatio = 1.6;
  static const Duration _holdDelay = Duration(milliseconds: 220);
  static const double _baseSize = 44.0;
  static const double _recordingScale = 1.45;
  static const double _minAuraExtra = 18.0;
  static const double _maxAuraExtra = 48.0; // должен совпадать с максимумом auraExtra ниже

  void _resetDrag() {
    setState(() { _dragX = 0; _dragY = 0; });
    widget.onDragFraction?.call(0.0);
    widget.onLockFraction?.call(0.0);
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isRecording && !widget.isRecording) {
      _cancelled = false;
      _locked = false;
      _axis = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auraExtra = widget.isRecording ? _minAuraExtra + widget.amplitude * (_maxAuraExtra - _minAuraExtra) : 0.0;
    final auraOpacity = widget.isRecording ? 0.22 + widget.amplitude * 0.35 : 0.0;

    if (widget.isLocked) {
      return GlitchPressable(
        onTap: widget.onEnd,
        child: _buildButton(auraExtra, auraOpacity),
      );
    }

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        _pointer = e.pointer;
        _startX = e.position.dx;
        _startY = e.position.dy;
        _cancelled = false;
        _locked = false;
        _axis = null;
        _dragX = 0;
        _dragY = 0;

        if (widget.onQuickTap != null) {
          _startFired = false;
          _holdTimer?.cancel();
          _holdTimer = Timer(_holdDelay, () {
            if (!mounted || _pointer == null) return;
            _startFired = true;
            widget.onStart();
          });
        } else {
          _startFired = true;
          widget.onStart();
        }
      },
      onPointerUp: (e) {
        if (e.pointer != _pointer) return;
        _pointer = null;
        _holdTimer?.cancel();
        _holdTimer = null;
        _resetDrag();
        if (_cancelled) return;

        if (!_startFired) {
          widget.onQuickTap?.call();
          return;
        }
        widget.onEnd();
      },
      onPointerMove: (e) {
        if (e.pointer != _pointer || _cancelled || _locked) return;
        if (!_startFired) return;
        final rawDx = e.position.dx - _startX;
        final rawDy = e.position.dy - _startY;

        if (_axis == null) {
          if (rawDx.abs() < _axisSlop && rawDy.abs() < _axisSlop) return;
          _axis = rawDy.abs() > rawDx.abs() ? _DragAxis.vertical : _DragAxis.horizontal;
        } else {
          final switchToHorizontal = _axis == _DragAxis.vertical &&
              rawDx.abs() > rawDy.abs() * _axisSwitchRatio;
          final switchToVertical = _axis == _DragAxis.horizontal &&
              rawDy.abs() > rawDx.abs() * _axisSwitchRatio;
          if (switchToHorizontal || switchToVertical) {
            _axis = switchToHorizontal ? _DragAxis.horizontal : _DragAxis.vertical;
            if (_axis == _DragAxis.horizontal) {
              _dragY = 0;
              widget.onLockFraction?.call(0.0);
            } else {
              _dragX = 0;
              widget.onDragFraction?.call(0.0);
            }
          }
        }

        if (_axis == _DragAxis.vertical) {
          final dy = rawDy.clamp(_lockThreshold, 0.0);
          if (mounted) setState(() => _dragY = dy);
          widget.onLockFraction?.call(dy.abs() / _lockThreshold.abs());
          if (widget.isRecording && dy <= _lockThreshold) {
            _locked = true;
            _pointer = null;
            HapticFeedback.mediumImpact();
            _resetDrag();
            widget.onLock();
          }
        } else {
          final dx = rawDx.clamp(_cancelThreshold, 0.0);
          if (mounted) setState(() => _dragX = dx);
          widget.onDragFraction?.call(dx.abs() / _cancelThreshold.abs());
          if (widget.isRecording && dx <= _cancelThreshold) {
            _cancelled = true;
            _pointer = null;
            _resetDrag();
            widget.onCancel();
          }
        }
      },
      onPointerCancel: (e) {
        if (e.pointer != _pointer) return;
        _pointer = null;
        _holdTimer?.cancel();
        _holdTimer = null;
        _cancelled = true;
        _resetDrag();
        if (_startFired) widget.onCancel();
      },
      child: _buildButton(auraExtra, auraOpacity),
    );
  }

  Widget _buildButton(double auraExtra, double auraOpacity) {
    return ClickableCursor(
      child: TapRegion(
      groupId: EditableText,
      child: Transform.translate(
        offset: Offset(_dragX, _dragY),
        child: SizedBox(
          width: _baseSize,
          height: _baseSize,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              OverflowBox(
                minWidth: 0,
                maxWidth: _baseSize + _maxAuraExtra * 2,
                minHeight: 0,
                maxHeight: _baseSize + _maxAuraExtra * 2,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 80),
                  width: _baseSize + auraExtra * 2,
                  height: _baseSize + auraExtra * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(auraOpacity),
                  ),
                ),
              ),
              AnimatedScale(
                scale: widget.isRecording ? _recordingScale : 1.0,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutBack,
                child: Container(
                  width: _baseSize,
                  height: _baseSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.isRecording ? GlitchColors.error : GlitchColors.accentBlue,
                  ),
                  child: Icon(
                    widget.isLocked
                        ? Icons.arrow_forward_rounded
                        : (widget.videoMode ? Icons.videocam_rounded : Icons.mic_rounded),
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
