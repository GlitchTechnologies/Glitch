import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/glitch_ink.dart';
import '../theme/glitch_palette.dart';
import 'glitch_hover_row.dart';
import 'glitch_divider.dart';
import 'glitch_menu.dart';
import 'glitch_icon_button.dart';


class GlitchCascadeOption {
  final String label;
  final IconData? icon;
  final bool? selected;
  final VoidCallback onSelect;

  const GlitchCascadeOption({required this.label, this.selected, required this.onSelect, this.icon});
}

class GlitchCascadeEntry {
  final String title;
  final String value;
  final List<GlitchCascadeOption> options;
  final Widget? leading;
  final VoidCallback? onSelect;
  final int subtitleMaxLines;
  final bool separatorBefore;

  const GlitchCascadeEntry({required this.title, required this.value, required this.options, this.leading, this.onSelect, this.subtitleMaxLines = 1, this.separatorBefore = false});
}

class GlitchCascadeMenu extends StatefulWidget {
  final List<GlitchCascadeEntry> entries;

  final List<Widget> footer;
  final Future<void> Function() close;
  final double maxHeight;
  final double mainWidth;
  final double listWidth;

  final bool listOnLeft;

  final bool opensUp;

  const GlitchCascadeMenu({
    super.key,
    required this.entries,
    required this.close,
    required this.maxHeight,
    this.footer = const [],
    this.mainWidth = 260,
    this.listWidth = 300,
    this.listOnLeft = false,
    this.opensUp = false,
  });

  static const double gap = kGlitchPopupSideGap;

  static double popupWidth({double mainWidth = 260, double listWidth = 300}) => mainWidth + gap + listWidth;

  @override
  State<GlitchCascadeMenu> createState() => _GlitchCascadeMenuState();
}

const Duration _kListCloseDelay = Duration(milliseconds: 150);

class _GlitchCascadeMenuState extends State<GlitchCascadeMenu> {
  int? _open;
  int? _overRow;
  bool _overList = false;
  Timer? _closeTimer;

  @override
  void dispose() {
    _closeTimer?.cancel();
    super.dispose();
  }

  void _hover({int? row, bool leftRow = false, bool? list}) {
    if (row != null) _overRow = row;
    if (leftRow) _overRow = null;
    if (list != null) _overList = list;
    _closeTimer?.cancel();
    final over = _overRow;
    if (over != null) {
      final next = widget.entries[over].options.isEmpty ? null : over;
      if (_open != next) setState(() => _open = next);
      return;
    }
    if (_overList) return;
    _closeTimer = Timer(_kListCloseDelay, () {
      if (mounted && _overRow == null && !_overList && _open != null) setState(() => _open = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ink = GlitchInk.of(context);
    final entries = widget.entries;
    final open = _open != null && _open! < entries.length ? _open : null;
    final menu = SizedBox(
      width: widget.mainWidth,
      child: GlitchPopupCard(
        maxHeight: widget.maxHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (entries[i].separatorBefore)
                  KeyedSubtree(key: ValueKey('separator_$i'), child: glitchMenuSeparator()),
                KeyedSubtree(key: ValueKey('entry_$i'), child: _row(ink, entries[i], i, open == i)),
              ],
              if (entries.isNotEmpty && widget.footer.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: GlitchDivider(),
                ),
              ...widget.footer,
            ],
          ),
        ),
      ),
    );
    final list = open == null
        ? null
        : MouseRegion(
            onEnter: (_) => _hover(list: true),
            onExit: (_) => _hover(list: false),
            child: SizedBox(width: widget.listWidth, child: _list(ink, entries[open])),
          );
    final children = <Widget>[
      menu,
      const SizedBox(width: GlitchCascadeMenu.gap),
      if (list != null) list,
    ];
    return Row(
      mainAxisAlignment: widget.listOnLeft ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: widget.opensUp ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: widget.listOnLeft ? children.reversed.toList() : children,
    );
  }

  Widget _row(GlitchPalette ink, GlitchCascadeEntry entry, int index, bool isOpen) => MouseRegion(
        onEnter: (_) => _hover(row: index),
        onExit: (_) => _hover(leftRow: true),
        child: GlitchHoverRow(
          onTap: () {
            if (entry.onSelect case final action?) {
              action();
              unawaited(widget.close());
            } else {
              setState(() => _open = isOpen ? null : index);
            }
          },
          selected: isOpen,
          padding: const EdgeInsets.fromLTRB(16, 9, 12, 9),
          child: Row(
            children: [
              if (entry.leading != null) ...[
                KeyedSubtree(key: const ValueKey('leading'), child: entry.leading!),
                const SizedBox(key: ValueKey('leadingGap'), width: 10),
              ],
              Expanded(
                key: const ValueKey('label'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.title,
                      key: const ValueKey('title'),
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: ink.textPrimary),
                    ),
                    if (entry.value.isNotEmpty) const SizedBox(key: ValueKey('subtitleGap'), height: 2),
                    if (entry.value.isNotEmpty) Text(
                      entry.value,
                      key: const ValueKey('subtitle'),
                      maxLines: entry.subtitleMaxLines,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: ink.textSecond),
                    ),
                  ],
                ),
              ),
              if (entry.options.isNotEmpty && entry.onSelect != null) GlitchIconButton(
                key: const ValueKey('chevron'),
                size: 20,
                extent: 20,
                iconSize: 20,
                onTap: () => setState(() => _open = index),
                icon: Icon(widget.listOnLeft ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                    color: ink.textSecond),
              ) else if (entry.options.isNotEmpty) Icon(
                widget.listOnLeft ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                key: const ValueKey('chevron'),
                size: 20,
                color: ink.textSecond,
              ),
            ],
          ),
        ),
      );

  Widget _list(GlitchPalette ink, GlitchCascadeEntry entry) => GlitchPopupCard(
        maxHeight: widget.maxHeight,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final option in entry.options)
                GlitchHoverRow(
                  onTap: () {
                    option.onSelect();
                    unawaited(widget.close());
                  },
                  padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
                  child: Row(
                    children: [
                      if (option.icon != null) ...[
                        Icon(option.icon, size: 18, color: ink.textSecond),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(
                          option.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, color: ink.textPrimary),
                        ),
                      ),
                      if (option.selected != null) const SizedBox(width: 10),
                      if (option.selected != null) _Radio(on: option.selected!),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
}

class GlitchCascadeAnchor extends StatefulWidget {
  final Widget Function(VoidCallback open) childBuilder;
  final Widget Function(Future<void> Function() close, double maxHeight) menuBuilder;
  final double width;
  final bool enabled;

  final BuildContext? surfaceContext;

  const GlitchCascadeAnchor({super.key, required this.childBuilder, required this.menuBuilder, required this.width, this.enabled = true, this.surfaceContext});

  @override
  State<GlitchCascadeAnchor> createState() => _GlitchCascadeAnchorState();
}

class _GlitchCascadeAnchorState extends State<GlitchCascadeAnchor> {
  Timer? _timer;
  Future<void> Function()? _close;
  bool _opened = false;

  void _leave() {
    _timer?.cancel();
    _timer = Timer(_kListCloseDelay, () {
      final close = _close;
      if (close != null) unawaited(close());
    });
  }

  Future<void> _open() async {
    _timer?.cancel();
    if (_opened || !widget.enabled) return;
    _opened = true;
    try {
      Rect? anchorRect;
      final surfaceContext = widget.surfaceContext;
      if (surfaceContext != null) {
        final surface = surfaceContext.findRenderObject() as RenderBox;
        final row = context.findRenderObject() as RenderBox;
        anchorRect = Rect.fromLTWH(surface.localToGlobal(Offset.zero).dx,
            row.localToGlobal(Offset.zero).dy, surface.size.width, row.size.height);
      }
      await openGlitchPopup(
        context,
        width: widget.width,
        side: GlitchPopupSide.right,
        anchorRect: anchorRect,
        tapOutsideCloses: false,
        builder: (close, maxHeight) {
          _close = close;
          return MouseRegion(
            onEnter: (_) => _timer?.cancel(),
            onExit: (_) => _leave(),
            child: widget.menuBuilder(close, maxHeight),
          );
        },
      );
    } finally {
      _opened = false;
      _close = null;
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    final close = _close;
    if (close != null) unawaited(close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => unawaited(_open()),
        onExit: (_) => _leave(),
        child: widget.childBuilder(() => unawaited(_open())),
      );
}

class _Radio extends StatelessWidget {
  final bool on;

  const _Radio({required this.on});

  @override
  Widget build(BuildContext context) => Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? GlitchColors.accentBlue : Colors.transparent,
          border: on ? null : Border.all(color: GlitchInk.of(context).textSecond, width: 2),
        ),
        alignment: Alignment.center,
        child: on
            ? Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
              )
            : null,
      );
}
