import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/avatar_sizes.dart';
import '../core/media_content.dart' show isGifUrl;
import '../services/api_service.dart';
import 'animated_network_image.dart';

class BannerPicture extends StatelessWidget {
  final String? url;
  final Map<String, String>? sizes;
  final Uint8List? localBytes;

  final Widget fallback;

  const BannerPicture({
    super.key,
    this.url,
    this.sizes,
    this.localBytes,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final bytes = localBytes;
    if (bytes != null) {
      return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
    }
    final original = url;
    if (original == null) return fallback;

    return LayoutBuilder(builder: (context, constraints) {
      final picked = pickAvatarUrl(
        original: api.mediaUrl(original),
        sizes: sizes,
        logicalSize: constraints.maxWidth,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      )!;
      if (isGifUrl(picked)) {
        return AnimatedNetworkImage(
          url: picked,
          fit: BoxFit.cover,
          placeholder: (_) => fallback,
          errorWidget: (_) => fallback,
        );
      }
      return CachedNetworkImage(
        imageUrl: picked,
        cacheManager: mediaCacheManager,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        placeholder: (_, __) => fallback,
        errorWidget: (_, __, ___) => fallback,
      );
    });
  }
}
