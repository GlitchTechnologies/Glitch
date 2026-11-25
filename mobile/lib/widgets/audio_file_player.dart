import 'dart:async';
import 'dart:math' as math;
import 'glitch_menu.dart';
import 'package:flutter/material.dart';
import '../core/l10n.dart';
import '../core/platform_info.dart';
import '../models/file_audio.dart';
import '../services/message_audio.dart';
import '../theme/app_theme.dart';
import 'glitch_icon_button.dart';
import 'glitch_slider.dart';

class AudioFilePlayer extends StatefulWidget {
  final String url;
  final FileAudio? audio;
  const AudioFilePlayer({super.key, required this.url, this.audio});

  @override
  State<AudioFilePlayer> createState() => _AudioFilePlayerState();
}

class _AudioFilePlayerState extends State<AudioFilePlayer> {
  late MessageAudioController _audio;
  double? _seeking;
  bool _volumeOpen = false;
  bool _overVolume = false;
  bool _overPopup = false;
  bool _draggingVolume = false;
  Timer? _volumeTimer;
  Future<void> Function()? _closeVolume;

  void _scheduleVolume() {
    _volumeTimer?.cancel();
    if (!_overVolume && !_overPopup && !_draggingVolume && _volumeOpen) {
      _volumeTimer = Timer(const Duration(milliseconds: 180), _hideVolume);
    }
  }

  void _hideVolume() {
    _volumeTimer?.cancel();
    final close = _closeVolume;
    if (close != null) unawaited(close());
  }

  void _showVolume(BuildContext anchor) {
    _volumeTimer?.cancel();
    if (_volumeOpen || !mounted) return;
    _volumeOpen = true;
    final done = openGlitchPopup(anchor, width: 32, centered: true,
      preferAbove: true, tapOutsideCloses: false,
      builder: (close, maxHeight) {
        _closeVolume = close;
        if (!mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) { unawaited(close()); });
          return const SizedBox.shrink();
        }
        _scheduleVolume();
        return MouseRegion(
          onEnter: (_) { _overPopup = true; _scheduleVolume(); },
          onExit: (_) { _overPopup = false; _scheduleVolume(); },
          child: GlitchPopupCard(maxHeight: maxHeight,
            child: SizedBox(height: math.min(104.0, maxHeight),
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 6),
                child: RotatedBox(quarterTurns: 3,
                  child: AnimatedBuilder(animation: _audio, builder: (context, _) => GlitchSlider(
                    value: _audio.volume / 100,
                    onChangeStart: (_) { _draggingVolume = true; _scheduleVolume(); },
                    onChanged: (v) { _audio.setVolume(v * 100); },
                    onChangeEnd: (_) { _draggingVolume = false; _scheduleVolume(); },
                  )),
                ),
              ),
            ),
          ),
        );
      });
    unawaited(done.whenComplete(() {
      _volumeTimer?.cancel();
      _closeVolume = null;
      _volumeOpen = false;
      _overPopup = false;
      _draggingVolume = false;
    }));
  }
  double _lastVolume = 100;

  void _attach() {
    _audio = MessageAudioController(widget.url,
      duration: Duration(milliseconds: ((widget.audio?.duration ?? 0) * 1000).round()));
    _audio.addListener(_changed);
  }
  void _changed() { if (mounted) setState(() {}); }

  @override
  void initState() { super.initState(); _attach(); }

  @override
  void didUpdateWidget(covariant AudioFilePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url != oldWidget.url) {
      _hideVolume();
      _audio.removeListener(_changed);
      _audio.dispose();
      _seeking = null;
      _attach();
    } else if (_audio.duration == Duration.zero && widget.audio != null) {
      _audio.duration = Duration(milliseconds: (widget.audio!.duration * 1000).round());
    }
  }

  @override
  void dispose() {
    _hideVolume();
    _audio.removeListener(_changed);
    _audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = _audio.duration.inMilliseconds;
    final position = _seeking ?? (total > 0 ? _audio.position.inMilliseconds / total : 0);
    final shownPosition = _seeking == null ? _audio.position : Duration(milliseconds: (_seeking! * total).round());
    final busy = _audio.loading;
    final time = total > 0 ? audioTime(_audio.duration) : '—:——';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(children: [
          if (busy)
            const SizedBox(width: 32, height: 32, child: Padding(
              padding: EdgeInsets.all(7), child: CircularProgressIndicator(strokeWidth: 2)))
          else
            Semantics(button: true, label: _audio.playing ? context.s.audioPause : context.s.audioPlay,
              child: GlitchIconButton.panel(
                icon: Icon(_audio.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                onTap: () { _audio.toggle(); },
              )),
          const SizedBox(width: 6),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text('${audioTime(shownPosition)} / $time', maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: GlitchColors.textSecond))),
              if (_audio.buffering) const Padding(padding: EdgeInsets.only(left: 6),
                child: SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5))),
            ]),
            SizedBox(height: 24, child: GlitchSlider(
              value: position.clamp(0.0, 1.0).toDouble(),
              onChanged: total > 0 && _audio.opened && !_audio.loading && !_audio.failed
                  ? (v) => setState(() => _seeking = v) : null,
              onChangeEnd: (v) {
                _audio.seek(Duration(milliseconds: (v * total).round()));
                setState(() => _seeking = null);
              },
            )),
          ])),
          if (hasPointerInput) ...[
            const SizedBox(width: 6),
            Builder(builder: (anchor) => Semantics(button: true, label: context.s.audioVolume,
              child: GlitchIconButton.panel(
                icon: Icon(_audio.volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded),
                onHoverChanged: (over) {
                  _overVolume = over;
                  if (over) _showVolume(anchor);
                  _scheduleVolume();
                },
                onTap: () {
                  if (_audio.volume > 0) { _lastVolume = _audio.volume; _audio.setVolume(0); }
                  else { _audio.setVolume(_lastVolume); }
                },
              ))),
          ],
        ]),
        if (_audio.failed)
          Padding(padding: const EdgeInsets.only(top: 4),
            child: Text(context.s.audioPlaybackError,
              style: TextStyle(fontSize: 12, color: GlitchColors.textPrimary))),
      ],
    );
  }
}
