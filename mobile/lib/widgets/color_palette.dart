import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/avatar_color.dart';
import '../core/preset_colors.dart';
import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';
import 'glitch_form_field.dart';
import 'glitch_menu.dart';
import 'glitch_pressable.dart';

/// Открывается попапом от любой кнопки-образца ([openColorPalette]) и
/// сообщает о КАЖДОМ изменении сразу, пока человек тянет ползунок: форма
/// вокруг живая (шапка редактора роли перекрашивается на глазах), а «Сохранить»
/// она копит сама. Своих кнопок «Применить» у палитры нет.
class GlitchColorPalette extends StatefulWidget {
  final Color initial;
  final ValueChanged<Color> onChanged;
  final EdgeInsetsGeometry padding;

  const GlitchColorPalette({
    super.key,
    required this.initial,
    required this.onChanged,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  State<GlitchColorPalette> createState() => _GlitchColorPaletteState();
}

class _GlitchColorPaletteState extends State<GlitchColorPalette> {
  static const double _boxHeight = 150;
  static const double _hueHeight = 14;

  late HSVColor _hsv;
  final _hex = TextEditingController();

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
    _hex.text = _hexOf(_hsv.toColor());
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  static String _hexOf(Color c) => (avatarColorToJson(c) ?? '#000000').substring(1);

  void _drag(HSVColor next) {
    setState(() => _hsv = next);
    final color = next.toColor();
    _hex.text = _hexOf(color);
    widget.onChanged(color);
  }

  void _typed(String raw) {
    if (raw.length != 6) return;
    final value = int.tryParse(raw, radix: 16);
    if (value == null) return;
    final color = Color(0xFF000000 | value);
    var next = HSVColor.fromColor(color);
    if (next.saturation < 0.01 || next.value < 0.01) next = next.withHue(_hsv.hue);
    setState(() => _hsv = next);
    widget.onChanged(color);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _saturationValueBox(),
          const SizedBox(height: 12),
          _hueBar(),
          const SizedBox(height: 12),
          GlitchFormField(
            controller: _hex,
            maxLength: 6,
            prefixText: '# ',
            placeholder: '3498db',
            onChanged: _typed,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]'))],
          ),
        ],
      ),
    );
  }

  Widget _saturationValueBox() {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      void at(Offset p) {
        final s = (p.dx / width).clamp(0.0, 1.0);
        final v = 1 - (p.dy / _boxHeight).clamp(0.0, 1.0);
        _drag(_hsv.withSaturation(s).withValue(v));
      }

      return ClickableCursor(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) => at(d.localPosition),
          onPanUpdate: (d) => at(d.localPosition),
          child: SizedBox(
            width: width,
            height: _boxHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor()),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [Colors.white, Color(0x00FFFFFF)],
                            ),
                          ),
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0x00000000), Colors.black],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: _hsv.saturation * width - _kThumb / 2,
                  top: (1 - _hsv.value) * _boxHeight - _kThumb / 2,
                  child: _thumb(_hsv.toColor()),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _hueBar() {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      void at(Offset p) => _drag(_hsv.withHue((p.dx / width).clamp(0.0, 1.0) * 360));

      return ClickableCursor(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) => at(d.localPosition),
          onPanUpdate: (d) => at(d.localPosition),
          child: SizedBox(
            width: width,
            height: _kThumb,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(_hueHeight / 2),
                  child: Container(
                    height: _hueHeight,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          for (var h = 0; h <= 360; h += 60)
                            HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor(),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: (_hsv.hue / 360) * width - _kThumb / 2,
                  child: _thumb(HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor()),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  static const double _kThumb = 18;

  Widget _thumb(Color fill) => IgnorePointer(
        child: Container(
          width: _kThumb,
          height: _kThumb,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 4)],
          ),
        ),
      );
}

void openColorPalette(
  BuildContext anchorContext, {
  required Color initial,
  required ValueChanged<Color> onChanged,
}) {
  openGlitchPopup(
    anchorContext,
    growRight: true,
    width: _kPaletteWidth,
    builder: (_, maxHeight) => GlitchPopupCard(
      maxHeight: maxHeight,
      child: GlitchColorPalette(initial: initial, onChanged: onChanged),
    ),
  );
}

const double _kPaletteWidth = 260;

/// Готовые цвета — общий список приложения `kPresetColors`: тот же набор, что
/// у акцентного цвета в «Внешнем виде» (предложил владелец, 2026-09-23).
/// Своего набора у мест нет, иначе приложение показывало бы разные цвета
/// в разных местах.
class GlitchColorChoice extends StatelessWidget {
  final String? value;
  final bool enabled;
  final ValueChanged<String?> onPick;

  const GlitchColorChoice({required this.value, required this.enabled, required this.onPick});

  static final List<String> _presets = [for (final c in kPresetColors) avatarColorToJson(c)!];

  bool get _isPreset => value != null && _presets.contains(value!.toLowerCase());
  bool get _isCustom => value != null && !_isPreset;

  static const int _cols = 8;
  static const double _gap = 10;

  static const double _bigWidth = 84;
  static const double _sectionGap = 16;

  static const double _minDot = 26;
  static const double _maxDot = 38;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final free = constraints.maxWidth - 2 * _bigWidth - _gap - _sectionGap;
      final dot = ((free - 1 - (_cols - 1) * _gap) / _cols).clamp(0.0, _maxDot);
      final wide = dot >= _minDot;

      final none = _noneSwatch();
      final custom = _customSwatch();

      if (wide) {
        final height = 2 * dot + _gap;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: _bigWidth, height: height, child: none),
            const SizedBox(width: _gap),
            SizedBox(width: _bigWidth, height: height, child: custom),
            const SizedBox(width: _sectionGap),
            Expanded(child: _grid(dot)),
          ],
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 52,
            child: Row(
              children: [
                Expanded(child: none),
                const SizedBox(width: _gap),
                Expanded(child: custom),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: _gap,
            runSpacing: _gap,
            children: [for (final c in kPresetColors) _dot(c, 34)],
          ),
        ],
      );
    });
  }

  Widget _grid(double dot) {
    final rows = <List<Color>>[
      kPresetColors.sublist(0, _cols),
      kPresetColors.sublist(_cols),
    ];
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: _gap),
          Row(
            children: [
              for (var j = 0; j < _cols; j++) ...[
                if (j > 0) const SizedBox(width: _gap),
                j < rows[i].length ? _dot(rows[i][j], dot) : SizedBox(width: dot, height: dot),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _noneSwatch() => _bigSwatch(
        fill: GlitchColors.bgInput,
        selected: value == null,
        onTap: enabled ? () => onPick(null) : null,
        child: Icon(Icons.not_interested_rounded, size: 22, color: GlitchColors.textSecond),
      );

  Widget _customSwatch() {
    return Builder(
      builder: (btnContext) => _bigSwatch(
        fill: _isCustom ? parseAvatarColor(value) : GlitchColors.bgInput,
        selected: _isCustom,
        onTap: enabled
            ? () => openColorPalette(
                  btnContext,
                  initial: parseAvatarColor(value) ?? themeProvider.accent,
                  onChanged: (c) => onPick(avatarColorToJson(c)),
                )
            : null,
        alignEnd: true,
        child: Icon(
          Icons.edit_rounded,
          size: 16,
          color: _isCustom ? Colors.white : GlitchColors.textPrimary,
        ),
      ),
    );
  }

  Widget _bigSwatch({
    required Color? fill,
    required bool selected,
    required VoidCallback? onTap,
    required Widget child,
    bool alignEnd = false,
  }) {
    return ClickableCursor(
      enabled: onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.5 : 1,
          child: Container(
            padding: alignEnd ? const EdgeInsets.fromLTRB(0, 8, 8, 0) : null,
            alignment: alignEnd ? Alignment.topRight : Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? GlitchColors.textPrimary : GlitchColors.borderSoft,
                width: selected ? 2 : 1,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _dot(Color color, double size) {
    final selected = value?.toLowerCase() == avatarColorToJson(color);
    return ClickableCursor(
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onPick(avatarColorToJson(color)) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: selected
                ? Icon(Icons.check_rounded, size: size * 0.5, color: Colors.white)
                : null,
          ),
        ),
      ),
    );
  }
}
