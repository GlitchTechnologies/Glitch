import 'dart:async';

import 'package:flutter/material.dart';
import '../core/shell_metrics.dart';
import '../core/avatar_color.dart';
import '../core/adaptive_open.dart';
import '../core/l10n.dart';
import '../core/server_join.dart';
import '../core/shell_controller.dart';
import '../models/server.dart';
import '../providers/theme_provider.dart' show ThemeAwareState;
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar_shape.dart';
import '../widgets/banner_header_art.dart';
import '../widgets/glitch_avatar.dart';
import '../widgets/glitch_pressable.dart';
import '../widgets/glitch_search_field.dart';
import '../widgets/server_profile_card.dart';
import '../widgets/settings_parts.dart';
import '../widgets/glitch_icon_button.dart';


enum CatalogSection { servers, events }

String catalogSlotKey(CatalogSection section) => 'catalog:${section.name}';

Widget catalogSectionScreen(CatalogSection section) => switch (section) {
      CatalogSection.servers => const ServerCatalogScreen(),
      CatalogSection.events => const CatalogEventsScreen(),
    };


class ServerCatalogScreen extends StatefulWidget {
  const ServerCatalogScreen({super.key});

  @override
  State<ServerCatalogScreen> createState() => _ServerCatalogScreenState();
}

class _ServerCatalogScreenState extends State<ServerCatalogScreen>
    with ThemeAwareState<ServerCatalogScreen> {
  static const _pageSize = 24;

  final _search = TextEditingController();
  Timer? _debounce;

  List<ServerCatalogItem> _items = const [];
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  String get _query => _search.text.trim();

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _reload);
  }

  Future<void> _reload() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
    });
    try {
      final page = await api.getServerCatalog(query: _query, limit: _pageSize);
      if (!mounted || seq != _seq) return;
      setState(() {
        _items = page.items;
        _hasMore = page.hasMore;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() => _error = errorMessage(e));
    } finally {
      if (mounted && seq == _seq) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    final seq = _seq;
    setState(() => _loadingMore = true);
    try {
      final page = await api.getServerCatalog(
        query: _query,
        offset: _items.length,
        limit: _pageSize,
      );
      if (!mounted || seq != _seq) return;
      final seen = {for (final i in _items) i.server.serverId};
      setState(() {
        _items = [..._items, ...page.items.where((i) => !seen.contains(i.server.serverId))];
        _hasMore = page.hasMore;
      });
    } catch (_) {
    } finally {
      if (mounted && seq == _seq) setState(() => _loadingMore = false);
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.extentAfter < 600) _loadMore();
    return false;
  }

  void _openItem(ServerCatalogItem item) {
    joinServerAndShow(
      context,
      item.server,
      () => api.joinPublicServer(item.server.serverId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final searching = _query.isNotEmpty;
    return CatalogPageFrame(
      search: GlitchSearchField(
        controller: _search,
        hint: context.s.catalogSearch,
        onChanged: _onSearchChanged,
        loading: _loading && searching,
        height: 38,
      ),
      onScroll: _onScroll,
      slivers: [
        if (!searching)
          SliverToBoxAdapter(
            child: CatalogHero(
              title: context.s.catalogHeroTitle,
              subtitle: context.s.catalogHeroSubtitle,
            ),
          ),
        SliverToBoxAdapter(
          child: CatalogContentWidth(
            child: Padding(
              padding: EdgeInsets.only(top: searching ? 24 : 32, bottom: 16),
              child: Text(
                searching ? context.s.catalogResults : context.s.catalogPopular,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: GlitchColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
        ..._body(searching),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  List<Widget> _body(bool searching) {
    if (_loading && _items.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ];
    }
    if (_error != null) {
      return [
        SliverToBoxAdapter(child: SettingsRetry(text: _error!, onRetry: _reload)),
      ];
    }
    if (_items.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(48),
            child: Text(
              searching ? context.s.catalogNothingFound : context.s.catalogEmpty,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: GlitchColors.textPrimary),
            ),
          ),
        ),
      ];
    }
    return [
      SliverLayoutBuilder(
        builder: (context, constraints) {
          final grid = _CatalogGrid.of(constraints.crossAxisExtent);
          return SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: grid.sidePadding),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: grid.columns,
                mainAxisSpacing: _CatalogGrid.gap,
                crossAxisSpacing: _CatalogGrid.gap,
                mainAxisExtent: ServerCatalogCard.heightFor(
                  grid.cardWidth,
                  MediaQuery.textScalerOf(context),
                ),
              ),
              delegate: SliverChildBuilderDelegate(
                (_, i) => ServerCatalogCard(
                  item: _items[i],
                  onTap: () => _openItem(_items[i]),
                ),
                childCount: _items.length,
              ),
            ),
          );
        },
      ),
      if (_loadingMore)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
    ];
  }
}

class _CatalogGrid {
  static const double gap = 16;
  static const double _minCard = 260;

  final int columns;
  final double sidePadding;
  final double cardWidth;

  const _CatalogGrid(this.columns, this.sidePadding, this.cardWidth);

  factory _CatalogGrid.of(double width) {
    final side = CatalogContentWidth.sidePaddingFor(width);
    final avail = width - side * 2;
    final columns = ((avail + gap) / (_minCard + gap)).floor().clamp(1, 4);
    final card = (avail - gap * (columns - 1)) / columns;
    return _CatalogGrid(columns, side, card);
  }
}


class ServerCatalogCard extends StatelessWidget {
  final ServerCatalogItem item;
  final VoidCallback onTap;

  const ServerCatalogCard({super.key, required this.item, required this.onTap});

  static const double _avatarSize = 48;
  static const double _radius = 12;

  static const double _nameSize = 16;
  static const double _descSize = 14;
  static const double _statSize = 12;
  static const double _lineHeight = 1.3;

  static const int _descLines = 5;

  static const EdgeInsets _textPadding = EdgeInsets.fromLTRB(16, 10, 16, 14);
  static const double _nameGap = 6;
  static const double _statGap = 8;

  static double heightFor(double width, TextScaler scaler) {
    double line(double size) => scaler.scale(size) * _lineHeight;
    return width / kServerBannerAspect +
        _avatarSize * 0.55 +
        _textPadding.vertical +
        line(_nameSize) +
        _nameGap +
        line(_descSize) * _descLines +
        _statGap +
        line(_statSize) +
        2;
  }

  @override
  Widget build(BuildContext context) {
    final server = item.server;
    return GlitchPressable(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: GlitchColors.bgCard,
          borderRadius: BorderRadius.circular(_radius),
          border: Border.all(color: GlitchColors.borderCard),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BannerHeaderArt(
              banner: ServerBanner(
                url: server.banner,
                sizes: server.bannerSizes,
                fallbackColor: parseAvatarColor(server.avatarColor),
              ),
              bannerAspect: kServerBannerAspect,
              avatar: GlitchAvatar(
                initials: GlitchAvatar.initialsFromName(server.name),
                size: _avatarSize,
                colorIndex: GlitchAvatar.colorFromNickname(server.name),
                imageUrl: server.avatar != null ? api.mediaUrl(server.avatar!) : null,
                avatarSizes: server.avatarSizes,
                shape: AvatarShape.community,
              ),
              avatarSize: _avatarSize,
              avatarShape: AvatarShape.community,
              ringColor: GlitchColors.bgCard,
            ),
            Expanded(
              child: Padding(
                padding: _textPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: _nameSize,
                        height: _lineHeight,
                        fontWeight: FontWeight.w700,
                        color: GlitchColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: _nameGap),
                    SizedBox(
                      height: MediaQuery.textScalerOf(context).scale(_descSize) *
                          _lineHeight *
                          _descLines,
                      child: Text(
                        server.description ?? '',
                        maxLines: _descLines,
                        overflow: TextOverflow.ellipsis,
                        strutStyle: const StrutStyle(
                          fontSize: _descSize,
                          height: _lineHeight,
                          forceStrutHeight: true,
                        ),
                        style: TextStyle(
                          fontSize: _descSize,
                          height: _lineHeight,
                          color: GlitchColors.textSecond,
                        ),
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(height: _statGap),
                    Row(
                      children: [
                        _Stat(
                          dot: GlitchColors.online,
                          text: context.s.catalogOnline(item.onlineCount),
                        ),
                        const SizedBox(width: 14),
                        Flexible(
                          child: _Stat(
                            dot: GlitchColors.textHint,
                            text: context.s.membersCount(server.memberCount),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final Color dot;
  final String text;

  const _Stat({required this.dot, required this.text});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: ServerCatalogCard._statSize,
                height: ServerCatalogCard._lineHeight,
                color: GlitchColors.textPrimary,
              ),
            ),
          ),
        ],
      );
}


class CatalogEventsScreen extends StatefulWidget {
  const CatalogEventsScreen({super.key});

  @override
  State<CatalogEventsScreen> createState() => _CatalogEventsScreenState();
}

class _CatalogEventsScreenState extends State<CatalogEventsScreen>
    with ThemeAwareState<CatalogEventsScreen> {
  @override
  Widget build(BuildContext context) => CatalogPageFrame(
        slivers: [
          SliverToBoxAdapter(
            child: CatalogHero(
              title: context.s.catalogEvents,
              subtitle: context.s.catalogEventsSubtitle,
            ),
          ),
        ],
      );
}


const Color _heroBase = Colors.black;
Color _heroDark() => Color.alphaBlend(GlitchColors.accentBlue.withOpacity(0.28), _heroBase);
Color _heroLight() => Color.alphaBlend(GlitchColors.accentBlue.withOpacity(0.6), _heroBase);

class CatalogPageFrame extends StatelessWidget {
  final List<Widget> slivers;

  final Widget? search;
  final bool Function(ScrollNotification)? onScroll;

  const CatalogPageFrame({super.key, required this.slivers, this.search, this.onScroll});

  @override
  Widget build(BuildContext context) {
    final scroll = CustomScrollView(slivers: slivers);
    return Scaffold(
      backgroundColor: GlitchColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CatalogTopBar(search: search),
            Expanded(
              child: onScroll == null
                  ? scroll
                  : NotificationListener<ScrollNotification>(onNotification: onScroll, child: scroll),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogTopBar extends StatelessWidget {
  final Widget? search;

  const _CatalogTopBar({this.search});

  static const double _narrow = 640;

  @override
  Widget build(BuildContext context) {
    final inCenter = ShellPlace.slotForBuild(context) == ShellSlot.main;
    final tabs = Row(
      children: [
        if (inCenter)
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: Icon(Icons.explore_rounded, size: 22, color: Colors.white),
          )
        else
          GlitchIconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onTap: () => closeAdaptive(context),
          ),
        _Tab(label: context.s.catalogHome, selected: true),
        _Tab(label: context.s.catalogSoon),
        _Tab(label: context.s.catalogSoon),
      ],
    );
    return Container(
      color: _heroDark(),
      padding: EdgeInsets.fromLTRB(inCenter ? 20 : 4, 0, 16, 0),
      child: LayoutBuilder(
        builder: (context, c) {
          if (search == null) return SizedBox(height: kShellBarHeight, child: tabs);
          if (c.maxWidth < _narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: kShellBarHeight, child: tabs),
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 12),
                  child: search,
                ),
              ],
            );
          }
          return SizedBox(
            height: kShellBarHeight,
            child: Row(
              children: [
                Expanded(child: tabs),
                SizedBox(width: 240, child: search),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool selected;

  const _Tab({required this.label, this.selected = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : Colors.white.withOpacity(0.45),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: 28,
              height: 2,
              decoration: BoxDecoration(
                color: selected ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      );
}

class CatalogHero extends StatelessWidget {
  final String title;
  final String subtitle;

  const CatalogHero({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_heroDark(), _heroLight()],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 640;
          return CatalogContentWidth(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: wide ? 88 : 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Text(
                      title.toUpperCase(),
                      style: TextStyle(
                        fontSize: wide ? 38 : 26,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: wide ? 16 : 14,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class CatalogContentWidth extends StatelessWidget {
  static const double maxWidth = 1240;
  static const double _minSide = 16;
  static const double _wideSide = 32;

  final Widget child;

  const CatalogContentWidth({super.key, required this.child});

  static double sidePaddingFor(double width) {
    final side = width >= 640 ? _wideSide : _minSide;
    final centered = (width - maxWidth) / 2;
    return centered > side ? centered : side;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => Padding(
          padding: EdgeInsets.symmetric(horizontal: sidePaddingFor(c.maxWidth)),
          child: child,
        ),
      );
}
