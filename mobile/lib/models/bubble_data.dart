import 'collectible.dart';
import 'file_audio.dart';
import 'call.dart';
import 'poll.dart';
import 'mention.dart';
import 'embed.dart';
import 'system_info.dart';
import 'message.dart' show ReplyPreview, Reaction, kSenderUser, kSenderWebhook;

const Set<String> _editableTypes = {'text', 'photo', 'video', 'album', 'geo'};

const Set<String> kSentByPeopleTypes = {
  'text', 'photo', 'video', 'album', 'file', 'voice', 'geo', 'video_note', 'sticker', 'poll',
};

final Set<String> _forwardableTypes = kSentByPeopleTypes.difference({'poll', 'sticker'});

class BubbleData {
  final int id;
  final int senderId; // для определения isMine на экране
  final String senderKind; // человек или вебхук — Message.senderKind
  final String type; // 'text' | 'photo' | 'video' | 'album' | 'file' | 'voice' | 'geo' | 'call' | 'video_note' | 'sticker'
  final String? content; // текст / URL фото / URL видео / URL файла / "lat,lon"
  final String? caption; // подпись под медиа
  final String? fileName;
  final int? fileSize;
  final FileAudio? fileAudio;
  final String? localPath; // локальный путь пока идёт отправка
  final double? localAspectRatio; // пропорция одиночного медиа, пока идёт отправка (Message.localAspectRatio)
  final DateTime createdAt;
  final DateTime? editedAt; // null — не редактировалось (метка «изменено»)
  final ReplyPreview? replyTo; // цитата-исходник (ответ)
  final String? forwardedFrom; // метка «Переслано от X»
  final String senderNickname;
  final String senderDisplayName;
  final String? senderAvatar;
  final Map<String, String>? senderAvatarSizes;
  final CollectibleLook? senderAvatarDecoration; // украшение аватарки автора (оформление профиля)
  final String? senderColor; // цвет имени в канале сообщества ("#rrggbb"), null — обычный
  final String status; // 'sending' | 'sent' | 'read' | 'failed'
  final String? transcript; // расшифровка голосового (null — ещё не расшифровано)
  final List<Reaction> reactions;
  final CallInfo? call; // заполнено только у type == 'call'
  final PollInfo? poll; // у type == 'poll' и 'poll_result'
  final List<Mention> mentions; // упоминания в тексте (Message.mentions)
  final bool mentionsMe; // сообщение упомянуло меня — подсветка строки
  final List<Embed> embeds; // карточки сообщения программы (Message.embeds)
  final SystemInfo? system; // служебное: событие и второй участник (Message.system)

  const BubbleData({
    required this.id,
    required this.senderId,
    this.senderKind = kSenderUser,
    required this.type,
    this.content,
    this.caption,
    this.fileName,
    this.fileSize,
    this.fileAudio,
    this.localPath,
    this.localAspectRatio,
    required this.createdAt,
    this.editedAt,
    this.replyTo,
    this.forwardedFrom,
    required this.senderNickname,
    required this.senderDisplayName,
    this.senderAvatar,
    this.senderAvatarSizes,
    this.senderAvatarDecoration,
    this.senderColor,
    required this.status,
    this.transcript,
    this.reactions = const [],
    this.call,
    this.poll,
    this.mentions = const [],
    this.mentionsMe = false,
    this.embeds = const [],
    this.system,
  });

  bool get isEditable => forwardedFrom == null && _editableTypes.contains(type);

  String? get previewText {
    final own = switch (type) {
      'text' || 'system' => content,
      _ => poll?.question ?? caption,
    };
    return own != null && own.isNotEmpty ? own : Embed.summaryOf(embeds);
  }

  bool get isForwardable =>
      _forwardableTypes.contains(type) && !(type == 'text' && (content == null || content!.isEmpty));

  bool get isReplyable => type != 'system';

  bool get fromWebhook => senderKind == kSenderWebhook;

  BubbleData copyWith({String? status, String? content, List<Reaction>? reactions}) => BubbleData(
    id: id, senderId: senderId, senderKind: senderKind, type: type,
    content: content ?? this.content,
    caption: caption,
    fileName: fileName, fileSize: fileSize, fileAudio: fileAudio, localPath: localPath, localAspectRatio: localAspectRatio,
    createdAt: createdAt,
    editedAt: editedAt,
    replyTo: replyTo, forwardedFrom: forwardedFrom,
    senderNickname: senderNickname, senderDisplayName: senderDisplayName,
    senderAvatar: senderAvatar,
    senderAvatarSizes: senderAvatarSizes,
    senderAvatarDecoration: senderAvatarDecoration,
    senderColor: senderColor,
    status: status ?? this.status,
    transcript: transcript,
    reactions: reactions ?? this.reactions,
    call: call, // как и остальные поля — не теряется при смене статуса
    poll: poll,
    mentions: content != null ? const [] : mentions,
    mentionsMe: mentionsMe,
    embeds: embeds,
    system: system,
  );
}
