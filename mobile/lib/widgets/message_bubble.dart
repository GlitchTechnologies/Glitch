import '../screens/user_profile_screen.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'local_image_web.dart' if (dart.library.io) 'local_image_native.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/media_platform_web.dart' if (dart.library.io) '../services/media_platform_native.dart';
import '../models/bubble_data.dart';
import '../models/poll.dart' show PollAnswer;
import '../models/mention.dart' show Mention;
import '../core/date_text.dart';
import '../core/glitch_link.dart';
import '../core/l10n.dart';
import '../core/file_size.dart';
import '../core/media_content.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import 'animated_network_image.dart';
import '../widgets/glitch_avatar.dart';
import '../widgets/geo_map_widget.dart';
import '../widgets/file_attachment_widget.dart';
import '../widgets/file_badge.dart';
import '../widgets/linked_text.dart';
import '../widgets/video_note_player.dart';
import '../widgets/chat_metrics.dart';
import '../widgets/media_grid.dart';
import '../widgets/selectable_content.dart';
import '../widgets/glitch_pressable.dart' show ClickableCursor;
import 'viewport_gate.dart';
import '../widgets/sticker_view.dart';
import '../screens/media_viewer_screen.dart';
import '../models/user.dart' show User;
import 'voice_message_player.dart';
import 'invite_link_card.dart';
import 'embed_card.dart';
import 'message_card.dart';
import 'poll_card.dart';

class MessageBubble extends StatelessWidget {
  final BubbleData data;

  final bool isMine;

  final double? uploadProgress;
  final (int, int)? uploadBytes;

  final Future<String> Function()? onTranscribe;

  final Future<bool> Function(List<int> answerIds)? onPollVote;
  final void Function(PollAnswer answer)? onPollVoters;
  final void Function(int messageId)? onOpenPoll;

  final void Function(BuildContext context, Mention mention, Rect rect)? onMentionTap;

  const MessageBubble({
    super.key,
    required this.data,
    required this.isMine,
    this.uploadProgress,
    this.uploadBytes,
    this.onTranscribe,
    this.onPollVote,
    this.onPollVoters,
    this.onOpenPoll,
    this.onMentionTap,
  });

  static const double _mediaRadius = 8;

  static const double _textGap = 6;

  bool get _hasCaption => data.caption != null && data.caption!.isNotEmpty;

  TextStyle get _textStyle => TextStyle(color: GlitchColors.textPrimary, fontSize: 15, height: 1.375);

  InlineSpan? _editedSuffix(BuildContext context) => data.editedAt == null
      ? null
      : TextSpan(
          text: ' (${context.s.edited})',
          style: TextStyle(fontSize: 11, color: GlitchColors.textHint),
        );

  Widget _richText(BuildContext context, String text) {
    final suffix = _editedSuffix(context);
    final Widget body = LinkedText.needed(text, data.mentions)
        ? LinkedText(text: text, baseStyle: _textStyle, onLaunch: launchSmartUrl, suffix: suffix,
            mentions: data.mentions, onMentionTap: onMentionTap)
        : Text.rich(TextSpan(text: text, children: [if (suffix != null) suffix]), style: _textStyle);
    return data.type == 'text' ? body : SelectableContent(fillWidth: true, child: body);
  }

  List<Widget> _captionAbove(BuildContext context) => _hasCaption
      ? [_richText(context, data.caption!), const SizedBox(height: _textGap)]
      : const [];

  Widget _uploadOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.45),
        child: Center(
          child: SizedBox(
            width: 54, height: 54,
            child: CircularProgressIndicator(
              value: uploadProgress,
              strokeWidth: 3.5,
              color: Colors.white,
              backgroundColor: Colors.white.withOpacity(0.22),
            ),
          ),
        ),
      ),
    );
  }

  Widget _uploadSizeLabel(BuildContext context) {
    final label = uploadBytes != null
        ? '${formatBytes(context.s, uploadBytes!.$1)} / ${formatBytes(context.s, uploadBytes!.$2)}'
        : data.type == 'video'
            ? context.s.compressing
            : null;
    if (label == null) return const SizedBox.shrink();
    return Positioned(
      top: 8, right: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = ChatMetrics.of(context);
    final content = _content(context, m);
    if (data.embeds.isEmpty) return content ?? const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (content != null) ...[content, const SizedBox(height: _textGap)],
        for (var i = 0; i < data.embeds.length; i++) ...[
          if (i > 0) const SizedBox(height: _textGap),
          EmbedCard(
            embed: data.embeds[i],
            inheritSelection: data.type == 'text',
            onOpenImage: (media) => _openPhoto(context, media.url, [media.url], [media.aspectRatio], [false]),
          ),
        ],
      ],
    );
  }

  Widget? _content(BuildContext context, ChatMetrics m) {
    switch (data.type) {
      case 'photo':
      case 'album':
        return _buildPhoto(context, m);
      case 'video':
        return _buildVideo(context, m);
      case 'file':
        return _buildFile(context, m);
      case 'geo':
        return _buildGeo(context, m);
      case 'voice':
        return _buildVoice(context, m);
      case 'video_note':
        return ViewportGate(
          placeholder: SizedBox.square(dimension: m.videoNote),
          builder: (_) => VideoNoteView(
            note: parseVideoNote(data.content),
            size: m.videoNote,
            localThumbPath: data.localPath,
            sending: data.status == 'sending',
            failed: data.status == 'failed',
            progress: uploadProgress,
          ),
        );
      case 'sticker':
        return ViewportGate(
          placeholder: SizedBox.square(dimension: m.sticker),
          builder: (_) => StickerView(
            sticker: parseSticker(data.content),
            size: m.sticker,
          ),
        );
      case 'call':
        return _buildCall(context, m);
      case 'poll':
        final poll = data.poll;
        if (poll == null) return _buildUnsupported(context, m);
        return PollCard(
          poll: poll,
          maxWidth: m.card,
          onVote: data.id > 0 ? onPollVote : null,
          onShowVoters: data.id > 0 ? onPollVoters : null,
        );
      case 'poll_result':
        final poll = data.poll;
        return PollResultCard(
          poll: poll,
          maxWidth: m.card,
          onOpen: poll == null || onOpenPoll == null ? null : () => onOpenPoll!(poll.messageId),
        );
      case 'text':
        if ((data.content ?? '').isEmpty && data.embeds.isNotEmpty) return null;
        return _buildText(context, m);
      default:
        return _buildUnsupported(context, m);
    }
  }

  Widget _buildUnsupported(BuildContext context, ChatMetrics m) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: m.card),
      child: MessageCard(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline_rounded, size: 20, color: GlitchColors.textHint),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                context.s.messageUnsupported,
                style: TextStyle(fontSize: 14, color: GlitchColors.textHint),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildText(BuildContext context, ChatMetrics m) {
    final linkCard = switch (glitchTargetInText(data.content ?? '')) {
      ProfileLinkTarget(:final nickname) => _ProfileLinkPreview(nickname: nickname),
      InviteLinkTarget(:final code) => InviteLinkCard(code: code),
      null => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _richText(context, data.content ?? ''),
        if (linkCard != null) ...[
          const SizedBox(height: _textGap),
          SelectionContainer.disabled(
            child: ConstrainedBox(constraints: BoxConstraints(maxWidth: m.card), child: linkCard),
          ),
        ],
      ],
    );
  }

  Widget _buildPhoto(BuildContext context, ChatMetrics m) {
    final isLocal = data.localPath != null;
    final List<String> urls;
    double? photoAspectRatio;
    List<double?>? itemAspectRatios;
    List<bool>? videoFlags;
    List<String?>? videoThumbs;
    if (isLocal) {
      final lp = data.localPath!;
      urls = lp.startsWith('[') ? (jsonDecode(lp) as List).cast<String>() : [lp];
      photoAspectRatio = data.localAspectRatio;
    } else if (data.type == 'album') {
      final items = parseAlbumContent(data.content ?? '');
      urls = items.map((i) => i.url).toList();
      videoFlags = items.map((i) => i.isVideo).toList();
      videoThumbs = items.map((i) => i.thumb).toList();
      itemAspectRatios = items.map((i) => i.aspectRatio).toList();
      photoAspectRatio = itemAspectRatios.isNotEmpty ? itemAspectRatios.first : null;
    } else {
      final parsed = parseMediaContent(data.content ?? '');
      urls = [parsed.url];
      photoAspectRatio = parsed.aspectRatio;
      itemAspectRatios = [parsed.aspectRatio];
      videoThumbs = [parsed.thumb];
    }

    final width = urls.length == 1 ? m.singleMedia(photoAspectRatio) : m.media;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ..._captionAbove(context),
        SizedBox(
          width: width,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_mediaRadius),
            child: Stack(
              children: [
                _buildPhotoGrid(context, urls, isLocal: isLocal, singleAspectRatio: photoAspectRatio, itemAspectRatios: itemAspectRatios, videoFlags: videoFlags, videoThumbs: videoThumbs),
                if (data.status == 'sending') _uploadOverlay(),
                if (data.status == 'sending') _uploadSizeLabel(context),
              ],
            ),
          ),
        ),
      ],
    );
  }

  bool _isVideoUrl(String url) {
    final u = url.toLowerCase();
    return u.endsWith('.mp4') || u.endsWith('.mov') || u.endsWith('.webm') || u.endsWith('.avi');
  }

  Widget _buildPhotoGrid(BuildContext context, List<String> urls, {bool isLocal = false, double? singleAspectRatio, List<double?>? itemAspectRatios, List<bool>? videoFlags, List<String?>? videoThumbs}) {
    bool isVideoAt(int i) => (videoFlags != null && i < videoFlags.length) ? videoFlags[i] : _isVideoUrl(urls[i]);
    String? thumbAt(int i) => (videoThumbs != null && i < videoThumbs.length) ? videoThumbs[i] : null;

    Widget tile(int i, double w, double? h) {
      final url = urls[i];
      final isVideo = isVideoAt(i);
      final networkUrl = isLocal ? url : api.mediaUrl(url);
      final fit = h == null ? BoxFit.fitWidth : BoxFit.cover;
      final ar = h == null ? (singleAspectRatio ?? (itemAspectRatios != null && i < itemAspectRatios.length ? itemAspectRatios[i] : null)) : null;

      Widget stub(Widget inner) => ar != null
          ? AspectRatio(
              aspectRatio: ar,
              child: Container(width: w, color: GlitchColors.bgInput, child: Center(child: inner)),
            )
          : Container(width: w, height: h ?? 180, color: GlitchColors.bgInput, child: Center(child: inner));

      final Widget content;
      if (isVideo) {
        content = Stack(children: [
          ViewportGate(
            placeholder: VideoNetworkThumb.placeholder(width: w, height: h),
            builder: (_) => VideoNetworkThumb(key: ValueKey(networkUrl), url: networkUrl, width: w, height: h,
              headers: isLocal ? const {} : api.headersFor(networkUrl),
              thumbUrl: isLocal ? null : thumbAt(i)),
          ),
          const Positioned.fill(child: Center(child: VideoPlayBadge())),
        ]);
      } else if (isLocal) {
        content = localImage(url, width: w, height: h, fit: fit);
      } else if (isGifUrl(url)) {
        content = ViewportGate(
          placeholder: stub(const SizedBox.shrink()),
          builder: (_) => AnimatedNetworkImage(
            url: api.mediaUrl(url),
            headers: api.headersFor(api.mediaUrl(url)),
            width: w, height: h, fit: fit,
            placeholder: (_) => stub(CircularProgressIndicator(strokeWidth: 2, color: GlitchColors.accentBlue)),
          ),
        );
      } else {
        content = ViewportGate(
          placeholder: stub(const SizedBox.shrink()),
          builder: (_) => CachedNetworkImage(
            imageUrl: api.mediaUrl(url),
            cacheManager: mediaCacheManager,
            width: w, height: h, fit: fit, alignment: Alignment.center,
            placeholder: (_, __) => stub(CircularProgressIndicator(strokeWidth: 2, color: GlitchColors.accentBlue)),
            errorWidget: (_, __, ___) => stub(Icon(Icons.broken_image, color: GlitchColors.textHint)),
          ),
        );
      }

      return ClickableCursor(
        enabled: !isLocal,
        child: GestureDetector(
          onTap: isLocal ? null : () => _openPhoto(context, url, urls, itemAspectRatios, videoFlags),
          child: content,
        ),
      );
    }

    return MediaGridLayout(count: urls.length, tile: tile);
  }

  void _openPhoto(BuildContext context, String url, List<String> allUrls, [List<double?>? itemAspectRatios, List<bool>? videoFlags]) {
    final items = [
      for (int i = 0; i < allUrls.length; i++)
        MediaItem(
          url: api.mediaUrl(allUrls[i]),
          isVideo: (videoFlags != null && i < videoFlags.length) ? videoFlags[i] : _isVideoUrl(allUrls[i]),
          aspectRatio: (itemAspectRatios != null && i < itemAspectRatios.length) ? itemAspectRatios[i] : null,
        ),
    ];
    final initialIndex = allUrls.indexOf(url).clamp(0, allUrls.length - 1);
    openMediaViewer(
      context,
      items: items,
      initialIndex: initialIndex,
      senderName: data.senderDisplayName,
      senderNickname: data.senderNickname,
      senderAvatarUrl: data.senderAvatar != null ? api.mediaUrl(data.senderAvatar!) : null,
      senderAvatarSizes: data.senderAvatarSizes,
      time: formatTime(data.createdAt),
      colorIndex: GlitchAvatar.colorFromNickname(data.senderNickname),
    );
  }

  Widget _buildGeo(BuildContext context, ChatMetrics m) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ..._captionAbove(context),
        SizedBox(
          width: m.card,
          child: GeoMapWidget(
            geo: data.content ?? '0,0',
            borderRadius: BorderRadius.circular(_mediaRadius),
          ),
        ),
      ],
    );
  }

  Widget _buildVoice(BuildContext context, ChatMetrics m) {
    final Widget player = data.status == 'sending'
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 40, height: 40,
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2, color: GlitchColors.accentBlue),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: kVoiceWaveformWidth,
                child: Text(
                  context.s.recordingSending,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: GlitchColors.textSecond),
                ),
              ),
              if (onTranscribe != null) ...[
                const SizedBox(width: 10),
                const SizedBox(width: 36, height: 36),
              ],
            ],
          )
        : VoiceMessagePlayer(
            content: data.content ?? '',
            transcript: data.transcript,
            onTranscribe: onTranscribe,
          );
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: m.card),
      child: MessageCard(child: player),
    );
  }

  Widget _buildFile(BuildContext context, ChatMetrics m) {
    final name = data.fileName ?? context.s.file;
    final Widget body;
    if (data.status != 'sending' && data.localPath == null) {
      body = FileAttachmentWidget(
        url: api.mediaUrl(data.content ?? ''),
        fileName: name,
        fileSize: data.fileSize,
        audio: data.fileAudio,
      );
    } else {
      body = Row(children: [
        FileBadge(name),
        const SizedBox(width: 10),
        Expanded(child: Text(name,
          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: GlitchColors.textPrimary),
          maxLines: 2, overflow: TextOverflow.ellipsis,
        )),
        if (data.status == 'sending') ...[
          const SizedBox(width: 8),
          SizedBox(width: 22, height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: GlitchColors.accentBlue)),
        ],
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ..._captionAbove(context),
        SizedBox(width: m.card, child: MessageCard(child: body)),
      ],
    );
  }

  Widget _buildCall(BuildContext context, ChatMetrics m) {
    final call = data.call;

    final status = call?.status ?? 'ended';
    final missed = call?.isMissed ?? false;

    final group = call?.isGroup ?? false;
    final String title = group ? context.s.groupCallTitle : switch (status) {
      'missed' => context.s.callMissed,
      'declined' => context.s.callDeclined,
      'cancelled' => context.s.callCancelled,
      'failed' => context.s.callFailed,
      _ => isMine ? context.s.callOutgoing : context.s.callIncoming,
    };

    final String subtitle = [
      (call?.wasAnswered ?? false) ? call!.formattedDuration : context.s.callAudio,
      if (group && (call?.participants ?? 0) > 0) context.s.membersCount(call!.participants),
    ].join(' · ');

    final IconData icon = switch (status) {
      'missed' => isMine ? Icons.call_missed_outgoing_rounded : Icons.call_missed_rounded,
      'ended' => isMine ? Icons.call_made_rounded : Icons.call_received_rounded,
      _ => Icons.call_end_rounded,
    };

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: m.card),
      child: MessageCard(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: missed ? GlitchColors.error.withOpacity(0.16) : GlitchColors.bgInput,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 21, color: missed ? GlitchColors.error : GlitchColors.textPrimary),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: missed ? GlitchColors.error : GlitchColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: GlitchColors.textHint),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideo(BuildContext context, ChatMetrics m) {
    final isLocal = data.localPath != null;
    final String url;
    double? videoAspectRatio;
    String? videoThumbUrl;
    if (isLocal) {
      url = data.localPath!;
      videoAspectRatio = data.localAspectRatio;
    } else {
      final parsed = parseMediaContent(data.content ?? '');
      url = api.mediaUrl(parsed.url);
      videoAspectRatio = parsed.aspectRatio;
      videoThumbUrl = parsed.thumb;
    }
    final width = m.singleMedia(videoAspectRatio);
    final double? height = videoAspectRatio != null ? width / videoAspectRatio : null;

    final mediaWidget = ClickableCursor(
      enabled: !isLocal,
      child: GestureDetector(
        onTap: isLocal ? null : () => _openVideo(context, url, videoAspectRatio),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_mediaRadius),
          child: Stack(
            children: [
              ViewportGate(
                placeholder: VideoNetworkThumb.placeholder(width: width, height: height),
                builder: (_) => VideoNetworkThumb(key: ValueKey(url), url: url, width: width,
                  height: height, headers: isLocal ? const {} : api.headersFor(url),
                  thumbUrl: isLocal ? null : videoThumbUrl),
              ),
              if (data.status != 'sending')
                const Positioned.fill(
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                      child: Padding(
                        padding: EdgeInsets.all(14),
                        child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40),
                      ),
                    ),
                  ),
                ),
              if (data.status == 'sending') _uploadOverlay(),
              if (data.status == 'sending') _uploadSizeLabel(context),
            ],
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ..._captionAbove(context),
        SizedBox(width: width, child: mediaWidget),
      ],
    );
  }

  void _openVideo(BuildContext context, String url, double? aspectRatio) {
    openMediaViewer(
      context,
      items: [MediaItem(url: url, isVideo: true, aspectRatio: aspectRatio)],
      senderName: data.senderDisplayName,
      senderNickname: data.senderNickname,
      senderAvatarUrl: data.senderAvatar != null ? api.mediaUrl(data.senderAvatar!) : null,
      senderAvatarSizes: data.senderAvatarSizes,
      time: formatTime(data.createdAt),
      colorIndex: GlitchAvatar.colorFromNickname(data.senderNickname),
    );
  }
}


class VideoPlayBadge extends StatelessWidget {
  const VideoPlayBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
      child: Padding(
        padding: EdgeInsets.all(10),
        child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
      ),
    );
  }
}

class VideoNetworkThumb extends StatefulWidget {
  final String url;
  final double width;
  final double? height;
  final Map<String, String> headers;
  final bool transparentPlaceholder;

  final String? thumbUrl;

  const VideoNetworkThumb({
    super.key,
    required this.url,
    required this.width,
    this.height,
    required this.headers,
    this.transparentPlaceholder = false,
    this.thumbUrl,
  });

  static Widget placeholder({required double width, double? height}) => Container(
        width: width,
        height: height ?? 200,
        color: const Color(0xFF1e1e1e),
      );

  @override
  State<VideoNetworkThumb> createState() => _VideoNetworkThumbState();
}

class _VideoNetworkThumbState extends State<VideoNetworkThumb> {
  Uint8List? _thumb;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    if (widget.thumbUrl == null) _generate();
  }

  @override
  void didUpdateWidget(VideoNetworkThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.thumbUrl != widget.thumbUrl) {
      _thumb = null;
      _done = false;
      if (widget.thumbUrl == null) _generate();
    }
  }

  Future<void> _generate() async {
    try {
      final data = await videoFrameFromUrl(
        widget.url,
        headers: widget.headers,
        maxWidth: (widget.width * 2).toInt(),
        quality: 70,
      );
      if (mounted) setState(() { _thumb = data; _done = true; });
    } catch (_) {
      if (mounted) setState(() => _done = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = widget.thumbUrl;
    if (ready != null) {
      return CachedNetworkImage(
        imageUrl: api.mediaUrl(ready),
        httpHeaders: api.headersFor(api.mediaUrl(ready)),
        width: widget.width,
        height: widget.height,
        fit: widget.height != null ? BoxFit.cover : BoxFit.fitWidth,
        placeholder: (_, __) => widget.transparentPlaceholder
            ? SizedBox(width: widget.width, height: widget.height ?? 200)
            : VideoNetworkThumb.placeholder(width: widget.width, height: widget.height),
        // Превью не открылось — не повод показывать «сломанную картинку»:
        // поверх всё равно лежит кнопка воспроизведения, видео откроется.
        errorWidget: (_, __, ___) => VideoNetworkThumb.placeholder(width: widget.width, height: widget.height),
      );
    }
    if (_thumb != null) {
      return Image.memory(
        _thumb!,
        width: widget.width,
        height: widget.height,
        fit: widget.height != null ? BoxFit.cover : BoxFit.fitWidth,
      );
    }
    if (widget.transparentPlaceholder) {
      return SizedBox(width: widget.width, height: widget.height ?? 200);
    }
    return Container(
      width: widget.width,
      height: widget.height ?? 200,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF1c1c1c), Color(0xFF2c2c2c)],
        ),
      ),
      child: _done ? null : const Center(
        child: SizedBox(width: 24, height: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white30)),
      ),
    );
  }
}


class _ProfileLinkPreview extends StatefulWidget {
  final String nickname;
  const _ProfileLinkPreview({required this.nickname});

  @override
  State<_ProfileLinkPreview> createState() => _ProfileLinkPreviewState();
}


class _ProfileLinkPreviewState extends State<_ProfileLinkPreview> {
  User? _user;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load(widget.nickname);
  }

  @override
  void didUpdateWidget(_ProfileLinkPreview old) {
    super.didUpdateWidget(old);
    if (old.nickname != widget.nickname) {
      setState(() { _user = null; _loading = true; });
      _load(widget.nickname);
    }
  }

  Future<void> _load(String nickname) async {
    if (api.userPreviewCache.containsKey(nickname)) {
      if (mounted) setState(() { _user = api.userPreviewCache[nickname]; _loading = false; });
      return;
    }
    try {
      final u = await api.getUser(nickname);
      api.userPreviewCache[nickname] = u;
      if (mounted && widget.nickname == nickname) {
        setState(() { _user = u; _loading = false; });
      }
    } catch (_) {
      if (mounted && widget.nickname == nickname) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return MessageCard(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        child: SizedBox(height: 18, width: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: GlitchColors.accentBlue)),
      );
    }

    final u = _user;
    if (u == null) return const SizedBox.shrink();

    final name = u.displayName;
    final avatarUrl = u.avatar;
    final initials = GlitchAvatar.initialsFromName(name);
    final colorIdx = GlitchAvatar.colorFromNickname(name);
    final subtitle = u.bio;

    return ClickableCursor(child: GestureDetector(
      onTap: () => showUserProfile(context, nickname: u.nickname),
      child: IntrinsicWidth(
      child: MessageCard(
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GlitchAvatar(
                    initials: initials,
                    colorIndex: colorIdx,
                    size: 46,
                    imageUrl: avatarUrl != null ? api.mediaUrl(avatarUrl) : null,
                    avatarSizes: u.avatarSizes,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            color: GlitchColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        if (subtitle != null && subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: TextStyle(color: GlitchColors.textSecond, fontSize: 13, height: 1.3),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: GlitchColors.borderSoft),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                context.s.goToProfile,
                style: TextStyle(
                  color: GlitchColors.accentBlue,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    ));
  }
}
