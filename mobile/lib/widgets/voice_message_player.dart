import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import '../services/message_audio.dart';
import '../core/l10n.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'glitch_toast.dart';
import 'glitch_icon_button.dart';

const kMaxTranscribeSeconds = 30;

const kVoiceWaveformBars = 30;

const _barWidth = 2.5;
const _barGap = 1.5;
const _barStep = _barWidth + _barGap;
const kVoiceWaveformWidth = kVoiceWaveformBars * _barStep;

({String url, double duration, List<double>? waveform}) _parseVoiceContent(String content) {
  if (content.startsWith('{')) {
    try {
      final m = jsonDecode(content) as Map<String, dynamic>;
      final rawWaveform = m['waveform'] as List?;
      return (
        url: m['url'] as String? ?? '',
        duration: (m['duration'] as num?)?.toDouble() ?? 0,
        waveform: rawWaveform?.map((e) => (e as num).toDouble()).toList(),
      );
    } catch (_) {}
  }
  return (url: content, duration: 0, waveform: null);
}

class VoiceMessagePlayer extends StatefulWidget {
  final String content; // JSON {"url":"..","duration":12.5}
  final String? transcript;
  final Future<String> Function()? onTranscribe;

  const VoiceMessagePlayer({
    super.key,
    required this.content,
    this.transcript,
    this.onTranscribe,
  });

  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer> {
  late MessageAudioController _audio;
  late ({String url, double duration, List<double>? waveform}) _parsed;
  bool get _playing => _audio.playing;
  bool get _loading => _audio.loading;
  Duration get _position => _audio.position;
  Duration get _total => _audio.duration;
  bool _reportedFailure = false;

  void _attachAudio() {
    _audio = MessageAudioController(_parsed.url,
      duration: Duration(milliseconds: (_parsed.duration * 1000).toInt()));
    _audio.addListener(_audioChanged);
    _reportedFailure = false;
  }

  void _audioChanged() {
    if (!mounted) return;
    if (_audio.failed && !_reportedFailure) {
      _reportedFailure = true;
      GlitchToast.show(context, context.s.audioPlaybackError);
    }
    if (!_audio.failed) _reportedFailure = false;
    setState(() {});
  }

  String? _transcript;
  bool _transcribing = false;
  bool _expanded = false;

  bool get _eligibleForTranscribe => _parsed.duration > 0 && _parsed.duration <= kMaxTranscribeSeconds;

  @override
  void initState() {
    super.initState();
    _transcript = widget.transcript;
    _parsed = _parseVoiceContent(widget.content);
    _attachAudio();
  }

  @override
  void didUpdateWidget(covariant VoiceMessagePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.content != oldWidget.content) {
      _audio.removeListener(_audioChanged);
      _audio.dispose();
      _parsed = _parseVoiceContent(widget.content);
      _attachAudio();
    }
    if (widget.transcript != oldWidget.transcript && _transcript == null) {
      _transcript = widget.transcript;
    }
  }

  @override
  void dispose() {
    _audio.removeListener(_audioChanged);
    _audio.dispose();
    super.dispose();
  }

  Future<void> _onTapTranscribe() async {
    if (_transcript != null) {
      setState(() => _expanded = !_expanded);
      return;
    }
    if (!_eligibleForTranscribe) {
      GlitchToast.show(
        context,
        'Расшифровка доступна только для голосовых до $kMaxTranscribeSeconds секунд',
        type: ToastType.info,
      );
      return;
    }
    if (_transcribing || widget.onTranscribe == null) return;
    setState(() => _transcribing = true);
    try {
      final text = await widget.onTranscribe!();
      if (!mounted) return;
      setState(() { _transcript = text; _expanded = true; _transcribing = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _transcribing = false);
        GlitchToast.show(context, errorMessage(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent    = GlitchColors.accentBlue;
    final secondary = GlitchColors.textSecond;
    final trackBg   = GlitchColors.border;

    final totalMs  = _total.inMilliseconds > 0 ? _total.inMilliseconds : 1;
    final progress = (_position.inMilliseconds / totalMs).clamp(0.0, 1.0);
    final timeLabel = (_playing || _position.inMilliseconds > 0) ? audioTime(_position) : audioTime(_total);

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 40, height: 40, child: _loading
          ? Padding(padding: const EdgeInsets.all(10),
              child: CircularProgressIndicator(strokeWidth: 2, color: accent))
          : Semantics(button: true, label: _playing ? context.s.audioPause : context.s.audioPlay,
            child: GlitchIconButton(
              size: 40, extent: 40,
              icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: accent),
              onTap: () { _audio.toggle(); },
            ))),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 28,
              width: kVoiceWaveformWidth,
              child: CustomPaint(
                painter: _WaveformPainter(
                  progress: progress,
                  activeColor: accent,
                  inactiveColor: trackBg,
                  seed: widget.content.hashCode,
                  realWaveform: _parsed.waveform,
                ),
                size: const Size(kVoiceWaveformWidth, 28),
              ),
            ),
            const SizedBox(height: 2),
            Text(timeLabel, style: TextStyle(fontSize: 11, color: secondary)),
          ],
        ),
        if (widget.onTranscribe != null) ...[
          const SizedBox(width: 10),
          _buildTranscribeButton(accent),
        ],
      ],
    );

    final showTranscript = _expanded && _transcript != null;

    // AnimatedSize — чтобы пузырь плавно увеличивался/уменьшался при
    // разворачивании расшифровки, а не менял высоту одним кадром.
    // alignment: topLeft — рост идёт вниз (текст добавляется под плеером),
    // а не расширяет пузырь одновременно во все стороны.
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: !showTranscript
          ? row
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                row,
                const SizedBox(height: 8),
                Text(
                  _transcript!,
                  textWidthBasis: TextWidthBasis.longestLine,
                  style: TextStyle(fontSize: 13.5, color: GlitchColors.textPrimary, height: 1.35),
                ),
              ],
            ),
    );
  }

  Widget _buildTranscribeButton(Color accent) {
    return GlitchIconButton(
      size: 36, extent: 36,
      onTap: _transcribing ? null : _onTapTranscribe,
      icon: _transcribing
          ? SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: accent))
          : Opacity(
              opacity: (_transcript != null || _eligibleForTranscribe) ? 1.0 : 0.35,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.arrow_forward_rounded, size: 11, color: accent),
                Text('T', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: accent)),
              ]),
            ),
    );
  }

}

class _WaveformPainter extends CustomPainter {
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final int seed;
  final List<double>? realWaveform;

  const _WaveformPainter({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.seed,
    this.realWaveform,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const bars = kVoiceWaveformBars;
    final real = realWaveform;
    final useReal = real != null && real.isNotEmpty;
    final rng = useReal ? null : Random(seed);

    final activePaint   = Paint()..color = activeColor;
    final inactivePaint = Paint()..color = inactiveColor;
    final offsetX = (size.width - bars * _barStep) / 2;

    for (int i = 0; i < bars; i++) {
      final level = useReal ? real[i.clamp(0, real.length - 1)].clamp(0.0, 1.0) : rng!.nextDouble();
      final h = (level * 0.7 + 0.2) * size.height;
      final x = offsetX + i * _barStep;
      final y = (size.height - h) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, _barWidth, h), const Radius.circular(1.5)),
        (i / bars) <= progress ? activePaint : inactivePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      old.activeColor != activeColor ||
      old.inactiveColor != inactiveColor ||
      // realWaveform — новый List создаётся заново в _parseVoiceContent
      // (didUpdateWidget/initState), никогда не мутируется на месте, поэтому
      // сравнение по ссылке корректно отличает "реально другие данные" —
      // без этого при подмене content (кэш → сервер) форма палочек могла
      // остаться от старых (например, псевдо-случайных) данных, пока
      // progress/activeColor не поменяются по какой-то другой причине.
      old.realWaveform != realWaveform;
}
