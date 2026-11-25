import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'api_service.dart';

const _audioCommandTimeout = Duration(seconds: 15);

class MessageAudio with WidgetsBindingObserver {
  Player? _player;
  MessageAudioController? _active;
  final List<StreamSubscription<dynamic>> _subs = [];
  Future<void> _tail = Future<void>.value();
  int _generation = 0;
  bool _attached = false;
  bool _paused = false;

  void attach() {
    if (_attached) return;
    _attached = true;
    final state = WidgetsBinding.instance.lifecycleState;
    _paused = state == AppLifecycleState.paused || state == AppLifecycleState.detached;
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.catchError((Object e, StackTrace s) {
      debugPrint('MessageAudio: $e');
    });
    return _tail;
  }

  Future<void> _closePlayer() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    final old = _player;
    _player = null;
    await old?.dispose();
  }

  Future<void> toggle(MessageAudioController controller) {
    if (!_attached || controller._disposed || controller.loading) return Future<void>.value();
    if (_active == controller && _player != null && !controller.failed) {
      return _command(controller, (p) async {
        if (controller.playing) {
          await p.pause();
        } else {
          if (controller.completed || controller.duration > Duration.zero && controller.position >= controller.duration) {
            await p.seek(Duration.zero);
          }
          await p.play();
        }
      });
    }
    final generation = ++_generation;
    final previous = _active;
    _active = controller;
    previous?._stopped();
    controller.loading = true;
    controller.failed = false;
    controller._changed();
    return _enqueue(() async {
      try {
        await _closePlayer();
        if (!_current(controller, generation)) return;
        final player = _player = Player();
        void observe<T>(Stream<T> stream, void Function(T) change) {
          _subs.add(stream.listen((value) {
            if (!_current(controller, generation)) return;
            change(value);
            controller._changed();
          }));
        }
        observe<bool>(player.stream.playing, (v) => controller.playing = v);
        observe<bool>(player.stream.buffering, (v) => controller.buffering = v);
        observe<Duration>(player.stream.position, controller._acceptPosition);
        observe<Duration>(player.stream.duration, (v) {
          if (v > Duration.zero) controller.duration = v;
        });
        observe<bool>(player.stream.completed, (v) {
          if (v && controller._pendingSeek != null) {
            if (controller._dispatchedSeek != controller._seekVersion ||
                controller._pendingSeek != controller.duration) return;
            controller._clearSeek(invalidate: false);
          }
          controller.completed = v;
          if (v) { controller._position = controller.duration; controller.playing = false; }
        });
        observe<String>(player.stream.error, (e) {
          debugPrint('MessageAudio: playback error: $e');
          _fail(controller, generation);
        });
        final url = api.mediaUrl(controller.url);
        await player.open(Media(url, httpHeaders: api.headersFor(url)), play: false)
            .timeout(_audioCommandTimeout);
        if (!_current(controller, generation) || controller.failed) return;
        controller.opened = true;
        await player.setVolume(controller.volume);
        if (!_current(controller, generation) || _paused) return;
        await player.play().timeout(_audioCommandTimeout);
      } catch (e) {
        debugPrint('MessageAudio: open failed: $e');
        if (_current(controller, generation)) _fail(controller, generation);
      } finally {
        if (_current(controller, generation)) {
          controller.loading = false;
          controller._changed();
        }
      }
    });
  }

  bool _current(MessageAudioController c, int generation) =>
      generation == _generation && _active == c && !c._disposed;

  void _fail(MessageAudioController c, int generation) {
    c._failed();
    unawaited(_enqueue(() async {
      if (_current(c, generation)) await _closePlayer();
    }));
  }

  Future<void> _command(MessageAudioController c, Future<void> Function(Player) action, {bool Function()? isRelevant}) {
    final generation = _generation;
    return _enqueue(() async {
      if (!_current(c, generation) || _player == null) return;
      try {
        await action(_player!).timeout(_audioCommandTimeout);
      } catch (e) {
        debugPrint('MessageAudio: command failed: $e');
        if (_current(c, generation) && (isRelevant?.call() ?? true)) _fail(c, generation);
      }
    });
  }

  Future<void> seek(MessageAudioController c, Duration value) {
    if (!_attached || _active != c || c._disposed || !c.opened || c.failed) {
      return Future<void>.value();
    }
    final target = Duration(milliseconds: value.inMilliseconds.clamp(0, c.duration.inMilliseconds).toInt());
    c._clearSeek();
    final version = c._seekVersion;
    final generation = _generation;
    c._pendingSeek = target;
    c._changed();
    return _command(c, (p) async {
      if (version != c._seekVersion) return;
      c._dispatchedSeek = version;
      c._seekTimeout = Timer(_audioCommandTimeout, () {
        if (_current(c, generation) && version == c._seekVersion) {
          debugPrint('MessageAudio: seek position was not confirmed');
          _fail(c, generation);
        }
      });
      final wasPlaying = p.state.playing;
      await p.seek(target);
      if (!wasPlaying) await p.pause();
    }, isRelevant: () => version == c._seekVersion);
  }

  void release(MessageAudioController controller) {
    if (_active != controller) return;
    ++_generation;
    _active = null;
    controller._stopped();
    unawaited(_enqueue(_closePlayer));
  }

  Future<void> reset() {
    if (_attached) WidgetsBinding.instance.removeObserver(this);
    _attached = false;
    ++_generation;
    _active?._stopped();
    _active = null;
    return _enqueue(_closePlayer);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _paused = state == AppLifecycleState.paused || state == AppLifecycleState.detached;
    final active = _active;
    if (state == AppLifecycleState.paused && active != null && active.playing) {
      unawaited(_command(active, (p) => p.pause()));
    }
  }
}

class MessageAudioController extends ChangeNotifier {
  final String url;
  Duration duration;
  Duration _position = Duration.zero;
  Duration? _pendingSeek;
  Timer? _seekTimeout;
  int _seekVersion = 0;
  int? _dispatchedSeek;
  Duration get position => _pendingSeek ?? _position;
  bool playing = false;
  bool loading = false;
  bool buffering = false;
  bool failed = false;
  bool opened = false;
  bool completed = false;
  double volume = 100;
  bool _disposed = false;

  MessageAudioController(this.url, {this.duration = Duration.zero});
  Future<void> toggle() => messageAudio.toggle(this);
  Future<void> seek(Duration value) => messageAudio.seek(this, value);

  void _acceptPosition(Duration value) {
    _position = value;
    final target = _pendingSeek;
    if (target != null && _dispatchedSeek == _seekVersion &&
        (value - target).inMilliseconds.abs() < 400) {
      _clearSeek(invalidate: false);
    }
  }

  void _clearSeek({bool invalidate = true}) {
    _seekTimeout?.cancel();
    _seekTimeout = null;
    _pendingSeek = null;
    _dispatchedSeek = null;
    if (invalidate) ++_seekVersion;
  }
  Future<void> setVolume(double value) {
    volume = value.clamp(0, 100).toDouble();
    _changed();
    return messageAudio._command(this, (p) => p.setVolume(volume));
  }
  void _changed() { if (!_disposed) notifyListeners(); }
  void _stopped() { _clearSeek(); playing = false; loading = false; buffering = false; opened = false; completed = false; _position = Duration.zero; _changed(); }
  void _failed() { _clearSeek(); failed = true; playing = false; loading = false; buffering = false; opened = false; _changed(); }
  @override
  void dispose() {
    _disposed = true;
    _clearSeek();
    messageAudio.release(this);
    super.dispose();
  }
}

final messageAudio = MessageAudio();

String audioTime(Duration value) {
  final seconds = value.inSeconds;
  final minutes = seconds ~/ 60;
  final rest = (seconds % 60).toString().padLeft(2, '0');
  return '$minutes:$rest';
}
