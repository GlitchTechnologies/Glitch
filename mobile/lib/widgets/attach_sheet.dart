import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:camera/camera.dart' hide ImageFormat;
export '../models/attach_result.dart';
export 'video_thumb_preview.dart';

import '../models/attach_result.dart';
import 'video_thumb_preview.dart';
import '../core/l10n.dart';
import '../theme/app_theme.dart';
import '../providers/theme_provider.dart';
import '../services/camera_service.dart';
import '../services/file_pick.dart';
import '../services/gallery_access.dart';
import '../services/upload_limits.dart';
import 'glitch_toast.dart';
import '../screens/camera_capture_screen.dart';
import 'gallery_access_views.dart';
import 'glitch_icon_button.dart';
import 'poll_composer.dart' show PollComposerForm;



class _GalleryPage {
  final AssetPathEntity? album;
  final List<AssetEntity> assets;
  final int total;

  const _GalleryPage({this.album, this.assets = const [], this.total = 0});
}

class AttachSheet extends StatefulWidget {
  final bool allowFiles;
  final bool allowPoll;

  const AttachSheet({super.key, required this.allowFiles, required this.allowPoll});

  @override
  State<AttachSheet> createState() => _AttachSheetState();
}

class _AttachSheetState extends State<AttachSheet> with ThemeAwareState<AttachSheet> {
  static const int _pollTab = 4;
  late int _tab = widget.allowFiles ? 0 : _pollTab;
  List<AssetEntity> _assets = [];
  final Set<int> _selected = {};
  bool _loading = true;
  bool _confirming = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  AssetPathEntity? _album;
  GalleryStatus _galleryStatus = GalleryStatus.ok;
  bool _galleryLimited = false;
  static const _pageSize = 80;
  final Map<int, Future<Uint8List?>> _thumbCache = {};
  final ScrollController _scrollCtrl = ScrollController();
  List<AssetEntity> _musicAssets = [];
  bool _musicLoading = true;
  GalleryStatus _musicStatus = GalleryStatus.ok;
  Position? _position;
  bool _geoLoading = false;
  String? _geoError;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    if (widget.allowFiles) _loadGallery();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadGallery() async {
    final read = await readGallery(() async {
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        filterOption: FilterOptionGroup(
          orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
        ),
      );
      if (albums.isEmpty) return const _GalleryPage();
      final album = albums.firstWhere((a) => a.isAll, orElse: () => albums.first);
      final assets = await album.getAssetListRange(start: 0, end: _pageSize);
      final total = await album.assetCountAsync;
      return _GalleryPage(album: album, assets: assets, total: total);
    });
    if (!mounted) return;
    final page = read.data;
    setState(() {
      _loading = false;
      _galleryStatus = read.status;
      _galleryLimited = read.limited;
      if (page == null) {
        _hasMore = false;
      } else {
        _album = page.album;
        _assets = List<AssetEntity>.of(page.assets);
        _hasMore = page.assets.length < page.total;
      }
    });
  }

  Future<void> _reloadGallery() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _selected.clear();
      _thumbCache.clear();
      _assets = [];
      _album = null;
      _hasMore = true;
    });
    await _loadGallery();
  }

  Future<void> _loadMusic() async {
    if (!_musicLoading) return;
    final read = await readGallery(() async {
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.audio,
        filterOption: FilterOptionGroup(
          orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
        ),
      );
      if (albums.isEmpty) return <AssetEntity>[];
      final all = albums.firstWhere((a) => a.isAll, orElse: () => albums.first);
      final total = await all.assetCountAsync;
      return all.getAssetListRange(start: 0, end: total.clamp(0, 1000));
    });
    if (!mounted) return;
    setState(() {
      _musicLoading = false;
      _musicStatus = read.status;
      _musicAssets = read.data ?? const [];
    });
  }

  Future<void> _reloadMusic() async {
    if (!mounted) return;
    setState(() => _musicLoading = true);
    await _loadMusic();
  }

  Future<void> _openCameraCapture() async {
    final result = await withDimmedStatusBar(() => Navigator.push<CameraCaptureResult>(
          context,
          MaterialPageRoute(fullscreenDialog: true, builder: (_) => const CameraCaptureScreen()),
        ));
    if (result == null || !mounted) return;
    final durations = result.isVideo && result.durationSeconds != null
        ? {result.file.path: result.durationSeconds!}
        : <String, int>{};
    Navigator.pop(context, PhotosResult([result.file], durations: durations));
  }

  void _openPreview(int idx) {
    Navigator.push(context, MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => GalleryPreviewScreen(
        asset: _assets[idx],
        isSelected: _selected.contains(idx),
        selectionOrder: _selected.toList().indexOf(idx) + 1,
        onToggle: () => _toggle(idx),
      ),
    ));
  }

  Future<void> _openNativePicker() async {
    final picker = ImagePicker();
    final max = uploadLimits.maxAttachments;
    final picked = await picker.pickMultipleMedia(limit: max != null && max >= 1 ? max : null);
    if (picked.isEmpty || !mounted) return;
    if (mounted) Navigator.pop(context, PhotosResult(picked, durations: const {}));
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _album == null) return;
    _loadingMore = true;
    try {
      final album = _album!;
      final start = _assets.length;
      final read = await readGallery(() async {
        final next = await album.getAssetListRange(start: start, end: start + _pageSize);
        final total = await album.assetCountAsync;
        return _GalleryPage(album: album, assets: next, total: total);
      });
      if (!mounted || !identical(_album, album)) return;
      final page = read.data;
      setState(() {
        if (page == null) {
          _hasMore = false;
          return;
        }
        _assets.addAll(page.assets);
        _hasMore = _assets.length < page.total;
      });
    } finally {
      _loadingMore = false;
    }
  }

  bool _toggle(int idx) {
    if (!_selected.contains(idx)) {
      final max = uploadLimits.maxAttachments;
      if (max != null && _selected.length >= max) {
        GlitchToast.show(context, context.s.attachTooMany(max));
        return false;
      }
    }
    setState(() => _selected.contains(idx) ? _selected.remove(idx) : _selected.add(idx));
    return true;
  }

  Future<void> _confirm() async {
    if (_selected.isEmpty || _confirming) return;
    setState(() => _confirming = true);
    try {
      final files = <XFile>[];
      final durations = <String, int>{};
      for (final idx in _selected.toList()..sort()) {
        final asset = _assets[idx];
        final f = (await readGallery(() => asset.originFile)).data;
        if (f == null) continue;
        files.add(XFile(f.path));
        if (asset.type == AssetType.video && asset.duration > 0) {
          durations[f.path] = asset.duration;
        }
      }
      if (mounted) Navigator.pop(context, PhotosResult(files, durations: durations));
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Future<void> _pickFile() async {
    final picked = await pickSystemFiles();
    if (picked.isEmpty) return;
    if (mounted) Navigator.pop(context, FileResult(picked.first));
  }

  Future<void> _loadGeo() async {
    if (_position != null || _geoLoading) return;
    setState(() { _geoLoading = true; _geoError = null; });
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever) {
        setState(() { _geoError = context.s.attachGeoDenied; _geoLoading = false; });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      if (mounted) setState(() { _position = pos; _geoLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _geoError = context.s.attachGeoFailed; _geoLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final h = math.min(media.size.height * 0.62, media.size.height - keyboard - media.padding.top);
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Container(
      height: h,
      decoration: BoxDecoration(
        color: GlitchColors.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(top: BorderSide(color: GlitchColors.borderCard)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 9, bottom: 4),
            width: 38, height: 4,
            decoration: BoxDecoration(color: GlitchColors.border, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 12, 12),
            child: Row(
              children: [
                Text(context.s.attachSheetTitle, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary)),
                const Spacer(),
                if (_selected.isNotEmpty)
                  GestureDetector(
                    onTap: _confirming ? null : _confirm,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: GlitchColors.accentBlue,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: _confirming
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text(context.s.sendCount(_selected.length), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(color: GlitchColors.bgInput, shape: BoxShape.circle),
                      child: Icon(Icons.close, color: GlitchColors.textSecond, size: 18),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 38,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
              scrollDirection: Axis.horizontal,
              children: [
                if (widget.allowFiles) ...[
                  _tabBtn(0, Icons.image_outlined, context.s.attachGallery),
                  const SizedBox(width: 7),
                  _tabBtn(1, Icons.insert_drive_file_outlined, context.s.attachFile),
                  const SizedBox(width: 7),
                  _tabBtn(2, Icons.location_on_outlined, context.s.attachGeo),
                  const SizedBox(width: 7),
                  _tabBtn(3, Icons.music_note_rounded, context.s.attachMusic),
                ],
                if (widget.allowFiles && widget.allowPoll) const SizedBox(width: 7),
                if (widget.allowPoll) _tabBtn(_pollTab, Icons.poll_outlined, context.s.attachPoll),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: switch (_tab) {
              0 => _buildGallery(),
              3 => _buildMusicTab(),
              _pollTab => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  child: PollComposerForm(onSubmit: (draft) => Navigator.pop(context, PollResult(draft))),
                ),
              _ => _buildPlaceholder(),
            },
          ),
        ],
      ),
      ),
    );
  }

  Widget _tabBtn(int idx, IconData icon, String label) {
    final active = _tab == idx;
    return GestureDetector(
      onTap: () {
        setState(() => _tab = idx);
        if (idx == 2) _loadGeo();
        if (idx == 3) _loadMusic();
      },
      onDoubleTap: idx == 0 ? _openNativePicker : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? GlitchColors.accentBlue : GlitchColors.bgInput,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: active ? Colors.white : GlitchColors.textSecond),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: active ? Colors.white : GlitchColors.textSecond)),
          ],
        ),
      ),
    );
  }

  Widget _buildGeoTab() {
    if (_geoLoading) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(color: GlitchColors.accentBlue),
        const SizedBox(height: 14),
        Text(context.s.attachGeoDetecting, style: TextStyle(color: GlitchColors.textSecond, fontSize: 14)),
      ]));
    }
    if (_geoError != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.location_off_rounded, size: 44, color: GlitchColors.textHint),
        const SizedBox(height: 12),
        Text(_geoError!, textAlign: TextAlign.center, style: TextStyle(color: GlitchColors.textSecond, fontSize: 14)),
        const SizedBox(height: 16),
        GestureDetector(onTap: () { setState(() { _geoError = null; }); _loadGeo(); },
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
            decoration: BoxDecoration(color: GlitchColors.accentBlue, borderRadius: BorderRadius.circular(20)),
            child: Text(context.s.retry, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          )),
      ])));
    }
    if (_position == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.location_on_outlined, size: 52, color: GlitchColors.textHint),
        const SizedBox(height: 14),
        Text(context.s.attachGeoTap, style: TextStyle(fontSize: 14, color: GlitchColors.textSecond)),
        const SizedBox(height: 16),
        GestureDetector(onTap: _loadGeo,
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
            decoration: BoxDecoration(color: GlitchColors.accentBlue, borderRadius: BorderRadius.circular(22)),
            child: Text(context.s.attachGeoDetect, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
          )),
      ]));
    }
    final lat = _position!.latitude;
    final lon = _position!.longitude;
    final mapUrl = 'https://static-maps.yandex.ru/1.x/'
        '?ll=${lon.toStringAsFixed(6)},${lat.toStringAsFixed(6)}'
        '&z=14&size=400,240&l=map'
        '&pt=${lon.toStringAsFixed(6)},${lat.toStringAsFixed(6)},pm2rdl'
        '&lang=ru_RU';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: CachedNetworkImage(
                imageUrl: mapUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                placeholder: (_, __) => Container(color: const Color(0xFF1a2218),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: GlitchColors.accentBlue))),
                errorWidget: (_, __, ___) => Container(color: const Color(0xFF1a2218),
                  child: const Center(child: Icon(Icons.location_on_rounded, color: Color(0xFF4caf50), size: 48))),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.location_on_rounded, color: Color(0xFF4caf50), size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text('${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}',
                style: TextStyle(fontSize: 13, color: GlitchColors.textSecond))),
              GestureDetector(
                onTap: () => Navigator.pop(context, GeoResult(lat, lon)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(color: GlitchColors.accentBlue, borderRadius: BorderRadius.circular(20)),
                  child: Text(context.s.send, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildGallery() {
    if (_loading) return Center(child: CircularProgressIndicator(color: GlitchColors.accentBlue));
    final itemCount = 1 + _assets.length + (_hasMore ? 1 : 0);
    return Column(
      children: [
        GalleryAccessNotice(
          status: _galleryStatus,
          limited: _galleryLimited,
          mediaType: RequestType.common,
          onReload: _reloadGallery,
        ),
        Expanded(child: _buildGalleryGrid(itemCount)),
      ],
    );
  }

  Widget _buildGalleryGrid(int itemCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.builder(
        controller: _scrollCtrl,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        itemCount: itemCount,
        itemBuilder: (ctx, i) {
          if (i == 0) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _CameraTile(onTap: _openCameraCapture),
            );
          }
          final assetIdx = i - 1;
          if (assetIdx >= _assets.length) {
            return Center(child: SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: GlitchColors.accentBlue)));
          }
          final selected = _selected.contains(assetIdx);
          final order = _selected.toList().indexOf(assetIdx) + 1;
          return Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                onTap: () => _openPreview(assetIdx),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: FutureBuilder<Uint8List?>(
                    future: _thumbCache[assetIdx] ??= _assets[assetIdx].thumbnailDataWithSize(const ThumbnailSize.square(200)),
                    builder: (_, snap) => snap.hasData
                        ? Image.memory(snap.data!, fit: BoxFit.cover, width: double.infinity, height: double.infinity)
                        : Container(color: const Color(0xFF212121)),
                  ),
                ),
              ),
              if (_assets[assetIdx].type == AssetType.video)
                Positioned(
                  bottom: 5, left: 5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 14),
                  ),
                ),
              if ((_assets[assetIdx].title ?? '').toLowerCase().endsWith('.gif'))
                Positioned(
                  bottom: 5, right: 5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                    child: const Text('GIF', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
                ),
              Positioned(
                top: 6, right: 6,
                child: GestureDetector(
                  onTap: () => _toggle(assetIdx),
                  child: Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      color: selected ? GlitchColors.accentBlue : Colors.black45,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: selected
                        ? Center(child: Text('$order', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)))
                        : null,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMusicTab() {
    if (_musicLoading) {
      return Center(child: CircularProgressIndicator(color: GlitchColors.accentBlue));
    }
    if (_musicStatus != GalleryStatus.ok) {
      return GalleryAccessEmpty(status: _musicStatus, onReload: _reloadMusic);
    }
    if (_musicAssets.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.music_off_rounded, size: 52, color: GlitchColors.textHint),
        const SizedBox(height: 12),
        Text(context.s.attachMusicEmpty, style: TextStyle(color: GlitchColors.textSecond, fontSize: 14)),
      ]));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: _musicAssets.length,
      itemBuilder: (ctx, i) {
        final asset = _musicAssets[i];
        final rawTitle = asset.title ?? asset.relativePath ?? context.s.attachMusicTrack;
        final title = rawTitle.contains('.')
            ? rawTitle.substring(0, rawTitle.lastIndexOf('.'))
            : rawTitle;
        final folder = (asset.relativePath ?? '')
            .replaceAll(RegExp(r'^/+|/+$'), '')
            .split('/')
            .last;
        final sub = folder.isNotEmpty && folder.toLowerCase() != 'music' ? folder : null;
        final dur = asset.duration;
        final durStr = dur > 0
            ? '${(dur ~/ 60).toString().padLeft(2, '0')}:${(dur % 60).toString().padLeft(2, '0')}'
            : '';
        final colors = [
          const Color(0xFF5856d6), const Color(0xFF34aadc), const Color(0xFF4cd964),
          const Color(0xFFff9500), const Color(0xFFff2d55), const Color(0xFFaf52de),
        ];
        final iconColor = colors[i % colors.length];
        return GestureDetector(
          onTap: () async {
            final file = await asset.originFile;
            if (file == null || !mounted) return;
            final size = await file.length();
            final ext = file.path.split('.').last.toLowerCase();
            final mime = {
              'mp3': 'audio/mpeg', 'wav': 'audio/wav', 'aac': 'audio/aac',
              'ogg': 'audio/ogg', 'flac': 'audio/flac', 'm4a': 'audio/mp4',
              'opus': 'audio/opus',
            }[ext] ?? 'audio/mpeg';
            if (mounted) Navigator.pop(context, FileResult(PendingFile(file: XFile(file.path), name: '$title.$ext', size: size, mimeType: mime)));
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: GlitchColors.bgCard, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: iconColor.withOpacity(0.15), shape: BoxShape.circle),
                  child: Icon(Icons.music_note_rounded, color: iconColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (sub != null) ...[
                        const SizedBox(height: 2),
                        Text(sub, style: TextStyle(fontSize: 12, color: GlitchColors.textSecond), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (durStr.isNotEmpty)
                  Text(durStr, style: TextStyle(fontSize: 12, color: GlitchColors.textHint, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlaceholder() {
    if (_tab == 1) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file_outlined, size: 52, color: GlitchColors.textHint),
            const SizedBox(height: 14),
            Text(context.s.attachFileChoose, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: GlitchColors.textSecond)),
            const SizedBox(height: 4),
            Text('PDF, DOC, ZIP и другие', style: TextStyle(fontSize: 13, color: GlitchColors.textHint)),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _pickFile,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                decoration: BoxDecoration(color: GlitchColors.accentBlue, borderRadius: BorderRadius.circular(22)),
                child: Text(context.s.attachFileOpen, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      );
    }
    return _buildGeoTab();
  }
}


// acquire()/release() в initState/dispose — CameraService шарит один и тот же
// CameraController между этой плашкой и полноэкранным CameraCaptureScreen
// (см. camera_service.dart), поэтому переход из плашки на экран съёмки не
// переинициализирует камеру заново.
class _CameraTile extends StatefulWidget {
  final VoidCallback onTap;
  const _CameraTile({required this.onTap});

  @override
  State<_CameraTile> createState() => _CameraTileState();
}

class _CameraTileState extends State<_CameraTile> {
  @override
  void initState() {
    super.initState();
    cameraService.addListener(_onCameraChange);
    cameraService.acquire();
  }

  @override
  void dispose() {
    cameraService.removeListener(_onCameraChange);
    cameraService.release();
    super.dispose();
  }

  void _onCameraChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        color: const Color(0xFF212121),
        child: _content(),
      ),
    );
  }

  Widget _content() {
    if (cameraService.isReady) {
      final controller = cameraService.controller!;
      final size = controller.value.previewSize!;
      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.height,
          height: size.width,
          child: CameraPreview(controller),
        ),
      );
    }
    if (cameraService.state == CameraServiceState.permissionDenied) {
      return const Center(child: Icon(Icons.no_photography_rounded, color: Colors.white38, size: 22));
    }
    if (cameraService.state == CameraServiceState.error) {
      return const Center(child: Icon(Icons.error_outline_rounded, color: Colors.white38, size: 22));
    }
    return const Center(
      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)),
    );
  }
}



class GalleryPreviewScreen extends StatefulWidget {
  final AssetEntity asset;
  final bool isSelected;
  final int selectionOrder;
  final bool Function() onToggle;

  const GalleryPreviewScreen({
    super.key,
    required this.asset,
    required this.isSelected,
    required this.selectionOrder,
    required this.onToggle,
  });

  @override
  State<GalleryPreviewScreen> createState() => _GalleryPreviewScreenState();
}

class _GalleryPreviewScreenState extends State<GalleryPreviewScreen> {
  bool _selected = false;
  Uint8List? _thumb;

  @override
  void initState() {
    super.initState();
    _selected = widget.isSelected;
    _loadThumb();
  }

  Future<void> _loadThumb() async {
    final data = await widget.asset.thumbnailDataWithSize(const ThumbnailSize(1080, 1080));
    if (mounted) setState(() => _thumb = data);
  }

  void _toggle() {
    if (widget.onToggle()) setState(() => _selected = !_selected);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          SizedBox.expand(
            child: _thumb != null
                ? InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 5.0,
                    child: Center(child: Image.memory(_thumb!, fit: BoxFit.contain)),
                  )
                : const Center(child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2)),
          ),
          if (widget.asset.type == AssetType.video)
            Center(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                  child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 44),
                  ),
                ),
              ),
            ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xCC000000), Colors.transparent],
              ),
            ),
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 6,
              left: 4, right: 12, bottom: 20,
            ),
            child: Row(
              children: [
                GlitchIconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 22),
                  onTap: () => Navigator.pop(context),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _toggle,
                  child: Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                      color: _selected ? GlitchColors.accentBlue : Colors.black45,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: _selected
                        ? const Center(child: Icon(Icons.check_rounded, color: Colors.white, size: 17))
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
