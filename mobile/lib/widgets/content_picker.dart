import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/adaptive_open.dart';
import '../core/l10n.dart';
import '../models/gif.dart';
import '../models/sticker.dart';
import '../theme/app_theme.dart';
import 'adaptive_sheet.dart';
import 'emoji_picker_panel.dart';
import 'gif_picker_sheet.dart';
import 'glitch_hover_row.dart';
import 'glitch_divider.dart';
import 'glitch_pressable.dart';
import 'glitch_segmented_control.dart';
import 'sticker_picker_panel.dart';

class ContentPicker extends StatefulWidget {
  final ValueChanged<String>? onEmoji;

  final ValueChanged<GifItem>? onGif;

  final ValueChanged<Sticker>? onSticker;

  final VoidCallback? onClose;

  const ContentPicker({
    super.key,
    this.onEmoji,
    this.onGif,
    this.onSticker,
    this.onClose,
  }) : assert(onEmoji != null || onGif != null || onSticker != null);

  static Color background(BuildContext context) =>
      isWideLayout(context) ? GlitchColors.bgPicker : GlitchColors.bgPickerNarrow;

  static const double narrowTopInset = 22;

  @override
  State<ContentPicker> createState() => _ContentPickerState();
}

enum _Tab { gif, sticker, emoji }

class _ContentPickerState extends State<ContentPicker> {
  static _Tab _lastTab = _Tab.emoji;

  late final List<_Tab> _tabs = [
    if (widget.onGif != null) _Tab.gif,
    if (widget.onSticker != null) _Tab.sticker,
    if (widget.onEmoji != null) _Tab.emoji,
  ];

  late _Tab _tab = _tabs.contains(_lastTab) ? _lastTab : (_tabs.contains(_Tab.emoji) ? _Tab.emoji : _tabs.first);

  late final Set<_Tab> _visited = {_tab};

  void _select(_Tab tab) => setState(() {
        _tab = tab;
        _lastTab = tab;
        _visited.add(tab);
      });

  String _label(BuildContext context, _Tab tab) => switch (tab) {
        _Tab.gif => context.s.contentTabGif,
        _Tab.sticker => context.s.contentTabStickers,
        _Tab.emoji => context.s.contentTabEmoji,
      };

  Widget _body(_Tab tab) {
    if (!_visited.contains(tab)) return const SizedBox.shrink();
    return switch (tab) {
      _Tab.gif => GifPickerPanel(onPick: widget.onGif!),
      _Tab.sticker => StickerPickerPanel(onPicked: widget.onSticker!),
      _Tab.emoji => EmojiPickerPanel(onPicked: widget.onEmoji!),
    };
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWideLayout(context);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_tabs.length > 1)
          Padding(
            key: const ValueKey('tabs'),
            padding: EdgeInsets.fromLTRB(12, wide ? 12 : ContentPicker.narrowTopInset, 12, 10),
            child: wide
                ? Row(
                    children: [
                      for (final tab in _tabs)
                        _SmallTab(label: _label(context, tab), selected: tab == _tab, onTap: () => _select(tab)),
                    ],
                  )
                : GlitchSegmentedControl(
                    height: 48,
                    labels: [for (final tab in _tabs) _label(context, tab)],
                    selected: _tabs.indexOf(_tab),
                    onChanged: (i) => _select(_tabs[i]),
                  ),
          )
        else
          SizedBox(key: const ValueKey('no-tabs'), height: wide ? 6 : ContentPicker.narrowTopInset),
        Expanded(
          key: const ValueKey('body'),
          child: IndexedStack(
            index: _tabs.indexOf(_tab),
            sizing: StackFit.expand,
            children: [for (final tab in _tabs) _body(tab)],
          ),
        ),
      ],
    );
    final painted = ColoredBox(color: ContentPicker.background(context), child: content);
    final close = widget.onClose;
    if (close == null) return painted;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
      child: FocusScope(autofocus: true, child: painted),
    );
  }
}

class PickerRail extends StatelessWidget {
  final int count;

  final int selected;

  final Widget Function(int index, bool lit) item;
  final ValueChanged<int> onTap;

  const PickerRail({
    super.key,
    required this.count,
    required this.selected,
    required this.item,
    required this.onTap,
  });

  static const double width = 48;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      color: GlitchColors.bgPickerRail,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: count,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: GlitchHoverArea(
              onTap: () => onTap(i),
              builder: (_, active) => Container(
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: GlitchHoverRow.highlight(context, active: active, selected: i == selected),
                  borderRadius: BorderRadius.circular(GlitchHoverRow.radius),
                ),
                child: item(i, active || i == selected),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ContentPickerDivider extends StatelessWidget {
  const ContentPickerDivider({super.key});

  @override
  Widget build(BuildContext context) => const GlitchDivider();
}

class _SmallTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SmallTab({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 4),
        child: GlitchHoverArea(
          onTap: onTap,
          builder: (_, active) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: GlitchHoverRow.highlight(context, active: active, selected: selected),
              borderRadius: BorderRadius.circular(GlitchHoverRow.radius),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected || active ? GlitchColors.textPrimary : GlitchColors.textSecond,
              ),
            ),
          ),
        ),
      );
}

const double _kWindowWidth = 480;
const double _kWindowHeight = 460;

const double _kSheetHeightFactor = 0.6;

Future<void> openEmojiPicker(
  BuildContext anchor, {
  required ValueChanged<String> onEmoji,
  bool growRight = false,
}) =>
    openContentPicker(anchor, onEmoji: onEmoji, growRight: growRight);

Future<void> openContentPicker(
  BuildContext anchor, {
  ValueChanged<String>? onEmoji,
  ValueChanged<GifItem>? onGif,
  ValueChanged<Sticker>? onSticker,
  bool growRight = false,
}) {
  final screenHeight = MediaQuery.of(anchor).size.height;
  final wide = isWideLayout(anchor);
  return openAdaptivePopup(
    anchor,
    width: _kWindowWidth,
    growRight: growRight,
    builder: (close, maxHeight) {
      void Function(T) closing<T>(ValueChanged<T> pick) => (value) {
            close();
            pick(value);
          };
      return SizedBox(
        height: math.min(maxHeight, wide ? _kWindowHeight : screenHeight * _kSheetHeightFactor),
        child: ContentPicker(
          onEmoji: onEmoji == null ? null : closing(onEmoji),
          onGif: onGif == null ? null : closing(onGif),
          onSticker: onSticker == null ? null : closing(onSticker),
          onClose: wide ? close : null,
        ),
      );
    },
  );
}
