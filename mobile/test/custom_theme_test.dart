import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glitch/providers/theme_provider.dart';
import 'package:glitch/theme/custom_theme.dart';
import 'package:glitch/theme/glitch_ink.dart';
import 'package:glitch/theme/glitch_palette.dart';
import 'package:glitch/widgets/glitch_hover_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final draft = CustomTheme(light: false, colors: [Colors.red, Colors.blue], angle: 210, intensity: 65);

  setUp(() => SharedPreferences.setMockInitialValues({'theme_mode': 'onyx'}));

  test('отмена возвращает Оникс, правка цветов сохраняет палитру основы', () async {
    final provider = ThemeProvider();
    await provider.load();
    expect(provider.preset, GlitchThemePreset.onyx);
    final onyx = provider.palette;

    provider.showPreview(draft);
    final dark = provider.palette;
    expect(dark.bg, GlitchPalette.dark(provider.accent).bg);
    final next = draft.copyWith(angle: 90);
    provider.showPreview(next);
    expect(provider.palette, same(dark));
    expect(provider.custom.value, same(next));

    provider.showPreview(null);
    expect(provider.custom.value, isNull);
    expect(provider.palette, same(onyx));
    expect(provider.savedCustom, isNull);
  });

  test('тема применяется для текущего аккаунта и сохраняется отдельно от других', () async {
    final provider = ThemeProvider();
    await provider.load();
    expect(await provider.applyCustom(draft, account: 8), isFalse);
    provider.bindAccount(8);
    expect(await provider.applyCustom(draft, account: 9), isFalse);
    expect(await provider.applyCustom(draft, account: 8), isTrue);

    provider.bindAccount(9);
    expect(provider.custom.value, isNull);
    provider.bindAccount(8);
    expect(provider.custom.value?.toJson(), draft.toJson());

    await provider.setPreset(GlitchThemePreset.onyx);
    final reloaded = ThemeProvider();
    await reloaded.load();
    reloaded.bindAccount(8);
    expect(reloaded.custom.value, isNull);
    expect(reloaded.savedCustom?.toJson(), draft.toJson());
  });

  test('из сохранения принимаются только допустимые цвета и параметры', () {
    expect(CustomTheme.fromJson(draft.toJson())?.toJson(), draft.toJson());
    expect(CustomTheme.fromJson({...draft.toJson(), 'colors': <int>[]}), isNull);
    expect(CustomTheme.fromJson({...draft.toJson(), 'colors': [0x1000000]}), isNull);
    expect(CustomTheme.fromJson({...draft.toJson(), 'angle': -1}), isNull);
    expect(CustomTheme.fromJson({...draft.toJson(), 'intensity': 101}), isNull);
  });

  test('горизонтальный градиент доходит до краёв широкого окна', () {
    final theme = draft.copyWith(angle: 90);
    final gradient = theme.background(theme.palette(Colors.teal), const Size(1600, 500));
    expect((gradient.begin as Alignment).x, closeTo(1, 1e-9));
    expect((gradient.end as Alignment).x, closeTo(-1, 1e-9));
    expect((gradient.end as Alignment).y, closeTo(0, 1e-9));
  });

  test('интенсивность сохраняет оттенок и ограничивается контрастом', () {
    const teal = Color(0xFF008080);
    final theme = draft.copyWith(colors: [Colors.black, teal]);
    final palette = theme.palette(Colors.teal);
    const size = Size(1200, 800);
    final stops = theme.background(palette, size).colors;
    expect(stops.last.green, greaterThan(80));
    expect(stops.last.green, stops.last.blue);
    expect(theme.copyWith(intensity: 0).background(palette, size).colors, [palette.bg, palette.bg]);

    for (final light in [false, true]) {
      final extreme = theme.copyWith(light: light, colors: [Colors.white, Colors.black, Colors.blue], intensity: 100);
      final ink = extreme.palette(Colors.teal);
      for (final color in extreme.background(ink, size).colors) {
        final text = ink.textHint.computeLuminance() + 0.05;
        final surface = color.computeLuminance() + 0.05;
        expect(light ? surface / text : text / surface, greaterThanOrEqualTo(4.5));
      }
    }
  });

  testWidgets('подсветка меняет яркость градиента и сохраняет фон под строкой', (tester) async {
    late Color hover;
    late Color selected;
    late Color feed;
    Future<void> paint(GlitchPalette palette) => tester.pumpWidget(GlitchInk(
      palette: palette,
      child: Builder(builder: (context) {
        hover = GlitchHoverRow.highlight(context, active: true);
        selected = GlitchHoverRow.highlight(context, active: true, selected: true);
        feed = GlitchHoverRow.feedHighlight(context, active: true);
        return const SizedBox.shrink();
      }),
    ));

    for (final light in [false, true]) {
      final theme = draft.copyWith(light: light, colors: const [Color(0xFF008080)]);
      final palette = theme.palette(Colors.teal);
      await paint(palette);
      final background = theme.background(palette, const Size(1200, 800)).colors.first;
      final lit = Color.alphaBlend(feed, background);
      expect(lit.green, greaterThan(lit.red));
      expect(lit.computeLuminance(), light ? lessThan(background.computeLuminance()) : greaterThan(background.computeLuminance()));
      expect(feed.alpha, lessThan(hover.alpha));
      expect(hover.alpha, lessThan(selected.alpha));
      expect(selected.opacity, lessThan(0.11));
    }

    final call = GlitchPalette.dark(Colors.teal);
    await paint(call);
    expect(hover, call.bgChip.withOpacity(0.8));
  });

  test('выбор стандартной темы отменяет ожидающее применение градиента', () async {
    final provider = ThemeProvider();
    await provider.load();
    provider.bindAccount(8);

    final applying = provider.applyCustom(draft, account: 8);
    await provider.setPreset(GlitchThemePreset.light);
    expect(await applying, isFalse);
    expect(provider.usesCustomTheme, isFalse);
    expect(provider.isLight, isTrue);
  });
}
