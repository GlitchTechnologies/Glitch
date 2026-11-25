import 'package:flutter/material.dart';
import '../core/platform_info.dart';
import '../theme/glitch_ink.dart';
import '../theme/glitch_palette.dart';
import 'glitch_pressable.dart';

class GlitchHoverRow extends StatelessWidget {
  final Widget? child;

  final Widget Function(bool active)? builder;

  final VoidCallback? onTap;

  final ValueChanged<bool>? onHoverChanged;
  final EdgeInsets padding;

  /// ⚠️ ВЫСОТА СТРОКИ НЕ ДОЛЖНА МЕНЯТЬСЯ, когда кнопка появляется, — иначе при
  /// наведении строка «прыгает» (найдено владельцем 2026-09-23: кнопка была 26
  /// точек при содержимом строки в 20). Поэтому кнопка обязана вписываться в
  /// [trailingSize] — сторону слота, равную высоте самого высокого содержимого
  /// строки (иконка канала, 20). Строка кладёт кнопку в слот такого размера
  /// сама и по высоте больше не растёт. Понадобится кнопка крупнее — растить
  /// нужно и содержимое, а не слот.
  final Widget? trailing;

  final bool selected;

  const GlitchHoverRow({
    super.key,
    this.child,
    this.builder,
    required this.onTap,
    this.onHoverChanged,
    this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 10),
    this.selected = false,
    this.trailing,
    this.highlightInset = defaultHighlightInset,
  });

  final EdgeInsets highlightInset;

  static const EdgeInsets defaultHighlightInset =
      EdgeInsets.symmetric(horizontal: 8, vertical: 1);

  static const double trailingSize = 20;

  static const double radius = 8;

  static const double _hoverStrength = 0.8;
  static const double _selectedStrength = _hoverStrength * 1.2;

  static const double _feedStrength = _hoverStrength * 0.75;

  static Color highlight(BuildContext context, {
    required bool active,
    bool selected = false,
    GlitchPalette? palette,
  }) {
    if (!active && !selected) return Colors.transparent;
    return _layer(palette ?? GlitchInk.of(context), selected ? _selectedStrength : _hoverStrength);
  }

  static Color feedHighlight(BuildContext context, {required bool active}) =>
      active ? _layer(GlitchInk.of(context), _feedStrength) : Colors.transparent;

  static Color _layer(GlitchPalette palette, double strength) {
    final tint = palette.hoverTint ?? palette.bgChip;
    return tint.withOpacity(tint.opacity * strength);
  }

  Widget _content(bool active) => builder?.call(active) ?? child!;

  @override
  Widget build(BuildContext context) {
    final inset = highlightInset;
    assert(
      padding.left >= inset.left && padding.right >= inset.right &&
          padding.top >= inset.top && padding.bottom >= inset.bottom,
      'GlitchHoverRow: padding меньше отступа подсветки ($inset)',
    );
    assert((child == null) != (builder == null), 'GlitchHoverRow: нужен ровно один из child / builder');
    return GlitchHoverArea(
      onTap: onTap,
      onHoverChanged: onHoverChanged,
      builder: (context, active) => Container(
        margin: inset,
        padding: EdgeInsets.fromLTRB(
          padding.left - inset.left,
          padding.top - inset.top,
          padding.right - inset.right,
          padding.bottom - inset.bottom,
        ),
        decoration: BoxDecoration(
          color: highlight(context, active: active, selected: selected),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: trailing == null
            ? _content(active || selected)
            : Row(
                children: [
                  Expanded(child: _content(active || selected)),
                  if (active || selected || !hasPointerInput) ...[
                    const SizedBox(width: 6),
                    SizedBox.square(dimension: trailingSize, child: trailing),
                  ],
                ],
              ),
      ),
    );
  }
}
