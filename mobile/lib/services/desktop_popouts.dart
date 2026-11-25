import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/glitch_palette.dart';
import 'desktop_shell.dart';

/// Нет программы или она старше версии 6 — [available] ложно, и вызывающий
/// показывает то же самое поверх приложения.
class DesktopPopouts {
  DesktopPopouts._();


  bool get available => desktopShell?.hasPopouts ?? false;

  bool get themeEditorAvailable => desktopShell?.hasThemeEditor ?? false;

  Stream<Map<String, Object?>> get themeEditorActions =>
      (desktopShell?.themeEditorActions ?? const Stream<String>.empty())
          .map(_decode)
          .where((data) => data != null)
          .cast<Map<String, Object?>>();

  void sendThemeEditorAction(Map<String, Object?> data) => desktopShell?.sendThemeEditorAction(jsonEncode(data));

  void open(DesktopPopout kind) => desktopShell?.openPopout(kind);

  void close(DesktopPopout kind) => desktopShell?.closePopout(kind);

  void post(DesktopPopout kind, Map<String, Object?> body) {
    desktopShell?.postToPopout(kind, jsonEncode({'look': _look(), 'body': body}));
  }

  Stream<DesktopPopout> get readies => desktopShell?.popoutReadies ?? const Stream.empty();

  Stream<DesktopPopout> get closings => desktopShell?.popoutClosings ?? const Stream.empty();

  Map<String, Object?> _look() => {
        'mode': (themeProvider.usesCustomTheme ? themeProvider.savedCustom?.base : null)?.id ?? themeProvider.preset.id,
        'accent': themeProvider.accent.value,
        'locale': localeProvider.locale.languageCode,
      };


  DesktopPopout? get current => desktopShell?.popout;

  void ready() => desktopShell?.popoutReady();

  Stream<Map<String, Object?>> get bodies =>
      (desktopShell?.popoutData ?? const Stream<String>.empty()).map(_unpack).where((b) => b != null).cast();

  Map<String, Object?>? _decode(String data) {
    final Object? raw;
    try {
      raw = jsonDecode(data);
    } on FormatException catch (e) {
      debugPrint('desktopPopouts: не JSON: $e');
      return null;
    }
    return raw is Map<String, Object?> ? raw : null;
  }

  Map<String, Object?>? _unpack(String data) {
    final raw = _decode(data);
    if (raw == null) return null;
    final look = raw['look'];
    if (look is Map) {
      final accent = look['accent'];
      themeProvider.follow(
        GlitchThemePreset.fromId(look['mode']),
        accent is int ? Color(accent) : themeProvider.accent,
      );
      final locale = look['locale'];
      if (locale is String && locale.isNotEmpty) localeProvider.follow(Locale(locale));
    }
    final body = raw['body'];
    return body is Map ? body.cast<String, Object?>() : null;
  }
}

final desktopPopouts = DesktopPopouts._();
