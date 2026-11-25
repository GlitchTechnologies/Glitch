import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/call_video_quality.dart';
import '../core/platform_info.dart';
import '../services/desktop_shell.dart';
import '../services/screen_share_quality.dart';
import '../theme/app_theme.dart';
import '../theme/glitch_icons.dart';
import 'adaptive_sheet.dart';
import 'glitch_bar_buttons.dart';
import 'glitch_cascade_menu.dart';
import 'glitch_menu.dart';
import 'glitch_action_button.dart';
import 'glitch_segmented_control.dart';
import 'glitch_switch.dart';
import 'glitch_toast.dart';

Future<bool> pickScreenSource(BuildContext context) async {
  final shell = desktopShell;
  if (shell == null) return false;
  final picked = await openAdaptiveWindow<bool>(
    context,
    wideSize: const Size(760, 600),
    wideBuilder: (_) => _ScreenSourcePicker(shell: shell),
    narrowBuilder: (_) => Scaffold(
      backgroundColor: GlitchColors.bg,
      body: SafeArea(child: _ScreenSourcePicker(shell: shell)),
    ),
  );
  return picked == true;
}

const _kRefreshEvery = Duration(seconds: 2);

class _ScreenSourcePicker extends StatefulWidget {
  final DesktopShell shell;

  const _ScreenSourcePicker({required this.shell});

  @override
  State<_ScreenSourcePicker> createState() => _ScreenSourcePickerState();
}

class _ScreenSourcePickerState extends State<_ScreenSourcePicker> {
  List<ScreenSource>? _sources;
  bool _failed = false;

  int _tab = 0;
  String? _selectedId;

  bool _oldWindows = false;
  bool _starting = false;

  final Map<String, Uint8List> _images = {};

  Timer? _timer;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(isWindowsBefore11.then((old) {
      if (old && mounted) setState(() => _oldWindows = true);
    }));
    // Снимается в dispose — на любом пути закрытия окна.
    _timer = Timer.periodic(_kRefreshEvery, (_) => unawaited(_load()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return; // предыдущий запрос ещё не вернулся
    _loading = true;
    try {
      final list = await widget.shell.listScreenSources();
      if (!mounted) return;
      final alive = <String>{};
      for (final source in list) {
        for (final url in [source.thumbnail, source.icon]) {
          if (url == null) continue;
          alive.add(url);
          _images.putIfAbsent(url, () => _decode(url));
        }
      }
      _images.removeWhere((url, _) => !alive.contains(url));
      setState(() {
        _sources = list;
        _failed = false;
        if (_selectedId != null && !list.any((source) => source.id == _selectedId)) _selectedId = null;
      });
    } catch (_) {
      if (mounted && _sources == null) setState(() => _failed = true);
    } finally {
      _loading = false;
    }
  }

  static Uint8List _decode(String dataUrl) {
    final comma = dataUrl.indexOf(',');
    return base64Decode(comma < 0 ? dataUrl : dataUrl.substring(comma + 1));
  }

  List<ScreenSource> get _shown =>
      (_sources ?? const []).where((source) => source.isScreen == (_tab == 1)).toList();

  Future<void> _start() async {
    final id = _selectedId;
    if (id == null || _starting) return;
    setState(() => _starting = true);
    try {
      final ok = await widget.shell.chooseScreenSource(id, withAudio: screenShareSound.value);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(true);
        return;
      }
      GlitchToast.show(context, context.s.screenShareSourceGone);
      setState(() => _selectedId = null);
      unawaited(_load());
    } catch (_) {
      if (mounted) GlitchToast.show(context, context.s.screenShareListFailed);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 40),
                child: Text(
                  s.screenShareTitle,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  SizedBox(
                    width: 300,
                    child: GlitchSegmentedControl(
                      labels: [s.screenShareTabApps, s.screenShareTabScreens],
                      selected: _tab,
                      onChanged: (i) => setState(() => _tab = i),
                    ),
                  ),
                  const Spacer(),
                  _QualityButton(oldWindows: _oldWindows),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(child: _grid(context)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GlitchPlainButton(label: s.cancel, onTap: () => Navigator.of(context).pop(false)),
                  const SizedBox(width: 8),
                  GlitchFilledButton(
                    label: s.screenShareStart,
                    loading: _starting,
                    onTap: _selectedId == null ? null : _start,
                  ),
                ],
              ),
            ],
          ),
        ),
        AdaptiveWindowCloseButton(onPressed: () => Navigator.of(context).pop(false)),
      ],
    );
  }

  Widget _grid(BuildContext context) {
    final s = context.s;
    if (_sources == null) {
      return Center(
        child: _failed
            ? Text(s.screenShareListFailed, style: TextStyle(color: GlitchColors.textPrimary, fontSize: 14))
            : CircularProgressIndicator(color: GlitchColors.accentBlue, strokeWidth: 2),
      );
    }
    final shown = _shown;
    if (shown.isEmpty) {
      return Center(
        child: Text(s.screenShareNoWindows, style: TextStyle(color: GlitchColors.textPrimary, fontSize: 14)),
      );
    }
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 240,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.35,
      ),
      itemCount: shown.length,
      itemBuilder: (context, i) {
        final source = shown[i];
        return _SourceTile(
          name: source.isScreen ? s.screenShareScreenN(i + 1) : source.name,
          thumbnail: source.thumbnail == null ? null : _images[source.thumbnail!],
          icon: source.icon == null ? null : _images[source.icon!],
          selected: source.id == _selectedId,
          onTap: () => setState(() => _selectedId = source.id),
        );
      },
    );
  }
}

class _QualityButton extends StatelessWidget {
  final bool oldWindows;

  const _QualityButton({required this.oldWindows});

  static const double _mainWidth = 260;
  static const double _listWidth = 180;

  static const double _size = 40;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: _size,
        child: Builder(
          builder: (anchor) => GlitchActionButton(
            soft: true,
            icon: GlitchIcons.settings,
            onTap: () => unawaited(openGlitchPopup(
              anchor,
              width: GlitchCascadeMenu.popupWidth(mainWidth: _mainWidth, listWidth: _listWidth),
              builder: (close, maxHeight) => ListenableBuilder(
                listenable: Listenable.merge([screenShareQuality, screenShareSound]),
                builder: (context, _) => _menu(context, screenShareQuality.value, close, maxHeight),
              ),
            )),
          ),
        ),
      );

  Widget _menu(BuildContext context, ScreenShareQuality q, Future<void> Function() close, double maxHeight) {
    final s = context.s;
    String resolution(ScreenResolution r) => switch (r) {
          ScreenResolution.p720 => '720p',
          ScreenResolution.p1080 => '1080p',
          ScreenResolution.p1440 => '1440p',
          ScreenResolution.source => s.screenShareResolutionSource,
        };
    return GlitchCascadeMenu(
      close: close,
      maxHeight: maxHeight,
      mainWidth: _mainWidth,
      listWidth: _listWidth,
      listOnLeft: true,
      entries: [
        GlitchCascadeEntry(
          title: s.screenShareResolution,
          value: resolution(q.resolution),
          options: [
            for (final r in ScreenShareQuality.resolutions)
              GlitchCascadeOption(
                label: resolution(r),
                selected: r == q.resolution,
                onSelect: () => unawaited(screenShareQuality.choose(q.copyWith(resolution: r))),
              ),
          ],
        ),
        GlitchCascadeEntry(
          title: s.screenShareFrameRate,
          value: s.screenShareFps(q.fps),
          options: [
            for (final fps in ScreenShareQuality.fpsChoices)
              GlitchCascadeOption(
                label: s.screenShareFps(fps),
                selected: fps == q.fps,
                onSelect: () => unawaited(screenShareQuality.choose(q.copyWith(fps: fps))),
              ),
          ],
        ),
      ],
      footer: [
        GlitchSwitchRow(
          label: s.screenShareSound,
          description: oldWindows ? s.screenShareSoundHintWin10 : s.screenShareSoundHint,
          value: screenShareSound.value,
          onChanged: (on) => unawaited(screenShareSound.choose(on)),
          border: false,
          padding: const EdgeInsets.fromLTRB(16, 6, 12, 8),
        ),
      ],
    );
  }
}

class _SourceTile extends StatelessWidget {
  final String name;
  final Uint8List? thumbnail;
  final Uint8List? icon;
  final bool selected;
  final VoidCallback onTap;

  const _SourceTile({
    required this.name,
    required this.thumbnail,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final thumb = thumbnail;
    final ic = icon;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  decoration: BoxDecoration(
                    color: GlitchColors.bgCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected ? GlitchColors.accentBlue : GlitchColors.border,
                      width: 2,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: thumb == null
                      ? Center(child: Icon(Icons.web_asset_rounded, color: GlitchColors.textHint, size: 32))
                      : Image.memory(thumb, fit: BoxFit.contain, gaplessPlayback: true),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (ic != null) ...[
                    Image.memory(ic, width: 16, height: 16, gaplessPlayback: true),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        color: GlitchColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
