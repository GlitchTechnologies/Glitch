import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/media_content.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'animated_network_image.dart';

class StickerView extends StatelessWidget {
  final ParsedSticker? sticker;

  final double size;

  final String? fallbackText;

  const StickerView({
    super.key,
    required this.sticker,
    required this.size,
    this.fallbackText,
  });

  @override
  Widget build(BuildContext context) {
    final st = sticker;
    if (st != null && st.unavailable) {
      return SizedBox(
        width: size,
        height: size,
        child: Column(
          children: [
            Expanded(child: _image(st)),
            const SizedBox(height: 4),
            Text(
              context.s.stickerUnavailable,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: GlitchColors.textSecond),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: st == null
          ? _fallback(fallbackText)
          : _image(st),
    );
  }

  Widget _image(ParsedSticker st) => AnimatedNetworkImage(
        url: st.url,
        headers: api.headersFor(st.url),
        fit: BoxFit.contain,
        errorWidget: (_) => _fallback(st.emoji ?? fallbackText),
      );

  Widget _fallback(String? text) => Center(
        child: Text(
          (text == null || text.isEmpty) ? '🎨' : text,
          style: const TextStyle(fontSize: 44),
        ),
      );
}
