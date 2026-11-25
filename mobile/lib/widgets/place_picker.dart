import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n.dart';
import '../models/search.dart';
import '../providers/search_session.dart';
import '../providers/theme_provider.dart' show ThemeAwareState;
import '../services/api_service.dart';
import '../services/recent_places.dart';
import '../theme/app_theme.dart';
import 'avatar_shape.dart';
import 'glitch_dialog.dart' show GlitchCheckMark;
import 'glitch_avatar.dart';
import 'glitch_hover_row.dart';
import 'glitch_search_field.dart';
import 'server_user_avatar.dart';

class PlacePicker extends StatefulWidget {
  final String hint;
  final ValueChanged<SearchHit> onChoose;
  final Set<SearchKind>? kinds;
  final bool Function(SearchHit hit)? accepts;

  final double fieldHeight;
  final EdgeInsetsGeometry fieldPadding;

  final Widget? fieldLeading;

  final bool Function(SearchHit hit)? checked;

  final bool canCheckMore;

  const PlacePicker({
    super.key,
    required this.hint,
    required this.onChoose,
    this.kinds,
    this.accepts,
    this.fieldHeight = 44,
    this.fieldPadding = EdgeInsets.zero,
    this.fieldLeading,
    this.checked,
    this.canCheckMore = true,
  });

  @override
  State<PlacePicker> createState() => _PlacePickerState();
}

String _sectionTitle(BuildContext context, SearchKind kind) => switch (kind) {
      SearchKind.person => context.s.searchSectionPeople,
      SearchKind.group => context.s.searchSectionGroups,
      SearchKind.room => context.s.searchSectionRooms,
      SearchKind.server => context.s.searchSectionServers,
    };

// ThemeAwareState: цвета берутся при сборке — смена темы перекрашивает окно.
class _PlacePickerState extends State<PlacePicker> with ThemeAwareState<PlacePicker> {
  final _ctrl = TextEditingController();
  late final _session = SearchSession<SearchHit>(search: (q) => api.searchEverything(q, kinds: widget.kinds));
  final _scroll = ScrollController();

  List<SearchHit>? _recent;

  int _active = 0;

  final Map<int, GlobalKey> _rowKeys = {};

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSession);
    _loadRecent();
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    _session.dispose();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    try {
      final hits = await recentPlaces.load();
      if (mounted) setState(() => _recent = hits);
    } catch (_) {
      if (mounted) setState(() => _recent = const []);
    }
  }

  void _onSession() {
    if (!mounted) return;
    setState(() => _active = 0);
  }

  bool _fits(SearchHit hit) =>
      (widget.kinds == null || widget.kinds!.contains(hit.kind)) && (widget.accepts?.call(hit) ?? true);

  List<SearchHit> get _hits =>
      (_session.isEmpty ? (_recent ?? const <SearchHit>[]) : _session.hits).where(_fits).toList();

  void _move(int delta) {
    final n = _hits.length;
    if (n == 0) return;
    setState(() => _active = (_active + delta) % n);
    final ctx = _rowKeys[_active]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 120), alignmentPolicy:
          delta > 0 ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd : ScrollPositionAlignmentPolicy.keepVisibleAtStart);
    }
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      _move(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _submit(String _) {
    final hits = _hits;
    if (_active < hits.length) widget.onChoose(hits[_active]);
  }

  @override
  Widget build(BuildContext context) {
    final field = Focus(
      onKeyEvent: _onKey,
      canRequestFocus: false,
      skipTraversal: true,
      child: GlitchSearchField(
        controller: _ctrl,
        hint: widget.hint,
        autofocus: true,
        height: widget.fieldHeight,
        loading: _session.loading,
        onChanged: _session.setQuery,
        onSubmitted: _submit,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: widget.fieldPadding,
          child: widget.fieldLeading == null
              ? field
              : Row(children: [widget.fieldLeading!, Expanded(child: field)]),
        ),
        Expanded(child: _results(context)),
      ],
    );
  }

  Widget _results(BuildContext context) {
    final searching = !_session.isEmpty;
    if (searching && _session.failed && _session.hits.isEmpty) {
      return _notice(context.s.searchFailed, action: TextButton(
        onPressed: _session.retry,
        child: Text(context.s.retry, style: TextStyle(color: GlitchColors.accentBlue)),
      ));
    }
    if (!searching && _recent == null) return const SizedBox.shrink();
    final hits = _hits;
    if (hits.isEmpty) {
      if (searching && !_session.loading) return _notice(context.s.searchNothingFound);
      return const SizedBox.shrink();
    }

    final rows = <Widget>[];
    SearchKind? section;
    for (var i = 0; i < hits.length; i++) {
      final hit = hits[i];
      if (!searching && i == 0) {
        rows.add(_header(context.s.searchSectionRecent));
      } else if (searching && hit.kind != section) {
        rows.add(_header(_sectionTitle(context, hit.kind)));
      }
      section = hit.kind;
      final key = _rowKeys.putIfAbsent(i, GlobalKey.new);
      rows.add(KeyedSubtree(key: key, child: _row(hit, i)));
    }
    return SingleChildScrollView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
    );
  }

  Widget _notice(String text, {Widget? action}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(text, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: GlitchColors.textPrimary)),
            if (action != null) ...[const SizedBox(height: 8), action],
          ]),
        ),
      );

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: Text(text, style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: GlitchColors.textHint,
        )),
      );

  Widget _row(SearchHit hit, int index) {
    final (leading, title, subtitle, trailing) = _parts(hit);
    final checked = widget.checked?.call(hit);
    return GlitchHoverRow(
      onTap: () => widget.onChoose(hit),
      onHoverChanged: (on) {
        if (on && _active != index) setState(() => _active = index);
      },
      selected: index == _active,
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
      child: Row(children: [
        SizedBox.square(dimension: 28, child: Center(child: leading)),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: title, style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w500, color: GlitchColors.textPrimary,
              )),
              if (subtitle != null)
                TextSpan(text: '  $subtitle', style: TextStyle(fontSize: 13, color: GlitchColors.textSecond)),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(trailing, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: GlitchColors.textSecond)),
          ),
        ],
        if (checked != null) ...[
          const SizedBox(width: 12),
          GlitchCheckMark(value: checked, enabled: checked || widget.canCheckMore),
        ],
      ]),
    );
  }

  (Widget, String, String?, String?) _parts(SearchHit hit) {
    switch (hit.kind) {
      case SearchKind.person:
        final p = hit.person!;
        return (ServerUserAvatar(user: p, name: p.displayName, size: 24), p.displayName, p.nickname, null);
      case SearchKind.group:
        final g = hit.group!;
        return (
          GlitchAvatar(
            initials: GlitchAvatar.initialsFromName(g.name),
            size: 24,
            colorIndex: GlitchAvatar.colorFromNickname(g.name),
            imageUrl: g.avatar != null ? api.mediaUrl(g.avatar!) : null,
            avatarSizes: g.avatarSizes,
            shape: AvatarShape.group,
          ),
          g.name, null, null,
        );
      case SearchKind.room:
        final r = hit.room!;
        return (
          Icon(r.isVoice ? Icons.volume_up_rounded : Icons.tag_rounded, size: 20, color: GlitchColors.textSecond),
          r.name, r.category, r.server.name,
        );
      case SearchKind.server:
        final server = hit.server!;
        return (
          GlitchAvatar(
            initials: GlitchAvatar.initialsFromName(server.name),
            size: 24,
            colorIndex: GlitchAvatar.colorFromNickname(server.name),
            imageUrl: server.avatar != null ? api.mediaUrl(server.avatar!) : null,
            avatarSizes: server.avatarSizes,
            shape: AvatarShape.community,
          ),
          server.name, null, null,
        );
    }
  }
}
