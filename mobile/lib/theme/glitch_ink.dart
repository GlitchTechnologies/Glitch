import 'package:flutter/material.dart';

import '../providers/theme_provider.dart';
import 'glitch_palette.dart';

class GlitchInk extends InheritedWidget {
  final GlitchPalette palette;

  const GlitchInk({super.key, required this.palette, required super.child});

  static GlitchPalette of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlitchInk>()?.palette ?? themeProvider.palette;

  static Widget wrap(GlitchPalette? palette, Widget child) {
    if (palette == null) return child;
    return GlitchInk(palette: palette, child: Builder(builder: (context) => _withInkResponse(context, palette, child)));
  }

  static Widget _withInkResponse(BuildContext context, GlitchPalette palette, Widget child) {
    final theme = Theme.of(context);
    final own = ThemeData.estimateBrightnessForColor(palette.bgMenu);
    if (own == theme.brightness) return child;
    final defaults = own == Brightness.dark ? _dark : _light;
    return Theme(
      data: theme.copyWith(
        hoverColor: defaults.hoverColor,
        splashColor: defaults.splashColor,
        highlightColor: defaults.highlightColor,
        focusColor: defaults.focusColor,
      ),
      child: child,
    );
  }

  static final ThemeData _dark = ThemeData(brightness: Brightness.dark);
  static final ThemeData _light = ThemeData(brightness: Brightness.light);

  @override
  bool updateShouldNotify(GlitchInk old) => old.palette != palette;
}
