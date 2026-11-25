import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/glitch_ink.dart';
import 'glitch_tooltip.dart';

class GlitchSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final int? divisions;

  /// null — ползунок недоступен.
  final ValueChanged<double>? onChanged;

  final ValueChanged<double>? onChangeEnd;
  final ValueChanged<double>? onChangeStart;

  final String Function(double value)? valueLabel;

  final Widget? track;

  const GlitchSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.onChangeStart,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.valueLabel,
    this.track,
  });

  static String percentLabel(double fraction) => '${(fraction * 100).round()}%';

  static const double _thumbRadius = 8;

  double get _shown => value.clamp(min, max).toDouble();

  Rect _thumbRect(Size size) {
    final t = max > min ? (_shown - min) / (max - min) : 0.0;
    final x = _thumbRadius + t * (size.width - 2 * _thumbRadius);
    return Rect.fromCircle(center: Offset(x, size.height / 2), radius: _thumbRadius);
  }

  @override
  Widget build(BuildContext context) {
    final slider = _slider(context);
    final label = valueLabel;
    if (label == null) return slider;
    return GlitchTooltip(message: label(_shown), target: _thumbRect, child: slider);
  }

  Widget _slider(BuildContext context) {
    final track = this.track;
    final slider = _material(context, ownTrack: track != null);
    if (track == null) return slider;
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: _thumbRadius),
            child: Center(child: track),
          ),
        ),
        slider,
      ],
    );
  }

  Widget _material(BuildContext context, {required bool ownTrack}) {
    final hint = GlitchInk.of(context).textHint;
    return SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: ownTrack ? Colors.transparent : GlitchColors.accentBlue,
          inactiveTrackColor: ownTrack ? Colors.transparent : hint.withOpacity(0.35),
          thumbColor: Colors.white,
          disabledActiveTrackColor: hint,
          disabledInactiveTrackColor: hint.withOpacity(0.35),
          disabledThumbColor: hint,
          trackHeight: 4,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: _thumbRadius),
          overlayShape: SliderComponentShape.noOverlay,
        ),
        child: Slider(
          value: _shown,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
          onChangeStart: onChangeStart,
        ),
      );
  }
}
