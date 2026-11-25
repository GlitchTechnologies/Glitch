import 'file_audio.dart';
import 'bubble_data.dart';
import '../core/time_json.dart';
import 'call.dart';
import 'poll.dart';
import 'mention.dart';
import 'embed.dart';
import 'system_info.dart';
import '../core/avatar_sizes.dart';
import 'collectible.dart';

/// Вид автора, который сервер прислал готовым (событие о смене профиля):
/// имя и аватарка разом — аватарка может стать и пустой.
/// Украшение аватарки — тоже часть вида (оформление профиля, 2026-10-24).
typedef AuthorLook = ({
  String displayName,
  String? avatar,
  Map<String, String>? avatarSizes,
  CollectibleLook? avatarDecoration,
});

class ReplyPreview {
  final int id;
  /// Автор исходника — по нему вид в цитате подменяется, когда человек
  /// меняет профиль. `null` — ответ старого формата (кэш, старый сервер).
  final int? senderId;
  final String senderDisplayName;
  /// Мини-аватарка автора в строке ответа (как у Discord, 2026-10-03). `null` —
  /// аватарки нет или ответ старого формата: рисуется буква.
  final String? senderAvatar;
  final Map<String, String>? senderAvatarSizes;
  final String? senderColor;
  final String type;
  final String? preview; // null — исходник без текста, показываем плейсхолдер по type

  const ReplyPreview({
    required this.id,
    this.senderId,
    required this.senderDisplayName,
    this.senderAvatar,
    this.senderAvatarSizes,
    this.senderColor,
    required this.type,
    this.preview,
  });

  factory ReplyPreview.fromJson(Map<String, dynamic> j) => ReplyPreview(
    id: j['id'],
    senderId: j['sender_id'] as int?,
    senderDisplayName: j['sender_display_name'] ?? '',
    senderAvatar: j['sender_avatar'] as String?,
    senderAvatarSizes: parseAvatarSizes(j['sender_avatar_sizes']),
    senderColor: j['sender_color'] as String?,
    type: j['type'] ?? 'text',
    preview: j['preview'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'sender_id': senderId,
    'sender_display_name': senderDisplayName,
    'sender_avatar': senderAvatar,
    'sender_avatar_sizes': senderAvatarSizes,
    'sender_color': senderColor,
    'type': type,
    'preview': preview,
  };

  ReplyPreview withSenderLook(AuthorLook look) => ReplyPreview(
    id: id,
    senderId: senderId,
    senderDisplayName: look.displayName,
    senderAvatar: look.avatar,
    senderAvatarSizes: look.avatarSizes,
    senderColor: senderColor,
    type: type,
    preview: preview,
  );

  ReplyPreview withSenderColor(String? color) => ReplyPreview(
    id: id,
    senderId: senderId,
    senderDisplayName: senderDisplayName,
    senderAvatar: senderAvatar,
    senderAvatarSizes: senderAvatarSizes,
    senderColor: color,
    type: type,
    preview: preview,
  );
}

class Reaction {
  final String emoji;
  final int count;
  final bool reactedByMe;

  const Reaction({required this.emoji, required this.count, this.reactedByMe = false});

  factory Reaction.fromJson(Map<String, dynamic> j) => Reaction(
    emoji: j['emoji'] as String,
    count: j['count'] as int,
    reactedByMe: j['reacted_by_me'] == true,
  );

  Map<String, dynamic> toJson() => {'emoji': emoji, 'count': count, 'reacted_by_me': reactedByMe};

  static List<Reaction> applyOptimisticToggle(List<Reaction> current, String emoji) {
    final list = List<Reaction>.from(current);

    final mineIdx = list.indexWhere((r) => r.reactedByMe);
    if (mineIdx != -1) {
      final mine = list[mineIdx];
      if (mine.count <= 1) {
        list.removeAt(mineIdx);
      } else {
        list[mineIdx] = Reaction(emoji: mine.emoji, count: mine.count - 1);
      }
      if (mine.emoji == emoji) return list; // тот же эмодзи — просто сняли
    }

    final targetIdx = list.indexWhere((r) => r.emoji == emoji);
    if (targetIdx == -1) {
      list.add(Reaction(emoji: emoji, count: 1, reactedByMe: true));
    } else {
      final r = list[targetIdx];
      list[targetIdx] = Reaction(emoji: r.emoji, count: r.count + 1, reactedByMe: true);
    }
    return list;
  }
}

extension ReactionListX on List<Reaction> {
  String? get mine {
    for (final r in this) {
      if (r.reactedByMe) return r.emoji;
    }
    return null;
  }
}

List<Reaction> mergeReactionsFromEvent(List<Reaction> incoming, List<Reaction> previous, {required bool actorIsMe}) {
  if (actorIsMe) return incoming;
  final prevMine = previous.mine;
  return incoming.map((r) => Reaction(emoji: r.emoji, count: r.count, reactedByMe: r.emoji == prevMine)).toList();
}

const kSenderUser = 'user';
const kSenderWebhook = 'webhook';

class Message {
  final int id;
  final int chatId;
  final int senderId;
  final String senderKind;
  final String senderNickname;
  final String senderDisplayName;
  final String? senderAvatar;
  final Map<String, String>? senderAvatarSizes;
  /// Украшение аватарки автора (оформление профиля, 2026-10-24). `null` — не
  /// надето или автор — вебхук.
  final CollectibleLook? senderAvatarDecoration;
  final String? senderColor;
  final String? content;
  final String? caption;
  final FileAudio? fileAudio;
  final String? fileUrl; // выделенное поле на тип, не общий content
  final String? fileName;
  final int? fileSize;
  final String? geo; // "lat,lon" — выделенное поле на тип
  final String? voiceUrl; // JSON {"url":..,"duration":..} — выделенное поле на тип
  final String? videoNote; // JSON {"url":..,"thumb":..,"duration":..} — «кружок», своё поле
  final String? sticker; // JSON {"url","format","emoji","w","h"} — стикер, своё поле
  final String? transcript; // расшифровка голосового (null — ещё не расшифровано)
  final String type; // text / photo / video / file
  final DateTime createdAt;
  final DateTime? editedAt; // null — не редактировалось
  final int? replyToId; // ответ на сообщение этого же чата
  final ReplyPreview? replyTo; // превью исходника (null — исходник удалён/не ответ)
  final String? forwardedFrom; // display_name автора оригинала при пересылке
  /// sending / sent / delivered / read / failed.
  final String status;
  final String? localPath; // путь к локальному файлу для pending-сообщений
  /// Пропорция (ширина / высота) одиночного фото или видео, пока оно
  /// отправляется: у отправленного она приходит с сервера в content
  /// (`{"url","w","h"}`), а у временного её меряет ChatProvider по файлу на
  /// устройстве — иначе временное рисовалось бы во всю ширину и сжималось
  /// после отправки. Живёт столько же, сколько [localPath].
  final double? localAspectRatio;
  final List<Reaction> reactions;
  final CallInfo? call; // заполнено только у type == 'call' (запись о звонке)
  final PollInfo? poll;
  final List<Mention> mentions;
  final bool mentionsMe;
  final List<Embed> embeds;
  final SystemInfo? system;

  const Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    this.senderKind = kSenderUser,
    required this.senderNickname,
    required this.senderDisplayName,
    this.senderAvatar,
    this.senderAvatarSizes,
    this.senderAvatarDecoration,
    this.senderColor,
    this.content,
    this.caption,
    this.fileUrl,
    this.fileName,
    this.fileSize,
    this.fileAudio,
    this.geo,
    this.voiceUrl,
    this.videoNote,
    this.sticker,
    this.transcript,
    required this.type,
    required this.createdAt,
    this.editedAt,
    this.replyToId,
    this.replyTo,
    this.forwardedFrom,
    required this.status,
    this.localPath,
    this.localAspectRatio,
    this.reactions = const [],
    this.call,
    this.poll,
    this.mentions = const [],
    this.mentionsMe = false,
    this.embeds = const [],
    this.system,
  });

  BubbleData toBubble() => BubbleData(
    id: id,
    senderId: senderId,
    senderKind: senderKind,
    type: type,
    content: switch (type) { 'geo' => geo, 'file' => fileUrl, 'voice' => voiceUrl, 'video_note' => videoNote, 'sticker' => sticker, _ => content },
    caption: caption,
    fileName: fileName,
    fileSize: fileSize,
    fileAudio: fileAudio,
    localPath: localPath,
    localAspectRatio: localAspectRatio,
    createdAt: createdAt,
    editedAt: editedAt,
    replyTo: replyTo,
    forwardedFrom: forwardedFrom,
    senderNickname: senderNickname,
    senderDisplayName: senderDisplayName,
    senderAvatar: senderAvatar,
    senderAvatarSizes: senderAvatarSizes,
    senderAvatarDecoration: senderAvatarDecoration,
    senderColor: senderColor,
    status: status,
    transcript: transcript,
    reactions: reactions,
    call: call,
    poll: poll,
    mentions: mentions,
    mentionsMe: mentionsMe,
    embeds: embeds,
    system: system,
  );

  Message copyWith({String? status, String? content, String? caption, String? localPath, double? localAspectRatio, String? transcript, DateTime? editedAt, List<Reaction>? reactions, AuthorLook? author, ({String? color})? senderColor, ReplyPreview? replyTo, PollInfo? poll, List<Mention>? mentions, bool? mentionsMe, List<Embed>? embeds, SystemInfo? system}) => Message(
    id: id, chatId: chatId, senderId: senderId, senderKind: senderKind,
    senderNickname: senderNickname, senderDisplayName: author?.displayName ?? senderDisplayName,
    senderAvatar: author != null ? author.avatar : senderAvatar,
    senderAvatarSizes: author != null ? author.avatarSizes : senderAvatarSizes,
    senderAvatarDecoration: author != null ? author.avatarDecoration : senderAvatarDecoration,
    senderColor: senderColor != null ? senderColor.color : this.senderColor,
    content: content ?? this.content,
    caption: caption ?? this.caption, fileUrl: fileUrl, fileName: fileName, fileSize: fileSize, fileAudio: fileAudio, geo: geo, voiceUrl: voiceUrl,
    videoNote: videoNote,
    sticker: sticker,
    transcript: transcript ?? this.transcript,
    type: type, createdAt: createdAt,
    editedAt: editedAt ?? this.editedAt,
    replyToId: replyToId, replyTo: replyTo ?? this.replyTo, forwardedFrom: forwardedFrom,
    status: status ?? this.status,
    localPath: localPath ?? this.localPath,
    localAspectRatio: localAspectRatio ?? this.localAspectRatio,
    reactions: reactions ?? this.reactions,
    // Сохраняем данные звонка, иначе при обновлении статуса исчезнет плашка вызова.
    call: call,
    poll: poll ?? this.poll,
    mentions: mentions ?? ((content != null || caption != null) ? const [] : this.mentions),
    mentionsMe: mentionsMe ?? this.mentionsMe,
    embeds: embeds ?? this.embeds,
    system: system ?? this.system,
  );

  Message withAuthorLook(int userId, AuthorLook look) {
    final mine = senderId == userId;
    final quote = replyTo;
    final quoted = quote != null && quote.senderId == userId;
    final sys = system?.withPersonName(userId, look.displayName);
    final named = sys != null && !identical(sys, system);
    if (!mine && !quoted && !named) return this;
    return copyWith(
      author: mine ? look : null,
      replyTo: quoted ? quote.withSenderLook(look) : null,
      system: named ? sys : null,
    );
  }

  Message withNameColor(int userId, String? color) {
    final mine = senderId == userId && senderColor != color;
    final quote = replyTo;
    final quoted = quote != null && quote.senderId == userId && quote.senderColor != color;
    if (!mine && !quoted) return this;
    return copyWith(
      senderColor: mine ? (color: color) : null,
      replyTo: quoted ? quote.withSenderColor(color) : null,
    );
  }

  factory Message.fromJson(Map<String, dynamic> j) => Message(
    id: j['id'],
    chatId: j['chat_id'],
    senderId: j['sender_id'],
    senderKind: j['sender_kind'] as String? ?? kSenderUser,
    senderNickname: j['sender_nickname'],
    senderDisplayName: j['sender_display_name'],
    senderAvatar: j['sender_avatar'],
    senderAvatarSizes: parseAvatarSizes(j['sender_avatar_sizes']),
    senderAvatarDecoration: CollectibleLook.fromJson(j['sender_avatar_decoration']),
    senderColor: j['sender_color'] as String?,
    content: j['content'],
    caption: j['caption'],
    fileUrl: j['file_url'],
    fileName: j['file_name'],
    fileSize: j['file_size'],
    fileAudio: FileAudio.fromJson(j['file_audio']),
    geo: j['geo'],
    voiceUrl: j['voice_url'],
    videoNote: j['video_note'],
    sticker: j['sticker'],
    transcript: j['transcript'],
    type: j['type'] ?? 'text',
    createdAt: parseUtcLocal(j['created_at']),
    editedAt: j['edited_at'] != null ? parseUtcLocal(j['edited_at']) : null,
    replyToId: j['reply_to_id'],
    replyTo: j['reply_to'] != null ? ReplyPreview.fromJson(j['reply_to'] as Map<String, dynamic>) : null,
    forwardedFrom: j['forwarded_from'],
    status: j['status'] ?? 'sent',
    reactions: (j['reactions'] as List? ?? []).map((r) => Reaction.fromJson(r)).toList(),
    call: j['call'] != null ? CallInfo.fromJson(j['call'] as Map<String, dynamic>) : null,
    poll: j['poll'] != null ? PollInfo.fromJson(j['poll'] as Map<String, dynamic>) : null,
    mentions: Mention.listFrom(j['mentions'], (j['type'] ?? 'text') == 'text' ? j['content'] as String? : j['caption'] as String?),
    mentionsMe: j['mentions_me'] == true,
    embeds: Embed.listFrom(j['embeds']),
    system: SystemInfo.fromJson(j['system']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'chat_id': chatId,
    'sender_id': senderId,
    'sender_kind': senderKind,
    'sender_nickname': senderNickname,
    'sender_display_name': senderDisplayName,
    'sender_avatar': senderAvatar,
    'sender_avatar_sizes': senderAvatarSizes,
    'sender_avatar_decoration': senderAvatarDecoration?.toJson(),
    'sender_color': senderColor,
    'content': content,
    'caption': caption,
    'file_url': fileUrl,
    'file_name': fileName,
    'file_size': fileSize,
    'file_audio': fileAudio?.toJson(),
    'geo': geo,
    'voice_url': voiceUrl,
    'video_note': videoNote,
    'sticker': sticker,
    'transcript': transcript,
    'type': type,
    'created_at': utcIso(createdAt),
    'edited_at': editedAt == null ? null : utcIso(editedAt!),
    'reply_to_id': replyToId,
    'reply_to': replyTo?.toJson(),
    'forwarded_from': forwardedFrom,
    'status': status,
    'reactions': [for (final r in reactions) r.toJson()],
    'call': call?.toJson(),
    'poll': poll?.toJson(),
    'mentions': [for (final m in mentions) m.toJson()],
    'mentions_me': mentionsMe,
    'embeds': [for (final e in embeds) e.toJson()],
    'system': system?.toJson(),
  };
}

class MessagePreview {
  final int? id;
  final String? content;
  final String type;
  final DateTime createdAt;
  final String senderNickname;
  final String? caption;
  final String? mediaUrl;
  final SystemInfo? system;
  final String? senderDisplayName;

  const MessagePreview({
    this.id,
    this.content,
    required this.type,
    required this.createdAt,
    required this.senderNickname,
    this.caption,
    this.mediaUrl,
    this.system,
    this.senderDisplayName,
  });

  factory MessagePreview.fromJson(Map<String, dynamic> j) => MessagePreview(
    id: j['id'] as int?,
    content: j['content'],
    type: j['type'] ?? 'text',
    createdAt: parseUtcLocal(j['created_at']),
    senderNickname: j['sender_nickname'] as String? ?? '',
    caption: j['caption'],
    mediaUrl: j['media_url'],
    system: SystemInfo.fromJson(j['system']),
    senderDisplayName: j['sender_display_name'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'type': type,
    'created_at': utcIso(createdAt),
    'sender_nickname': senderNickname,
    'caption': caption,
    'media_url': mediaUrl,
    'system': system?.toJson(),
    'sender_display_name': senderDisplayName,
  };

  String? get previewText => switch (type) {
    'text' || 'system' || 'poll' || 'poll_result' => content,
    _ => caption,
  };

  factory MessagePreview.fromBubble(BubbleData b) => MessagePreview(
    id: b.id,
    content: b.poll?.question ?? b.content,
    type: b.type,
    createdAt: b.createdAt,
    senderNickname: b.senderNickname,
    caption: b.caption,
    mediaUrl: _previewMediaTypes.contains(b.type) ? b.content : null,
    system: b.system,
    senderDisplayName: b.senderDisplayName,
  );

  static const _previewMediaTypes = {'photo', 'video', 'album', 'sticker'};

  MessagePreview copyWith({String? content, String? caption}) => MessagePreview(
    id: id,
    content: content ?? this.content,
    type: type,
    createdAt: createdAt,
    senderNickname: senderNickname,
    caption: caption ?? this.caption,
    mediaUrl: mediaUrl,
    system: system,
    senderDisplayName: senderDisplayName,
  );
}
