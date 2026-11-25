import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/call_audio_prefs.dart' show CallAudioPrefs;
import '../theme/app_theme.dart';

/// ПОЛОСА «ЧУВСТВИТЕЛЬНОСТЬ ВВОДА» — как у Discord: шкала в децибелах от
/// [CallAudioPrefs.minSensitivityDb] до 0, по ней — громкость своего голоса
/// сейчас ([levelDb]: зажжено до неё, дальше — бледно).
///
/// С порогом ([thresholdDb]) левее него — жёлтым (`inputCut`: тише — не
/// уйдёт), правее — зелёным (`inputPass`: уйдёт); порог двигает кружок
/// ползунка, под которым полоса стоит (GlitchSlider, `track`). Без порога
/// (автоматически) — громкость одним зелёным, как у Discord.
class InputSensitivityBar extends StatelessWidget {
  final ValueListenable<double> levelDb;

  final double? thresholdDb;

  const InputSensitivityBar({super.key, required this.levelDb, this.thresholdDb});

  static const double height = 8;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: ValueListenableBuilder<double>(
          valueListenable: levelDb,
          builder: (context, level, _) => CustomPaint(
            painter: _BarPainter(
              level: _fraction(level),
              threshold: thresholdDb == null ? null : _fraction(thresholdDb!),
              idle: GlitchColors.textHint,
            ),
          ),
        ),
      );

  static double _fraction(double db) {
    const min = CallAudioPrefs.minSensitivityDb;
    return ((db - min) / -min).clamp(0.0, 1.0).toDouble();
  }
}

class _BarPainter extends CustomPainter {
  final double level;
  final double? threshold;

  final Color idle;

  _BarPainter({required this.level, required this.threshold, required this.idle});

  static const double _dim = 0.3;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(Offset.zero & size, radius));
    final cut = threshold;
    final split = cut == null ? 0.0 : cut * size.width;
    final lit = level * size.width;
    final left = cut == null ? GlitchColors.inputPass : GlitchColors.inputCut;
    final right = GlitchColors.inputPass;
    final dimRight = cut == null ? idle.withOpacity(0.35) : right.withOpacity(_dim);
    _segment(canvas, size, 0, split, left, lit, left.withOpacity(_dim));
    _segment(canvas, size, split, size.width, right, lit, dimRight);
    canvas.restore();
  }

  void _segment(Canvas canvas, Size size, double from, double to, Color bright, double lit, Color dim) {
    if (to <= from) return;
    final edge = lit.clamp(from, to).toDouble();
    if (edge > from) canvas.drawRect(Rect.fromLTRB(from, 0, edge, size.height), Paint()..color = bright);
    if (to > edge) canvas.drawRect(Rect.fromLTRB(edge, 0, to, size.height), Paint()..color = dim);
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.level != level || old.threshold != threshold || old.idle != idle;
}
