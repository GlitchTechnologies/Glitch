import 'dart:convert';
import '../models/message.dart';

/// Результат разбора одиночного content-поля сообщения/поста с медиа:
/// либо голый URL (старый формат), либо {"url":..,"w":W,"h":H}.
class ParsedMedia {
  final String url;
  final double? aspectRatio; // w / h, null если размеры неизвестны
  final String? thumb;
  const ParsedMedia({required this.url, this.aspectRatio, this.thumb});
}

bool isGifUrl(String url) => url.toLowerCase().split('?').first.endsWith('.gif');

class ParsedVideoNote {
  final String url;
  final String thumb;
  final double duration; // секунды
  const ParsedVideoNote({required this.url, required this.thumb, required this.duration});
}

/// Единая точка разбора кружка. Возвращает null, если строка не разбирается —
/// вызывающий рисует заглушку вместо того, чтобы падать: сюда может прийти
/// content чужого формата (например, fallback-подпись «Видеосообщение»,
/// которую сервер кладёт в content ради старых клиентов).
ParsedVideoNote? parseVideoNote(String? raw) {
  if (raw == null || !raw.startsWith('{')) return null;
  try {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final url = m['url'] as String?;
    final thumb = m['thumb'] as String?;
    if (url == null || url.isEmpty || thumb == null || thumb.isEmpty) return null;
    return ParsedVideoNote(
      url: url,
      thumb: thumb,
      duration: (m['duration'] as num?)?.toDouble() ?? 0,
    );
  } catch (_) {
    return null;
  }
}

class ParsedSticker {
  final int? id;
  final String? name;
  final String url;
  final String format; // 'webp' | 'webp_anim' — оба рисуются одинаково, обычным Image
  final String? emoji;
  final int width;
  final int height;

  final bool unavailable;

  const ParsedSticker({
    this.id,
    this.name,
    required this.url,
    required this.format,
    this.emoji,
    required this.width,
    required this.height,
    this.unavailable = false,
  });

  double get aspectRatio => height > 0 ? width / height : 1;
}

ParsedSticker? parseSticker(String? raw) {
  if (raw == null || !raw.startsWith('{')) return null;
  try {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final url = m['url'] as String?;
    if (url == null || url.isEmpty) return null;
    return ParsedSticker(
      id: (m['id'] as num?)?.toInt(),
      name: m['name'] as String?,
      unavailable: m['unavailable'] == true,
      url: url,
      format: (m['format'] as String?) ?? 'webp',
      emoji: m['emoji'] as String?,
      width: (m['w'] as num?)?.toInt() ?? 512,
      height: (m['h'] as num?)?.toInt() ?? 512,
    );
  } catch (_) {
    return null;
  }
}

double? aspectRatioFromMap(Map<String, dynamic> m) {
  final w = (m['w'] as num?)?.toDouble();
  final h = (m['h'] as num?)?.toDouble();
  return (w != null && h != null && h > 0) ? w / h : null;
}

ParsedMedia parseMediaContent(String content) {
  if (content.startsWith('{')) {
    try {
      final m = jsonDecode(content) as Map<String, dynamic>;
      final url = m['url'] as String?;
      if (url != null) {
        return ParsedMedia(
          url: url,
          aspectRatio: aspectRatioFromMap(m),
          thumb: m['thumb'] as String?,
        );
      }
    } catch (_) {}
  }
  return ParsedMedia(url: content);
}

class AlbumItem {
  final String url;
  final bool isVideo;
  final double? aspectRatio;
  final String? thumb;
  const AlbumItem({required this.url, required this.isVideo, this.aspectRatio, this.thumb});
}

List<AlbumItem> parseAlbumContent(String content) {
  try {
    final list = jsonDecode(content) as List;
    return list.map((e) {
      final m = e as Map<String, dynamic>;
      return AlbumItem(
        url: m['url'] as String,
        isVideo: m['type'] == 'video',
        aspectRatio: aspectRatioFromMap(m),
        thumb: m['thumb'] as String?,
      );
    }).toList();
  } catch (_) {
    return const [];
  }
}

class GalleryTile {
  final Message message;
  final String url;
  final bool isVideo;
  final double? aspectRatio;
  const GalleryTile({required this.message, required this.url, required this.isVideo, this.aspectRatio});
}

List<GalleryTile> flattenMediaMessages(List<Message> messages) {
  final tiles = <GalleryTile>[];
  for (final msg in messages) {
    if (msg.content == null) continue;
    if (msg.type == 'album') {
      for (final item in parseAlbumContent(msg.content!)) {
        tiles.add(GalleryTile(message: msg, url: item.url, isVideo: item.isVideo, aspectRatio: item.aspectRatio));
      }
    } else {
      final parsed = parseMediaContent(msg.content!);
      tiles.add(GalleryTile(message: msg, url: parsed.url, isVideo: msg.type == 'video', aspectRatio: parsed.aspectRatio));
    }
  }
  return tiles;
}
