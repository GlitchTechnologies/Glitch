import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/adaptive_open.dart';
import '../core/emoji_search.dart';
import '../core/l10n.dart';
import '../core/text_match.dart';
import '../models/sticker.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'avatar_shape.dart';
import 'content_picker.dart' show ContentPickerDivider, PickerRail;
import 'glitch_action_button.dart';
import 'glitch_avatar.dart';
import 'glitch_hover_row.dart';
import 'glitch_pressable.dart';
import 'glitch_search_field.dart';
import 'sticker_view.dart';

class StickerPickerPanel extends StatefulWidget {
  final ValueChanged<Sticker> onPicked;

  const StickerPickerPanel({super.key, required this.onPicked});

  @override
  State<StickerPickerPanel> createState() => _StickerPickerPanelState();
}

class _StickerPickerPanelState extends State<StickerPickerPanel> {
  final _scrollCtrl = ScrollController();
  final _searchCtrl = TextEditingController();

  List<StickerGroup>? _groups;
  bool _failed = false;

  /// Найденное по запросу; пока запроса нет — лента.
  List<Sticker> _results = const [];
  bool get _searching => _searchCtrl.text.trim().isNotEmpty;

  final Set<int> _collapsed = {};

  static const double _tileMaxExtent = 96;
  static const double _gridSidePadding = 8;
  static const double _gridTop = 4;
  static const double _gridBottom = 8;
  static const double _headerHeight = 32;

  int _selectedIndex = 0;
  List<double> _groupTops = const [];

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final groups = await api.getMyStickers();
      if (!mounted) return;
      setState(() => _groups = groups);
    } catch (e) {
      debugPrint('StickerPickerPanel: не удалось загрузить стикеры: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  void _pick(Sticker sticker) {
    HapticFeedback.selectionClick();
    widget.onPicked(sticker);
  }

  void _layoutGroups(double gridWidth, List<StickerGroup> groups) {
    final available = gridWidth - _gridSidePadding * 2;
    final crossAxisCount = (available / _tileMaxExtent).ceil().clamp(1, 999).toInt();
    final rowHeight = available / crossAxisCount;
    var offset = _gridTop;
    final tops = <double>[];
    for (final g in groups) {
      tops.add(offset);
      offset += _headerHeight;
      if (_collapsed.contains(g.serverId)) continue;
      offset += (g.stickers.length / crossAxisCount).ceil() * rowHeight;
    }
    _groupTops = tops;
  }

  int _groupAtOffset(double scrollOffset) {
    var idx = 0;
    for (var i = 0; i < _groupTops.length; i++) {
      if (_groupTops[i] <= scrollOffset + 0.5) idx = i;
    }
    return idx;
  }

  void _onScroll() {
    if (_groupTops.isEmpty) return;
    final idx = _groupAtOffset(_scrollCtrl.position.pixels);
    if (idx != _selectedIndex) setState(() => _selectedIndex = idx);
  }

  void _jumpToGroup(int i) {
    if (i < 0 || i >= _groupTops.length || !_scrollCtrl.hasClients) return;
    _scrollCtrl.jumpTo(_groupTops[i].clamp(0.0, _scrollCtrl.position.maxScrollExtent));
  }

  /// Поиск по названию и описанию, а ещё по смыслу эмодзи стикера: «кот»
  /// найдёт стикер с 😺, даже если назван он иначе (словарь эмодзи —
  /// core/emoji_search.dart). Точные совпадения названия — первыми.
  void _onSearchChanged(String query) {
    final groups = _groups ?? const <StickerGroup>[];
    final byMeaning = searchEmoji(query, Localizations.localeOf(context).languageCode).toSet();
    final ranked = <(int, int, Sticker)>[];
    var order = 0;
    for (final g in groups) {
      for (final st in g.stickers) {
        final rank = matchRank(query, [st.name, st.description]) ??
            (byMeaning.contains(st.emoji) || st.emoji == query.trim() ? 3 : null);
        if (rank != null) ranked.add((rank, order, st));
        order++;
      }
    }
    ranked.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    setState(() => _results = [for (final r in ranked) r.$3]);
  }

  void _onRailTap(int i) {
    if (!_searching) {
      _jumpToGroup(i);
      return;
    }
    _searchCtrl.clear();
    setState(() => _results = const []);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _jumpToGroup(i);
    });
  }

  void _toggleCollapsed(StickerGroup g) => setState(() {
        if (!_collapsed.remove(g.serverId)) _collapsed.add(g.serverId);
      });

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: GlitchSearchField(
            controller: _searchCtrl,
            hint: context.s.stickerSearchHint,
            onChanged: _onSearchChanged,
            autofocus: isWideLayout(context),
            height: 42,
            brightIcon: true,
          ),
        ),
        const ContentPickerDivider(),
        Expanded(
          child: groups == null
              ? (_failed ? _buildRetry() : const Center(child: CircularProgressIndicator(strokeWidth: 2)))
              : groups.isEmpty
                  ? _buildNote(context.s.stickersPickerEmpty)
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        _layoutGroups(constraints.maxWidth - PickerRail.width, groups);
                        _selectedIndex = _scrollCtrl.hasClients
                            ? _groupAtOffset(_scrollCtrl.position.pixels).clamp(0, groups.length - 1)
                            : _selectedIndex.clamp(0, groups.length - 1);
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildRail(groups, _searching ? -1 : _selectedIndex),
                            Expanded(
                              key: ValueKey(_searching ? 'results' : 'grid'),
                              child: _searching ? _buildResults() : _buildContinuousGrid(groups),
                            ),
                          ],
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildNote(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: GlitchColors.textPrimary)),
        ),
      );

  Widget _buildRetry() => Center(
        child: GlitchActionButton(label: context.s.retry, soft: true, compact: true, onTap: _load),
      );

  Widget _buildResults() {
    if (_results.isEmpty) return _buildNote(context.s.gifNoResults);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(_gridSidePadding, _gridTop + 4, _gridSidePadding, _gridBottom),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: _tileMaxExtent,
        childAspectRatio: 1,
      ),
      itemCount: _results.length,
      itemBuilder: (_, i) => _StickerCell(sticker: _results[i], onTap: _pick),
    );
  }

  Widget _buildContinuousGrid(List<StickerGroup> groups) {
    return CustomScrollView(
      controller: _scrollCtrl,
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: _gridTop)),
        for (final g in groups) ...[
          SliverToBoxAdapter(key: ValueKey('head-${g.serverId}'), child: _buildHeader(g)),
          if (!_collapsed.contains(g.serverId))
            SliverPadding(
              key: ValueKey('grid-${g.serverId}'),
              padding: const EdgeInsets.symmetric(horizontal: _gridSidePadding),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: _tileMaxExtent,
                  childAspectRatio: 1,
                ),
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _StickerCell(sticker: g.stickers[i], onTap: _pick),
                  childCount: g.stickers.length,
                ),
              ),
            ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: _gridBottom)),
      ],
    );
  }

  Widget _buildHeader(StickerGroup g) {
    final collapsed = _collapsed.contains(g.serverId);
    final style = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary);
    return SizedBox(
      height: _headerHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: ClickableCursor(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _toggleCollapsed(g),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(_gridSidePadding + 4, 6, 8, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _avatar(g, 16),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Transform.translate(
                      offset: const Offset(0, 1),
                      child: Text(g.serverName, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    collapsed ? Icons.chevron_right_rounded : Icons.expand_more_rounded,
                    size: 16,
                    color: GlitchColors.textPrimary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatar(StickerGroup g, double size) => GlitchAvatar(
        initials: GlitchAvatar.initialsFromName(g.serverName),
        size: size,
        colorIndex: GlitchAvatar.colorFromNickname(g.serverName),
        imageUrl: g.serverAvatar != null ? api.mediaUrl(g.serverAvatar!) : null,
        avatarSizes: g.serverAvatarSizes,
        shape: AvatarShape.community,
      );

  Widget _buildRail(List<StickerGroup> groups, int selected) => PickerRail(
        count: groups.length,
        selected: selected,
        onTap: _onRailTap,
        item: (i, _) => _avatar(groups[i], 26),
      );
}

class _StickerCell extends StatelessWidget {
  final Sticker sticker;
  final ValueChanged<Sticker> onTap;

  const _StickerCell({required this.sticker, required this.onTap});

  @override
  Widget build(BuildContext context) => GlitchHoverArea(
        onTap: () => onTap(sticker),
        builder: (_, active) => Container(
          margin: const EdgeInsets.all(2),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: GlitchHoverRow.highlight(context, active: active),
            borderRadius: BorderRadius.circular(GlitchHoverRow.radius),
          ),
          child: LayoutBuilder(
            builder: (_, box) => StickerView(sticker: sticker.toParsed(), size: box.biggest.shortestSide),
          ),
        ),
      );
}
