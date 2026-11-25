import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'local_image_web.dart' if (dart.library.io) 'local_image_native.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../core/media_content.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'chat_metrics.dart' show videoNotePlayingScale;
import 'glitch_pressable.dart' show ClickableCursor;

class VideoNoteView extends StatelessWidget {
  final ParsedVideoNote? note;
  final String? localThumbPath;
  final double size;
  final bool sending;
  final bool failed;
  /// 0..1; null — идёт сжатие, доля ещё неизвестна.
  final double? progress;

  const VideoNoteView({
    super.key,
    required this.note,
    required this.size,
    this.localThumbPath,
    this.sending = false,
    this.failed = false,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final ready = note != null && !sending && !failed;
    if (ready) {
      return VideoNotePlayer(note: note!, size: size);
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        ClipOval(
          child: SizedBox(
            width: size,
            height: size,
            child: localThumbPath != null
                ? localImage(localThumbPath!, width: size, height: size, fit: BoxFit.cover)
                : Container(
                    color: GlitchColors.bgMessage,
                    child: Icon(Icons.videocam_rounded, color: GlitchColors.textHint, size: 36),
                  ),
          ),
        ),
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withOpacity(0.45)),
          child: failed
              ? const Icon(Icons.error_outline_rounded, color: GlitchColors.error, size: 24)
              : Padding(
                  padding: const EdgeInsets.all(13),
                  child: CircularProgressIndicator(value: progress, color: Colors.white, strokeWidth: 2),
                ),
        ),
      ],
    );
  }
}

class VideoNotePlayer extends StatefulWidget {
  final ParsedVideoNote note;
  final String? localThumbPath;
  final double size;

  const VideoNotePlayer({
    super.key,
    required this.note,
    this.localThumbPath,
    this.size = 200,
  });

  @override
  State<VideoNotePlayer> createState() => _VideoNotePlayerState();
}

class _VideoNotePlayerState extends State<VideoNotePlayer> {
  static const Duration _scaleDuration = Duration(milliseconds: 220);

  Player? _player;
  VideoController? _videoCtrl;
  StreamSubscription<Duration>? _subPosition;
  StreamSubscription<bool>? _subCompleted;
  StreamSubscription<bool>? _subPlaying;
  Duration _position = Duration.zero;
  bool _starting = false;
  bool _playing = false;

  bool get _active => _player != null;

  bool get _enlarged => _active || _starting;

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }

  void _teardown() {
    _subPosition?.cancel();
    _subPosition = null;
    _subCompleted?.cancel();
    _subCompleted = null;
    _subPlaying?.cancel();
    _subPlaying = null;
    _player?.dispose();
    _player = null;
    _videoCtrl = null;
    _playing = false;
  }

  Future<void> _start() async {
    if (_active || _starting) return;
    setState(() => _starting = true);
    final player = Player();
    final ctrl = VideoController(player);
    _subPosition = player.stream.position.listen((v) {
      if (mounted) setState(() => _position = v);
    });
    _subCompleted = player.stream.completed.listen((done) {
      if (done && mounted) setState(_teardown);
    });
    _subPlaying = player.stream.playing.listen((v) {
      if (mounted) setState(() => _playing = v);
    });
    try {
      await player.open(Media(widget.note.url, httpHeaders: api.headersFor(widget.note.url)));
      if (!mounted) {
        await player.dispose();
        return;
      }
      setState(() {
        _player = player;
        _videoCtrl = ctrl;
        _starting = false;
        _position = Duration.zero;
      });
    } catch (_) {
      await player.dispose();
      if (mounted) setState(() => _starting = false);
    }
  }

  // Тап по уже играющему кружку — пауза/возобновление, а не остановка: тот же
  // приём, что и в полноэкранном видео-просмотрщике (media_viewer_screen.dart,
  // _player.playOrPause()) — играющий плеер не разбирается, только меняет
  // состояние. Полностью плеер отпускается лишь по завершении ролика
  // (_subCompleted выше) или когда виджет уходит с экрана (dispose).
  void _togglePlayPause() => _player!.playOrPause();

  @override
  Widget build(BuildContext context) {
    final d = widget.size;
    final double total = widget.note.duration > 0 ? widget.note.duration : 1.0;
    final double progress =
        _active ? (_position.inMilliseconds / 1000.0 / total).clamp(0.0, 1.0).toDouble() : 0.0;
    final double secondsLeft = _active
        ? (total - _position.inMilliseconds / 1000.0).clamp(0.0, total).toDouble()
        : total;

    return ClickableCursor(
      child: GestureDetector(
        onTap: _active ? _togglePlayPause : _start,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: d, end: _enlarged ? d * videoNotePlayingScale : d),
          duration: _scaleDuration,
          curve: Curves.easeOutCubic,
          builder: (context, size, _) => SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ClipOval(
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: _active && _videoCtrl != null
                        ? Video(
                            controller: _videoCtrl!,
                            controls: NoVideoControls,
                            fit: BoxFit.cover,
                            width: size,
                            height: size,
                          )
                        : _buildThumb(size),
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: VideoNoteRingPainter(
                      progress: progress,
                      color: GlitchColors.accentBlue,
                      trackColor: Colors.white.withOpacity(0.25),
                    ),
                  ),
                ),
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withOpacity(0.45)),
                  child: _starting
                      ? const Padding(
                          padding: EdgeInsets.all(13),
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Icon(
                          _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                ),
                Positioned(
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.45),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _formatDuration(secondsLeft),
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThumb(double d) {
    final local = widget.localThumbPath;
    if (local != null) {
      return localImage(local, width: d, height: d, fit: BoxFit.cover);
    }
    return CachedNetworkImage(
      imageUrl: widget.note.thumb,
      httpHeaders: api.headersFor(widget.note.thumb),
      width: d,
      height: d,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(color: GlitchColors.bgMessage),
      errorWidget: (_, __, ___) => Container(
        color: GlitchColors.bgMessage,
        child: Icon(Icons.videocam_off_rounded, color: GlitchColors.textHint, size: 32),
      ),
    );
  }

  String _formatDuration(double seconds) {
    final total = seconds.ceil();
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

// Кольцо прогресса по краю кружка. Рисуем сами: готовый
// CircularProgressIndicator не даёт ни нужной толщины по краю, ни точного
// совпадения диаметра с ClipOval.
class VideoNoteRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;
  final double stroke;

  const VideoNoteRingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    this.stroke = 3.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.shortestSide - stroke) / 2;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = trackColor;
    canvas.drawCircle(center, radius, track);

    if (progress <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.14159 / 2, // с 12 часов
      2 * 3.14159 * progress,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(VideoNoteRingPainter old) =>
      old.progress != progress || old.color != color || old.trackColor != trackColor || old.stroke != stroke;
}
