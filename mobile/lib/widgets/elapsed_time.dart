import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ElapsedTime extends StatefulWidget {
  final DateTime? _since;
  final Duration Function()? _readElapsed;
  final TextStyle style;

  const ElapsedTime({super.key, required DateTime since, this.style = defaultStyle})
      : _since = since, _readElapsed = null;

  const ElapsedTime.counting({
    super.key,
    required Duration Function() readElapsed,
    this.style = defaultStyle,
  }) : _readElapsed = readElapsed, _since = null;

  Duration get _elapsed => _readElapsed?.call() ?? DateTime.now().difference(_since!);

  static const defaultStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: GlitchColors.online,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static String format(Duration duration) {
    final total = duration.isNegative ? 0 : duration.inSeconds;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;
    String two(int value) => value.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:${two(minutes)}:${two(seconds)}' : '${two(minutes)}:${two(seconds)}';
  }

  @override
  State<ElapsedTime> createState() => _ElapsedTimeState();
}

class _ElapsedTimeState extends State<ElapsedTime> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Text(ElapsedTime.format(widget._elapsed), style: widget.style);
}
