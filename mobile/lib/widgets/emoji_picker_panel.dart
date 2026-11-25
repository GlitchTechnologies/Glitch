import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/adaptive_open.dart';
import '../core/emoji_data.dart';
import '../core/emoji_search.dart';
import '../core/l10n.dart';
import '../providers/theme_provider.dart';
import '../services/recent_emoji_service.dart';
import '../theme/app_theme.dart';
import 'content_picker.dart' show ContentPickerDivider, PickerRail;
import 'glitch_hover_row.dart';
import 'glitch_pressable.dart';
import 'glitch_search_field.dart';
import 'reaction_emoji.dart';

class EmojiPickerPanel extends StatefulWidget {
  final ValueChanged<String> onPicked;

  const EmojiPickerPanel({super.key, required this.onPicked});

  @override
  State<EmojiPickerPanel> createState() => _EmojiPickerPanelState();
}

class _EmojiPickerPanelState extends State<EmojiPickerPanel> with ThemeAwareState<EmojiPickerPanel> {
  final _scrollCtrl = ScrollController();
  final _searchCtrl = TextEditingController();

  /// Найденное по запросу (core/emoji_search.dart); пока запроса нет — лента.
  List<String> _results = const [];
  bool get _searching => _searchCtrl.text.trim().isNotEmpty;

  static const double _tileMaxExtent = 44;
  static const double _gridSidePadding = 8;
  static const double _gridTop = 4;
  static const double _gridBottom = 8;

  static const double _headerHeight = 32;

  List<String> _recents = [];

  final Set<IconData> _collapsed = {};

  List<EmojiCategory> get _cats => [
        if (_recents.isNotEmpty)
          EmojiCategory(icon: Icons.access_time, emojis: _recents, name: (c) => c.s.gifRecent),
        ...emojiCategories,
      ];

  int _selectedIndex = 0;

  // Верх (в пикселях ленты) каждой категории — параллельно _cats.
  List<double> _categoryTops = const [];

  @override
  void initState() {
    super.initState();
    _loadRecents();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // Недавние — украшение: не прочитались — раздела просто нет.
  Future<void> _loadRecents() async {
    try {
      await recentEmoji.load();
    } catch (e) {
      debugPrint('EmojiPickerPanel: не удалось прочитать недавние эмодзи: $e');
      return;
    }
    if (!mounted) return;
    setState(() => _recents = List.of(recentEmoji.current));
  }

  Future<void> _pick(String emoji) async {
    HapticFeedback.selectionClick();
    widget.onPicked(emoji);
    try {
      await recentEmoji.recordUsed(emoji);
    } catch (e) {
      debugPrint('EmojiPickerPanel: не удалось сохранить недавние эмодзи: $e');
      return;
    }
    if (!mounted) return;
    setState(() => _recents = List.of(recentEmoji.current));
  }

  void _layoutCategories(double gridWidth, List<EmojiCategory> cats) {
    final available = gridWidth - _gridSidePadding * 2;
    final crossAxisCount = (available / _tileMaxExtent).ceil().clamp(1, 999).toInt();
    final rowHeight = available / crossAxisCount;

    var offset = _gridTop;
    final tops = <double>[];
    for (final cat in cats) {
      tops.add(offset);
      offset += _headerHeight;
      if (_collapsed.contains(cat.icon)) continue;
      final rows = (cat.emojis.length / crossAxisCount).ceil();
      offset += rows * rowHeight;
    }
    _categoryTops = tops;
  }

  int _categoryAtOffset(double scrollOffset) {
    var idx = 0;
    for (var i = 0; i < _categoryTops.length; i++) {
      if (_categoryTops[i] <= scrollOffset + 0.5) idx = i;
    }
    return idx;
  }

  void _onScroll() {
    if (_categoryTops.isEmpty) return;
    final idx = _categoryAtOffset(_scrollCtrl.position.pixels);
    if (idx != _selectedIndex) setState(() => _selectedIndex = idx);
  }

  void _jumpToCategory(int i) {
    if (i < 0 || i >= _categoryTops.length || !_scrollCtrl.hasClients) return;
    final target = _categoryTops[i].clamp(0.0, _scrollCtrl.position.maxScrollExtent);
    _scrollCtrl.jumpTo(target);
  }

  void _onSearchChanged(String query) =>
      setState(() => _results = searchEmoji(query, Localizations.localeOf(context).languageCode));

  void _onRailTap(int i) {
    if (!_searching) {
      _jumpToCategory(i);
      return;
    }
    _searchCtrl.clear();
    setState(() => _results = const []);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _jumpToCategory(i);
    });
  }

  void _toggleCollapsed(EmojiCategory cat) => setState(() {
        if (!_collapsed.remove(cat.icon)) _collapsed.add(cat.icon);
      });

  @override
  Widget build(BuildContext context) {
    final cats = _cats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Поиск — как у гифок и стикеров. На ПК курсор сразу в нём (окно
        // открыли — можно печатать), на телефоне — нет: иначе вместе с
        // панелью выезжала бы клавиатура.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: GlitchSearchField(
            controller: _searchCtrl,
            hint: context.s.emojiSearchHint,
            onChanged: _onSearchChanged,
            autofocus: isWideLayout(context),
            height: 42,
            brightIcon: true,
          ),
        ),
        const ContentPickerDivider(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _layoutCategories(constraints.maxWidth - PickerRail.width, cats);
              _selectedIndex = _scrollCtrl.hasClients
                  ? _categoryAtOffset(_scrollCtrl.position.pixels).clamp(0, cats.length - 1)
                  : _selectedIndex.clamp(0, cats.length - 1);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildRail(cats, _searching ? -1 : _selectedIndex),
                  Expanded(
                    key: ValueKey(_searching ? 'results' : 'grid'),
                    child: _searching ? _buildResults() : _buildContinuousGrid(cats),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// Найденные эмодзи — одной сеткой, лучшие совпадения первыми.
  Widget _buildResults() {
    if (_results.isEmpty) {
      return Center(
        child: Text(context.s.gifNoResults, style: TextStyle(fontSize: 14, color: GlitchColors.textPrimary)),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(_gridSidePadding, _gridTop + 4, _gridSidePadding, _gridBottom),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: _tileMaxExtent,
        childAspectRatio: 1,
      ),
      itemCount: _results.length,
      itemBuilder: (_, i) => _EmojiCell(emoji: _results[i], onTap: _pick),
    );
  }

  Widget _buildContinuousGrid(List<EmojiCategory> cats) {
    return CustomScrollView(
      controller: _scrollCtrl,
      cacheExtent: MediaQuery.of(context).size.height,
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: _gridTop)),
        for (final cat in cats) ...[
          SliverToBoxAdapter(key: ValueKey('head-${cat.icon.codePoint}'), child: _buildCategoryHeader(cat)),
          if (!_collapsed.contains(cat.icon))
            SliverPadding(
              key: ValueKey('grid-${cat.icon.codePoint}'),
              padding: const EdgeInsets.symmetric(horizontal: _gridSidePadding),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: _tileMaxExtent,
                  childAspectRatio: 1,
                ),
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _EmojiCell(emoji: cat.emojis[i], onTap: _pick),
                  childCount: cat.emojis.length,
                ),
              ),
            ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: _gridBottom)),
      ],
    );
  }

  Widget _buildCategoryHeader(EmojiCategory cat) {
    final collapsed = _collapsed.contains(cat.icon);
    final style = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary);
    return SizedBox(
      height: _headerHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: ClickableCursor(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _toggleCollapsed(cat),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(_gridSidePadding + 4, 6, 8, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(cat.icon, size: 14, color: GlitchColors.textPrimary),
                  const SizedBox(width: 6),
                  Transform.translate(offset: const Offset(0, 1), child: Text(cat.name(context), style: style)),
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

  Widget _buildRail(List<EmojiCategory> cats, int selected) => PickerRail(
        count: cats.length,
        selected: selected,
        onTap: _onRailTap,
        item: (i, lit) => Icon(
          cats[i].icon,
          size: 20,
          color: lit ? GlitchColors.textPrimary : GlitchColors.textSecond,
        ),
      );
}

class _EmojiCell extends StatelessWidget {
  final String emoji;
  final ValueChanged<String> onTap;

  const _EmojiCell({required this.emoji, required this.onTap});

  @override
  Widget build(BuildContext context) => GlitchHoverArea(
        onTap: () => onTap(emoji),
        builder: (_, active) => Container(
          margin: const EdgeInsets.all(2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: GlitchHoverRow.highlight(context, active: active),
            borderRadius: BorderRadius.circular(GlitchHoverRow.radius),
          ),
          child: ReactionEmoji(emoji, size: 26),
        ),
      );
}
