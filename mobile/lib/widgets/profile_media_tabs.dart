import '../services/file_open_result.dart';
import '../services/file_open_web.dart' if (dart.library.io) '../services/file_open_native.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/media_platform_web.dart' if (dart.library.io) '../services/media_platform_native.dart';
import '../core/l10n.dart';
import '../core/date_text.dart';
import '../core/file_size.dart';
import '../core/media_content.dart';
import '../models/message.dart';
import '../providers/contact_provider.dart';
import '../screens/media_viewer_screen.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'glitch_avatar.dart';
import 'glitch_pressable.dart' show ClickableCursor;
import 'glitch_segmented_control.dart';
import 'glitch_toast.dart';
import 'file_badge.dart';
import 'media_tab_placeholder.dart';

class ProfileMediaTabs extends StatefulWidget {
  final ContactProvider provider;
  final double? height;

  const ProfileMediaTabs({super.key, required this.provider, this.height});

  @override
  State<ProfileMediaTabs> createState() => _ProfileMediaTabsState();
}

class _ProfileMediaTabsState extends State<ProfileMediaTabs> {
  int _tab = 0; // 0 = медиа, 1 = файлы

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.provider,
      builder: (context, _) {
        final content = _tab == 0 ? _buildMediaGrid() : _buildFilesList();
        final h = widget.height;
        return Column(
          mainAxisSize: h == null ? MainAxisSize.max : MainAxisSize.min,
          children: [
            GlitchSegmentedControl(
              labels: [context.s.media, context.s.files],
              selected: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
            const SizedBox(height: 12),
            if (h == null) Expanded(child: content) else SizedBox(height: h, child: content),
          ],
        );
      },
    );
  }

  List<GalleryTile> get _tiles => flattenMediaMessages(widget.provider.mediaMessages);

  void _openMedia(int index) {
    final tiles = _tiles;
    final tile = tiles[index];
    final allItems = tiles
        .map((t) => MediaItem(url: api.mediaUrl(t.url), isVideo: t.isVideo, aspectRatio: t.aspectRatio))
        .toList();
    openMediaViewer(
      context,
      items: allItems,
      initialIndex: index,
      senderName: tile.message.senderDisplayName,
      senderNickname: tile.message.senderNickname,
      senderAvatarUrl: tile.message.senderAvatar != null ? api.mediaUrl(tile.message.senderAvatar!) : null,
      senderAvatarSizes: tile.message.senderAvatarSizes,
      colorIndex: GlitchAvatar.colorFromNickname(tile.message.senderNickname),
    );
  }

  Widget _buildMediaGrid() {
    if (widget.provider.mediaLoading) {
      return const MediaTabPlaceholder(loading: true);
    }
    final tiles = _tiles;
    if (tiles.isEmpty) {
      return MediaTabPlaceholder(loading: false, emptyText: context.s.contactNoMedia);
    }
    return GridView.builder(
      physics: const ClampingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: tiles.length,
      itemBuilder: (_, i) {
        final tile = tiles[i];
        final mediaUrl = api.mediaUrl(tile.url);
        final isVideo = tile.isVideo;
        return GestureDetector(
          onTap: () => _openMedia(i),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (isVideo)
                  _MediaGridVideoThumb(url: mediaUrl)
                else
                  CachedNetworkImage(
                    imageUrl: mediaUrl,
                    cacheManager: mediaCacheManager,
                    fit: BoxFit.cover,
                    httpHeaders: api.headersFor(mediaUrl),
                    placeholder: (_, __) => Container(color: GlitchColors.bgInput),
                    errorWidget: (_, __, ___) => Container(color: GlitchColors.bgInput),
                  ),
                if (isVideo)
                  Container(
                    color: Colors.black26,
                    alignment: Alignment.center,
                    child: Container(
                      width: 32, height: 32,
                      decoration: const BoxDecoration(color: Color(0x88000000), shape: BoxShape.circle),
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilesList() {
    if (widget.provider.mediaLoading) {
      return const MediaTabPlaceholder(loading: true);
    }
    if (widget.provider.fileMessages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file_outlined, color: GlitchColors.textHint, size: 40),
            const SizedBox(height: 10),
            Text(context.s.contactNoFiles, style: TextStyle(color: GlitchColors.textSecond, fontSize: 14)),
          ],
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: GlitchColors.bgCard,
        border: Border.all(color: GlitchColors.borderCard),
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        physics: const ClampingScrollPhysics(),
        itemCount: widget.provider.fileMessages.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: GlitchColors.borderSoft, indent: 70),
        itemBuilder: (_, i) => _FileRow(msg: widget.provider.fileMessages[i]),
      ),
    );
  }
}

class _FileRow extends StatefulWidget {
  final Message msg;
  const _FileRow({required this.msg});

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _loading = false;

  Future<void> _download() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final url = api.mediaUrl(widget.msg.content ?? '');
      final result = await downloadAndOpenFile(
        url: url,
        fileName: widget.msg.fileName ?? 'file',
        headers: api.headersFor(url),
      );
      if (mounted && result == FileOpenResult.failed) {
        GlitchToast.show(context, context.s.fileDownloadError);
      }
    } catch (e) {
      if (mounted) GlitchToast.show(context, context.s.contactError('$e'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.msg.fileName ?? context.s.file;
    final date = formatMessageStamp(context, widget.msg.createdAt);
    final fileSize = widget.msg.fileSize;
    final meta = [if (fileSize != null) formatBytes(context.s, fileSize), date].where((s) => s.isNotEmpty).join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          FileBadge(name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: GlitchColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (meta.isNotEmpty)
                  Text(meta, style: TextStyle(fontSize: 12.5, color: GlitchColors.textSecond)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _loading
              ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: GlitchColors.accentBlue))
              : ClickableCursor(
                  child: GestureDetector(
                    onTap: _download,
                    child: Icon(Icons.download_rounded, color: GlitchColors.textSecond, size: 22),
                  ),
                ),
        ],
      ),
    );
  }
}

class _MediaGridVideoThumb extends StatefulWidget {
  final String url;
  const _MediaGridVideoThumb({required this.url});

  @override
  State<_MediaGridVideoThumb> createState() => _MediaGridVideoThumbState();
}

class _MediaGridVideoThumbState extends State<_MediaGridVideoThumb> {
  Uint8List? _thumb;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await videoFrameFromUrl(
        widget.url,
        headers: api.headersFor(widget.url),
        maxWidth: 300,
        quality: 70,
      );
      if (mounted) setState(() { _thumb = data; _done = true; });
    } catch (_) {
      if (mounted) setState(() => _done = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_thumb != null) {
      return Image.memory(_thumb!, fit: BoxFit.cover);
    }
    return Container(
      color: GlitchColors.bgInput,
      child: _done
          ? Icon(Icons.videocam_rounded, color: GlitchColors.textHint, size: 28)
          : Center(child: SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: GlitchColors.textHint))),
    );
  }
}
