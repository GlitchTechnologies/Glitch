import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';

/// КАРТИНКА ПРЕДМЕТА ОФОРМЛЕНИЯ — одна на украшение, плашку и слои эффекта
/// (2026-10-24, core/collectibles.dart).
///
/// Не играет — неподвижный кадр [staticUrl]. Играет ([playing]) — анимация
/// [animatedUrl] С ПЕРВОГО КАДРА: как у Discord, украшение оживает при
/// наведении и начинается с начала, а вступление эффекта играет ровно один раз
/// при открытии профиля ([loop] = false, конец — [onFinished]).
class CollectibleImage extends StatefulWidget {
  final String? staticUrl;
  final String? animatedUrl;
  final bool playing;
  final bool loop;
  final VoidCallback? onFinished;
  final BoxFit fit;
  final Alignment alignment;

  const CollectibleImage({
    super.key,
    required this.staticUrl,
    required this.animatedUrl,
    this.playing = false,
    this.loop = true,
    this.onFinished,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
  });

  @override
  State<CollectibleImage> createState() => _CollectibleImageState();
}

class _CollectibleImageState extends State<CollectibleImage> {
  ui.Codec? _codec;
  ui.Image? _frame;
  Timer? _timer;
  int _shown = 0;
  bool _reduceMotion = false;

  int _run = 0;

  bool get _shouldPlay => widget.playing && widget.animatedUrl != null && !_reduceMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce != _reduceMotion) {
      _reduceMotion = reduce;
      _sync(restart: false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _codec == null && _shouldPlay) _start();
    });
  }

  @override
  void didUpdateWidget(covariant CollectibleImage old) {
    super.didUpdateWidget(old);
    final restart = old.animatedUrl != widget.animatedUrl || (!old.playing && widget.playing);
    _sync(restart: restart);
  }

  void _sync({required bool restart}) {
    if (!_shouldPlay) {
      if (_codec != null || _frame != null) _stop();
      return;
    }
    if (restart || _codec == null) _start();
  }

  Future<void> _start() async {
    _stop();
    final run = ++_run;
    final url = widget.animatedUrl!;
    try {
      final file = await mediaCacheManager.getSingleFile(url);
      final bytes = await file.readAsBytes();
      if (!mounted || run != _run) return;
      final codec = await ui.instantiateImageCodec(bytes);
      if (!mounted || run != _run) {
        codec.dispose();
        return;
      }
      _codec = codec;
      _shown = 0;
      await _next(run);
    } catch (_) {
      if (mounted && run == _run) _stop();
    }
  }

  Future<void> _next(int run) async {
    final codec = _codec;
    if (codec == null) return;
    final info = await codec.getNextFrame();
    if (!mounted || run != _run) {
      info.image.dispose();
      return;
    }
    final old = _frame;
    setState(() => _frame = info.image);
    old?.dispose();
    _shown++;
    final last = _shown >= codec.frameCount;
    if (last && !widget.loop) {
      _timer = Timer(info.duration, () {
        if (!mounted || run != _run) return;
        widget.onFinished?.call();
      });
      return;
    }
    if (codec.frameCount <= 1) return;
    _timer = Timer(info.duration, () => _next(run));
  }

  void _stop() {
    _run++;
    _timer?.cancel();
    _timer = null;
    _codec?.dispose();
    _codec = null;
    final old = _frame;
    _frame = null;
    old?.dispose();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _run++;
    _timer?.cancel();
    _codec?.dispose();
    _frame?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frame;
    if (frame != null) {
      return RawImage(image: frame, fit: widget.fit, alignment: widget.alignment, filterQuality: FilterQuality.medium);
    }
    final still = widget.staticUrl;
    if (still == null) return const SizedBox.shrink();
    return CachedNetworkImage(
      imageUrl: still,
      cacheManager: mediaCacheManager,
      fit: widget.fit,
      alignment: widget.alignment,
      filterQuality: FilterQuality.medium,
      fadeInDuration: Duration.zero,
      placeholder: (_, __) => const SizedBox.shrink(),
      errorWidget: (_, __, ___) => const SizedBox.shrink(),
    );
  }
}
