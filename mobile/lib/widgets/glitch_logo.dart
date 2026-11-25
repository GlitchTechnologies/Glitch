import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

class GlitchLogo extends StatefulWidget {
  final double size;
  const GlitchLogo({super.key, this.size = 74});

  @override
  State<GlitchLogo> createState() => _GlitchLogoState();
}

class _GlitchLogoState extends State<GlitchLogo> {
  double _shiftA = 0;
  double _shiftB = 0;
  double _shiftC = 0;
  Timer? _timer;
  final _rnd = Random();

  @override
  void initState() {
    super.initState();
    _scheduleNext();
  }

  void _scheduleNext() {
    _timer = Timer(Duration(milliseconds: 3000 + _rnd.nextInt(3000)), _runGlitch);
  }

  Future<void> _runGlitch() async {
    if (!mounted) return;

    setState(() { _shiftA = 5; _shiftB = -6; _shiftC = 4; });
    await Future.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;

    setState(() { _shiftA = -3; _shiftB = 3; _shiftC = -2; });
    await Future.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;

    setState(() { _shiftA = 2; _shiftB = -2; _shiftC = 1; });
    await Future.delayed(const Duration(milliseconds: 60));
    if (!mounted) return;

    setState(() { _shiftA = 0; _shiftB = 0; _shiftC = 0; });
    _scheduleNext();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;

    final r = s * 0.213;

    final cacheWidth = (s * MediaQuery.of(context).devicePixelRatio).round();

    return Container(
      width: s, height: s,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(r),
        boxShadow: const [
          BoxShadow(color: Color(0x8C000000), blurRadius: 40, offset: Offset(0, 16)),
          BoxShadow(color: Color(0x24FFFFFF), blurRadius: 0, spreadRadius: 1),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: Stack(
          children: [
            _layer(s, cacheWidth, 0, null),
            _layer(s, cacheWidth, _shiftA, const _FractionClip(0.07, 0.71)),
            _layer(s, cacheWidth, _shiftB, const _FractionClip(0.45, 0.33)),
            _layer(s, cacheWidth, _shiftC, const _FractionClip(0.76, 0.05)),
          ],
        ),
      ),
    );
  }

  Widget _layer(double size, int cacheWidth, double shiftX, _FractionClip? clip) {
    Widget g = Transform.translate(
      offset: Offset(shiftX, 0),
      child: Image.asset(
        'assets/icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        filterQuality: FilterQuality.medium,
      ),
    );

    if (clip != null) {
      g = ClipRect(clipper: _RectClipper(clip.top, clip.bottom), child: g);
    }

    return g;
  }
}

class _FractionClip {
  final double top;
  final double bottom;
  const _FractionClip(this.top, this.bottom);
}

class _RectClipper extends CustomClipper<Rect> {
  final double top;
  final double bottom;
  const _RectClipper(this.top, this.bottom);

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    0,
    size.height * top,
    size.width,
    size.height * (1 - bottom),
  );

  @override
  bool shouldReclip(_RectClipper old) => old.top != top || old.bottom != bottom;
}
