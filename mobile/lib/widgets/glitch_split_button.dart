import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/glitch_ink.dart';
import 'glitch_hover_row.dart';
import 'glitch_pressable.dart';
import 'glitch_tooltip.dart';

class GlitchSplitButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Future<void> Function(BuildContext anchor)? onMenu;

  final double height;
  final double mainWidth;
  final double arrowWidth;
  final double iconSize;
  final double radius;

  final Color? iconColor;

  final Color? fill;

  final String? tooltip;
  final String? menuTooltip;

  const GlitchSplitButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.onMenu,
    required this.height,
    required this.mainWidth,
    required this.arrowWidth,
    required this.iconSize,
    required this.radius,
    this.iconColor,
    this.fill,
    this.tooltip,
    this.menuTooltip,
  });

  @override
  State<GlitchSplitButton> createState() => _GlitchSplitButtonState();
}

class _GlitchSplitButtonState extends State<GlitchSplitButton> {
  bool _open = false;

  Future<void> _showMenu(BuildContext anchor) async {
    setState(() => _open = true);
    await widget.onMenu!(anchor);
    if (mounted) setState(() => _open = false);
  }

  Color _background(BuildContext context, bool active) =>
      widget.fill ?? GlitchHoverRow.highlight(context, active: active);

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final withArrow = w.onMenu != null;
    final r = Radius.circular(w.radius);
    final palette = GlitchInk.of(context);
    final ink = w.iconColor ?? palette.textPrimary;
    return SizedBox(
      height: w.height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlitchTooltip(
            message: w.tooltip,
            child: GlitchHoverArea(
              onTap: w.onTap,
              builder: (context, active) => Container(
                width: w.mainWidth,
                height: w.height,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _background(context, active),
                  borderRadius: withArrow ? BorderRadius.horizontal(left: r) : BorderRadius.all(r),
                ),
                child: Icon(w.icon, size: w.iconSize, color: ink),
              ),
            ),
          ),
          if (withArrow)
            Builder(
              builder: (anchor) => GlitchTooltip(
                message: w.menuTooltip,
                child: GlitchHoverArea(
                  onTap: () => unawaited(_showMenu(anchor)),
                  builder: (context, active) => Container(
                    width: w.arrowWidth,
                    height: w.height,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _background(context, active || _open),
                      borderRadius: BorderRadius.horizontal(right: r),
                    ),
                    child: Icon(
                      _open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: w.fill != null
                          ? ink
                          : active || _open
                              ? palette.textPrimary
                              : palette.textSecond,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
