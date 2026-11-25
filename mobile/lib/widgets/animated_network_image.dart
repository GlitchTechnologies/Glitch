import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/platform_info.dart';
import '../services/api_service.dart';

/// ЗАЧЕМ ЭТО ВООБЩЕ (2026-09-02, жалоба: «на телефоне GIF-аватарка крутится, в
/// вебе — нет»). Раньше везде стоял `Image` + `CachedNetworkImageProvider` —
/// так на Android анимация гарантированно проигрывается: Skia честно
/// декодирует все кадры файла. В браузере ТА ЖЕ комбинация показывает только
/// первый кадр: веб-ветка `cached_network_image` при загрузке ПО URL идёт
/// через `createImageCodecFromUrl` (браузерное декодирование напрямую), а
/// собственный многокадровый кодек Flutter при этом не вызывается вовсе — та
/// же причина, по которой на вебе не работал и `memCacheWidth` (см.
/// `core/avatar_sizes.dart`, разбор от 2026-08-23).
class AnimatedNetworkImage extends StatefulWidget {
  final String url;
  final Map<String, String>? headers;
  final BoxFit fit;
  final double? width;
  final double? height;

  final WidgetBuilder? placeholder;

  final WidgetBuilder? errorWidget;

  const AnimatedNetworkImage({
    super.key,
    required this.url,
    this.headers,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
  });

  @override
  State<AnimatedNetworkImage> createState() => _AnimatedNetworkImageState();
}

class _AnimatedNetworkImageState extends State<AnimatedNetworkImage> {
  Future<Uint8List>? _bytesFuture;

  @override
  void initState() {
    super.initState();
    if (isWebPlatform) _bytesFuture = _loadBytes();
  }

  @override
  void didUpdateWidget(covariant AnimatedNetworkImage old) {
    super.didUpdateWidget(old);
    if (isWebPlatform && old.url != widget.url) {
      _bytesFuture = _loadBytes();
    }
  }

  Future<Uint8List> _loadBytes() async {
    final file = await mediaCacheManager.getSingleFile(widget.url, headers: widget.headers);
    return file.readAsBytes();
  }

  Widget _placeholder(BuildContext context) => widget.placeholder?.call(context) ?? const SizedBox.shrink();
  Widget _error(BuildContext context) => widget.errorWidget?.call(context) ?? const SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    if (!isWebPlatform) {
      return Image(
        image: CachedNetworkImageProvider(widget.url, headers: widget.headers, cacheManager: mediaCacheManager),
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        frameBuilder: (_, child, frame, wasSynchronouslyLoaded) =>
            wasSynchronouslyLoaded || frame != null ? child : _placeholder(context),
        errorBuilder: (_, __, ___) => _error(context),
      );
    }

    return FutureBuilder<Uint8List>(
      future: _bytesFuture,
      builder: (context, snap) {
        if (snap.hasError) return _error(context);
        if (snap.connectionState != ConnectionState.done || snap.data == null) {
          return _placeholder(context);
        }
        return Image(
          image: MemoryImage(snap.data!),
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          errorBuilder: (_, __, ___) => _error(context),
        );
      },
    );
  }
}
