import 'dart:async';
import 'package:cross_file/cross_file.dart';
import '../services/media_platform_web.dart' if (dart.library.io) '../services/media_platform_native.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../core/l10n.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../models/gif.dart';
import '../providers/theme_provider.dart';
import 'glitch_search_field.dart';
import 'glitch_toast.dart';
import 'content_picker.dart' show ContentPickerDivider;
import 'glitch_pressable.dart' show ClickableCursor;

Future<void> sendGifFile(
  BuildContext context,
  GifItem gif,
  Future<void> Function(XFile) onFile,
) async {
  try {
    final res = await http.get(Uri.parse(gif.url));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final file = await saveTempBytes(
      res.bodyBytes, '${DateTime.now().microsecondsSinceEpoch}.gif');
    if (file == null) throw Exception('Не удалось сохранить GIF');
    await onFile(file);
    api.recordRecentGif(gif.url, gif.thumbnailUrl).catchError((_) {});
  } catch (e) {
    if (context.mounted) GlitchToast.show(context, errorMessage(e));
  }
}

class GifPickerPanel extends StatefulWidget {
  final ValueChanged<GifItem> onPick;

  const GifPickerPanel({super.key, required this.onPick});

  @override
  State<GifPickerPanel> createState() => _GifPickerPanelState();
}

class _GifPickerPanelState extends State<GifPickerPanel> with ThemeAwareState<GifPickerPanel> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timer? _debounce;

  bool _loading = true;
  String? _error;

  List<GifCategory> _categories = [];
  List<GifItem> _recent = [];

  String? _activeQuery;
  bool _activeFeatured = false;
  List<GifItem> _gridItems = [];
  String? _nextPos;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _loadHome();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_activeQuery == null || _nextPos == null || _loadingMore) return;
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _loadHome() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        api.getGifCategories(),
        api.getRecentGifs().catchError((_) => <GifItem>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _categories = results[0] as List<GifCategory>;
        _recent = results[1] as List<GifItem>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = errorMessage(e); _loading = false; });
    }
  }

  Future<void> _openQuery(String query) async {
    setState(() {
      _activeQuery = query;
      _activeFeatured = false;
      _loading = true;
      _error = null;
      _gridItems = [];
      _nextPos = null;
    });
    try {
      final page = await api.searchGifs(query);
      if (!mounted) return;
      setState(() { _gridItems = page.items; _nextPos = page.next; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = errorMessage(e); _loading = false; });
    }
  }

  Future<void> _openFeatured(String title) async {
    setState(() {
      _activeQuery = title;
      _activeFeatured = true;
      _loading = true;
      _error = null;
      _gridItems = [];
      _nextPos = null;
    });
    try {
      final page = await api.getFeaturedGifs();
      if (!mounted) return;
      setState(() { _gridItems = page.items; _nextPos = page.next; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = errorMessage(e); _loading = false; });
    }
  }

  void _openCategory(GifCategory cat) =>
      cat.searchterm.isEmpty ? _openFeatured(cat.name) : _openQuery(cat.searchterm);

  Future<void> _loadMore() async {
    if (_nextPos == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = _activeFeatured
          ? await api.getFeaturedGifs(pos: _nextPos)
          : await api.searchGifs(_activeQuery!, pos: _nextPos);
      if (!mounted) return;
      setState(() { _gridItems = [..._gridItems, ...page.items]; _nextPos = page.next; _loadingMore = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    final q = v.trim();
    if (q.isEmpty) {
      setState(() { _activeQuery = null; _activeFeatured = false; _gridItems = []; _nextPos = null; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () => _openQuery(q));
  }

  void _back() {
    _searchCtrl.clear();
    setState(() { _activeQuery = null; _activeFeatured = false; _gridItems = []; _nextPos = null; });
  }

  void _pick(GifItem item) => widget.onPick(item);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              if (_activeQuery != null)
                ClickableCursor(
                  child: GestureDetector(
                  onTap: _back,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Icon(Icons.arrow_back_ios_new_rounded, color: GlitchColors.textPrimary, size: 18),
                  ),
                ),
                ),
              Expanded(
                child: GlitchSearchField(
                  controller: _searchCtrl,
                  hint: context.s.gifSearchHint,
                  onChanged: _onSearchChanged,
                  height: 42,
                  brightIcon: true,
                ),
              ),
            ],
          ),
        ),
        const ContentPickerDivider(),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: GlitchColors.accentBlue, strokeWidth: 2));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, color: GlitchColors.textHint, size: 44),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: GlitchColors.textSecond, fontSize: 14)),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _activeQuery == null
                  ? _loadHome
                  : (_activeFeatured ? () => _openFeatured(_activeQuery!) : () => _openQuery(_activeQuery!)),
              child: Text(context.s.retry, style: TextStyle(color: GlitchColors.accentBlue)),
            ),
          ],
        ),
      );
    }
    if (_activeQuery == null) return _buildHome();
    return _buildGrid(_gridItems, showLoadMore: _loadingMore);
  }

  TextStyle get _sectionStyle =>
      TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary);

  Widget _buildHome() {
    return ListView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        if (_recent.isNotEmpty) ...[
          Text(context.s.gifRecent, style: _sectionStyle),
          const SizedBox(height: 8),
          SizedBox(
            height: 90,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _recent.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) => _GifTile(item: _recent[i], onTap: () => _pick(_recent[i]), width: 120),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Text(context.s.gifCategories, style: _sectionStyle),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _categories.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 1.6,
          ),
          itemBuilder: (_, i) {
            final cat = _categories[i];
            return _CategoryTile(category: cat, onTap: () => _openCategory(cat));
          },
        ),
      ],
    );
  }

  Widget _buildGrid(List<GifItem> items, {required bool showLoadMore}) {
    if (items.isEmpty) {
      return Center(child: Text(context.s.gifNoResults, style: TextStyle(color: GlitchColors.textSecond)));
    }
    return GridView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: items.length + (showLoadMore ? 1 : 0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 1.3,
      ),
      itemBuilder: (_, i) {
        if (i == items.length) {
          return Center(child: CircularProgressIndicator(color: GlitchColors.accentBlue, strokeWidth: 2));
        }
        final item = items[i];
        return _GifTile(item: item, onTap: () => _pick(item));
      },
    );
  }
}

class _GifTile extends StatelessWidget {
  final GifItem item;
  final VoidCallback onTap;
  final double? width;
  const _GifTile({required this.item, required this.onTap, this.width});

  @override
  Widget build(BuildContext context) {
    return ClickableCursor(
      child: GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: width,
          color: GlitchColors.bgInput,
          child: Image.network(
            item.thumbnailUrl,
            fit: BoxFit.cover,
            loadingBuilder: (_, child, progress) => progress == null ? child : const Center(
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            errorBuilder: (_, __, ___) => Icon(Icons.broken_image_outlined, color: GlitchColors.textHint),
          ),
        ),
      ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final GifCategory category;
  final VoidCallback onTap;
  const _CategoryTile({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClickableCursor(
      child: GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: GlitchColors.bgInput),
            Image.network(
              category.thumbnailUrl,
              fit: BoxFit.cover,
              loadingBuilder: (_, child, progress) => progress == null ? child : const SizedBox(),
              errorBuilder: (_, __, ___) => Icon(Icons.broken_image_outlined, color: GlitchColors.textHint),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.55)],
                ),
              ),
            ),
            Positioned(
              left: 10, bottom: 8,
              child: Text(category.name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
