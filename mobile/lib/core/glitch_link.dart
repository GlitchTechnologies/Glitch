library;

const glitchDomain = 'glitchapp.online';

const linkDomain = 'glitchtech.ru';

const _invitePath = 'inv';

String inviteLink(String code) => 'https://${inviteLinkShort(code)}';

String inviteLinkShort(String code) => '$linkDomain/$code';

sealed class GlitchLinkTarget {
  const GlitchLinkTarget();
}

class ProfileLinkTarget extends GlitchLinkTarget {
  final String nickname;
  const ProfileLinkTarget(this.nickname);
}

class InviteLinkTarget extends GlitchLinkTarget {
  final String code;
  const InviteLinkTarget(this.code);
}

final _nickRe = RegExp(r'^[a-zA-Z0-9_]{3,32}$');

final _codeRe = RegExp(r'^[a-z0-9_-]{2,32}$');

final _glitchLinkInText = RegExp(
  r'(?:https?://)?(?:www\.)?glitchtech\.ru/([^\s?#]*)',
  caseSensitive: false,
);

GlitchLinkTarget? glitchTargetInText(String text) {
  for (final m in _glitchLinkInText.allMatches(text)) {
    final target = _fromShortLink(m.group(1)!.split('/').where((p) => p.isNotEmpty).toList());
    if (target != null) return target;
  }
  return null;
}

GlitchLinkTarget? glitchTargetFromUri(Uri uri) {
  if (uri.scheme == 'glitch') {
    return _fromPath([uri.host, ...uri.pathSegments].where((s) => s.isNotEmpty).toList(), bareNick: true);
  }
  final host = uri.host.toLowerCase();
  if (host != linkDomain && host != 'www.$linkDomain') return null;
  return _fromShortLink(uri.pathSegments.where((s) => s.isNotEmpty).toList());
}

GlitchLinkTarget? _fromShortLink(List<String> segments) {
  if (segments.length != 1) return null;
  final part = _trimPunctuation(segments.first);
  if (part.startsWith('@')) {
    final nick = part.substring(1);
    return _nickRe.hasMatch(nick) ? ProfileLinkTarget(nick) : null;
  }
  final code = part.toLowerCase();
  return _codeRe.hasMatch(code) ? InviteLinkTarget(code) : null;
}

GlitchLinkTarget? _fromPath(List<String> segments, {required bool bareNick}) {
  if (segments.isEmpty) return null;
  if (segments.first.toLowerCase() == _invitePath) {
    if (segments.length < 2) return null;
    final code = _trimPunctuation(segments[1]).toLowerCase();
    return _codeRe.hasMatch(code) ? InviteLinkTarget(code) : null;
  }
  if (segments.length != 1) return null;
  var nick = _trimPunctuation(segments.first);
  if (nick.startsWith('@')) {
    nick = nick.substring(1);
  } else if (!bareNick) {
    return null;
  }
  return _nickRe.hasMatch(nick) ? ProfileLinkTarget(nick) : null;
}

String _trimPunctuation(String raw) => raw.trim().replaceFirst(RegExp(r'[.,!?;:)\]]+$'), '');


const webAppDomain = 'web.$glitchDomain';

sealed class WebPlace {
  const WebPlace();

  String get path;
}

final class ChatsPlace extends WebPlace {
  final int? chatId;
  final int? messageId;

  const ChatsPlace({this.chatId, this.messageId});

  @override
  String get path => _joinPath(['chats', chatId, if (chatId != null) messageId]);

  @override
  bool operator ==(Object other) =>
      other is ChatsPlace && other.chatId == chatId && other.messageId == messageId;

  @override
  int get hashCode => Object.hash('chats', chatId, messageId);
}

final class ServerPlace extends WebPlace {
  final int serverId;
  final int? roomId;
  final int? messageId;

  const ServerPlace(this.serverId, {this.roomId, this.messageId});

  @override
  String get path => _joinPath(['servers', serverId, roomId, if (roomId != null) messageId]);

  @override
  bool operator ==(Object other) =>
      other is ServerPlace && other.serverId == serverId && other.roomId == roomId && other.messageId == messageId;

  @override
  int get hashCode => Object.hash('servers', serverId, roomId, messageId);
}

final class CatalogPlace extends WebPlace {
  const CatalogPlace();

  @override
  String get path => '/catalog';

  @override
  bool operator ==(Object other) => other is CatalogPlace;

  @override
  int get hashCode => (CatalogPlace).hashCode;
}

final class LinkPlace extends WebPlace {
  final GlitchLinkTarget target;

  const LinkPlace(this.target);

  @override
  String get path => switch (target) {
        ProfileLinkTarget(:final nickname) => '/@$nickname',
        InviteLinkTarget(:final code) => '/$_invitePath/$code',
      };
}

WebPlace placeWithoutMessage(WebPlace place) => switch (place) {
      ChatsPlace(:final chatId) => ChatsPlace(chatId: chatId),
      ServerPlace(:final serverId, :final roomId) => ServerPlace(serverId, roomId: roomId),
      _ => place,
    };

WebPlace webPlaceFromPath(String path) {
  final parts = path.split('/').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return const ChatsPlace();
  final ids = [for (final p in parts.skip(1)) _idOf(p)];
  final idsOk = !ids.contains(null);
  switch (parts.first.toLowerCase()) {
    case 'chats' when idsOk && ids.length <= 2:
      return ChatsPlace(chatId: ids.elementAtOrNull(0), messageId: ids.elementAtOrNull(1));
    case 'servers' when idsOk && ids.isNotEmpty && ids.length <= 3:
      return ServerPlace(ids[0]!, roomId: ids.elementAtOrNull(1), messageId: ids.elementAtOrNull(2));
    case 'catalog' when parts.length == 1:
      return const CatalogPlace();
  }
  final link = _fromPath(parts, bareNick: false);
  return link == null ? const ChatsPlace() : LinkPlace(link);
}

String messageLink({int? serverId, required int chatId, required int messageId}) {
  final place = serverId == null
      ? ChatsPlace(chatId: chatId, messageId: messageId)
      : ServerPlace(serverId, roomId: chatId, messageId: messageId);
  return 'https://$webAppDomain${place.path}';
}

int? _idOf(String raw) {
  final id = int.tryParse(raw);
  return id != null && id > 0 ? id : null;
}

String _joinPath(List<Object?> parts) {
  final out = <String>[];
  for (final p in parts) {
    if (p == null) break;
    out.add('$p');
  }
  return '/${out.join('/')}';
}
