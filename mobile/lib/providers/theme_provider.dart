import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/custom_theme.dart';
import '../theme/glitch_palette.dart';

class ThemeProvider extends ChangeNotifier {
  static const defaultAccent = Color(0xFF2FAE9A);
  static const _themeKey = 'theme_mode';
  static const _accentKey = 'accent_color';

  GlitchThemePreset _preset = GlitchThemePreset.dark;
  Color _accent = defaultAccent;
  GlitchThemePreset _renderedPreset = GlitchThemePreset.dark;
  bool _renderedCustom = false;
  late GlitchPalette _savedPalette = _preset.palette(_accent);
  late GlitchPalette _palette = _savedPalette;
  Future<void> _pendingSave = Future<void>.value();

  SharedPreferences? _prefs;
  int? _account;
  bool _customSelected = false;
  int _selectionRevision = 0;
  CustomTheme? _savedCustom;
  CustomTheme? _preview;
  final _custom = ValueNotifier<CustomTheme?>(null);

  GlitchThemePreset get preset => _preset;
  Color get accent => _accent;
  GlitchPalette get palette => _palette;
  GlitchPalette get savedPalette => _savedPalette;
  bool get isLight => _palette.brightness == Brightness.light;
  bool get usesCustomTheme => _account != null && _customSelected;
  CustomTheme? get savedCustom => _savedCustom;
  ValueListenable<CustomTheme?> get custom => _custom;

  bool _apply(GlitchThemePreset preset, Color accent) {
    if (_preset == preset && _accent == accent) return false;
    _preset = preset;
    _accent = accent;
    return true;
  }

  void _refresh({bool savedChanged = false}) {
    final saved = usesCustomTheme ? _savedCustom : null;
    final current = _preview ?? saved;
    final preset = current?.base ?? _preset;
    if (savedChanged) _savedPalette = saved?.palette(_accent) ?? _preset.palette(_accent);
    final rebuild = savedChanged || _renderedPreset != preset || _renderedCustom != (current != null);
    if (rebuild) {
      _renderedPreset = preset;
      _renderedCustom = current != null;
      _palette = _preview?.palette(_accent) ?? _savedPalette;
    }
    _custom.value = current;
    if (rebuild) notifyListeners();
  }

  void bindAccount(int? account) {
    if (_account == account) return;
    _selectionRevision++;
    _account = account;
    _preview = null;
    final saved = account == null ? null : _readCustom(_prefs?.get('custom_theme_$account'));
    _savedCustom = saved?.theme;
    _customSelected = saved?.active == true;
    _refresh(savedChanged: true);
  }

  void showPreview(CustomTheme? theme) {
    _preview = theme;
    _refresh();
  }

  Future<bool> applyCustom(CustomTheme theme, {required int account}) async {
    if (_account != account) return false;
    final revision = ++_selectionRevision;
    bool current() => _selectionRevision == revision && _account == account;
    final saved = await _save((prefs) async {
      if (!current()) return false;
      return _writeCustom(prefs, account, theme, active: true);
    });
    if (!saved || !current()) return false;
    _savedCustom = theme;
    _customSelected = true;
    _preview = null;
    _refresh(savedChanged: true);
    return true;
  }

  Future<bool> _writeCustom(SharedPreferences prefs, int account, CustomTheme theme, {required bool active}) =>
      prefs.setString('custom_theme_$account', jsonEncode({'active': active, 'theme': theme.toJson()}));

  Future<bool> _deactivateSavedCustom(int account) => _save((prefs) async {
    final saved = _readCustom(prefs.get('custom_theme_$account'));
    return saved == null || !saved.active || await _writeCustom(prefs, account, saved.theme, active: false);
  });

  ({CustomTheme theme, bool active})? _readCustom(Object? raw) {
    if (raw is! String) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final theme = CustomTheme.fromJson(decoded['theme']);
      return theme == null ? null : (theme: theme, active: decoded['active'] == true);
    } on FormatException catch (e) {
      debugPrint('ThemeProvider: неверный формат сохранённой темы: $e');
      return null;
    }
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      final accentValue = prefs.get(_accentKey);
      follow(
        GlitchThemePreset.fromId(prefs.get(_themeKey)),
        accentValue is int ? Color(accentValue) : _accent,
      );
    } catch (e) {
      debugPrint('ThemeProvider.load: $e');
    }
  }

  Future<void> setPreset(GlitchThemePreset preset) async {
    final changed = _apply(preset, _accent);
    if (!changed && !_customSelected && _preview == null) return;
    _selectionRevision++;
    final account = _account;
    _customSelected = false;
    _preview = null;
    final saves = [
      _save((prefs) => prefs.setString(_themeKey, preset.id)),
      if (account != null) _deactivateSavedCustom(account),
    ];
    _refresh(savedChanged: true);
    await Future.wait(saves);
  }

  void follow(GlitchThemePreset preset, Color accent) {
    if (_apply(preset, accent)) _refresh(savedChanged: true);
  }

  Future<void> setAccent(Color color) async {
    if (!_apply(_preset, color)) return;
    final saved = _save((prefs) => prefs.setInt(_accentKey, color.value));
    _refresh(savedChanged: true);
    await saved;
  }

  Future<bool> _save(Future<bool> Function(SharedPreferences) write) {
    final saved = _pendingSave.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final written = await write(prefs);
        if (!written) debugPrint('ThemeProvider: настройка не сохранена');
        return written;
      } catch (e) {
        debugPrint('ThemeProvider.save: $e');
        return false;
      }
    });
    _pendingSave = saved.then<void>((_) {});
    return saved;
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }
}

final themeProvider = ThemeProvider();

mixin ThemeAwareState<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    themeProvider.addListener(_onGlitchThemeChanged);
  }

  @override
  void dispose() {
    themeProvider.removeListener(_onGlitchThemeChanged);
    super.dispose();
  }

  void _onGlitchThemeChanged() {
    if (mounted) setState(() {});
  }
}
