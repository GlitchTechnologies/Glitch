import 'package:cross_file/cross_file.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';
import '../core/glitch_plus_gate.dart';
import '../core/l10n.dart';
import '../theme/app_theme.dart';
import 'image_crop_screen.dart';
import '../providers/theme_provider.dart';
import '../services/gallery_access.dart';
import '../services/media_service.dart';
import '../widgets/avatar_shape.dart';
import '../widgets/gallery_access_views.dart';
import '../widgets/glitch_dialog.dart';
import '../widgets/glitch_icon_button.dart';

class _GalleryContent {
  final List<AssetEntity> recent;
  final List<AssetPathEntity> albums;
  final List<AssetEntity> favorites;

  const _GalleryContent({
    this.recent = const [],
    this.albums = const [],
    this.favorites = const [],
  });
}

class AvatarGalleryScreen extends StatefulWidget {
  final AvatarShape? cropShape;

  final bool gifAsIs;

  const AvatarGalleryScreen({super.key, required this.cropShape, this.gifAsIs = true});

  @override
  State<AvatarGalleryScreen> createState() => _AvatarGalleryScreenState();
}

class _AvatarGalleryScreenState extends State<AvatarGalleryScreen> with ThemeAwareState<AvatarGalleryScreen> {
  List<AssetEntity> _recentAssets = [];
  List<AssetEntity> _favoriteAssets = [];
  List<AssetPathEntity> _albums = [];

  List<AssetEntity> _displayAssets = [];

  bool _loading = true;
  GalleryStatus _status = GalleryStatus.ok;
  bool _limited = false;
  int _activeTab = 0;

  bool _inAlbum = false;
  String _albumName = '';
  bool _loadingAlbum = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final read = await readGallery(() async {
      final dateOrder = FilterOptionGroup(
        orders: [OrderOption(type: OrderOptionType.createDate, asc: false)],
      );

      final allAlbums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        hasAll: true,
        filterOption: dateOrder,
      );

      if (allAlbums.isEmpty) return const _GalleryContent();

      final recentCount = await allAlbums.first.assetCountAsync;
      final recent = await allAlbums.first.getAssetListRange(start: 0, end: recentCount);

      final albums = allAlbums.skip(1).toList();

      AssetPathEntity? favAlbum;
      for (final a in albums) {
        final n = a.name.toLowerCase();
        if (n.contains('избранн') || n.contains('favorit') || n.contains('favourite') ||
            n.contains('liked') || n.contains('starred') || n.contains('любимые') ||
            n.contains('понравив') || n.contains('loved') || n.contains('закреплён') ||
            n.contains('мои избр')) {
          favAlbum = a;
          break;
        }
      }

      final List<AssetEntity> favorites;
      if (favAlbum != null) {
        final favCount = await favAlbum.assetCountAsync;
        favorites = await favAlbum.getAssetListRange(start: 0, end: favCount);
      } else {
        favorites = recent.where((a) => a.isFavorite).toList();
      }

      return _GalleryContent(recent: recent, albums: albums, favorites: favorites);
    });

    if (!mounted) return;
    final content = read.data;
    setState(() {
      _loading = false;
      _status = read.status;
      _limited = read.limited;
      if (content != null) {
        _recentAssets = content.recent;
        _albums = content.albums;
        _favoriteAssets = content.favorites;
        _inAlbum = false;
        _displayAssets = _activeTab == 2 ? _favoriteAssets : _recentAssets;
      }
    });
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() => _loading = true);
    await _load();
  }

  void _onTabChange(int tab) {
    setState(() {
      _activeTab = tab;
      _inAlbum = false;
      if (tab == 0) _displayAssets = _recentAssets;
      if (tab == 2) _displayAssets = _favoriteAssets;
    });
  }

  Future<void> _openAlbum(AssetPathEntity album) async {
    setState(() { _loadingAlbum = true; _albumName = album.name; _inAlbum = true; });
    final read = await readGallery(() async {
      final count = await album.assetCountAsync;
      return album.getAssetListRange(start: 0, end: count);
    });
    if (!mounted) return;
    setState(() { _displayAssets = read.data ?? const []; _loadingAlbum = false; });
  }

  void _backFromAlbum() {
    setState(() { _inAlbum = false; });
  }

  Future<void> _pick(AssetEntity asset) async {
    final file = (await readGallery(() => asset.file)).data;
    if (file == null || !mounted) return;
    await _openCropOrReturn(XFile(file.path));
  }

  Future<void> _pickFromSystemPicker() async {
    final xFile = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 100);
    if (xFile == null || !mounted) return;
    await _openCropOrReturn(xFile);   // ImagePicker и так отдаёт XFile
  }

  Future<void> _openCropOrReturn(XFile file) async {
    if (widget.gifAsIs && mediaService.isGif(file)) {
      if (!mounted) return;
      final allowed = await ensureGlitchPlus(
        context,
        title: context.s.glitchPlusGifPromoTitle,
        body: context.s.glitchPlusGifPromoBody,
      );
      if (!allowed) return;
      Navigator.pop(context, file);
      return;
    }
    final shape = widget.cropShape;
    if (shape == null) {
      Navigator.pop(context, file);
      return;
    }
    final result = await openImageCrop(context, file, CropTarget.avatar(shape));
    if (result != null && mounted) Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GlitchColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 14, 0),
              child: Row(
                children: [
                  GlitchIconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded, color: GlitchColors.accentBlue, size: 22),
                    onTap: (_activeTab == 1 && _inAlbum) ? _backFromAlbum : () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (_activeTab == 1 && _inAlbum) ? _albumName : context.s.galleryTitle,
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          (_activeTab == 1 && _inAlbum) ? context.s.photosCount(_displayAssets.length) : context.s.gallerySelectPhoto,
                          style: TextStyle(fontSize: 12, color: GlitchColors.textSecond),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _pickFromSystemPicker,
                    child: Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(color: GlitchColors.bgInput, shape: BoxShape.circle),
                      child: Icon(Icons.photo_library_outlined, color: GlitchColors.textDim, size: 20),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            Divider(height: 1, color: GlitchColors.borderSoft),

            if (!(_activeTab == 1 && _inAlbum))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: Row(
                  children: [
                    _tab(context.s.galleryTabRecent, 0),
                    const SizedBox(width: 8),
                    _tab(context.s.galleryTabAlbums, 1),
                    const SizedBox(width: 8),
                    _tab(context.s.galleryTabFavorites, 2),
                  ],
                ),
              ),

            if (!_loading && _limited)
              GalleryAccessNotice(
                status: _status,
                limited: _limited,
                mediaType: RequestType.image,
                onReload: _reload,
              ),

            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return Center(child: CircularProgressIndicator(color: GlitchColors.accentBlue));
    if (_status != GalleryStatus.ok) {
      return GalleryAccessEmpty(status: _status, onReload: _reload);
    }

    if (_activeTab == 1 && !_inAlbum) {
      if (_albums.isEmpty) {
        return Center(child: Text(context.s.galleryNoAlbums, style: TextStyle(color: GlitchColors.textSecond, fontSize: 15)));
      }
      return _albumList();
    }

    if (_loadingAlbum) return Center(child: CircularProgressIndicator(color: GlitchColors.accentBlue));

    if (_activeTab == 2 && _favoriteAssets.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_border_rounded, color: GlitchColors.textHint, size: 56),
            SizedBox(height: 14),
            Text(context.s.galleryNoFavorites, style: TextStyle(color: GlitchColors.textSecond, fontSize: 15)),
          ],
        ),
      );
    }

    if (_displayAssets.isEmpty) {
      return Center(child: Text(context.s.galleryNoPhotos, style: TextStyle(color: GlitchColors.textSecond, fontSize: 15)));
    }

    return _photoGrid();
  }

  Widget _albumList() {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 30),
      itemCount: _albums.length,
      itemBuilder: (ctx, i) => _albumRow(_albums[i]),
    );
  }

  Widget _albumRow(AssetPathEntity album) {
    return FutureBuilder<int>(
      future: album.assetCountAsync,
      builder: (ctx, countSnap) {
        final count = countSnap.data ?? 0;
        return GestureDetector(
          onTap: () => _openAlbum(album),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            child: Row(
              children: [
                FutureBuilder<List<AssetEntity>>(
                  future: album.getAssetListRange(start: 0, end: 1),
                  builder: (ctx, snap) {
                    if (snap.data == null || snap.data!.isEmpty) {
                      return Container(width: 54, height: 54, decoration: BoxDecoration(color: GlitchColors.bgInput, borderRadius: BorderRadius.circular(10)));
                    }
                    return FutureBuilder<Uint8List?>(
                      future: snap.data!.first.thumbnailDataWithSize(const ThumbnailSize.square(120)),
                      builder: (ctx, tSnap) {
                        if (tSnap.data == null) {
                          return Container(width: 54, height: 54, decoration: BoxDecoration(color: GlitchColors.bgInput, borderRadius: BorderRadius.circular(10)));
                        }
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(tSnap.data!, width: 54, height: 54, fit: BoxFit.cover),
                        );
                      },
                    );
                  },
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(album.name, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(context.s.photosCount(count), style: TextStyle(fontSize: 13, color: GlitchColors.textSecond)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: GlitchColors.textHint, size: 22),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _photoGrid() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(3, 2, 3, 30),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 3,
        crossAxisSpacing: 3,
      ),
      itemCount: _displayAssets.length,
      itemBuilder: (ctx, i) => _photoCell(_displayAssets[i]),
    );
  }

  Widget _photoCell(AssetEntity asset) {
    return GestureDetector(
      onTap: () => _pick(asset),
      child: Container(
        color: GlitchColors.bgInput,
        child: FutureBuilder<Uint8List?>(
          future: asset.thumbnailDataWithSize(const ThumbnailSize.square(200)),
          builder: (ctx, snap) {
            if (snap.data == null) return const SizedBox();
            return Image.memory(snap.data!, fit: BoxFit.cover, width: double.infinity, height: double.infinity);
          },
        ),
      ),
    );
  }

  Widget _tab(String label, int idx) {
    final active = _activeTab == idx;
    return GestureDetector(
      onTap: () => _onTabChange(idx),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? GlitchColors.textPrimary : GlitchColors.bgInput,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            color: active ? GlitchColors.bg : GlitchColors.textDim,
          ),
        ),
      ),
    );
  }

}
