import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'glitch_hover_row.dart';
import 'glitch_pressable.dart';
import 'glitch_tooltip.dart';

class GlitchIconButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onHoverChanged;
  final double size;
  final double? extent;
  final double iconSize;

  final bool selected;

  final String? tooltip;
  final GlitchTooltipSide tooltipSide;

  final bool hoverWhenDisabled;

  const GlitchIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.onHoverChanged,
    this.size = 40,
    this.extent = 48,
    this.iconSize = 24,
    this.selected = false,
    this.tooltip,
    this.tooltipSide = GlitchTooltipSide.top,
    this.hoverWhenDisabled = false,
  });

  const GlitchIconButton.panel({
    super.key,
    required this.icon,
    required this.onTap,
    this.onHoverChanged,
    this.selected = false,
    this.tooltip,
  })  : size = panelSize,
        extent = panelSize,
        iconSize = panelIconSize,
        tooltipSide = GlitchTooltipSide.top,
        hoverWhenDisabled = true;

  static const double panelSize = 32;
  static const double panelIconSize = 20;

  static const double _disabledOpacity = 0.4;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final side = extent ?? size;
    Widget glyph = IconTheme.merge(
      data: IconThemeData(size: iconSize, color: GlitchColors.textPrimary),
      child: icon,
    );
    if (!enabled && !hoverWhenDisabled) glyph = Opacity(opacity: _disabledOpacity, child: glyph);
    return GlitchTooltip(
      message: tooltip,
      side: tooltipSide,
      child: GlitchHoverArea(
        onTap: onTap,
        onHoverChanged: onHoverChanged,
        hoverWhenDisabled: hoverWhenDisabled,
        builder: (context, active) => SizedBox(
          width: side,
          height: side,
          child: Center(
            child: Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: GlitchHoverRow.highlight(context, active: active || selected),
                borderRadius: BorderRadius.circular(GlitchHoverRow.radius),
              ),
              child: glyph,
            ),
          ),
        ),
      ),
    );
  }
}

class GlitchAddButton extends StatelessWidget {
  final VoidCallback? onTap;
  final double size;

  const GlitchAddButton({super.key, required this.onTap, this.size = 34});

  @override
  Widget build(BuildContext context) => GlitchIconButton(
        onTap: onTap,
        size: size,
        extent: size,
        iconSize: size * 22 / 34,
        icon: const Icon(Icons.add_rounded),
      );
}
