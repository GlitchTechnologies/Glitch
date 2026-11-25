import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/chat_preview.dart';
import '../models/message.dart';
import '../services/api_service.dart';

const double _kThumbSize = 18;

class ChatPreviewLine extends StatelessWidget {
  final MessagePreview? preview;
  final TextStyle? style;

  const ChatPreviewLine({super.key, required this.preview, this.style});

  @override
  Widget build(BuildContext context) {
    final spec = buildChatPreviewSpec(context, preview);

    return Row(
      children: [
        for (final thumb in spec.thumbs) ...[
          _thumbBox(thumb),
          const SizedBox(width: 3),
        ],
        if (spec.thumbs.isNotEmpty) const SizedBox(width: 3),
        Expanded(
          child: Text(spec.label, style: style, overflow: TextOverflow.ellipsis, maxLines: 1),
        ),
      ],
    );
  }

  Widget _thumbBox(PreviewThumb thumb) {
    final url = api.mediaUrl(thumb.url);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Stack(
        alignment: Alignment.center,
        children: [
          CachedNetworkImage(
            imageUrl: url,
            cacheManager: mediaCacheManager,
            width: _kThumbSize,
            height: _kThumbSize,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => const SizedBox(width: _kThumbSize, height: _kThumbSize),
          ),
          if (thumb.isVideo) ...[
            Container(width: _kThumbSize, height: _kThumbSize, color: Colors.black26),
            const Icon(Icons.play_arrow_rounded, size: 14, color: Colors.white),
          ],
        ],
      ),
    );
  }
}
