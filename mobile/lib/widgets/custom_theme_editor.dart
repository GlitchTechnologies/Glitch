import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/adaptive_open.dart' show isWideLayout, kWideLayoutBreakpoint;
import '../core/l10n.dart';
import '../core/own_account_open.dart' show openMySettings;
import '../providers/theme_provider.dart';
import '../screens/user_settings_window.dart' show UserSettingsSection;
import '../services/auth_service.dart';
import '../services/desktop_popouts.dart';
import '../services/desktop_shell.dart' show DesktopPopout;
import '../theme/app_theme.dart';
import '../theme/custom_theme.dart';
import 'adaptive_sheet.dart';
import 'color_palette.dart';
import 'glitch_action_button.dart';
import 'glitch_segmented_control.dart';
import 'glitch_slider.dart';
import 'glitch_toast.dart';
import 'settings_page_parts.dart';
import 'settings_window.dart' show SettingsPageHeader;

bool _editorOpen = false;

enum _EditorExit { back }

enum _ApplyResult { applied, failed, cancelled }

final _dockedEditor = ValueNotifier<Widget?>(null);

class CustomThemeEditorFrame extends StatelessWidget {
  final Widget child;

  const CustomThemeEditorFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Widget?>(
        valueListenable: _dockedEditor,
        child: child,
        builder: (context, editor, app) => LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth;
            final full = editor != null && width < 660;
            final panelWidth = (width - kWideLayoutBreakpoint).clamp(300.0, 380.0).toDouble();
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  key: const ValueKey('workspace'),
                  right: editor == null || full ? 0 : panelWidth,
                  child: Offstage(
                    offstage: full,
                    child: ExcludeFocus(
                      excluding: full,
                      child: LayoutBuilder(
                        builder: (context, workspace) => MediaQuery(
                          data: MediaQuery.of(context).copyWith(size: workspace.biggest),
                          child: app!,
                        ),
                      ),
                    ),
                  ),
                ),
                if (editor != null)
                  Positioned(
                    key: const ValueKey('theme-editor'),
                    width: full ? width : panelWidth,
                    top: 0,
                    right: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(left: BorderSide(color: GlitchColors.borderWindow)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 1),
                        child: LayoutBuilder(
                          builder: (context, panel) => MediaQuery(
                            data: MediaQuery.of(context).copyWith(size: panel.biggest),
                            child: Overlay.wrap(child: editor),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      );
}

Future<void> openCustomThemeEditor(BuildContext context) async {
  final account = authService.currentUser?.id;
  if (_editorOpen || account == null) return;
  final navigator = Navigator.of(context, rootNavigator: true);
  final wide = isWideLayout(context);
  _EditorExit? exit;
  _editorOpen = true;
  try {
    if (wide && !await navigator.maybePop()) return;
    if (!navigator.mounted || authService.currentUser?.id != account) return;
    final initial = themeProvider.savedCustom ?? CustomTheme(
      light: themeProvider.isLight,
      colors: const [Color(0xFF00FFEB), Color(0xFF000000)],
      angle: 300,
      intensity: 100,
    );
    if (desktopPopouts.themeEditorAvailable) {
      exit = await _showDesktopEditor(navigator.context, account, initial);
    } else {
      themeProvider.showPreview(initial);
      final dock = wide ? Completer<_EditorExit?>() : null;
      void close([_EditorExit? result]) {
        if (dock == null) {
          navigator.pop(result);
        } else if (!dock.isCompleted) {
          dock.complete(result);
        }
      }

      Widget editor() => _ThemeEditor(
          initial: initial,
          onClose: dock == null ? null : close,
          onExit: close,
          onPreview: (draft) {
            if (authService.currentUser?.id == account) themeProvider.showPreview(draft);
          },
          onApply: (context, draft) async {
            final route = ModalRoute.of(context);
            bool stillOpen() => context.mounted &&
                (dock == null ? route?.isCurrent == true : !dock.isCompleted);
            final result = await _applyTheme(account, draft, stillOpen: stillOpen);
            if (!stillOpen()) return;
            if (result == _ApplyResult.applied) close();
            if (result == _ApplyResult.failed) GlitchToast.show(context, context.s.appearanceEditorSaveError);
          },
        );
      if (dock == null) {
        exit = await openAdaptiveWindow<_EditorExit>(
          navigator.context,
          wideBuilder: (_) => editor(),
          narrowBuilder: (_) => editor(),
        );
      } else {
        void accountChanged() {
          if (authService.currentUser?.id != account) close();
        }

        authService.currentUserListenable.addListener(accountChanged);
        _dockedEditor.value = CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
          child: Focus(autofocus: true, child: editor()),
        );
        try {
          exit = await dock.future;
        } finally {
          _dockedEditor.value = null;
          authService.currentUserListenable.removeListener(accountChanged);
        }
      }
    }
  } finally {
    themeProvider.showPreview(null);
    _editorOpen = false;
  }
  if (!navigator.mounted || authService.currentUser?.id != account) return;
  if (exit == _EditorExit.back && wide) {
    await openMySettings(navigator.context, section: UserSettingsSection.appearance);
  }
}

Future<_ApplyResult> _applyTheme(int account, CustomTheme draft, {
  required bool Function() stillOpen,
}) async {
  if (!stillOpen() || authService.currentUser?.id != account) return _ApplyResult.cancelled;
  final saved = await themeProvider.applyCustom(draft, account: account);
  return saved ? _ApplyResult.applied : _ApplyResult.failed;
}

Future<_EditorExit?> _showDesktopEditor(BuildContext context, int account, CustomTheme initial) async {
  const kind = DesktopPopout.themeEditor;
  final closed = Completer<void>();
  var draft = initial;
  _EditorExit? exit;
  Future<void>? pendingApply;
  void post({_ApplyResult? result}) => desktopPopouts.post(kind, {
        'draft': draft.toJson(),
        'applyFinished': result != null,
        'error': result == _ApplyResult.failed,
      });
  void accountChanged() {
    if (authService.currentUser?.id != account) {
      desktopPopouts.close(kind);
    }
  }

  final ready = desktopPopouts.readies.where((value) => value == kind).listen((_) {
    if (authService.currentUser?.id != account) return;
    themeProvider.showPreview(draft);
    post();
  });
  final closing = desktopPopouts.closings.where((value) => value == kind).listen((_) {
    if (!closed.isCompleted) closed.complete();
  });
  Future<void> apply() async {
    try {
      final result = await _applyTheme(
        account, draft,
        stillOpen: () => context.mounted && !closed.isCompleted,
      );
      if (closed.isCompleted) return;
      if (result == _ApplyResult.applied) {
        desktopPopouts.close(kind);
      } else {
        post(result: result);
      }
    } finally {
      pendingApply = null;
    }
  }

  final actions = desktopPopouts.themeEditorActions.listen((action) {
    if (pendingApply != null || exit != null || closed.isCompleted || authService.currentUser?.id != account || !context.mounted) return;
    final operation = action['operation'];
    if (operation == _EditorExit.back.name) {
      exit = _EditorExit.back;
      desktopPopouts.close(kind);
      return;
    }
    final next = CustomTheme.fromJson(action['draft']);
    if (next == null) return;
    switch (operation) {
      case 'preview':
        draft = next;
        themeProvider.showPreview(draft);
      case 'apply':
        draft = next;
        pendingApply = apply();
    }
  });
  authService.currentUserListenable.addListener(accountChanged);
  try {
    desktopPopouts.open(kind);
    await closed.future;
    await pendingApply;
    return exit;
  } finally {
    authService.currentUserListenable.removeListener(accountChanged);
    await Future.wait([ready.cancel(), closing.cancel(), actions.cancel()]);
  }
}

class DesktopThemeEditorView extends StatefulWidget {
  const DesktopThemeEditorView({super.key});

  @override
  State<DesktopThemeEditorView> createState() => _DesktopThemeEditorViewState();
}

class _DesktopThemeEditorViewState extends State<DesktopThemeEditorView> {
  late final StreamSubscription<Map<String, Object?>> _subscription;
  CustomTheme? _initial;
  Completer<void>? _applying;

  @override
  void initState() {
    super.initState();
    _subscription = desktopPopouts.bodies.listen((body) {
      final draft = CustomTheme.fromJson(body['draft']);
      if (draft == null || !mounted) return;
      setState(() {
        _initial ??= draft;
      });
      if (body['applyFinished'] == true) {
        _applying?.complete();
        _applying = null;
      }
      if (body['error'] == true) {
        GlitchToast.show(context, context.s.appearanceEditorSaveError);
      }
    });
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    _applying?.complete();
    super.dispose();
  }

  void _send(String operation, [CustomTheme? draft]) => desktopPopouts.sendThemeEditorAction({
        'operation': operation,
        if (draft != null) 'draft': draft.toJson(),
      });

  @override
  Widget build(BuildContext context) {
    final initial = _initial;
    if (initial == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return _ThemeEditor(
      initial: initial,
      onExit: (exit) => _send(exit.name),
      onPreview: (draft) => _send('preview', draft),
      onApply: (_, draft) {
        final applying = _applying = Completer<void>();
        _send('apply', draft);
        return applying.future;
      },
    );
  }
}

class _ThemeEditor extends StatefulWidget {
  final CustomTheme initial;
  final VoidCallback? onClose;
  final ValueChanged<_EditorExit> onExit;
  final ValueChanged<CustomTheme> onPreview;
  final Future<void> Function(BuildContext, CustomTheme) onApply;

  const _ThemeEditor({
    required this.initial,
    required this.onExit,
    required this.onPreview,
    required this.onApply,
    this.onClose,
  });

  @override
  State<_ThemeEditor> createState() => _ThemeEditorState();
}

class _ThemeEditorState extends State<_ThemeEditor> with ThemeAwareState<_ThemeEditor> {
  late CustomTheme _draft = widget.initial;
  int _selected = 0;
  int _paletteVersion = 0;
  bool _applying = false;

  void _change(CustomTheme next) {
    setState(() => _draft = next);
    widget.onPreview(next);
  }

  void _pick(Color color) {
    final colors = [..._draft.colors];
    colors[_selected] = color;
    _change(_draft.copyWith(colors: colors));
  }

  void _addColor() {
    final colors = [..._draft.colors, themeProvider.accent];
    _selected = colors.length - 1;
    _change(_draft.copyWith(colors: colors));
  }

  void _removeColor() {
    final colors = [..._draft.colors]..removeAt(_selected);
    if (_selected == colors.length) _selected--;
    _paletteVersion++;
    _change(_draft.copyWith(colors: colors));
  }

  Future<void> _apply() async {
    if (_applying) return;
    setState(() => _applying = true);
    try {
      await widget.onApply(context, _draft);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final title = s.appearanceCustomThemeTitle;
    final palette = _draft.palette(themeProvider.accent);
    final editor = Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (widget.onClose != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 60, 10),
                child: Align(alignment: Alignment.centerLeft, child: SettingsBlockTitle(title)),
              )
            else if (desktopPopouts.current == null)
              SettingsPageHeader(title: title),
            Expanded(
              child: IgnorePointer(
                ignoring: _applying,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GlitchSegmentedControl(
                        labels: [s.appearanceLight, s.appearanceDark],
                        selected: _draft.light ? 0 : 1,
                        onChanged: (index) => _change(_draft.copyWith(light: index == 0)),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 50,
                        child: LayoutBuilder(
                          builder: (context, constraints) => DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: _draft.background(palette, constraints.biggest),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(child: Text(s.appearanceEditorPreview, style: TextStyle(color: palette.textPrimary))),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SettingsBlockTitle(s.appearanceEditorColors),
                      DecoratedBox(
                        decoration: BoxDecoration(gradient: _draft.swatch, borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [for (var i = 0; i < _draft.colors.length; i++) _colorStop(i)],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      GlitchColorPalette(
                        key: ValueKey((_selected, _paletteVersion)),
                        initial: _draft.colors[_selected],
                        onChanged: _pick,
                        padding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          GlitchActionButton(
                            label: s.appearanceEditorAddColor,
                            compact: true,
                            soft: true,
                            onTap: _draft.colors.length < CustomTheme.maxColors ? _addColor : null,
                          ),
                          if (_draft.colors.length > 1)
                            GlitchActionButton(label: s.appearanceEditorRemoveColor, compact: true, soft: true, onTap: _removeColor),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_draft.colors.length > 1) ...[
                        Text('${s.appearanceEditorDirection} · ${_draft.angle}°', key: const ValueKey('direction-label')),
                        GlitchSlider(
                          key: const ValueKey('direction-slider'),
                          value: _draft.angle.toDouble(),
                          max: 360,
                          onChanged: (v) => _change(_draft.copyWith(angle: v.round())),
                        ),
                        const SizedBox(key: ValueKey('slider-gap'), height: 16),
                      ],
                      Text('${s.appearanceEditorIntensity} · ${_draft.intensity}%', key: const ValueKey('intensity-label')),
                      GlitchSlider(
                        key: const ValueKey('intensity-slider'),
                        value: _draft.intensity.toDouble(),
                        max: 100,
                        onChanged: (v) => _change(_draft.copyWith(intensity: v.round())),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: GlitchActionButton(
                      label: s.back,
                      soft: true,
                      onTap: _applying ? null : () => widget.onExit(_EditorExit.back),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlitchActionButton(
                      label: s.appearanceEditorApply,
                      height: 40,
                      brandAccent: true,
                      loading: _applying,
                      onTap: _apply,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    final onClose = widget.onClose;
    if (onClose == null) return editor;
    return Stack(children: [editor, AdaptiveWindowCloseButton(onPressed: onClose)]);
  }

  Widget _colorStop(int index) {
    final selected = _selected == index;
    final color = _draft.colors[index];
    return Semantics(
      label: '${context.s.appearanceEditorColors} ${index + 1}',
      selected: selected,
      button: true,
      child: InkWell(
        onTap: () => setState(() => _selected = index),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white, width: selected ? 3 : 1),
          ),
          child: selected
              ? Icon(Icons.check, size: 18, color: color.computeLuminance() > 0.18 ? Colors.black : Colors.white)
              : null,
        ),
      ),
    );
  }
}
