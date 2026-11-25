import 'package:flutter/material.dart';

enum GlitchThemePreset {
  light('light'),
  dark('dark'),
  onyx('onyx');

  const GlitchThemePreset(this.id);

  final String id;

  static GlitchThemePreset fromId(Object? id) {
    for (final preset in values) {
      if (preset.id == id) return preset;
    }
    return dark;
  }

  GlitchPalette palette(Color accent) => switch (this) {
        light => GlitchPalette.light(accent),
        dark => GlitchPalette.dark(accent),
        onyx => GlitchPalette.onyx(accent),
      };
}

class GlitchPalette {
  final Brightness brightness;
  final Color bg, bgInput, bgCard, bgMessage, bgChip, bgMenu, bgToolbar;
  final Color? hoverTint;
  final Color bgEmbed;
  final Color bgEmbedForm;
  final Color bgPicker, bgPickerNarrow, bgPickerRail;
  final Color border, borderCard, borderSoft, borderMuted, borderMenu;
  final Color borderWindow;
  final Color borderMessageCard;
  final Color textPrimary, textSecond, textHint, textDim;
  final Color textNavIdle;
  final Color accent, accentDark;

  const GlitchPalette({
    required this.brightness,
    required this.bg,
    required this.bgInput,
    required this.bgCard,
    required this.bgMessage,
    required this.bgChip,
    this.hoverTint,
    required this.bgMenu,
    required this.bgToolbar,
    required this.bgEmbed,
    required this.bgEmbedForm,
    required this.bgPicker,
    required this.bgPickerNarrow,
    required this.bgPickerRail,
    required this.border,
    required this.borderCard,
    required this.borderSoft,
    required this.borderMuted,
    required this.borderMenu,
    required this.borderWindow,
    required this.borderMessageCard,
    required this.textPrimary,
    required this.textSecond,
    required this.textHint,
    required this.textDim,
    required this.textNavIdle,
    required this.accent,
    required this.accentDark,
  });

  GlitchPalette copyWith({
    Color? bg,
    Color? bgInput,
    Color? bgCard,
    Color? bgMessage,
    Color? bgChip,
    Color? hoverTint,
    Color? bgMenu,
    Color? bgToolbar,
    Color? bgEmbed,
    Color? bgEmbedForm,
    Color? bgPicker,
    Color? bgPickerNarrow,
    Color? bgPickerRail,
    Color? border,
    Color? borderCard,
    Color? borderSoft,
    Color? borderMuted,
    Color? borderMenu,
    Color? borderWindow,
    Color? borderMessageCard,
    Color? textPrimary,
    Color? textSecond,
    Color? textHint,
    Color? textDim,
    Color? textNavIdle,
    Color? accent,
    Color? accentDark,
  }) =>
      GlitchPalette(
        brightness: brightness,
        bg: bg ?? this.bg,
        bgInput: bgInput ?? this.bgInput,
        bgCard: bgCard ?? this.bgCard,
        bgMessage: bgMessage ?? this.bgMessage,
        bgChip: bgChip ?? this.bgChip,
        hoverTint: hoverTint ?? this.hoverTint,
        bgMenu: bgMenu ?? this.bgMenu,
        bgToolbar: bgToolbar ?? this.bgToolbar,
        bgEmbed: bgEmbed ?? this.bgEmbed,
        bgEmbedForm: bgEmbedForm ?? this.bgEmbedForm,
        bgPicker: bgPicker ?? this.bgPicker,
        bgPickerNarrow: bgPickerNarrow ?? this.bgPickerNarrow,
        bgPickerRail: bgPickerRail ?? this.bgPickerRail,
        border: border ?? this.border,
        borderCard: borderCard ?? this.borderCard,
        borderSoft: borderSoft ?? this.borderSoft,
        borderMuted: borderMuted ?? this.borderMuted,
        borderMenu: borderMenu ?? this.borderMenu,
        borderWindow: borderWindow ?? this.borderWindow,
        borderMessageCard: borderMessageCard ?? this.borderMessageCard,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecond: textSecond ?? this.textSecond,
        textHint: textHint ?? this.textHint,
        textDim: textDim ?? this.textDim,
        textNavIdle: textNavIdle ?? this.textNavIdle,
        accent: accent ?? this.accent,
        accentDark: accentDark ?? this.accentDark,
      );

  static Color _darken(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness - 0.14).clamp(0.0, 1.0)).toColor();
  }

  factory GlitchPalette.dark(Color accent) => GlitchPalette(
    brightness: Brightness.dark,
    bg: const Color(0xFF151515),
    bgInput: const Color(0xFF212121),
    bgCard: const Color(0xFF1C1C1C),
    bgMessage: const Color(0xFF1E1E1E),
    bgChip: const Color(0xFF2E2E2E),
    bgMenu: const Color(0xFF2C2C2C),
    bgToolbar: const Color(0xFF282828),
    bgEmbed: const Color(0xFF202020),
    bgEmbedForm: const Color(0xFF282828),
    bgPicker: const Color(0xFF282828),
    bgPickerNarrow: const Color(0xFF262626),
    bgPickerRail: const Color(0xFF1E1E1E),
    border: const Color(0xFF2C2C2C),
    borderCard: const Color(0xFF262626),
    borderSoft: const Color(0xFF191919),
    borderWindow: const Color(0x1FFFFFFF), // белый 12%
    borderMessageCard: const Color(0x14FFFFFF), // белый 8%
    borderMuted: const Color(0xFF232323),
    borderMenu: const Color(0xFF424242),
    textPrimary: const Color(0xFFEDEDED),
    textSecond: const Color(0xFF8A8A8A),
    textHint: const Color(0xFF7A7A7A),
    textDim: const Color(0xFF9A9A9A),
    textNavIdle: const Color(0xFFA8A8A8),
    accent: accent,
    accentDark: _darken(accent),
  );

  factory GlitchPalette.light(Color accent) => GlitchPalette(
    brightness: Brightness.light,
    bg: const Color(0xFFFFFFFF),
    bgInput: const Color(0xFFF0F0F0),
    bgCard: const Color(0xFFF7F7F7),
    bgMessage: const Color(0xFFF0F0F0),
    bgChip: const Color(0xFFE4E4E4),
    bgMenu: const Color(0xFFFFFFFF),
    bgToolbar: const Color(0xFFFFFFFF),
    bgEmbed: const Color(0xFFF7F7F7),
    bgEmbedForm: const Color(0xFFFFFFFF),
    bgPicker: const Color(0xFFFFFFFF),
    bgPickerNarrow: const Color(0xFFFFFFFF),
    bgPickerRail: const Color(0xFFF0F0F0),
    border: const Color(0xFFE0E0E0),
    borderCard: const Color(0xFFE7E7E7),
    borderSoft: const Color(0xFFEDEDED),
    borderWindow: const Color(0x14000000), // чёрный 8%
    borderMessageCard: const Color(0x14000000), // чёрный 8% — в светлой как у окон
    borderMuted: const Color(0xFFE5E5E5),
    borderMenu: const Color(0xFFE0E0E0),
    textPrimary: const Color(0xFF1A1A1A),
    textSecond: const Color(0xFF6E6E6E),
    textHint: const Color(0xFF9A9A9A),
    textDim: const Color(0xFF7A7A7A),
    textNavIdle: const Color(0xFF6E6E6E),
    accent: accent,
    accentDark: _darken(accent),
  );

  factory GlitchPalette.onyx(Color accent) => GlitchPalette.dark(accent).copyWith(
    bg: const Color(0xFF090A0B),
    bgInput: const Color(0xFF17181B),
    bgCard: const Color(0xFF111214),
    bgMessage: const Color(0xFF141517),
    bgChip: const Color(0xFF27282C),
    bgMenu: const Color(0xFF232428),
    bgToolbar: const Color(0xFF1C1D20),
    bgEmbed: const Color(0xFF1A1B1E),
    bgEmbedForm: const Color(0xFF1D1E22),
    bgPicker: const Color(0xFF1D1E22),
    bgPickerNarrow: const Color(0xFF191A1D),
    bgPickerRail: const Color(0xFF141517),
    border: const Color(0xFF2D2F34),
    borderCard: const Color(0xFF25262B),
    borderSoft: const Color(0xFF16171A),
    borderMuted: const Color(0xFF212226),
    borderMenu: const Color(0xFF3A3C42),
  );
}
