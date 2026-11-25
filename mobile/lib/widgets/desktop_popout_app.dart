import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:glitch/gen_l10n/app_localizations.dart';

import '../core/l10n.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';
import '../services/desktop_popouts.dart';
import '../services/desktop_shell.dart' show DesktopPopout;
import '../theme/app_theme.dart';
import '../theme/glitch_ink.dart';
import 'desktop_title_bar.dart';
import 'custom_theme_editor.dart' show DesktopThemeEditorView;
import 'voice_debug_window.dart';

Future<void> runDesktopPopout(DesktopPopout kind) async {
  await Future.wait([localeProvider.load(), themeProvider.load()]);
  runApp(_PopoutApp(kind: kind));
  WidgetsBinding.instance.addPostFrameCallback((_) => desktopPopouts.ready());
}

class _PopoutApp extends StatefulWidget {
  final DesktopPopout kind;

  const _PopoutApp({required this.kind});

  @override
  State<_PopoutApp> createState() => _PopoutAppState();
}

class _PopoutAppState extends State<_PopoutApp> {
  @override
  void initState() {
    super.initState();
    themeProvider.addListener(_rebuild);
    localeProvider.addListener(_rebuild);
  }

  @override
  void dispose() {
    themeProvider.removeListener(_rebuild);
    localeProvider.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        onGenerateTitle: (context) => switch (widget.kind) {
          DesktopPopout.voiceDebug => '${context.s.voiceDebug} — Glitch',
          DesktopPopout.themeEditor => context.s.appearanceCustomThemeTitle,
        },
        theme: AppTheme.current,
        themeAnimationDuration: Duration.zero,
        locale: localeProvider.locale,
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.supportedLocales,
        builder: (context, child) => GlitchInk(
          palette: themeProvider.palette,
          child: DesktopTitleBarFrame(showPlace: false, child: child ?? const SizedBox.shrink()),
        ),
        home: switch (widget.kind) {
          DesktopPopout.voiceDebug => const VoiceDebugPopoutView(),
          DesktopPopout.themeEditor => const DesktopThemeEditorView(),
        },
      );
}
