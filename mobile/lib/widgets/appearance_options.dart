import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/preset_colors.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';
import '../theme/glitch_ink.dart';
import '../theme/glitch_palette.dart';
import 'glitch_action_button.dart';
import 'custom_theme_editor.dart' show openCustomThemeEditor;
import 'glitch_pressable.dart' show ClickableCursor;
import 'settings_parts.dart' show SettingsCard;

class AppearanceThemeOptions extends StatelessWidget {
  const AppearanceThemeOptions({super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 590) {
            return const Row(
              children: [
                _ThemePresetOptions(),
                SizedBox(width: 16),
                Expanded(child: _CustomThemeCard()),
              ],
            );
          }
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ThemePresetOptions(),
              SizedBox(height: 12),
              _CustomThemeCard(),
            ],
          );
        },
      );
}

class _ThemePresetOptions extends StatelessWidget {
  const _ThemePresetOptions();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: themeProvider,
        builder: (context, _) => Wrap(
          spacing: 6,
          runSpacing: 8,
          children: [
            for (final preset in GlitchThemePreset.values)
              _ThemeSwatch(
                preset: preset,
                label: switch (preset) {
                  GlitchThemePreset.light => context.s.appearanceLight,
                  GlitchThemePreset.dark => context.s.appearanceDark,
                  GlitchThemePreset.onyx => context.s.appearanceOnyx,
                },
              ),
          ],
        ),
      );
}

class _CustomThemeCard extends StatelessWidget {
  const _CustomThemeCard();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: themeProvider,
        builder: (context, _) {
          final s = context.s;
          final intro = Row(
            children: [
              const _CustomThemePreview(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.appearanceCustomThemeTitle,
                      style: TextStyle(
                        color: GlitchColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.appearanceCustomThemeDescription,
                      style: TextStyle(color: GlitchColors.textPrimary, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          );
          final action = GlitchActionButton(
            label: s.commonCreate,
            compact: true,
            onTap: () => openCustomThemeEditor(context),
          );
          return SettingsCard(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: LayoutBuilder(
                builder: (context, constraints) => constraints.maxWidth >= 300
                    ? Row(children: [Expanded(child: intro), const SizedBox(width: 12), action])
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [intro, const SizedBox(height: 12), action],
                      ),
              ),
            ),
          );
        },
      );
}

class _CustomThemePreview extends StatelessWidget {
  const _CustomThemePreview();

  @override
  Widget build(BuildContext context) {
    final ink = GlitchInk.of(context);
    return SizedBox(
      width: 58,
      height: 48,
      child: Stack(
        children: [
          Positioned.fill(
            right: 7,
            bottom: 5,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: GlitchColors.gradientAccent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: 0.34,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: ink.bgCard.withOpacity(0.46),
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(6)),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 26,
              height: 24,
              decoration: BoxDecoration(
                color: ink.bgMenu,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: ink.borderWindow),
              ),
              child: Icon(Icons.gradient, size: 16, color: ink.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class AccentColorOptions extends StatelessWidget {
  const AccentColorOptions({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: themeProvider,
        builder: (context, _) => SettingsCard(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Align(
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [for (final c in kPresetColors) _AccentSwatch(color: c)],
              ),
            ),
          ),
        ),
      );
}

class LanguageOptions extends StatelessWidget {
  const LanguageOptions({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: localeProvider,
        builder: (context, _) => SettingsCard(
          child: Column(
            children: [
              for (var i = 0; i < kAppLanguages.length; i++)
                _LanguageRow(language: kAppLanguages[i], border: i < kAppLanguages.length - 1),
            ],
          ),
        ),
      );
}

class _ThemeSwatch extends StatelessWidget {
  final GlitchThemePreset preset;
  final String label;

  const _ThemeSwatch({required this.preset, required this.label});

  @override
  Widget build(BuildContext context) {
    final selected = !themeProvider.usesCustomTheme && themeProvider.preset == preset;
    final accent = themeProvider.accent;
    final preview = preset.palette(accent).bg;
    const radius = BorderRadius.all(Radius.circular(9));
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: () => themeProvider.setPreset(preset),
          child: SizedBox(
            width: 76,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Ink(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: preview,
                          borderRadius: radius,
                          border: Border.all(
                            color: selected ? accent : GlitchColors.textSecond,
                            width: selected ? 3 : 1,
                          ),
                        ),
                      ),
                      if (selected)
                        Positioned(
                          top: -4,
                          right: -4,
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: Icon(
                                Icons.check_rounded,
                                size: 14,
                                color: ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
                                    ? Colors.white
                                    : Colors.black,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: GlitchColors.textPrimary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageRow extends StatelessWidget {
  final (String, String, String) language;
  final bool border;

  const _LanguageRow({required this.language, required this.border});

  @override
  Widget build(BuildContext context) {
    final (name, code, flag) = language;
    final selected = localeProvider.locale.languageCode == code;
    return InkWell(
      onTap: () => localeProvider.setLocale(Locale(code)),
      child: Container(
        decoration: border
            ? BoxDecoration(border: Border(bottom: BorderSide(color: GlitchColors.border)))
            : null,
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
        child: Row(
          children: [
            SizedBox(width: 30, height: 30, child: Center(child: Text(flag, style: const TextStyle(fontSize: 22)))),
            const SizedBox(width: 13),
            Expanded(
              child: Text(name,
                  style: TextStyle(
                    fontSize: 15.5,
                    color: GlitchColors.textPrimary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  )),
            ),
            if (selected) Icon(Icons.check_rounded, color: GlitchColors.accentBlue, size: 20),
          ],
        ),
      ),
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  final Color color;
  const _AccentSwatch({required this.color});

  @override
  Widget build(BuildContext context) {
    final selected = themeProvider.accent.value == color.value;
    return ClickableCursor(
      child: GestureDetector(
        onTap: () => themeProvider.setAccent(color),
        child: Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: selected ? Border.all(color: color, width: 2) : null,
          ),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            child: selected ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
          ),
        ),
      ),
    );
  }
}
