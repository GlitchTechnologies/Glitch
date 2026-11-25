import 'dart:async';

import 'package:flutter/material.dart';

import '../core/collectibles.dart';
import '../models/collectible.dart';
import 'collectible_image.dart';

class ProfileEffectOverlay extends StatefulWidget {
  final CollectibleLook? effect;
  final bool playing;
  final Widget child;

  const ProfileEffectOverlay({super.key, required this.effect, this.playing = true, required this.child});

  @override
  State<ProfileEffectOverlay> createState() => _ProfileEffectOverlayState();
}

class _ProfileEffectOverlayState extends State<ProfileEffectOverlay> {
  final _started = <int>{};
  final _finished = <int>{};
  final _timers = <Timer>[];

  int _run = 0;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant ProfileEffectOverlay old) {
    super.didUpdateWidget(old);
    final now = widget.effect;
    final changed = now == null ? old.effect != null : !now.sameAs(old.effect);
    if (changed || (widget.playing && !old.playing)) _schedule();
  }

  void _schedule() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    _started.clear();
    _finished.clear();
    _run++;
    final layers = widget.effect?.layers ?? const <EffectLayer>[];
    for (var i = 0; i < layers.length; i++) {
      final start = layers[i].startMs;
      if (start <= 0) {
        _started.add(i);
        continue;
      }
      final run = _run;
      _timers.add(Timer(Duration(milliseconds: start), () {
        if (!mounted || run != _run) return;
        setState(() => _started.add(i));
      }));
    }
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effect = widget.effect;
    if (effect == null) return widget.child;
    final still = !widget.playing || MediaQuery.disableAnimationsOf(context);
    final layers = effect.layers;
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        KeyedSubtree(key: const ValueKey('profile'), child: widget.child),
        Positioned(
          key: const ValueKey('effect'),
          left: 0,
          top: 0,
          right: 0,
          child: IgnorePointer(
            child: AspectRatio(
              aspectRatio: kProfileEffectAspect,
              child: still
                  ? CollectibleImage(staticUrl: effect.staticUrl, animatedUrl: null, fit: BoxFit.fill)
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        for (var i = 0; i < layers.length; i++)
                          if (_started.contains(i) && !_finished.contains(i))
                            CollectibleImage(
                              key: ValueKey('layer-$_run-$i'),
                              staticUrl: null,
                              animatedUrl: layers[i].url,
                              playing: true,
                              loop: layers[i].loop,
                              fit: BoxFit.fill,
                              onFinished: () {
                                if (mounted) setState(() => _finished.add(i));
                              },
                            ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
