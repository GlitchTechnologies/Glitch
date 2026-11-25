import 'package:flutter/material.dart';
import '../models/message.dart';
import 'l10n.dart';
import 'media_content.dart';
import 'system_message.dart';
import '../widgets/message_interactions.dart' show bubblePreviewText;

const int _kMaxPreviewThumbs = 3;

class PreviewThumb {
  final String url;
  final bool isVideo;
  const PreviewThumb({required this.url, required this.isVideo});
}

class ChatPreviewSpec {
  final List<PreviewThumb> thumbs;
  final String label;
  const ChatPreviewSpec({this.thumbs = const [], required this.label});
}

ChatPreviewSpec buildChatPreviewSpec(BuildContext context, MessagePreview? preview) {
  if (preview == null) return const ChatPreviewSpec(label: '');

  final system = systemMessageText(
    context.s,
    system: preview.system,
    messageId: preview.id ?? 0,
    actorName: preview.senderDisplayName ?? preview.senderNickname,
  );
  if (system != null) return ChatPreviewSpec(label: system);

  final label = bubblePreviewText(context, preview.type, preview.previewText);
  final raw = preview.mediaUrl;
  if (raw == null) return ChatPreviewSpec(label: label);

  final thumbs = <PreviewThumb>[];
  switch (preview.type) {
    case 'photo':
      thumbs.add(PreviewThumb(url: parseMediaContent(raw).url, isVideo: false));
      break;
    case 'video':
      final t = parseMediaContent(raw).thumb;
      if (t != null) thumbs.add(PreviewThumb(url: t, isVideo: true));
      break;
    case 'sticker':
      final s = parseSticker(raw);
      if (s != null) thumbs.add(PreviewThumb(url: s.url, isVideo: false));
      break;
    case 'album':
      for (final item in parseAlbumContent(raw)) {
        if (thumbs.length >= _kMaxPreviewThumbs) break;
        final url = item.isVideo ? item.thumb : item.url;
        if (url != null) thumbs.add(PreviewThumb(url: url, isVideo: item.isVideo));
      }
      break;
  }

  return ChatPreviewSpec(thumbs: thumbs, label: label);
}
