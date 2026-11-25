import '../core/avatar_sizes.dart';
import '../core/media_content.dart' show ParsedSticker;

class Sticker {
  final int id;
  final int serverId;
  final String name;
  final String? description;
  final String emoji;
  final String url;
  final String format; // 'webp' | 'webp_anim'
  final int width;
  final int height;

  const Sticker({
    required this.id,
    required this.serverId,
    required this.name,
    this.description,
    required this.emoji,
    required this.url,
    required this.format,
    required this.width,
    required this.height,
  });

  factory Sticker.fromJson(Map<String, dynamic> j) => Sticker(
        id: j['id'] as int,
        serverId: j['server_id'] as int,
        name: j['name'] as String? ?? '',
        description: j['description'] as String?,
        emoji: j['emoji'] as String? ?? '',
        url: j['url'] as String? ?? '',
        format: j['format'] as String? ?? 'webp',
        width: (j['width'] as num?)?.toInt() ?? 512,
        height: (j['height'] as num?)?.toInt() ?? 512,
      );

  ParsedSticker toParsed() => ParsedSticker(
        id: id,
        name: name,
        url: url,
        format: format,
        emoji: emoji,
        width: width,
        height: height,
      );

  Map<String, dynamic> toMessageJson() => {
        'id': id,
        'server_id': serverId,
        'name': name,
        'emoji': emoji,
        'url': url,
        'format': format,
        'w': width,
        'h': height,
        'unavailable': false,
      };
}

class ServerStickersPage {
  final List<Sticker> stickers;
  final bool canManage;

  final int limit;
  final int freeLimit;

  const ServerStickersPage({
    required this.stickers,
    required this.canManage,
    required this.limit,
    required this.freeLimit,
  });

  ServerStickersPage withStickers(List<Sticker> list) =>
      ServerStickersPage(stickers: list, canManage: canManage, limit: limit, freeLimit: freeLimit);

  factory ServerStickersPage.fromJson(Map<String, dynamic> j) => ServerStickersPage(
        stickers: _parseStickers(j['stickers']),
        canManage: j['can_manage'] as bool? ?? false,
        limit: (j['limit'] as num?)?.toInt() ?? 0,
        freeLimit: (j['free_limit'] as num?)?.toInt() ?? 0,
      );
}

class StickerGroup {
  final int serverId;
  final String serverName;
  final String? serverAvatar;
  final Map<String, String>? serverAvatarSizes;
  final List<Sticker> stickers;

  const StickerGroup({
    required this.serverId,
    required this.serverName,
    this.serverAvatar,
    this.serverAvatarSizes,
    required this.stickers,
  });

  factory StickerGroup.fromJson(Map<String, dynamic> j) => StickerGroup(
        serverId: j['server_id'] as int,
        serverName: j['server_name'] as String? ?? '',
        serverAvatar: j['server_avatar'] as String?,
        serverAvatarSizes: parseAvatarSizes(j['server_avatar_sizes']),
        stickers: _parseStickers(j['stickers']),
      );
}

List<Sticker> _parseStickers(dynamic raw) =>
    ((raw as List?) ?? const []).whereType<Map<String, dynamic>>().map(Sticker.fromJson).toList();
