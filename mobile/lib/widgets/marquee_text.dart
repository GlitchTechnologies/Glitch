import 'dart:async';
import 'package:flutter/material.dart';

class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  final double gap;

  final double pixelsPerSecond;

  final Duration startDelay;

  const MarqueeText(
    this.text, {
    super.key,
    this.style,
    this.gap = 48,
    this.pixelsPerSecond = 32,
    this.startDelay = const Duration(milliseconds: 900),
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Timer? _startTimer;

  void _resetAnimation() {
    _startTimer?.cancel();
    _startTimer = null;
    _controller?.dispose();
    _controller = null;
  }

  @override
  void didUpdateWidget(covariant MarqueeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.style != widget.style) {
      _resetAnimation();
    }
  }

  @override
  void dispose() {
    _resetAnimation();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? DefaultTextStyle.of(context).style;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;

        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout();

        final textWidth = painter.width;

        if (!maxWidth.isFinite || textWidth <= maxWidth) {
          return Text(widget.text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
        }

        _controller ??= AnimationController(
          vsync: this,
          duration: Duration(
            milliseconds: ((textWidth + widget.gap) / widget.pixelsPerSecond * 1000).round(),
          ),
        );
        _startTimer ??= Timer(widget.startDelay, () {
          if (mounted) _controller?.repeat();
        });

        return ClipRect(
          child: SizedBox(
            width: maxWidth,
            height: painter.height,
            child: AnimatedBuilder(
              animation: _controller!,
              builder: (context, _) {
                final dx = -(_controller!.value * (textWidth + widget.gap));
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(left: dx, top: 0, child: Text(widget.text, style: style, maxLines: 1, softWrap: false)),
                    Positioned(left: dx + textWidth + widget.gap, top: 0, child: Text(widget.text, style: style, maxLines: 1, softWrap: false)),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
