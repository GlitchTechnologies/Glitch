import 'dart:async';

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../services/voice_connection.dart';
import '../theme/app_theme.dart';
import 'glitch_bar_buttons.dart';
import 'glitch_toast.dart';

class MicTestRow extends StatelessWidget {
  const MicTestRow({super.key});

  Future<void> _tap(BuildContext context) async {
    final v = voiceConnection;
    if (v.micTesting) {
      await v.stopMicTest();
      return;
    }
    if (await v.startMicTest() || !context.mounted) return;
    GlitchToast.show(context, context.s.voiceMicTestFailed, type: ToastType.info);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: voiceConnection,
        builder: (context, _) {
          final testing = voiceConnection.micTesting;
          return Row(
            children: [
              GlitchFilledButton(
                label: testing ? context.s.voiceMicTestStop : context.s.voiceMicTestStart,
                onTap: () => unawaited(_tap(context)),
              ),
              const SizedBox(width: 12),
              Expanded(child: _MicLevelBars(active: testing)),
            ],
          );
        },
      );
}

class _MicLevelBars extends StatelessWidget {
  final bool active;

  const _MicLevelBars({required this.active});

  static const double _height = 24;
  static const double _barWidth = 3;
  static const double _gap = 3;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: _height,
        child: ValueListenableBuilder<double>(
          valueListenable: voiceConnection.micTestLevel,
          builder: (context, level, _) => CustomPaint(
            painter: _BarsPainter(
              level: active ? level : 0,
              on: GlitchColors.switchOn,
              off: GlitchColors.textHint,
            ),
          ),
        ),
      );
}

class _BarsPainter extends CustomPainter {
  final double level;
  final Color on;
  final Color off;

  _BarsPainter({required this.level, required this.on, required this.off});

  @override
  void paint(Canvas canvas, Size size) {
    const step = _MicLevelBars._barWidth + _MicLevelBars._gap;
    final count = ((size.width + _MicLevelBars._gap) / step).floor();
    if (count <= 0) return;
    final lit = (level * count).round();
    final radius = const Radius.circular(_MicLevelBars._barWidth / 2);
    for (var i = 0; i < count; i++) {
      final rect = Rect.fromLTWH(i * step, 0, _MicLevelBars._barWidth, size.height);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), Paint()..color = i < lit ? on : off);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.level != level || old.on != on || old.off != off;
}
