import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'glitch_menu.dart';
import 'glitch_pressable.dart';
import 'glitch_switch.dart';

class GlitchSelectField<T> extends StatelessWidget {
  final T value;
  final List<T> options;
  final String Function(T option) label;

  final Widget Function(T option, TextStyle style)? view;

  /// null — поле недоступно: видно, что выбрано, но не открывается (серым,
  /// как неактивный ползунок).
  final ValueChanged<T>? onChanged;

  final bool expand;

  final double? menuLabelWidth;

  const GlitchSelectField({
    super.key,
    required this.value,
    required this.options,
    required this.label,
    required this.onChanged,
    this.expand = false,
    this.menuLabelWidth,
    this.view,
  });

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    final ink = onChanged == null ? GlitchColors.textHint : GlitchColors.textPrimary;
    final shown = _option(value, TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ink));
    return Builder(
      builder: (anchor) => ClickableCursor(
        enabled: onChanged != null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onChanged == null ? null : () => _open(anchor, onChanged),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
            decoration: BoxDecoration(
              color: GlitchColors.bgInput,
              border: Border.all(color: GlitchColors.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              children: [
                if (expand) Expanded(child: shown) else shown,
                const SizedBox(width: 4),
                Icon(Icons.expand_more_rounded, size: 20, color: ink),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _open(BuildContext anchor, ValueChanged<T> onChanged) {
    final fieldWidth = (anchor.findRenderObject() as RenderBox).size.width;
    final labelWidth = menuLabelWidth ??
        (expand
            ? (fieldWidth - kMenuItemPadding.horizontal - _menuGap - _checkWidth).clamp(40.0, double.infinity)
            : null);
    unawaited(openGlitchMenu<T>(
      anchor,
      growRight: true,
      onSelected: onChanged,
      items: [
        for (final option in options)
          GlitchMenuItem(
            value: option,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (menuLabelWidth != null)
                  SizedBox(width: menuLabelWidth, child: _menuLabel(option))
                else if (labelWidth != null) ...[
                  SizedBox(width: labelWidth, child: _menuLabel(option)),
                  const SizedBox(width: _menuGap),
                ] else ...[
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _menuLabelMax),
                    child: _menuLabel(option),
                  ),
                  const SizedBox(width: _menuGap),
                ],
                SizedBox(
                  width: _checkWidth,
                  child: option == value
                      ? Icon(Icons.check_rounded, size: 18, color: GlitchColors.accentBlue)
                      : null,
                ),
              ],
            ),
          ),
      ],
    ));
  }

  static const double _menuLabelMax = 320;
  static const double _menuGap = 12;
  static const double _checkWidth = 18;

  Widget _menuLabel(T option) => _option(option, TextStyle(fontSize: 15, color: GlitchColors.textPrimary));

  Widget _option(T option, TextStyle style) {
    final view = this.view;
    if (view != null) return view(option, style);
    return Text(label(option), maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
  }
}

class GlitchSelectRow<T> extends StatelessWidget {
  final String label;
  final String? description;
  final T value;
  final List<T> options;
  final String Function(T option) optionLabel;

  final Widget Function(T option, TextStyle style)? optionView;

  final ValueChanged<T>? onChanged;
  final bool border;
  final EdgeInsets padding;

  const GlitchSelectRow({
    super.key,
    required this.label,
    this.description,
    required this.value,
    required this.options,
    required this.optionLabel,
    this.optionView,
    required this.onChanged,
    this.border = false,
    required this.padding,
  });

  static const double _fieldWidth = 240;

  static const double _sideBySideMin = 480;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final field = GlitchSelectField<T>(
            value: value,
            options: options,
            label: optionLabel,
            view: optionView,
            onChanged: onChanged,
            expand: true,
          );
          final side = constraints.maxWidth >= _sideBySideMin;
          return GlitchControlRow(
            label: label,
            description: description,
            enabled: onChanged != null,
            border: border,
            padding: padding,
            control: side ? SizedBox(width: _fieldWidth, child: field) : null,
            below: side ? null : field,
          );
        },
      );
}
